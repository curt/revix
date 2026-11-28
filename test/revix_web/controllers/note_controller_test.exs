defmodule RevixWeb.NoteControllerTest do
  use RevixWeb.ConnCase

  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures

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
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/plain"
    end

    test "returns 404 for malformed note id", %{conn: conn} do
      conn = get(conn, "/notes/not-valid-id")
      assert conn.status == 404
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/plain"
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
end
