defmodule RevixWeb.PlaceControllerTest do
  use RevixWeb.ConnCase

  import Revix.PlacesFixtures
  import Revix.EntriesFixtures
  import Revix.PeopleFixtures

  describe "GET /places" do
    test "renders places index", %{conn: conn} do
      place_fixture(%{name: "Test Cafe"})

      conn = get(conn, ~p"/places")
      assert html_response(conn, 200) =~ "Test Cafe"
    end

    test "renders empty index when no places exist", %{conn: conn} do
      conn = get(conn, ~p"/places")
      assert html_response(conn, 200)
    end

    test "returns GeoJSON for geo format", %{conn: conn} do
      place_fixture()

      conn = get(conn, "/places?_format=geo")
      response = json_response(conn, 200)
      assert response["type"] == "FeatureCollection"
      assert length(response["features"]) == 1
    end

    test "sets the page title", %{conn: conn} do
      conn = get(conn, ~p"/places")
      assert html_response(conn, 200) =~ "Places · Revix"
    end
  end

  describe "GET /places/:id" do
    test "renders place show", %{conn: conn} do
      place = place_fixture(%{name: "Test Cafe", slug: "test-cafe"})

      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      assert html_response(conn, 200) =~ "Test Cafe"
    end

    test "redirects to slug URL when slug is missing", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})

      conn = get(conn, ~p"/places/#{place.id}")
      assert redirected_to(conn) == ~p"/places/#{place.id}/test-cafe"
    end

    test "redirects to correct slug when slug is wrong", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})

      conn = get(conn, ~p"/places/#{place.id}/wrong-slug")
      assert redirected_to(conn) == ~p"/places/#{place.id}/test-cafe"
    end

    test "redirects to country slug URL when place has country", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe", country: "us"})

      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      assert redirected_to(conn) == "/places/#{place.id}/us/test-cafe"
    end

    test "renders place with country slug URL", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe", country: "us"})

      conn = get(conn, "/places/#{place.id}/us/test-cafe")
      assert html_response(conn, 200) =~ "test-cafe"
    end

    test "redirects to country+city slug URL when place has country and city", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe", country: "us", city: "scottsdale"})

      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      assert redirected_to(conn) == "/places/#{place.id}/us/scottsdale/test-cafe"
    end

    test "renders place with country+city slug URL", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe", country: "us", city: "scottsdale"})

      conn = get(conn, "/places/#{place.id}/us/scottsdale/test-cafe")
      assert html_response(conn, 200) =~ "test-cafe"
    end

    test "redirects to full situation URL when place has country, secondary, and city", %{
      conn: conn
    } do
      place =
        place_fixture(%{slug: "test-cafe", country: "us", city: "scottsdale", secondary: "az"})

      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      assert redirected_to(conn) == "/places/#{place.id}/us/az/scottsdale/test-cafe"
    end

    test "renders place with full situation URL", %{conn: conn} do
      place =
        place_fixture(%{slug: "test-cafe", country: "us", city: "scottsdale", secondary: "az"})

      conn = get(conn, "/places/#{place.id}/us/az/scottsdale/test-cafe")
      assert html_response(conn, 200) =~ "test-cafe"
    end

    test "displays checkins section when checkins exist", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})

      checkin_fixture(%{
        place_uri: place.uri,
        starts_at_local: ~N[2026-01-20 10:00:00]
      })

      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ ~s(id="checkins")
      assert response =~ "2026-01-20"
    end

    test "hides checkins section when no checkins exist", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})

      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      refute html_response(conn, 200) =~ ~s(id="checkins")
    end

    test "displays nearby places", %{conn: conn} do
      place =
        place_fixture(%{
          slug: "test-cafe",
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      place_fixture(%{
        name: "Nearby Spot",
        coordinates: %Geo.Point{coordinates: {-105.001, 40.001}, srid: 4326}
      })

      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ ~s(id="nearby")
      assert response =~ "Nearby Spot"
    end

    test "owner sees 'Check in' link", %{conn: conn} do
      person = person_fixture()
      Revix.People.set_person_role(person, :owner)
      conn = log_in_person(conn, person)
      place = place_fixture(%{slug: "test-cafe"})

      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ "Check in"
      assert response =~ "/places/#{place.id}/checkins/new"
    end

    test "non-owner does not see 'Check in' link", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      place = place_fixture(%{slug: "test-cafe"})

      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      refute html_response(conn, 200) =~ "Check in"
    end

    test "unauthenticated visitor does not see 'Check in' link", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})

      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      refute html_response(conn, 200) =~ "Check in"
    end

    test "returns 404 for nonexistent place", %{conn: conn} do
      conn = get(conn, ~p"/places/11111111111")
      assert conn.status == 404
    end

    test "returns GeoJSON for geo format", %{conn: conn} do
      place = place_fixture()

      conn = get(conn, "/places/#{place.id}?_format=geo")
      response = json_response(conn, 200)
      assert response["type"] == "FeatureCollection"

      focus_feature = Enum.find(response["features"], & &1["properties"]["focus"])
      assert focus_feature["properties"]["name"] == place.name
    end

    test "returns ActivityStreams Place for activity format", %{conn: conn} do
      place = place_fixture(%{name: "Activity Cafe", slug: "activity-cafe"})

      conn =
        conn
        |> put_req_header("accept", "application/activity+json")
        |> get("/places/#{place.id}?_format=activity")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/activity+json"

      body = Jason.decode!(conn.resp_body)
      assert body["type"] == "Place"
      assert body["id"] == place.uri
      assert body["name"] == "Activity Cafe"
      assert body["url"] == place.url

      assert body["@context"] == [
               "https://www.w3.org/ns/activitystreams",
               %{"schema" => "https://schema.org/", "sameAs" => "schema:sameAs"}
             ]
    end

    test "activity response includes coordinates", %{conn: conn} do
      place =
        place_fixture(%{
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      conn = get(conn, "/places/#{place.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      assert body["longitude"] == -105.0
      assert body["latitude"] == 40.0
    end

    test "activity response includes sameAs for OSM place", %{conn: conn} do
      place = place_fixture(%{osm_type: :node, osm_id: 12345})

      conn = get(conn, "/places/#{place.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      assert body["sameAs"] == "https://www.openstreetmap.org/node/12345"
    end

    test "activity response omits sameAs when place has no OSM data", %{conn: conn} do
      place = place_fixture()

      conn = get(conn, "/places/#{place.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      refute Map.has_key?(body, "sameAs")
    end
  end

  describe "GET /places/:id JSON-LD" do
    test "includes unencoded TouristAttraction JSON-LD in head", %{conn: conn} do
      place = place_fixture(%{name: "Test Cafe", slug: "test-cafe"})

      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      response = html_response(conn, 200)

      assert response =~ ~s(type="application/ld+json")
      assert response =~ ~s("@type":"TouristAttraction")
      assert response =~ ~s("name":"Test Cafe")
    end

    test "includes unencoded geo coordinates in JSON-LD", %{conn: conn} do
      place =
        place_fixture(%{
          name: "Geo Cafe",
          slug: "geo-cafe",
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      conn = get(conn, ~p"/places/#{place.id}/geo-cafe")
      response = html_response(conn, 200)

      assert response =~ ~s("@type":"GeoCoordinates")
      assert response =~ ~s("latitude":40.0)
      assert response =~ ~s("longitude":-105.0)
    end
  end

  describe "GET /places/:id — posts section" do
    test "renders posts associated with the place", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})

      post =
        post_fixture(%{
          name: "My Visit",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      Revix.EntryPlaces.add_place(post.uri, place.uri)

      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ "Posts"
      assert response =~ "My Visit"
    end

    test "does not render posts section when no posts are associated", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      refute html_response(conn, 200) =~ ~s(id="posts")
    end

    test "renders posts above checkins", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})

      post =
        post_fixture(%{
          name: "Post Here",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      Revix.EntryPlaces.add_place(post.uri, place.uri)
      checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      response = html_response(conn, 200)
      posts_pos = :binary.match(response, "id=\"posts\"") |> elem(0)
      checkins_pos = :binary.match(response, "id=\"checkins\"") |> elem(0)
      assert posts_pos < checkins_pos
    end
  end

  describe "GET /places/:id head links" do
    test "includes canonical link with slug URL", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ ~s(rel="canonical")
      assert response =~ ~s(href="#{RevixWeb.CanonicalRoutes.place_url(place)}")
    end

    test "includes activity+json alternate link with slug-free URI", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ ~s(rel="alternate")
      assert response =~ ~s(type="application/activity+json")
      assert response =~ ~s(href="#{RevixWeb.CanonicalRoutes.place_uri(place)}")
    end
  end

  describe "GET /places/:id OpenGraph" do
    test "includes og:type, og:title, og:url meta tags", %{conn: conn} do
      place = place_fixture(%{name: "Test Cafe", slug: "test-cafe"})
      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      response = html_response(conn, 200)

      assert response =~ ~s(property="og:type")
      assert response =~ ~s(property="og:title")
      assert response =~ ~s(content="Test Cafe")
      assert response =~ ~s(property="og:url")
    end

    test "includes og:description when place has content", %{conn: conn} do
      place = place_fixture(%{name: "Desc Cafe", slug: "desc-cafe", content: "A great place."})
      conn = get(conn, ~p"/places/#{place.id}/desc-cafe")
      response = html_response(conn, 200)

      assert response =~ ~s(property="og:description")
      assert response =~ ~s(content="A great place.")
    end
  end

  describe "GET /places/:id page title" do
    test "sets the page title to the place name", %{conn: conn} do
      place = place_fixture(%{name: "Test Cafe", slug: "test-cafe"})
      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      assert html_response(conn, 200) =~ "Test Cafe · Revix"
    end
  end

  describe "GET /places/:id microformats" do
    test "root element has h-card class", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      assert html_response(conn, 200) =~ ~s(class="mx-auto max-w-7xl h-card")
    end

    test "place name has p-name class", %{conn: conn} do
      place = place_fixture(%{name: "Test Cafe", slug: "test-cafe"})
      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      assert html_response(conn, 200) =~ ~s(p-name)
    end

    test "u-uid link contains place uri", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ ~s(class="u-uid")
      assert response =~ place.uri
    end

    test "u-url link contains place url", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      assert html_response(conn, 200) =~ ~s(class="u-url")
    end

    test "p-latitude and p-longitude data elements present when coordinates exist", %{conn: conn} do
      place =
        place_fixture(%{
          slug: "test-cafe",
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      conn = get(conn, ~p"/places/#{place.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ ~s(class="p-latitude")
      assert response =~ ~s(class="p-longitude")
      assert response =~ ~s(value="40.0)
      assert response =~ ~s(value="-105.0)
    end
  end
end
