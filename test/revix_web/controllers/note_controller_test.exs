defmodule RevixWeb.NoteControllerTest do
  use RevixWeb.ConnCase

  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures

  alias Revix.People.Scope

  describe "GET /notes/:id (unauthenticated)" do
    test "redirects to checkin show page", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = person_scope_fixture()
      comment = comment_fixture(scope, checkin)

      conn = get(conn, ~p"/notes/#{comment.id}")
      assert redirected_to(conn) =~ "/checkins/#{checkin.id}/test-cafe"
      assert redirected_to(conn) =~ "#comment-#{comment.id}"
    end

    test "reply-to-reply redirects to the original checkin, not the parent note", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = person_scope_fixture()
      comment = comment_fixture(scope, checkin)
      reply = reply_fixture(scope, comment)
      reply_to_reply = reply_fixture(scope, reply)

      conn = get(conn, ~p"/notes/#{reply_to_reply.id}")
      redir = redirected_to(conn)
      assert redir =~ "/checkins/#{checkin.id}/test-cafe"
      assert redir =~ "#comment-#{reply_to_reply.id}"
      refute redir =~ "/notes/"
    end

    test "reply redirects to the original checkin with correct anchor", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = person_scope_fixture()
      comment = comment_fixture(scope, checkin)
      reply = reply_fixture(scope, comment)

      conn = get(conn, ~p"/notes/#{reply.id}")
      redir = redirected_to(conn)
      assert redir =~ "/checkins/#{checkin.id}/test-cafe"
      assert redir =~ "#comment-#{reply.id}"
    end

    test "returns 404 for nonexistent note", %{conn: conn} do
      conn = get(conn, ~p"/notes/11111111111")
      assert conn.status == 404
    end

    test "sets x-robots-tag to noindex, follow", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = person_scope_fixture()
      comment = comment_fixture(scope, checkin)

      conn = get(conn, ~p"/notes/#{comment.id}")
      assert get_resp_header(conn, "x-robots-tag") == ["noindex, follow"]
    end

    test "returns 404 when note has no in_reply_to_uri", %{conn: conn} do
      {:ok, orphan} =
        Revix.Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/orphan",
          url: "https://remote.example.com/notes/orphan",
          author_uri: "https://remote.example.com/users/alice",
          content: "Orphan",
          in_reply_to_uri: nil,
          context: nil,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      conn = get(conn, ~p"/notes/#{orphan.id}")
      assert conn.status == 404
    end

    test "returns 404 when in_reply_to_uri points to unknown entry", %{conn: conn} do
      {:ok, dangling} =
        Revix.Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/dangling",
          url: "https://remote.example.com/notes/dangling",
          author_uri: "https://remote.example.com/users/alice",
          content: "Dangling",
          in_reply_to_uri: "https://remote.example.com/notes/unknown-parent",
          context: nil,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      conn = get(conn, ~p"/notes/#{dangling.id}")
      assert conn.status == 404
    end
  end

  describe "GET /notes/:id activity format" do
    test "returns ActivityStreams Note for a comment", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = person_scope_fixture()
      comment = comment_fixture(scope, checkin, %{"content" => "Nice place!"})

      conn = get(conn, "/notes/#{comment.id}?_format=activity")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/activity+json"

      body = Jason.decode!(conn.resp_body)
      assert body["type"] == "Note"
      assert body["id"] == comment.uri
      assert body["url"] == comment.url
      assert body["attributedTo"] == comment.author_uri
      assert body["inReplyTo"] == checkin.uri
      assert body["context"] == checkin.context
      assert body["to"] == ["https://www.w3.org/ns/activitystreams#Public"]
      refute Map.has_key?(body, "tag")

      assert body["@context"] == [
               "https://www.w3.org/ns/activitystreams",
               %{"schema" => "https://schema.org/", "sameAs" => "schema:sameAs"}
             ]
    end

    test "includes inReplyTo pointing to parent note for a reply", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = person_scope_fixture()
      comment = comment_fixture(scope, checkin)
      reply = reply_fixture(scope, comment)

      conn = get(conn, "/notes/#{reply.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      assert body["inReplyTo"] == comment.uri
      assert body["context"] == checkin.context
    end

    test "includes content when comment has text", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = person_scope_fixture()
      comment = comment_fixture(scope, checkin, %{"content" => "Great spot!"})

      conn = get(conn, "/notes/#{comment.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      assert body["content"] =~ "Great spot!"
      assert body["mediaType"] == "text/html"
    end

    test "omits attachment key when comment has no images", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = person_scope_fixture()
      comment = comment_fixture(scope, checkin)

      conn = get(conn, "/notes/#{comment.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      refute Map.has_key?(body, "attachment")
    end

    test "returns a Tombstone ActivityStreams object for a tombstoned comment", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = person_scope_fixture()
      comment = comment_fixture(scope, checkin, %{"content" => "Nice place!"})
      {:ok, _} = Revix.Entries.tombstone_entry(comment)

      conn = get(conn, "/notes/#{comment.id}?_format=activity")

      assert conn.status == 410
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/activity+json"

      body = Jason.decode!(conn.resp_body)
      assert body["type"] == "Tombstone"
      assert body["id"] == comment.uri
      assert body["formerType"] == "Note"
      assert body["deleted"]
    end
  end

  describe "POST /notes (unauthenticated)" do
    test "redirects to sign in", %{conn: conn} do
      conn = post(conn, ~p"/notes", %{"note" => %{"content" => "Hello"}})
      assert redirected_to(conn) =~ "/people/signin"
    end
  end

  describe "POST /notes (authenticated)" do
    setup :register_and_log_in_person

    test "creates a comment and redirects to checkin", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn =
        post(conn, ~p"/notes", %{
          "note" => %{
            "in_reply_to_uri" => checkin.uri,
            "content" => "Great visit!",
            "published_tz" => "UTC"
          }
        })

      assert redir = redirected_to(conn)
      assert redir =~ "/checkins/#{checkin.id}/test-cafe"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Comment added."
    end

    test "redirects back with error flash when content is too long", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      long_content = String.duplicate("a", 2001)

      conn =
        post(conn, ~p"/notes", %{
          "note" => %{
            "in_reply_to_uri" => checkin.uri,
            "content" => long_content,
            "published_tz" => "UTC"
          }
        })

      assert redirected_to(conn) =~ "/checkins/#{checkin.id}/test-cafe"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Could not save comment"
    end

    test "redirects back with error flash when content is blank", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn =
        post(conn, ~p"/notes", %{
          "note" => %{
            "in_reply_to_uri" => checkin.uri,
            "content" => "",
            "published_tz" => "UTC"
          }
        })

      assert redirected_to(conn) =~ "/checkins/#{checkin.id}/test-cafe"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Could not save comment"
    end

    test "creates a reply to a comment and redirects to the original checkin", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment_scope = person_scope_fixture()
      comment = comment_fixture(comment_scope, checkin)

      conn =
        post(conn, ~p"/notes", %{
          "note" => %{
            "in_reply_to_uri" => comment.uri,
            "content" => "A reply!",
            "published_tz" => "UTC"
          }
        })

      redir = redirected_to(conn)
      assert redir =~ "/checkins/#{checkin.id}/test-cafe"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Comment added."
    end

    test "creates a reply-to-reply and redirects to the original checkin", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment_scope = person_scope_fixture()
      comment = comment_fixture(comment_scope, checkin)
      reply = reply_fixture(comment_scope, comment)

      conn =
        post(conn, ~p"/notes", %{
          "note" => %{
            "in_reply_to_uri" => reply.uri,
            "content" => "A reply to a reply!",
            "published_tz" => "UTC"
          }
        })

      redir = redirected_to(conn)
      assert redir =~ "/checkins/#{checkin.id}/test-cafe"
      refute redir =~ "/notes/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Comment added."
    end

    test "returns 422 when in_reply_to_uri is missing", %{conn: conn} do
      conn = post(conn, ~p"/notes", %{"note" => %{"content" => "Hello"}})
      assert response(conn, 422)
    end

    test "returns 404 when checkin does not exist", %{conn: conn} do
      conn =
        post(conn, ~p"/notes", %{
          "note" => %{
            "in_reply_to_uri" => "https://example.com/nonexistent",
            "content" => "Hello",
            "published_tz" => "UTC"
          }
        })

      assert conn.status == 404
    end
  end

  describe "PUT /notes/:id (unauthenticated)" do
    test "redirects to sign in", %{conn: conn} do
      conn = put(conn, ~p"/notes/11111111111", %{"note" => %{"content" => "Updated"}})
      assert redirected_to(conn) =~ "/people/signin"
    end
  end

  describe "PUT /notes/:id (authenticated)" do
    setup :register_and_log_in_person

    test "updates comment content and returns JSON for the author", %{conn: conn, person: person} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = Scope.for_person(person)
      comment = comment_fixture(scope, checkin)

      conn =
        put(conn, ~p"/notes/#{comment.id}", %{"note" => %{"content" => "Updated text"}})

      assert %{"content_html" => content_html, "content" => content} = json_response(conn, 200)
      assert content == "Updated text"
      assert content_html =~ "Updated text"
    end

    test "returns 403 when user is not the author", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      other_scope = person_scope_fixture()
      comment = comment_fixture(other_scope, checkin)
      conn = put(conn, ~p"/notes/#{comment.id}", %{"note" => %{"content" => "Hijacked!"}})
      assert conn.status == 403
    end

    test "returns 404 when comment does not exist", %{conn: conn} do
      conn = put(conn, ~p"/notes/11111111111", %{"note" => %{"content" => "Updated"}})
      assert conn.status == 404
    end

    test "returns 422 when content is blank", %{conn: conn, person: person} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = Scope.for_person(person)
      comment = comment_fixture(scope, checkin)

      conn =
        put(conn, ~p"/notes/#{comment.id}", %{"note" => %{"content" => ""}})

      assert %{"errors" => _} = json_response(conn, 422)
    end
  end

  describe "DELETE /notes/:id (unauthenticated)" do
    test "redirects to sign in", %{conn: conn} do
      conn = delete(conn, ~p"/notes/11111111111")
      assert redirected_to(conn) =~ "/people/signin"
    end
  end

  describe "DELETE /notes/:id (authenticated)" do
    setup :register_and_log_in_person

    test "deletes the comment and returns ok JSON for the author", %{conn: conn, person: person} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = Scope.for_person(person)
      comment = comment_fixture(scope, checkin)

      conn = delete(conn, ~p"/notes/#{comment.id}")
      assert %{"ok" => true} = json_response(conn, 200)
      assert {:error, :not_found} = Revix.Entries.get_comment(comment.id)
    end

    test "returns 403 when user is not the author", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      other_scope = person_scope_fixture()
      comment = comment_fixture(other_scope, checkin)
      conn = delete(conn, ~p"/notes/#{comment.id}")
      assert conn.status == 403
    end

    test "returns 404 when comment does not exist", %{conn: conn} do
      conn = delete(conn, ~p"/notes/11111111111")
      assert conn.status == 404
    end
  end
end
