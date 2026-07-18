defmodule RevixWeb.CheckinControllerTest do
  use RevixWeb.ConnCase

  import Revix.PlacesFixtures
  import Revix.EntriesFixtures
  import Revix.PeopleFixtures
  import Revix.MediaFixtures

  alias Revix.Likes
  alias Revix.Media

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

    test "sets the page title", %{conn: conn} do
      conn = get(conn, ~p"/checkins")
      assert html_response(conn, 200) =~ "Checkins · Revix"
    end

    test "sets the meta description", %{conn: conn} do
      conn = get(conn, ~p"/checkins")
      response = html_response(conn, 200)
      assert response =~ ~s(name="description")
      assert response =~ "Recent check-ins on Revix."
    end

    test "sets x-robots-tag to index, follow", %{conn: conn} do
      conn = get(conn, ~p"/checkins")
      assert get_resp_header(conn, "x-robots-tag") == ["index, follow"]
    end

    test "renders an h1", %{conn: conn} do
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins")
      assert html_response(conn, 200) =~ "<h1"
    end
  end

  describe "GET /checkins head links" do
    test "includes a self-referential canonical link", %{conn: conn} do
      conn = get(conn, ~p"/checkins")
      response = html_response(conn, 200)
      assert response =~ ~s(rel="canonical")
      assert response =~ ~s(href="#{RevixWeb.CanonicalRoutes.checkins_index_url()}")
    end
  end

  describe "GET /checkins OpenGraph" do
    test "includes og:type, og:title, og:description, og:url meta tags", %{conn: conn} do
      conn = get(conn, ~p"/checkins")
      response = html_response(conn, 200)

      assert response =~ ~s(property="og:type")
      assert response =~ ~s(property="og:title")
      assert response =~ ~s(content="Checkins")
      assert response =~ ~s(property="og:description")
      assert response =~ ~s(content="Recent check-ins on Revix.")
      assert response =~ ~s(property="og:url")
      assert response =~ ~s(content="#{RevixWeb.CanonicalRoutes.checkins_index_url()}")
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

    test "redirects to country slug URL when place has country", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe", country: "us"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      assert redirected_to(conn) == "/checkins/#{checkin.id}/us/test-cafe"
    end

    test "renders checkin with country slug URL", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe", country: "us"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/checkins/#{checkin.id}/us/test-cafe")
      assert html_response(conn, 200) =~ place.name
    end

    test "redirects to country+city slug URL when place has country and city", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe", country: "us", city: "scottsdale"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      assert redirected_to(conn) == "/checkins/#{checkin.id}/us/scottsdale/test-cafe"
    end

    test "renders checkin with country+city slug URL", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe", country: "us", city: "scottsdale"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/checkins/#{checkin.id}/us/scottsdale/test-cafe")
      assert html_response(conn, 200) =~ place.name
    end

    test "redirects to full situation URL when place has country, secondary, and city", %{
      conn: conn
    } do
      place =
        place_fixture(%{slug: "test-cafe", country: "us", city: "scottsdale", secondary: "az"})

      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      assert redirected_to(conn) == "/checkins/#{checkin.id}/us/az/scottsdale/test-cafe"
    end

    test "renders checkin with full situation URL", %{conn: conn} do
      place =
        place_fixture(%{slug: "test-cafe", country: "us", city: "scottsdale", secondary: "az"})

      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/checkins/#{checkin.id}/us/az/scottsdale/test-cafe")
      assert html_response(conn, 200) =~ place.name
    end

    test "renders without redirect when place has no slug", %{conn: conn} do
      place = place_fixture(%{slug: nil})
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
      conn = get(conn, ~p"/checkins/11111111111")
      assert conn.status == 404
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
      assert body["to"] == ["https://www.w3.org/ns/activitystreams#Public"]
      assert body["cc"] == [checkin.author_uri <> "/followers"]

      assert body["@context"] == [
               "https://www.w3.org/ns/activitystreams",
               %{"schema" => "https://schema.org/", "sameAs" => "schema:sameAs"}
             ]

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
      refute Map.has_key?(location, "sameAs")
    end

    test "activity location includes sameAs when place has OSM data", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe", osm_type: :way, osm_id: 99999})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/checkins/#{checkin.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      assert body["location"]["sameAs"] == "https://www.openstreetmap.org/way/99999"
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
    test "renders embedded comment LiveView placeholder", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      assert html_response(conn, 200) =~ "comment-section"
    end
  end

  describe "GET /checkins/:id like section" do
    test "embeds the EntryLikeLive LiveView mount stub", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ "like-section"
      assert response =~ "phx-session"
    end
  end

  describe "GET /checkins/:id activity format — attachments" do
    test "includes attachment when checkin has images", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(checkin.id, image.id, 0)

      conn = get(conn, "/checkins/#{checkin.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      assert [attachment] = body["attachment"]
      assert attachment["type"] == "Document"
      assert attachment["mediaType"] == image.content_type
      assert is_binary(attachment["url"])
    end

    test "omits attachment key when checkin has no images", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/checkins/#{checkin.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      refute Map.has_key?(body, "attachment")
    end
  end

  describe "GET /checkins/:id JSON-LD" do
    test "includes unencoded Event JSON-LD in head", %{conn: conn} do
      place = place_fixture(%{name: "Test Cafe", slug: "test-cafe"})

      checkin =
        checkin_fixture(%{
          place_uri: place.uri,
          starts_at_utc: ~U[2026-02-14 15:00:00Z],
          starts_at_local: ~N[2026-02-14 10:00:00],
          starts_tz: "America/Denver"
        })

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)

      assert response =~ ~s(type="application/ld+json")
      assert response =~ ~s("@type":"Event")
      assert response =~ ~s("name":"Checkin at Test Cafe")
      assert response =~ "2026-02-14"
    end

    test "includes unencoded place location in JSON-LD", %{conn: conn} do
      place =
        place_fixture(%{
          name: "Geo Cafe",
          slug: "geo-cafe",
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/geo-cafe")
      response = html_response(conn, 200)

      assert response =~ ~s("@type":"GeoCoordinates")
      assert response =~ ~s("latitude":40.0)
      assert response =~ ~s("longitude":-105.0)
    end
  end

  describe "GET /checkins/:id head links" do
    test "includes canonical link with slug URL", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ ~s(rel="canonical")
      assert response =~ ~s(href="#{RevixWeb.CanonicalRoutes.checkin_url(checkin)}")
    end

    test "includes activity+json alternate link with slug-free URI", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ ~s(rel="alternate")
      assert response =~ ~s(type="application/activity+json")
      assert response =~ ~s(href="#{RevixWeb.CanonicalRoutes.checkin_uri(checkin)}")
    end
  end

  describe "GET /checkins/:id OpenGraph" do
    test "includes og:type, og:title, og:url meta tags", %{conn: conn} do
      place = place_fixture(%{name: "Test Cafe", slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)

      assert response =~ ~s(property="og:type")
      assert response =~ ~s(property="og:title")
      assert response =~ ~s(content="Checkin at Test Cafe")
      assert response =~ ~s(property="og:url")
    end

    test "includes og:image when checkin has images", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(checkin.id, image.id, 0)

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      assert html_response(conn, 200) =~ ~s(property="og:image")
    end

    test "omits og:image when checkin has no images", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      refute html_response(conn, 200) =~ ~s(property="og:image")
    end
  end

  describe "GET /checkins/:id page title" do
    test "sets the page title from the place name", %{conn: conn} do
      place = place_fixture(%{name: "Test Cafe", slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      assert html_response(conn, 200) =~ "Checkin at Test Cafe · Revix"
    end
  end

  describe "GET /checkins/:id meta description" do
    test "sets the meta description from checkin content", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri, content: "Great tacos here."})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)

      assert response =~ ~s(name="description")
      assert response =~ "Great tacos here."
    end

    test "omits the meta description tag when checkin has no content", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri, content: nil})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      refute html_response(conn, 200) =~ ~s(name="description")
    end
  end

  describe "GET /checkins/:id robots" do
    test "sets x-robots-tag to index, follow", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      assert get_resp_header(conn, "x-robots-tag") == ["index, follow"]
    end
  end

  describe "GET /checkins/:id semantic structure" do
    test "wraps the checkin's own content in an article element", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      assert html_response(conn, 200) =~ "<article"
    end
  end

  describe "GET /checkins/:id image attachments" do
    test "attachment link uses :large version not :original", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(checkin.id, image.id, 0)

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      html = html_response(conn, 200)

      assert html =~ "uploads/images/#{image.id}/large"
      refute html =~ "uploads/images/#{image.id}/original"
    end
  end

  describe "GET /checkins/:id owner actions" do
    setup :register_and_log_in_person

    test "owner sees re-transform button when checkin has images", %{conn: conn, person: person} do
      {:ok, _} = Revix.People.set_person_role(person, :owner)
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(checkin.id, image.id, 0)

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      assert html_response(conn, 200) =~ "Re-transform photos"
    end

    test "non-owner does not see re-transform button", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(checkin.id, image.id, 0)

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      refute html_response(conn, 200) =~ "Re-transform photos"
    end

    test "owner does not see re-transform button when checkin has no images", %{
      conn: conn,
      person: person
    } do
      {:ok, _} = Revix.People.set_person_role(person, :owner)
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      refute html_response(conn, 200) =~ "Re-transform photos"
    end
  end

  describe "POST /checkins/:id/retransform_images" do
    setup :register_and_log_in_person

    test "owner redirects to checkin with success flash", %{conn: conn, person: person} do
      {:ok, _} = Revix.People.set_person_role(person, :owner)
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = post(conn, ~p"/checkins/#{checkin.id}/retransform_images")
      assert redirected_to(conn) == ~p"/checkins/#{checkin.id}"
      assert conn.assigns.flash["info"] == "Photos re-transformed."
    end

    test "non-owner is redirected to home with error", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = post(conn, ~p"/checkins/#{checkin.id}/retransform_images")
      assert redirected_to(conn) == ~p"/"
      assert conn.assigns.flash["error"] == "Not authorized."
    end

    test "owner gets error flash for nonexistent checkin", %{conn: conn, person: person} do
      {:ok, _} = Revix.People.set_person_role(person, :owner)
      conn = post(conn, ~p"/checkins/11111111111/retransform_images")
      assert redirected_to(conn) == ~p"/checkins"
      assert conn.assigns.flash["error"] == "Checkin not found."
    end
  end

  describe "POST /checkins/:id/retransform_images (unauthenticated)" do
    test "redirects to sign-in", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      conn = post(conn, ~p"/checkins/#{checkin.id}/retransform_images")
      assert redirected_to(conn) =~ "/people/signin"
    end
  end

  describe "GET /checkins/:id microformats" do
    test "root element has h-entry class", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      assert html_response(conn, 200) =~ ~s(class="mx-auto max-w-7xl h-entry")
    end

    test "u-uid link contains checkin uri", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ ~s(class="u-uid")
      assert response =~ checkin.uri
    end

    test "dt-start time element contains ISO 8601 UTC datetime", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})

      checkin =
        checkin_fixture(%{
          place_uri: place.uri,
          starts_at_utc: ~U[2026-02-14 15:00:00Z]
        })

      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      response = html_response(conn, 200)
      assert response =~ ~s(class="dt-start")
      assert response =~ ~s(datetime="2026-02-14T15:00:00Z")
    end

    test "place link has p-location class", %{conn: conn} do
      place = place_fixture(%{name: "Test Cafe", slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      assert html_response(conn, 200) =~ ~s(class="p-location")
    end

    test "author block has p-author h-card classes", %{conn: conn} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      conn = get(conn, ~p"/checkins/#{checkin.id}/test-cafe")
      assert html_response(conn, 200) =~ ~s(class="p-author h-card")
    end
  end
end
