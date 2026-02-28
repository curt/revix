defmodule Revix.OverpassTest do
  use ExUnit.Case, async: true

  alias Revix.Overpass

  describe "parse_elements/3" do
    test "parses node elements" do
      elements = %{
        "elements" => [
          %{
            "type" => "node",
            "id" => 123,
            "lat" => 40.001,
            "lon" => -105.001,
            "tags" => %{"name" => "Coffee Shop", "amenity" => "cafe"}
          }
        ]
      }

      assert [result] = Overpass.parse_elements(elements, 40.0, -105.0)
      assert result.name == "Coffee Shop"
      assert result.lat == 40.001
      assert result.lon == -105.001
      assert result.osm_type == :node
      assert result.osm_id == 123
      assert result.source == :osm
      assert result.id == nil
      assert is_float(result.distance)
      assert result.distance > 0
    end

    test "parses way elements using center coordinates" do
      elements = %{
        "elements" => [
          %{
            "type" => "way",
            "id" => 456,
            "center" => %{"lat" => 40.002, "lon" => -105.002},
            "tags" => %{"name" => "Big Building", "tourism" => "museum"}
          }
        ]
      }

      assert [result] = Overpass.parse_elements(elements, 40.0, -105.0)
      assert result.name == "Big Building"
      assert result.osm_type == :way
      assert result.osm_id == 456
      assert result.lat == 40.002
      assert result.lon == -105.002
    end

    test "parses relation elements using center coordinates" do
      elements = %{
        "elements" => [
          %{
            "type" => "relation",
            "id" => 789,
            "center" => %{"lat" => 40.003, "lon" => -105.003},
            "tags" => %{"name" => "Park Complex", "leisure" => "park"}
          }
        ]
      }

      assert [result] = Overpass.parse_elements(elements, 40.0, -105.0)
      assert result.osm_type == :relation
      assert result.osm_id == 789
    end

    test "skips elements without a name" do
      elements = %{
        "elements" => [
          %{
            "type" => "node",
            "id" => 111,
            "lat" => 40.001,
            "lon" => -105.001,
            "tags" => %{"amenity" => "bench"}
          }
        ]
      }

      assert [] = Overpass.parse_elements(elements, 40.0, -105.0)
    end

    test "sorts results by distance" do
      elements = %{
        "elements" => [
          %{
            "type" => "node",
            "id" => 1,
            "lat" => 40.01,
            "lon" => -105.01,
            "tags" => %{"name" => "Far"}
          },
          %{
            "type" => "node",
            "id" => 2,
            "lat" => 40.001,
            "lon" => -105.001,
            "tags" => %{"name" => "Near"}
          }
        ]
      }

      results = Overpass.parse_elements(elements, 40.0, -105.0)
      assert length(results) == 2
      assert Enum.at(results, 0).name == "Near"
      assert Enum.at(results, 1).name == "Far"
    end

    test "handles empty elements" do
      assert [] = Overpass.parse_elements(%{"elements" => []}, 40.0, -105.0)
    end

    test "handles missing elements key" do
      assert [] = Overpass.parse_elements(%{}, 40.0, -105.0)
    end
  end
end
