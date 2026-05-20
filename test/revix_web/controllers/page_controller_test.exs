defmodule RevixWeb.PageControllerTest do
  use RevixWeb.ConnCase

  import Revix.PlacesFixtures

  describe "GET /home.geo GeoJSON format" do
    test "returns GeoJSON for geo format", %{conn: conn} do
      place_fixture()

      conn = get(conn, "/home.geo")
      response = json_response(conn, 200)
      assert response["type"] == "FeatureCollection"
    end

    test "includes all places, not just those with checkins", %{conn: conn} do
      place_fixture(%{name: "Place With Checkin"})
      place_fixture(%{name: "Place Without Checkin"})

      conn = get(conn, "/home.geo")
      response = json_response(conn, 200)
      names = Enum.map(response["features"], & &1["properties"]["name"])
      assert "Place With Checkin" in names
      assert "Place Without Checkin" in names
    end

    test "includes place names in feature properties", %{conn: conn} do
      place_fixture(%{name: "Test Place"})

      conn = get(conn, "/home.geo")
      response = json_response(conn, 200)
      feature = List.first(response["features"])
      assert feature["properties"]["name"] == "Test Place"
    end
  end
end
