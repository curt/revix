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

  describe "change_place_for_edit/1" do
    test "returns a valid changeset pre-populated with the place's name" do
      place = place_fixture(%{name: "Original Name"})
      changeset = Places.change_place_for_edit(place)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :name) == "Original Name"
    end

    test "pre-populates latitude and longitude from coordinates" do
      place =
        place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})

      changeset = Places.change_place_for_edit(place)
      assert Ecto.Changeset.get_field(changeset, :latitude) == 40.0
      assert Ecto.Changeset.get_field(changeset, :longitude) == -105.0
    end

    test "pre-populates osm_type and osm_id when present" do
      place = place_fixture(%{osm_type: :way, osm_id: 54321})
      changeset = Places.change_place_for_edit(place)
      assert Ecto.Changeset.get_field(changeset, :osm_type) == :way
      assert Ecto.Changeset.get_field(changeset, :osm_id) == 54321
    end

    test "handles nil osm_type and osm_id" do
      place = place_fixture()
      changeset = Places.change_place_for_edit(place)
      assert Ecto.Changeset.get_field(changeset, :osm_type) == nil
      assert Ecto.Changeset.get_field(changeset, :osm_id) == nil
    end
  end

  describe "update_local_place/2" do
    test "updates the name and regenerates the slug" do
      place = place_fixture(%{name: "Old Name"})

      assert {:ok, updated} =
               Places.update_local_place(place, %{
                 "name" => "New Name",
                 "latitude" => 40.0,
                 "longitude" => -105.0
               })

      assert updated.name == "New Name"
      assert updated.slug == "new-name"
    end

    test "updates coordinates" do
      place = place_fixture()

      assert {:ok, updated} =
               Places.update_local_place(place, %{
                 "name" => place.name,
                 "latitude" => 51.5,
                 "longitude" => -0.1
               })

      assert updated.coordinates == %Geo.Point{coordinates: {-0.1, 51.5}, srid: 4326}
    end

    test "updates osm_type and osm_id" do
      place = place_fixture()

      assert {:ok, updated} =
               Places.update_local_place(place, %{
                 "name" => place.name,
                 "latitude" => 40.0,
                 "longitude" => -105.0,
                 "osm_type" => "relation",
                 "osm_id" => "77777"
               })

      assert updated.osm_type == :relation
      assert updated.osm_id == 77_777
    end

    test "does not change uri, url, or origin" do
      place = place_fixture()
      original_uri = place.uri
      original_url = place.url

      assert {:ok, updated} =
               Places.update_local_place(place, %{
                 "name" => "Updated",
                 "latitude" => 40.0,
                 "longitude" => -105.0
               })

      assert updated.uri == original_uri
      assert updated.url == original_url
      assert updated.origin == :local
    end

    test "returns error changeset for blank name" do
      place = place_fixture()

      assert {:error, changeset} =
               Places.update_local_place(place, %{
                 "name" => "",
                 "latitude" => 40.0,
                 "longitude" => -105.0
               })

      assert "can't be blank" in errors_on(changeset).name
    end

    test "returns error changeset for out-of-range coordinates" do
      place = place_fixture()

      assert {:error, changeset} =
               Places.update_local_place(place, %{
                 "name" => "Test",
                 "latitude" => 91.0,
                 "longitude" => -105.0
               })

      assert errors_on(changeset).latitude != []
    end
  end

  describe "unlink_place_osm/1" do
    test "sets osm_type and osm_id to nil" do
      place = place_fixture(%{osm_type: :node, osm_id: 11111})

      assert {:ok, updated} = Places.unlink_place_osm(place)
      assert updated.osm_type == nil
      assert updated.osm_id == nil
    end

    test "succeeds when osm fields are already nil" do
      place = place_fixture()

      assert {:ok, updated} = Places.unlink_place_osm(place)
      assert updated.osm_type == nil
      assert updated.osm_id == nil
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

  describe "search_local_places/1" do
    test "returns places matching the query" do
      place_fixture(%{name: "Blue Bottle Coffee"})
      results = Places.search_local_places("Blue")
      assert length(results) == 1
      assert hd(results).name == "Blue Bottle Coffee"
    end

    test "is case-insensitive" do
      place_fixture(%{name: "Blue Bottle Coffee"})
      assert [_] = Places.search_local_places("blue")
      assert [_] = Places.search_local_places("BLUE")
    end

    test "matches mid-string" do
      place_fixture(%{name: "Blue Bottle Coffee"})
      assert [_] = Places.search_local_places("Bottle")
    end

    test "returns empty list when no places match" do
      place_fixture(%{name: "Blue Bottle Coffee"})
      assert [] = Places.search_local_places("Zzzz")
    end

    test "limits results to 10" do
      for i <- 1..12, do: place_fixture(%{name: "Cafe #{i}"})
      results = Places.search_local_places("Cafe")
      assert length(results) == 10
    end

    test "returns results ordered by name" do
      place_fixture(%{name: "Zebra Cafe"})
      place_fixture(%{name: "Alpha Cafe"})
      [first | _] = Places.search_local_places("Cafe")
      assert first.name == "Alpha Cafe"
    end
  end
end
