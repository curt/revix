defmodule RevixWeb.PageControllerTest do
  use RevixWeb.ConnCase

  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures

  alias Revix.Entries
  alias Revix.People.Scope

  defp create_comment(scope, checkin, attrs) do
    uri_fn = fn id -> "https://example.com/notes/#{id}" end

    {:ok, comment} =
      Entries.create_comment(
        scope,
        checkin,
        Map.merge(%{"published_tz" => "UTC"}, attrs),
        uri_fn,
        uri_fn
      )

    comment
  end

  describe "GET / — GeoJSON format" do
    test "returns GeoJSON FeatureCollection via Accept header", %{conn: conn} do
      place_fixture()

      conn =
        conn
        |> put_req_header("accept", "application/geo+json")
        |> get("/")

      response = json_response(conn, 200)
      assert response["type"] == "FeatureCollection"
    end

    test "includes all local places", %{conn: conn} do
      place_fixture(%{name: "Place A"})
      place_fixture(%{name: "Place B"})

      conn =
        conn
        |> put_req_header("accept", "application/geo+json")
        |> get("/")

      response = json_response(conn, 200)
      names = Enum.map(response["features"], & &1["properties"]["name"])
      assert "Place A" in names
      assert "Place B" in names
    end
  end

  describe "GET / — unauthenticated HTML" do
    test "returns 200 with activity feed HTML", %{conn: conn} do
      conn = get(conn, "/")
      assert html_response(conn, 200) =~ "Home Page"
    end

    test "renders static HTML (no phx-session)", %{conn: conn} do
      conn = get(conn, "/")
      html = html_response(conn, 200)
      refute html =~ "phx-session"
    end

    test "sets the page title", %{conn: conn} do
      conn = get(conn, "/")
      assert html_response(conn, 200) =~ "<title"
      assert html_response(conn, 200) =~ "Revix"
    end

    test "sets the meta description", %{conn: conn} do
      conn = get(conn, "/")
      response = html_response(conn, 200)
      assert response =~ ~s(name="description")
      assert response =~ "Revix is a federated place to log check-ins and share posts."
    end

    test "sets x-robots-tag to index, follow", %{conn: conn} do
      conn = get(conn, "/")
      assert get_resp_header(conn, "x-robots-tag") == ["index, follow"]
    end

    test "renders a nav landmark", %{conn: conn} do
      conn = get(conn, "/")
      assert html_response(conn, 200) =~ "<nav"
    end

    test "displays checkin in static feed", %{conn: conn} do
      place = place_fixture(%{name: "Unauthenticated Place"})
      checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, "/")
      assert html_response(conn, 200) =~ "Unauthenticated Place"
    end

    test "does not show comments in unauthenticated feed", %{conn: conn} do
      scope = Scope.for_person(person_fixture())
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      create_comment(scope, checkin, %{"content" => "hi"})

      conn = get(conn, "/")
      refute html_response(conn, 200) =~ "commented on"
    end
  end

  describe "GET / — authenticated HTML" do
    test "returns response with phx-session (LiveView)", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      conn = get(conn, "/")
      assert html_response(conn, 200) =~ "phx-session"
    end
  end

  describe "GET / head links" do
    test "includes a self-referential canonical link", %{conn: conn} do
      conn = get(conn, "/")
      response = html_response(conn, 200)
      assert response =~ ~s(rel="canonical")
      assert response =~ ~s(href="#{RevixWeb.CanonicalRoutes.home_url()}")
    end
  end

  describe "GET / OpenGraph" do
    test "includes og:type, og:title, og:description, og:url meta tags", %{conn: conn} do
      conn = get(conn, "/")
      response = html_response(conn, 200)

      assert response =~ ~s(property="og:type")
      assert response =~ ~s(property="og:title")
      assert response =~ ~s(content="Revix")
      assert response =~ ~s(property="og:description")

      assert response =~
               ~s(content="Revix is a federated place to log check-ins and share posts.")

      assert response =~ ~s(property="og:url")
      assert response =~ ~s(content="#{RevixWeb.CanonicalRoutes.home_url()}")
    end
  end
end
