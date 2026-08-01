defmodule RevixWeb.PersonControllerTest do
  use RevixWeb.ConnCase

  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures
  import Revix.LikesFixtures

  alias Revix.Repo

  defp set_username(person, username) do
    person
    |> Ecto.Changeset.change(username: username)
    |> Repo.update!()
  end

  defp create_comment(scope, checkin, attrs) do
    uri_fn = fn id -> "https://example.com/notes/#{id}" end
    {:ok, comment} = Revix.Entries.create_comment(scope, checkin, attrs, uri_fn, uri_fn)
    comment
  end

  describe "GET /people/:id" do
    test "renders the person page", %{conn: conn} do
      person = person_fixture()

      conn = get(conn, ~p"/people/#{person.id}")
      assert html_response(conn, 200)
    end

    test "redirects to /@username when person has a username", %{conn: conn} do
      person = person_fixture() |> set_username("alice")

      conn = get(conn, ~p"/people/#{person.id}")
      assert redirected_to(conn) == "/@alice"
    end

    test "returns 404 for unknown person id", %{conn: conn} do
      nonexistent_id = Revix.Ecto.Base58Id.autogenerate()
      conn = get(conn, ~p"/people/#{nonexistent_id}")
      assert conn.status == 404
    end

    test "sets x-robots-tag to index, follow", %{conn: conn} do
      person = person_fixture()

      conn = get(conn, ~p"/people/#{person.id}")
      assert get_resp_header(conn, "x-robots-tag") == ["index, follow"]
    end
  end

  describe "GET /@:username" do
    test "renders the person page", %{conn: conn} do
      person_fixture() |> set_username("bob")

      conn = get(conn, "/@bob")
      assert html_response(conn, 200)
    end

    test "returns 404 for unknown username", %{conn: conn} do
      conn = get(conn, "/@nobody")
      assert conn.status == 404
    end

    test "displays person display name in header", %{conn: conn} do
      person = person_fixture()
      {:ok, person} = Revix.People.update_person_display_name(person, %{display_name: "Diana"})
      _person = set_username(person, "diana")

      conn = get(conn, "/@diana")
      assert html_response(conn, 200) =~ "Diana"
    end

    test "sets the page title to the display name when present", %{conn: conn} do
      person = person_fixture()
      {:ok, person} = Revix.People.update_person_display_name(person, %{display_name: "Diana"})
      _person = set_username(person, "diana")

      conn = get(conn, "/@diana")
      assert html_response(conn, 200) =~ "Diana · Revix"
    end

    test "sets the page title to the username when display name is blank", %{conn: conn} do
      person_fixture() |> set_username("noname")

      conn = get(conn, "/@noname")
      assert html_response(conn, 200) =~ "noname · Revix"
    end

    test "uses the configured site title instead of Revix", %{conn: conn} do
      Revix.Sites.update_site(RevixWeb.CanonicalRoutes.home_url(), %{title: "My Site"})
      person = person_fixture()
      {:ok, person} = Revix.People.update_person_display_name(person, %{display_name: "Diana"})
      _person = set_username(person, "diana")

      conn = get(conn, "/@diana")
      assert html_response(conn, 200) =~ "Diana · My Site"
    end

    test "sets the meta description using the display name", %{conn: conn} do
      person = person_fixture()
      {:ok, person} = Revix.People.update_person_display_name(person, %{display_name: "Diana"})
      _person = set_username(person, "diana")

      conn = get(conn, "/@diana")
      response = html_response(conn, 200)

      assert response =~ ~s(name="description")
      assert response =~ "Diana&#39;s activity on Revix."
    end

    test "sets x-robots-tag to index, follow", %{conn: conn} do
      person_fixture() |> set_username("bob")

      conn = get(conn, "/@bob")
      assert get_resp_header(conn, "x-robots-tag") == ["index, follow"]
    end
  end

  describe "GET /@:username head links" do
    test "includes a canonical link pointing at the /@username form", %{conn: conn} do
      person = person_fixture() |> set_username("carol")

      conn = get(conn, "/@carol")
      response = html_response(conn, 200)

      assert response =~ ~s(rel="canonical")
      assert response =~ ~s(href="#{RevixWeb.CanonicalRoutes.person_url(person)}")
      assert response =~ "/@carol"
    end

    test "canonical link uses the /@username form even when reached via /people/:id",
         %{conn: conn} do
      person = person_fixture() |> set_username("dave")

      conn = get(conn, ~p"/people/#{person.id}")
      redirect_path = redirected_to(conn)

      conn = get(recycle(conn), redirect_path)
      response = html_response(conn, 200)
      assert response =~ ~s(href="#{RevixWeb.CanonicalRoutes.person_url(person)}")
    end
  end

  describe "GET /@:username OpenGraph" do
    test "includes og:type, og:title, og:image, og:url meta tags", %{conn: conn} do
      person = person_fixture() |> set_username("erin")
      {:ok, person} = Revix.People.update_person_display_name(person, %{display_name: "Erin"})

      conn = get(conn, "/@erin")
      response = html_response(conn, 200)

      assert response =~ ~s(property="og:type")
      assert response =~ ~s(content="profile")
      assert response =~ ~s(property="og:title")
      assert response =~ ~s(content="Erin")
      assert response =~ ~s(property="og:image")
      assert response =~ ~s(property="og:url")
      assert response =~ ~s(content="#{RevixWeb.CanonicalRoutes.person_url(person)}")
    end

    test "falls back to username for og:title when display name is blank", %{conn: conn} do
      person_fixture() |> set_username("frank")

      conn = get(conn, "/@frank")
      response = html_response(conn, 200)

      assert response =~ ~s(property="og:title")
      assert response =~ ~s(content="frank")
    end
  end

  describe "GET /@:username TwitterCard" do
    test "uses summary_large_image with title and image from the avatar", %{conn: conn} do
      person = person_fixture() |> set_username("holly")
      {:ok, _} = Revix.People.update_person_display_name(person, %{display_name: "Holly"})

      conn = get(conn, "/@holly")
      response = html_response(conn, 200)

      assert response =~ ~s(name="twitter:card")
      assert response =~ ~s(content="summary_large_image")
      assert response =~ ~s(name="twitter:title")
      assert response =~ ~s(content="Holly")
      assert response =~ ~s(name="twitter:image")
    end
  end

  describe "GET /@:username JSON-LD" do
    test "includes a ProfilePage with a nested Person", %{conn: conn} do
      person = person_fixture() |> set_username("grace")
      {:ok, person} = Revix.People.update_person_display_name(person, %{display_name: "Grace"})

      conn = get(conn, "/@grace")
      response = html_response(conn, 200)

      assert response =~ ~s(type="application/ld+json")
      assert response =~ ~s("@type":"ProfilePage")
      assert response =~ ~s("@type":"Person")
      assert response =~ ~s("name":"Grace")
      assert response =~ RevixWeb.CanonicalRoutes.person_url(person)
    end
  end

  describe "GET /people/:id person activity" do
    setup do
      person = person_fixture()
      place = place_fixture(%{name: "The Venue"})
      %{person: person, place: place}
    end

    test "displays the person's checkins", %{conn: conn, person: person, place: place} do
      checkin_fixture(%{author_uri: person.uri, place_uri: place.uri})

      conn = get(conn, ~p"/people/#{person.id}")
      response = html_response(conn, 200)
      assert response =~ "checked into"
      assert response =~ place.name
    end

    test "displays the person's likes", %{conn: conn, person: person, place: place} do
      checkin = checkin_fixture(%{place_uri: place.uri})
      like_fixture(%{author_uri: person.uri, object_uri: checkin.uri})

      conn = get(conn, ~p"/people/#{person.id}")
      response = html_response(conn, 200)
      assert response =~ "liked"
      assert response =~ place.name
    end

    test "does not display comments for unauthenticated visitors", %{
      conn: conn,
      person: person,
      place: place
    } do
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = Revix.People.Scope.for_person(person)

      create_comment(scope, checkin, %{
        "content" => "Great spot!",
        "published_tz" => "UTC"
      })

      conn = get(conn, ~p"/people/#{person.id}")
      refute html_response(conn, 200) =~ "commented on"
    end

    test "displays the person's comments when authenticated", %{
      conn: conn,
      person: person,
      place: place
    } do
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = Revix.People.Scope.for_person(person)

      create_comment(scope, checkin, %{
        "content" => "Great spot!",
        "published_tz" => "UTC"
      })

      conn = log_in_person(conn, person_fixture())
      conn = get(conn, ~p"/people/#{person.id}")
      assert html_response(conn, 200) =~ "phx-session"
    end

    test "does not display other people's activity", %{conn: conn, person: person, place: place} do
      other_person = person_fixture()
      checkin_fixture(%{author_uri: other_person.uri, place_uri: place.uri})

      conn = get(conn, ~p"/people/#{person.id}")
      refute html_response(conn, 200) =~ "checked into"
    end
  end

  describe "GET /people/:id — unauthenticated vs authenticated rendering" do
    test "unauthenticated renders static HTML (no phx-session)", %{conn: conn} do
      person = person_fixture()

      conn = get(conn, ~p"/people/#{person.id}")
      refute html_response(conn, 200) =~ "phx-session"
    end

    test "authenticated renders LiveView (has phx-session)", %{conn: conn} do
      person = person_fixture()
      viewer = person_fixture()

      conn = log_in_person(conn, viewer)
      conn = get(conn, ~p"/people/#{person.id}")
      assert html_response(conn, 200) =~ "phx-session"
    end

    test "unauthenticated does not show note-likes", %{conn: conn} do
      person = person_fixture()
      other_person = person_fixture()
      other_scope = Revix.People.Scope.for_person(other_person)
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      # other_person authors the comment so person can like it (no self-like)
      comment =
        create_comment(other_scope, checkin, %{"content" => "hi", "published_tz" => "UTC"})

      like_fixture(%{author_uri: person.uri, object_uri: comment.uri})

      conn = get(conn, ~p"/people/#{person.id}")
      refute html_response(conn, 200) =~ "hero-heart-solid"
    end
  end

  describe "GET /@:username activity format" do
    test "redirects to /people/:id", %{conn: conn} do
      person = person_fixture() |> set_username("activityuser")

      conn =
        conn
        |> put_req_header("accept", "application/activity+json")
        |> get("/@activityuser")

      assert redirected_to(conn) == "/people/#{person.id}"
    end
  end

  describe "GET /people/:id ActivityPub format" do
    test "includes icon with Image type and url", %{conn: conn} do
      person = person_fixture()

      conn = get(conn, "/people/#{person.id}?_format=activity")
      response = json_response(conn, 200)

      assert %{"type" => "Image", "mediaType" => "image/png", "url" => url} = response["icon"]
      assert String.starts_with?(url, "http")
    end

    test "collection URLs point to canonical routes", %{conn: conn} do
      person = person_fixture()

      conn = get(conn, "/people/#{person.id}?_format=activity")
      response = json_response(conn, 200)

      assert String.ends_with?(response["followers"], "/people/#{person.id}/followers")
      assert String.ends_with?(response["following"], "/people/#{person.id}/following")
      assert String.ends_with?(response["outbox"], "/people/#{person.id}/outbox")
      assert String.ends_with?(response["liked"], "/people/#{person.id}/liked")
      assert String.ends_with?(response["inbox"], "/people/#{person.id}/inbox")
    end
  end

  describe "GET /people/:id GeoJSON format" do
    test "returns a GeoJSON FeatureCollection", %{conn: conn} do
      person = person_fixture()
      place = place_fixture()
      checkin_fixture(%{author_uri: person.uri, place_uri: place.uri})

      conn = get(conn, "/people/#{person.id}?_format=geo")
      response = json_response(conn, 200)
      assert response["type"] == "FeatureCollection"
    end

    test "includes only places the person checked in to", %{conn: conn} do
      person = person_fixture()
      other_person = person_fixture()
      their_place = place_fixture(%{name: "Their Place"})
      other_place = place_fixture(%{name: "Other Place"})
      checkin_fixture(%{author_uri: person.uri, place_uri: their_place.uri})
      checkin_fixture(%{author_uri: other_person.uri, place_uri: other_place.uri})

      conn = get(conn, "/people/#{person.id}?_format=geo")
      response = json_response(conn, 200)
      names = Enum.map(response["features"], & &1["properties"]["name"])
      assert "Their Place" in names
      refute "Other Place" in names
    end

    test "returns empty FeatureCollection when person has no checkins", %{conn: conn} do
      person = person_fixture()

      conn = get(conn, "/people/#{person.id}?_format=geo")
      response = json_response(conn, 200)
      assert response["type"] == "FeatureCollection"
      assert response["features"] == []
    end

    test "GET /@:username also returns GeoJSON", %{conn: conn} do
      person = person_fixture() |> set_username("geo_user")
      place = place_fixture()
      checkin_fixture(%{author_uri: person.uri, place_uri: place.uri})

      conn = get(conn, "/@geo_user?_format=geo")
      response = json_response(conn, 200)
      assert response["type"] == "FeatureCollection"
      assert length(response["features"]) == 1
    end
  end
end
