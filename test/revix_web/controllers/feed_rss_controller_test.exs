defmodule RevixWeb.FeedRSSControllerTest do
  use RevixWeb.ConnCase

  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures
  import Revix.LikesFixtures
  import Revix.MediaFixtures

  alias Revix.Media

  describe "GET /feed.rss — response basics" do
    test "returns 200 with rss content type", %{conn: conn} do
      conn = get(conn, "/feed.rss")
      assert conn.status == 200
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/rss+xml"
    end

    test "returns a valid RSS 2.0 document", %{conn: conn} do
      conn = get(conn, "/feed.rss")
      body = response(conn, 200)
      assert body =~ ~s(<rss version="2.0")
      assert body =~ "<channel>"
      assert body =~ ~s(<atom:link rel="self" type="application/rss+xml")
    end

    test "is accessible without authentication", %{conn: conn} do
      conn = get(conn, "/feed.rss")
      assert conn.status == 200
    end

    test "channel title falls back to the default site name", %{conn: conn} do
      conn = get(conn, "/feed.rss")
      body = response(conn, 200)
      assert body =~ "<title>Revix — activity</title>"
    end

    test "channel title uses the configured site name", %{conn: conn} do
      {:ok, _site} =
        Revix.Sites.update_site(RevixWeb.CanonicalRoutes.home_url(), %{title: "My Journal"})

      conn = get(conn, "/feed.rss")
      body = response(conn, 200)
      assert body =~ "<title>My Journal — activity</title>"
    end
  end

  describe "GET /feed.rss — empty feed" do
    test "returns a valid channel with no items", %{conn: conn} do
      conn = get(conn, "/feed.rss")
      body = response(conn, 200)
      refute body =~ "<item>"
    end
  end

  describe "GET /feed.rss — entries" do
    test "includes a checkin as an item with a permalink guid", %{conn: conn} do
      place = place_fixture(%{name: "The Coffee Shop"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/feed.rss")
      body = response(conn, 200)
      assert body =~ "<item>"
      assert body =~ "checked into"
      assert body =~ "The Coffee Shop"
      assert body =~ ~s(<guid isPermaLink="true">#{checkin.uri}</guid>)
    end

    test "includes a post as an item", %{conn: conn} do
      post = post_fixture(%{name: "My Thoughts", published_tz: "UTC"})

      conn = get(conn, "/feed.rss")
      body = response(conn, 200)
      assert body =~ "posted"
      assert body =~ "My Thoughts"
      assert body =~ ~s(<guid isPermaLink="true">#{post.uri}</guid>)
    end

    test "includes a like as an item with a non-permalink guid", %{conn: conn} do
      place = place_fixture(%{name: "Favorite Cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      like = like_fixture(%{object_uri: checkin.uri})

      conn = get(conn, "/feed.rss")
      body = response(conn, 200)
      assert body =~ "liked"
      assert body =~ ~s(<guid isPermaLink="false">#{checkin.uri}#like-#{like.id}</guid>)
    end

    test "pubDate is in RFC 822 format", %{conn: conn} do
      place = place_fixture()

      _checkin =
        checkin_fixture(%{
          place_uri: place.uri,
          published_at_utc: ~U[2026-01-01 10:00:00Z],
          starts_at_utc: ~U[2026-01-01 10:00:00Z]
        })

      conn = get(conn, "/feed.rss")
      body = response(conn, 200)
      assert body =~ "<pubDate>Thu, 01 Jan 2026 10:00:00 GMT</pubDate>"

      assert Regex.match?(
               ~r/<pubDate>\w{3}, \d{2} \w{3} \d{4} \d{2}:\d{2}:\d{2} GMT<\/pubDate>/,
               body
             )
    end

    test "guids are unique across two checkins", %{conn: conn} do
      place = place_fixture()
      a = checkin_fixture(%{place_uri: place.uri})
      b = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/feed.rss")
      body = response(conn, 200)
      assert body =~ "<guid isPermaLink=\"true\">#{a.uri}</guid>"
      assert body =~ "<guid isPermaLink=\"true\">#{b.uri}</guid>"
      refute a.uri == b.uri
    end

    test "includes an enclosure without a length attribute", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(checkin.id, image.id, 0)

      conn = get(conn, "/feed.rss")
      body = response(conn, 200)
      assert body =~ ~s(<enclosure url=)
      assert body =~ ~s(type="image/jpeg")
      refute body =~ "length="
    end
  end

  describe "GET /feed.rss — excluded content" do
    test "does not include comments", %{conn: conn} do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = comment_fixture(scope, checkin, %{"content" => "So tasty!"})

      conn = get(conn, "/feed.rss")
      body = response(conn, 200)
      refute body =~ "commented on"
      refute body =~ comment.uri
      refute body =~ "So tasty!"
    end

    test "does not include likes on comments", %{conn: conn} do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = comment_fixture(scope, checkin, %{"content" => "nice"})
      _like = like_fixture(%{object_uri: comment.uri})

      conn = get(conn, "/feed.rss")
      body = response(conn, 200)
      refute body =~ "liked"
    end

    test "does not include remote likes", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, _like} =
        Revix.Likes.upsert_inbound_like(%{
          author_uri: "https://remote.example/users/bob",
          object_uri: checkin.uri,
          like_uri: "https://remote.example/likes/3"
        })

      conn = get(conn, "/feed.rss")
      body = response(conn, 200)
      refute body =~ "liked"
    end
  end

  describe "GET /feed.rss — XML safety" do
    test "special characters in place names are escaped in item titles", %{conn: conn} do
      place = place_fixture(%{name: "Bob's & Alice's Café"})
      _checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/feed.rss")
      body = response(conn, 200)
      assert conn.status == 200
      assert body =~ "Bob&#39;s &amp; Alice&#39;s"
    end
  end
end
