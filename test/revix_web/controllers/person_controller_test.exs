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
    Revix.Entries.create_comment(scope, checkin, attrs, uri_fn, uri_fn)
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

      assert_raise Plug.BadRequestError, fn ->
        get(conn, ~p"/people/#{nonexistent_id}")
      end
    end
  end

  describe "GET /@:username" do
    test "renders the person page", %{conn: conn} do
      person_fixture() |> set_username("bob")

      conn = get(conn, "/@bob")
      assert html_response(conn, 200)
    end

    test "returns 404 for unknown username", %{conn: conn} do
      assert_raise Plug.BadRequestError, fn ->
        get(conn, "/@nobody")
      end
    end

    test "displays person display name in header", %{conn: conn} do
      person = person_fixture()
      {:ok, person} = Revix.People.update_person_display_name(person, %{display_name: "Diana"})
      _person = set_username(person, "diana")

      conn = get(conn, "/@diana")
      assert html_response(conn, 200) =~ "Diana"
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

    test "displays the person's comments", %{conn: conn, person: person, place: place} do
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = Revix.People.Scope.for_person(person)

      create_comment(scope, checkin, %{
        "content" => "Great spot!",
        "published_tz" => "UTC"
      })

      conn = get(conn, ~p"/people/#{person.id}")
      response = html_response(conn, 200)
      assert response =~ "commented on"
      assert response =~ place.name
    end

    test "does not display other people's activity", %{conn: conn, person: person, place: place} do
      other_person = person_fixture()
      checkin_fixture(%{author_uri: other_person.uri, place_uri: place.uri})

      conn = get(conn, ~p"/people/#{person.id}")
      refute html_response(conn, 200) =~ "checked into"
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
