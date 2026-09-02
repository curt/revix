defmodule RevixWeb.PersonFeedControllerTest do
  use RevixWeb.ConnCase

  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures

  describe "GET /people/:id/feed.atom" do
    test "returns 200 with atom content type", %{conn: conn} do
      person = person_fixture()

      conn = get(conn, "/people/#{person.id}/feed.atom")
      assert conn.status == 200
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/atom+xml"
      assert response(conn, 200) =~ "<feed"
    end

    test "feed title contains both the person name and the site name", %{conn: conn} do
      {:ok, _site} =
        Revix.Sites.update_site(RevixWeb.CanonicalRoutes.home_url(), %{title: "My Journal"})

      person =
        person_fixture()
        |> Ecto.Changeset.change(display_name: "Ada Lovelace")
        |> Revix.Repo.update!()

      conn = get(conn, "/people/#{person.id}/feed.atom")
      body = response(conn, 200)
      assert body =~ "Ada Lovelace"
      assert body =~ "My Journal"
    end

    test "self link matches the request URL", %{conn: conn} do
      person = person_fixture()

      conn = get(conn, "/people/#{person.id}/feed.atom")
      body = response(conn, 200)
      assert body =~ RevixWeb.CanonicalRoutes.person_feed_atom_url(person.id)
    end

    test "includes only the given person's activity", %{conn: conn} do
      person = person_fixture()
      other = person_fixture()
      place = place_fixture(%{name: "Shared Spot"})

      mine = checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})
      theirs = checkin_fixture(%{place_uri: place.uri, author_uri: other.uri})

      conn = get(conn, "/people/#{person.id}/feed.atom")
      body = response(conn, 200)
      assert body =~ mine.uri
      refute body =~ theirs.uri
    end

    test "excludes comments and drafts (unauthenticated scope)", %{conn: conn} do
      person = person_fixture()
      scope = person_scope_fixture(person)
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})
      comment = comment_fixture(scope, checkin, %{"content" => "my own note"})

      draft =
        checkin_fixture(%{
          place_uri: place.uri,
          author_uri: person.uri,
          published_at_utc: nil,
          published_at_local: nil,
          published_tz: nil
        })

      conn = get(conn, "/people/#{person.id}/feed.atom")
      body = response(conn, 200)
      refute body =~ comment.uri
      refute body =~ "my own note"
      refute body =~ draft.uri
    end

    test "returns 404 for an unknown id", %{conn: conn} do
      conn = get(conn, "/people/doesnotexist/feed.atom")
      assert conn.status == 404
    end

    test "returns 404 for a remote person", %{conn: conn} do
      {:ok, remote} =
        Revix.People.upsert_remote_person(%{
          uri: "https://remote.example/users/mallory",
          url: "https://remote.example/users/mallory",
          username: "mallory",
          display_name: "Mallory"
        })

      conn = get(conn, "/people/#{remote.id}/feed.atom")
      assert conn.status == 404
    end
  end

  describe "GET /people/:id/feed.rss" do
    test "returns 200 with rss content type and a valid RSS 2.0 document", %{conn: conn} do
      person = person_fixture()

      conn = get(conn, "/people/#{person.id}/feed.rss")
      assert conn.status == 200
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/rss+xml"
      assert response(conn, 200) =~ ~s(<rss version="2.0")
    end

    test "includes only the given person's activity", %{conn: conn} do
      person = person_fixture()
      other = person_fixture()
      place = place_fixture()

      mine = checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})
      theirs = checkin_fixture(%{place_uri: place.uri, author_uri: other.uri})

      conn = get(conn, "/people/#{person.id}/feed.rss")
      body = response(conn, 200)
      assert body =~ mine.uri
      refute body =~ theirs.uri
    end

    test "returns 404 for an unknown id", %{conn: conn} do
      conn = get(conn, "/people/doesnotexist/feed.rss")
      assert conn.status == 404
    end
  end
end
