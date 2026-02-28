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

    test "returns 404 for nonexistent note", %{conn: conn} do
      assert_raise Plug.BadRequestError, fn ->
        get(conn, ~p"/notes/11111111111")
      end
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

    test "returns 422 when in_reply_to_uri is missing", %{conn: conn} do
      conn = post(conn, ~p"/notes", %{"note" => %{"content" => "Hello"}})
      assert response(conn, 422)
    end

    test "returns 404 when checkin does not exist", %{conn: conn} do
      assert_raise Plug.BadRequestError, fn ->
        post(conn, ~p"/notes", %{
          "note" => %{
            "in_reply_to_uri" => "https://example.com/nonexistent",
            "content" => "Hello",
            "published_tz" => "UTC"
          }
        })
      end
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

      assert_raise Plug.BadRequestError, fn ->
        put(conn, ~p"/notes/#{comment.id}", %{"note" => %{"content" => "Hijacked!"}})
      end
    end

    test "returns 404 when comment does not exist", %{conn: conn} do
      assert_raise Plug.BadRequestError, fn ->
        put(conn, ~p"/notes/11111111111", %{"note" => %{"content" => "Updated"}})
      end
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

      assert_raise Plug.BadRequestError, fn ->
        delete(conn, ~p"/notes/#{comment.id}")
      end
    end

    test "returns 404 when comment does not exist", %{conn: conn} do
      assert_raise Plug.BadRequestError, fn ->
        delete(conn, ~p"/notes/11111111111")
      end
    end
  end
end
