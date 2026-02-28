defmodule RevixWeb.CheckinControllerTest do
  use RevixWeb.ConnCase

  import Revix.PlacesFixtures
  import Revix.EntriesFixtures
  import Revix.PeopleFixtures

  alias Revix.Likes

  describe "GET /checkins" do
    test "renders checkins index", %{conn: conn} do
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins")
      assert html_response(conn, 200) =~ place.name
    end

    test "renders empty index when no checkins exist", %{conn: conn} do
      conn = get(conn, ~p"/checkins")
      assert html_response(conn, 200)
    end

    test "renders checkin dates", %{conn: conn} do
      place = place_fixture()

      checkin_fixture(%{
        place_uri: place.uri,
        starts_at_local: ~N[2026-01-15 10:00:00]
      })

      conn = get(conn, ~p"/checkins")
      assert html_response(conn, 200) =~ "2026-01-15"
    end

    test "returns GeoJSON for geo format", %{conn: conn} do
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/checkins?_format=geo")
      response = json_response(conn, 200)
      assert response["type"] == "FeatureCollection"
    end
  end

  describe "GET /checkins/:id" do
    test "renders checkin show", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ place.name
    end

    test "redirects to slug URL when slug is missing", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}")
      assert redirected_to(conn) == ~p"/checkins/#{checkin.id}/test-cafe"
    end

    test "redirects to correct slug when slug is wrong", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/wrong-slug")
      assert redirected_to(conn) == ~p"/checkins/#{checkin.id}/test-cafe"
    end

    test "renders without redirect when place has no slug", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}")
      assert html_response(conn, 200) =~ place.name
    end

    test "renders checkin date and time with timezone", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})

      checkin =
        checkin_fixture(%{
          place_uri: place.uri,
          starts_at_utc: ~U[2026-02-14 15:00:00Z],
          starts_at_local: ~N[2026-02-14 10:00:00],
          starts_tz: "America/New_York"
        })

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ "2026-02-14"
      assert response =~ "10:00 EST"
    end

    test "renders checkin content", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})

      checkin =
        checkin_fixture(%{
          place_uri: place.uri,
          content_html: "<p>Great visit!</p>"
        })

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      assert html_response(conn, 200) =~ "Great visit!"
    end

    test "renders nearby places", %{conn: conn} do
      place =
        place_fixture(%{
          slug: "test-cafe",
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      place_fixture(%{
        name: "Nearby Spot",
        coordinates: %Geo.Point{coordinates: {-105.001, 40.001}, srid: 4326}
      })

      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ "Nearby Spot"
      assert response =~ "Nearby Places"
    end

    test "displays other checkins for the same place", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri, starts_at_local: ~N[2026-01-10 10:00:00]})

      checkin_fixture(%{
        place_uri: place.uri,
        starts_at_local: ~N[2026-01-20 10:00:00]
      })

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ ~s(id="checkins")
      assert response =~ "Other Checkins"
      assert response =~ "2026-01-20"
    end

    test "excludes current checkin from other checkins list", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})

      checkin =
        checkin_fixture(%{
          place_uri: place.uri,
          starts_at_local: ~N[2026-01-10 10:00:00]
        })

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      refute html_response(conn, 200) =~ ~s(id="checkins")
    end

    test "returns 404 for nonexistent checkin", %{conn: conn} do
      assert_raise Plug.BadRequestError, fn ->
        get(conn, ~p"/checkins/11111111111")
      end
    end

    test "returns GeoJSON for geo format", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/checkins/#{checkin.id}?_format=geo")
      response = json_response(conn, 200)
      assert response["type"] == "FeatureCollection"

      focus_feature = Enum.find(response["features"], & &1["properties"]["focus"])
      assert focus_feature["properties"]["name"] == place.name
    end

    test "returns ActivityStreams Event for activity format", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})

      checkin =
        checkin_fixture(%{
          place_uri: place.uri,
          starts_at_utc: ~U[2026-02-19 15:00:00Z],
          starts_at_local: ~N[2026-02-19 10:00:00],
          starts_tz: "America/New_York"
        })

      conn =
        conn
        |> put_req_header("accept", "application/activity+json")
        |> get("/checkins/#{checkin.id}?_format=activity")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/activity+json"

      body = Jason.decode!(conn.resp_body)
      assert body["type"] == "Note"
      assert body["id"] == checkin.uri
      assert body["url"] == checkin.url
      assert body["attributedTo"] == checkin.author_uri
      assert body["startTime"] == "2026-02-19T15:00:00Z"
      assert body["@context"] == "https://www.w3.org/ns/activitystreams"
      assert body["tag"] == [%{"type" => "Hashtag", "name" => "#checkin"}]
    end

    test "activity response includes location when checkin has place_uri", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/checkins/#{checkin.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      location = body["location"]
      assert location["id"] == place.uri
      assert location["type"] == "Place"
      assert location["name"] == place.name
    end

    test "activity response includes content when checkin has content", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})

      checkin =
        checkin_fixture(%{
          place_uri: place.uri,
          content: "Great visit!",
          content_html: "<p>Great visit!</p>"
        })

      conn = get(conn, "/checkins/#{checkin.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      assert body["content"] == "<p>Great visit!</p>"
      assert body["mediaType"] == "text/html"
    end
  end

  describe "GET /api/places/search (unauthenticated)" do
    test "redirects to sign in when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/places/search", %{lat: "40.0", lon: "-105.0"})
      assert redirected_to(conn) =~ "/people/signin"
    end
  end

  describe "GET /api/places/search (authenticated)" do
    setup :register_and_log_in_person

    setup do
      Req.Test.stub(:overpass, fn conn -> Req.Test.json(conn, %{"elements" => []}) end)
      :ok
    end

    test "returns JSON results for nearby places", %{conn: conn} do
      place_fixture(%{
        name: "Nearby Cafe",
        coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
      })

      conn =
        get(conn, ~p"/api/places/search", %{lat: "40.0001", lon: "-105.0001", accuracy: "10"})

      response = json_response(conn, 200)
      assert is_list(response)
    end

    test "returns empty list for invalid coordinates", %{conn: conn} do
      conn = get(conn, ~p"/api/places/search", %{lat: "invalid", lon: "-105.0"})
      assert json_response(conn, 200) == []
    end
  end

  describe "GET /checkins like counts" do
    test "renders like count for liked checkins", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = person_scope_fixture()
      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC")

      conn = get(conn, ~p"/checkins")
      response = html_response(conn, 200)
      assert response =~ "hero-heart"
    end

    test "does not render like icon when count is zero", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins")
      response = html_response(conn, 200)
      # The like icon should not be visible when count is 0
      refute response =~ ~s(hero-heart" class="w-4 h-4 inline)
    end
  end

  describe "GET /checkins/:id comments section" do
    test "renders comments section", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      assert html_response(conn, 200) =~ "comments-section"
    end

    test "renders existing comments with content", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = person_scope_fixture()
      comment = comment_fixture(scope, checkin, %{"content" => "My test comment"})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ "My test comment"
      assert response =~ "comment-#{comment.id}"
    end

    test "shows comment form for authenticated users", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      person = person_fixture()

      conn =
        conn
        |> log_in_person(person)
        |> get(~p"/checkins/#{checkin.id}/test-cafe")

      response = html_response(conn, 200)
      assert response =~ "Add a comment"
      assert response =~ ~s(action="/notes")
    end

    test "hides comment form for unauthenticated users", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      refute html_response(conn, 200) =~ "Add a comment"
    end

    test "hides Comments heading when there are no comments", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      refute html_response(conn, 200) =~ "<h2>Comments</h2>"
    end

    test "shows Comments heading when comments exist", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = person_scope_fixture()
      comment_fixture(scope, checkin, %{"content" => "A comment"})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      assert html_response(conn, 200) =~ "Comments"
    end
  end

  describe "GET /checkins/:id like section" do
    test "renders like section with no likes", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ "like-section"
      assert response =~ "like-btn"
      assert response =~ "like-avatars"
    end

    test "renders avatars when likes exist", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = person_scope_fixture()
      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC")

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ "like-section"
      assert response =~ "like-avatars"
    end

    test "renders liked state for authenticated liker", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      person = person_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = Revix.People.Scope.for_person(person)
      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC")

      conn =
        conn
        |> log_in_person(person)
        |> get(~p"/checkins/#{checkin.id}/test-cafe")

      response = html_response(conn, 200)
      assert response =~ ~s(data-liked="true")
      assert response =~ "hero-heart-solid"
    end

    test "renders unliked state for authenticated non-liker", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      person = person_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn =
        conn
        |> log_in_person(person)
        |> get(~p"/checkins/#{checkin.id}/test-cafe")

      response = html_response(conn, 200)
      assert response =~ ~s(data-liked="false")
      refute response =~ "hero-heart-solid"
    end

    test "like button is disabled for unauthenticated users", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ ~s(disabled)
    end

    test "like button is disabled for the checkin's own author", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      person = person_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})

      conn =
        conn
        |> log_in_person(person)
        |> get(~p"/checkins/#{checkin.id}/test-cafe")

      response = html_response(conn, 200)
      assert response =~ ~s(disabled)
    end

    test "like button is enabled for authenticated non-author", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      person = person_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn =
        conn
        |> log_in_person(person)
        |> get(~p"/checkins/#{checkin.id}/test-cafe")

      # The button should not have the disabled attribute
      # Parse out just the like-btn button to avoid other disabled elements
      response = html_response(conn, 200)
      refute response =~ ~s(id="like-btn" class="btn btn-ghost btn-sm px-1" disabled)
    end
  end
end
