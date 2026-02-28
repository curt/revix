defmodule Revix.PlacesTest do
  use Revix.DataCase

  alias Revix.Places
  alias Revix.Places.Place

  import Revix.PlacesFixtures
  import Revix.PeopleFixtures
  import Revix.EntriesFixtures
  import RevixWeb.CanonicalRoutes

  describe "get_local_places/0" do
    test "returns local places ordered by name" do
      zulu = place_fixture(%{name: "Zulu Cafe"})
      alpha = place_fixture(%{name: "Alpha Bakery"})

      assert [first, second] = Places.get_local_places()
      assert first.id == alpha.id
      assert second.id == zulu.id
    end

    test "excludes remote places" do
      place_fixture(%{origin: :remote})

      assert [] = Places.get_local_places()
    end

    test "returns empty list when no places exist" do
      assert [] = Places.get_local_places()
    end
  end

  describe "get_local_places_near/2" do
    test "returns nearby local places ordered by distance" do
      # Denver, CO
      origin =
        place_fixture(%{coordinates: %Geo.Point{coordinates: {-104.9903, 39.7392}, srid: 4326}})

      # Boulder, CO (~40km away)
      boulder =
        place_fixture(%{
          name: "Boulder",
          coordinates: %Geo.Point{coordinates: {-105.2705, 40.0150}, srid: 4326}
        })

      # Golden, CO (~20km away)
      golden =
        place_fixture(%{
          name: "Golden",
          coordinates: %Geo.Point{coordinates: {-105.2211, 39.7555}, srid: 4326}
        })

      results = Places.get_local_places_near(origin, radius: 50_000)
      assert length(results) == 2
      assert Enum.at(results, 0).place.id == golden.id
      assert Enum.at(results, 1).place.id == boulder.id
    end

    test "excludes the origin place from results" do
      origin = place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})

      assert [] = Places.get_local_places_near(origin)
    end

    test "excludes places beyond the radius" do
      origin =
        place_fixture(%{coordinates: %Geo.Point{coordinates: {-104.9903, 39.7392}, srid: 4326}})

      # New York (~2600km away)
      place_fixture(%{coordinates: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}})

      assert [] = Places.get_local_places_near(origin, radius: 50_000)
    end

    test "excludes remote places" do
      origin = place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})

      place_fixture(%{
        origin: :remote,
        coordinates: %Geo.Point{coordinates: {-105.001, 40.001}, srid: 4326}
      })

      assert [] = Places.get_local_places_near(origin)
    end

    test "respects the limit option" do
      origin = place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})
      place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.001, 40.001}, srid: 4326}})
      place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.002, 40.002}, srid: 4326}})

      results = Places.get_local_places_near(origin, limit: 1)
      assert length(results) == 1
    end

    test "includes distance in results" do
      origin = place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})
      place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.001, 40.001}, srid: 4326}})

      assert [result] = Places.get_local_places_near(origin)
      assert is_float(result.distance)
      assert result.distance > 0
    end
  end

  describe "get_local_place/1" do
    test "returns ok with the place for a valid id" do
      place = place_fixture()

      assert {:ok, %Place{} = found} = Places.get_local_place(place.id)
      assert found.id == place.id
    end

    test "returns error not_found for nonexistent id" do
      assert {:error, :not_found} = Places.get_local_place("11111111111")
    end

    test "returns error not_found for a remote place" do
      place = place_fixture(%{origin: :remote})

      assert {:error, :not_found} = Places.get_local_place(place.id)
    end
  end

  describe "create_local_place/1" do
    test "creates a local place with valid attributes" do
      attrs = %{"name" => "New Coffee Shop", "latitude" => 40.0, "longitude" => -105.0}

      assert {:ok, %Place{} = place} =
               Places.create_local_place(attrs, &place_uri/1, &place_url/2)

      assert place.name == "New Coffee Shop"
      assert place.origin == :local
      assert place.slug == "new-coffee-shop"
      assert place.coordinates == %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
      assert String.length(place.id) == 11
      assert place.uri =~ "/places/#{place.id}"
      assert place.url =~ "/places/#{place.id}/new-coffee-shop"
    end

    test "creates a place with OSM fields" do
      attrs = %{
        "name" => "Museum",
        "latitude" => 48.8566,
        "longitude" => 2.3522,
        "osm_type" => :node,
        "osm_id" => 98765
      }

      assert {:ok, %Place{} = place} =
               Places.create_local_place(attrs, &place_uri/1, &place_url/2)

      assert place.osm_type == :node
      assert place.osm_id == 98765
    end

    test "returns error changeset with invalid attributes" do
      assert {:error, changeset} =
               Places.create_local_place(%{"name" => ""}, &place_uri/1, &place_url/2)

      assert "can't be blank" in errors_on(changeset).name
    end
  end

  describe "change_place/1" do
    test "returns a changeset" do
      changeset = Places.change_place(%{"name" => "Test"})
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "get_local_place_by_osm/2" do
    test "returns a place matching OSM type and id" do
      place = place_fixture(%{osm_type: :node, osm_id: 12345})

      found = Places.get_local_place_by_osm(:node, 12345)
      assert found.id == place.id
    end

    test "returns nil when no match" do
      assert Places.get_local_place_by_osm(:node, 99999) == nil
    end
  end

  describe "get_local_place_by_uri/1" do
    test "returns ok with the place for a valid uri" do
      place = place_fixture()

      assert {:ok, %Place{} = found} = Places.get_local_place_by_uri(place.uri)
      assert found.id == place.id
    end

    test "returns error not_found for nonexistent uri" do
      assert {:error, :not_found} =
               Places.get_local_place_by_uri("https://example.com/places/nope")
    end

    test "returns error not_found for a remote place uri" do
      place = place_fixture(%{origin: :remote})

      assert {:error, :not_found} = Places.get_local_place_by_uri(place.uri)
    end
  end

  describe "get_places_for_person/1" do
    test "returns only places the person checked in to" do
      person = person_fixture()
      place = place_fixture()
      checkin_fixture(%{author_uri: person.uri, place_uri: place.uri})

      assert [found] = Places.get_places_for_person(person)
      assert found.id == place.id
    end

    test "returns empty list when person has no checkins" do
      person = person_fixture()
      assert [] = Places.get_places_for_person(person)
    end

    test "excludes places checked in to only by other people" do
      person = person_fixture()
      other_person = person_fixture()
      place = place_fixture()
      checkin_fixture(%{author_uri: other_person.uri, place_uri: place.uri})

      assert [] = Places.get_places_for_person(person)
    end

    test "excludes remote checkins (non-local origin)" do
      person = person_fixture()
      place = place_fixture()

      # Insert a remote-origin checkin directly via the fixture override
      checkin_fixture(%{author_uri: person.uri, place_uri: place.uri, origin: :remote})

      assert [] = Places.get_places_for_person(person)
    end

    test "returns each place at most once even with multiple checkins there" do
      person = person_fixture()
      place = place_fixture()
      checkin_fixture(%{author_uri: person.uri, place_uri: place.uri})
      checkin_fixture(%{author_uri: person.uri, place_uri: place.uri})

      assert [_single] = Places.get_places_for_person(person)
    end
  end
end
