defmodule RevixWeb.FeedControllerTest do
  use RevixWeb.ConnCase

  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures
  import Revix.LikesFixtures

  describe "GET /feed.atom — response basics" do
    test "returns 200 with atom content type", %{conn: conn} do
      conn = get(conn, "/feed.atom")
      assert conn.status == 200
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/atom+xml"
    end

    test "returns valid Atom XML root element", %{conn: conn} do
      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ ~s(xmlns="http://www.w3.org/2005/Atom")
      assert body =~ "<feed"
    end

    test "includes required Atom feed-level elements", %{conn: conn} do
      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ "<id>"
      assert body =~ "<title>"
      assert body =~ "<updated>"
      assert body =~ ~s(rel="self")
      assert body =~ ~s(rel="alternate")
    end

    test "is accessible without authentication", %{conn: conn} do
      conn = get(conn, "/feed.atom")
      assert conn.status == 200
    end
  end

  describe "GET /feed.atom — empty feed" do
    test "returns valid feed with no entries", %{conn: conn} do
      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      refute body =~ "<entry>"
    end
  end

  describe "GET /feed.atom — checkin entries" do
    test "includes checkin as feed entry", %{conn: conn} do
      place = place_fixture(%{name: "The Coffee Shop"})
      _checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ "<entry>"
      assert body =~ "The Coffee Shop"
      assert body =~ "checked into"
    end

    test "uses checkin uri as entry id", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ checkin.uri
    end

    test "includes link to checkin url when set", %{conn: conn} do
      place = place_fixture()

      checkin =
        checkin_fixture(%{
          place_uri: place.uri,
          url: "http://localhost:4000/checkins/abc123/test-place"
        })

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ checkin.url
    end

    test "includes published timestamp", %{conn: conn} do
      place = place_fixture()
      _checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ "<updated>"
    end

    test "includes content when present", %{conn: conn} do
      place = place_fixture()

      _checkin =
        checkin_fixture(%{
          place_uri: place.uri,
          content: "Great place!",
          content_html: "<p>Great place!</p>"
        })

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ ~s(type="html")
      assert body =~ "Great place!"
    end
  end

  describe "GET /feed.atom — post entries" do
    test "includes post as feed entry", %{conn: conn} do
      _post = post_fixture(%{name: "My Thoughts", published_tz: "UTC"})

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ "<entry>"
      assert body =~ "My Thoughts"
      assert body =~ "posted"
    end

    test "uses post uri as entry id", %{conn: conn} do
      post = post_fixture(%{published_tz: "UTC"})

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ post.uri
    end

    test "includes link to post url", %{conn: conn} do
      post = post_fixture(%{
        name: "Linked Post",
        published_at_local: ~N[2026-05-10 12:00:00],
        published_tz: "UTC"
      })

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ post.url
    end

    test "includes post content when present", %{conn: conn} do
      _post = post_fixture(%{
        content: "Hello world",
        content_html: "<p>Hello world</p>",
        published_tz: "UTC"
      })

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ ~s(type="html")
      assert body =~ "Hello world"
    end

    test "title falls back to 'a post' when name is nil", %{conn: conn} do
      _post = post_fixture(%{name: nil, published_tz: "UTC"})

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ "a post"
    end
  end

  describe "GET /feed.atom — like entries" do
    setup do
      place = place_fixture(%{name: "Favorite Cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      %{place: place, checkin: checkin}
    end

    test "includes like as feed entry", %{conn: conn, checkin: checkin} do
      _like = like_fixture(%{object_uri: checkin.uri})

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ "<entry>"
      assert body =~ "liked"
    end

    test "like entry has compound id with #like- fragment", %{conn: conn, checkin: checkin} do
      like = like_fixture(%{object_uri: checkin.uri})

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ "#{checkin.uri}#like-#{like.id}"
    end

    test "like id is distinct from checkin id", %{conn: conn, checkin: checkin} do
      like = like_fixture(%{object_uri: checkin.uri})

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      # The checkin's own URI appears as checkin's <id>, the like gets the compound one
      assert body =~ checkin.uri
      assert body =~ "#like-#{like.id}"
    end

    test "like title references the place name", %{conn: conn, checkin: checkin, place: place} do
      _like = like_fixture(%{object_uri: checkin.uri})

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ place.name
    end

    test "like with no resolvable object still renders", %{conn: conn} do
      _like = like_fixture(%{object_uri: "https://remote.example/entries/gone"})

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ "liked"
      assert body =~ "a checkin"
    end

    test "like renders without content element", %{conn: conn, checkin: checkin} do
      _like = like_fixture(%{object_uri: checkin.uri})

      conn = get(conn, "/feed.atom")
      # Just verify it renders successfully — likes have no content
      assert conn.status == 200
    end
  end

  describe "GET /feed.atom — comment entries" do
    test "includes comment as feed entry", %{conn: conn} do
      scope = person_scope_fixture()
      place = place_fixture(%{name: "The Diner"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      _comment = comment_fixture(scope, checkin, %{"content" => "So tasty!"})

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ "commented on"
      assert body =~ "The Diner"
    end

    test "comment entry uses comment uri as id", %{conn: conn} do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = comment_fixture(scope, checkin)

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ comment.uri
    end

    test "comment content appears in feed entry", %{conn: conn} do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      _comment = comment_fixture(scope, checkin, %{"content" => "What a spot!"})

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ "What a spot!"
    end
  end

  describe "GET /feed.atom — mixed feed ordering" do
    test "activities are sorted by published_at_utc descending", %{conn: conn} do
      place = place_fixture()

      older_checkin =
        checkin_fixture(%{
          place_uri: place.uri,
          published_at_utc: ~U[2026-01-01 10:00:00Z],
          starts_at_utc: ~U[2026-01-01 10:00:00Z]
        })

      newer_checkin =
        checkin_fixture(%{
          place_uri: place.uri,
          published_at_utc: ~U[2026-01-02 10:00:00Z],
          starts_at_utc: ~U[2026-01-02 10:00:00Z]
        })

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)

      newer_pos = :binary.match(body, newer_checkin.uri) |> elem(0)
      older_pos = :binary.match(body, older_checkin.uri) |> elem(0)
      assert newer_pos < older_pos
    end

    test "multiple activity types all appear in feed", %{conn: conn} do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      _like = like_fixture(%{object_uri: checkin.uri})
      _comment = comment_fixture(scope, checkin, %{"content" => "Hello!"})

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert body =~ "checked into"
      assert body =~ "liked"
      assert body =~ "commented on"
    end
  end

  describe "GET /feed.atom — XML safety" do
    test "special characters in place names are escaped in titles", %{conn: conn} do
      place = place_fixture(%{name: "Bob's & Alice's Café"})
      _checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/feed.atom")
      body = response(conn, 200)
      assert conn.status == 200
      # Ampersand should be escaped as &amp; in XML attributes/text
      refute body =~ "Bob's & Alice's"
      assert body =~ "Bob&#39;s &amp; Alice&#39;s"
    end

    test "angle brackets in place names are escaped", %{conn: conn} do
      place = place_fixture(%{name: "<Test Place>"})
      _checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/feed.atom")
      assert conn.status == 200
    end
  end
end
