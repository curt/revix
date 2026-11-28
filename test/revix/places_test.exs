defmodule Revix.PlacesTest do
  use Revix.DataCase

  alias Revix.Places
  alias Revix.Places.Place
  alias Revix.Repo
  alias Revix.EntryPlaces.EntryPlace

  import Revix.PlacesFixtures
  import Revix.PeopleFixtures
  import Revix.EntriesFixtures
  import RevixWeb.CanonicalRoutes

  defp listed_place_fixture(attrs \\ %{}) do
    place = place_fixture(attrs)
    checkin_fixture(%{place_uri: place.uri})
    place
  end

  defp attach_post(place, attrs \\ %{}) do
    post = post_fixture(attrs)
    Repo.insert!(%EntryPlace{entry_uri: post.uri, place_uri: place.uri})
    post
  end

  describe "get_local_places/0" do
    test "returns local places ordered by name" do
      zulu = listed_place_fixture(%{name: "Zulu Cafe"})
      alpha = listed_place_fixture(%{name: "Alpha Bakery"})

      assert [first, second] = Places.get_local_places()
      assert first.id == alpha.id
      assert second.id == zulu.id
    end

    test "excludes remote places" do
      listed_place_fixture(%{origin: :remote})

      assert [] = Places.get_local_places()
    end

    test "returns empty list when no places exist" do
      assert [] = Places.get_local_places()
    end

    test "excludes places with no checkins or posts" do
      place_fixture()

      assert [] = Places.get_local_places()
    end

    test "returns a place once even with several checkins and posts" do
      place = listed_place_fixture()
      checkin_fixture(%{place_uri: place.uri})
      attach_post(place)

      assert [found] = Places.get_local_places()
      assert found.id == place.id
    end

    test "includes a place that only has a published post" do
      place = place_fixture()
      attach_post(place)

      assert [found] = Places.get_local_places()
      assert found.id == place.id
    end

    test "excludes a place whose only checkin is a draft" do
      place = place_fixture()

      checkin_fixture(%{
        place_uri: place.uri,
        published_at_utc: nil,
        published_at_local: nil,
        published_tz: nil
      })

      assert [] = Places.get_local_places()
    end

    test "excludes a place whose only checkin is tombstoned" do
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri, tombstoned_at: DateTime.utc_now(:second)})

      assert [] = Places.get_local_places()
    end

    test "excludes a place whose only checkin is remote" do
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri, origin: :remote})

      assert [] = Places.get_local_places()
    end

    test "excludes a place whose only entry is a comment" do
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri, type: :note})

      assert [] = Places.get_local_places()
    end

    test "excludes a place whose only post is a draft" do
      place = place_fixture()
      draft = draft_post_fixture()
      Repo.insert!(%EntryPlace{entry_uri: draft.uri, place_uri: place.uri})

      assert [] = Places.get_local_places()
    end

    test "excludes a place whose only post is tombstoned" do
      place = place_fixture()
      attach_post(place, %{tombstoned_at: DateTime.utc_now(:second)})

      assert [] = Places.get_local_places()
    end

    test "excludes a place whose only post is remote" do
      place = place_fixture()
      attach_post(place, %{origin: :remote})

      assert [] = Places.get_local_places()
    end

    test "excludes a place linked through entry_places to a checkin" do
      place = place_fixture()
      other = place_fixture()
      checkin = checkin_fixture(%{place_uri: other.uri})
      Repo.insert!(%EntryPlace{entry_uri: checkin.uri, place_uri: place.uri})

      assert [found] = Places.get_local_places()
      assert found.id == other.id
    end
  end

  describe "get_local_places_for_sitemap/0" do
    test "returns only places with checkins or posts" do
      listed = listed_place_fixture()
      place_fixture()

      assert [found] = Places.get_local_places_for_sitemap()
      assert found.id == listed.id
    end
  end

  describe "search_nearby_db/3" do
    test "returns local places with no preferred name" do
      place =
        place_fixture(%{
          name: "Corner Cafe",
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      assert [result] = Places.search_nearby_db(40.0, -105.0, 50.0)
      assert result.id == place.id
      assert result.source == :db
      assert result.name == "Corner Cafe"
      assert Map.has_key?(result, :preferred_name)
      assert result.preferred_name == nil
    end
  end

  describe "get_local_places_near/2" do
    test "returns nearby local places ordered by distance" do
      # Denver, CO
      origin =
        place_fixture(%{coordinates: %Geo.Point{coordinates: {-104.9903, 39.7392}, srid: 4326}})

      # Boulder, CO (~40km away)
      boulder =
        listed_place_fixture(%{
          name: "Boulder",
          coordinates: %Geo.Point{coordinates: {-105.2705, 40.0150}, srid: 4326}
        })

      # Golden, CO (~20km away)
      golden =
        listed_place_fixture(%{
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
      listed_place_fixture(%{
        coordinates: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326}
      })

      assert [] = Places.get_local_places_near(origin, radius: 50_000)
    end

    test "excludes remote places" do
      origin = place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})

      listed_place_fixture(%{
        origin: :remote,
        coordinates: %Geo.Point{coordinates: {-105.001, 40.001}, srid: 4326}
      })

      assert [] = Places.get_local_places_near(origin)
    end

    test "respects the limit option" do
      origin = place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})

      listed_place_fixture(%{
        coordinates: %Geo.Point{coordinates: {-105.001, 40.001}, srid: 4326}
      })

      listed_place_fixture(%{
        coordinates: %Geo.Point{coordinates: {-105.002, 40.002}, srid: 4326}
      })

      results = Places.get_local_places_near(origin, limit: 1)
      assert length(results) == 1
    end

    test "includes distance in results" do
      origin = place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})

      listed_place_fixture(%{
        coordinates: %Geo.Point{coordinates: {-105.001, 40.001}, srid: 4326}
      })

      assert [result] = Places.get_local_places_near(origin)
      assert is_float(result.distance)
      assert result.distance > 0
    end

    test "excludes places with no checkins or posts" do
      origin = place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})
      place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.001, 40.001}, srid: 4326}})

      assert [] = Places.get_local_places_near(origin)
    end

    test "includes unlisted places when include_unlisted is true" do
      origin = place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})

      unlisted =
        place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.001, 40.001}, srid: 4326}})

      assert [result] = Places.get_local_places_near(origin, include_unlisted: true)
      assert result.place.id == unlisted.id
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

    test "returns error not_found for a malformed id" do
      assert {:error, :not_found} = Places.get_local_place("not-valid-id")
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

    test "stores the country and city given on create" do
      attrs = %{
        "name" => "Desert Cafe",
        "latitude" => 33.5,
        "longitude" => -111.9,
        "country" => "us",
        "city" => "scottsdale"
      }

      assert {:ok, place} = Places.create_local_place(attrs, &place_uri/1, &place_url/2)
      assert {place.country, place.city} == {"us", "scottsdale"}
    end

    test "rejects a city without a country on create, as the form says" do
      attrs = %{"name" => "Nowhere", "latitude" => 1.0, "longitude" => 1.0, "city" => "x"}

      assert {:error, changeset} = Places.create_local_place(attrs, &place_uri/1, &place_url/2)
      refute changeset.valid?
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

  describe "update_local_place/6" do
    defp place_uri_fn(place), do: place_uri(place)
    defp place_url_fn(place), do: place_url(place)
    defp checkin_uri_fn(checkin), do: checkin_uri(checkin)
    defp checkin_url_fn(checkin), do: checkin_url(checkin)

    test "updates the name and regenerates the slug" do
      place = place_fixture(%{name: "Old Name"})

      assert {:ok, updated} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => "New Name",
                   "latitude" => 40.0,
                   "longitude" => -105.0
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert updated.name == "New Name"
      assert updated.slug == "new-name"
    end

    test "updates coordinates" do
      place = place_fixture()

      assert {:ok, updated} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => place.name,
                   "latitude" => 51.5,
                   "longitude" => -0.1
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert updated.coordinates == %Geo.Point{coordinates: {-0.1, 51.5}, srid: 4326}
    end

    test "updates osm_type and osm_id" do
      place = place_fixture()

      assert {:ok, updated} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => place.name,
                   "latitude" => 40.0,
                   "longitude" => -105.0,
                   "osm_type" => "relation",
                   "osm_id" => "77777"
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert updated.osm_type == :relation
      assert updated.osm_id == 77_777
    end

    test "does not change uri or origin" do
      place = place_fixture()
      original_uri = place.uri

      assert {:ok, updated} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => "Updated",
                   "latitude" => 40.0,
                   "longitude" => -105.0
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert updated.uri == original_uri
      assert updated.origin == :local
    end

    test "updates place url when name changes" do
      place = place_fixture(%{name: "Old Name", slug: "old-name"})

      assert {:ok, updated} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => "New Name",
                   "latitude" => 40.0,
                   "longitude" => -105.0
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert updated.url =~ "new-name"
      refute updated.url =~ "old-name"
    end

    test "updates place url when country is added" do
      place = place_fixture(%{name: "The Place", slug: "the-place"})

      assert {:ok, updated} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => place.name,
                   "latitude" => 40.0,
                   "longitude" => -105.0,
                   "country" => "us"
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert updated.url =~ "/us/the-place"
    end

    test "updates place url with country and city" do
      place = place_fixture(%{name: "The Place", slug: "the-place"})

      assert {:ok, updated} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => place.name,
                   "latitude" => 40.0,
                   "longitude" => -105.0,
                   "country" => "us",
                   "city" => "phoenix"
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert updated.url =~ "/us/phoenix/the-place"
    end

    test "updates place url with all three situation fields" do
      place = place_fixture(%{name: "The Place", slug: "the-place"})

      assert {:ok, updated} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => place.name,
                   "latitude" => 40.0,
                   "longitude" => -105.0,
                   "country" => "us",
                   "city" => "phoenix",
                   "secondary" => "az"
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert updated.url =~ "/us/az/phoenix/the-place"
    end

    test "updates checkin urls when place slug changes" do
      place = place_fixture(%{slug: "old-name"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      assert {:ok, _updated_place} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => "New Name",
                   "latitude" => 40.0,
                   "longitude" => -105.0
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      updated_checkin = Repo.reload(checkin)
      assert updated_checkin.url =~ "new-name"
      refute updated_checkin.url =~ "old-name"
    end

    test "updates checkin urls when country is added to place" do
      place = place_fixture(%{name: "The Place", slug: "the-place"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      assert {:ok, _} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => place.name,
                   "latitude" => 40.0,
                   "longitude" => -105.0,
                   "country" => "us"
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      updated_checkin = Repo.reload(checkin)
      assert updated_checkin.url =~ "/us/the-place"
    end

    test "updates checkin updated_at when url changes" do
      place = place_fixture(%{name: "The Place", slug: "the-place"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      assert {:ok, updated_place} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => place.name,
                   "latitude" => 40.0,
                   "longitude" => -105.0,
                   "country" => "us"
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert Repo.reload(checkin).updated_at == updated_place.updated_at
    end

    test "does not update checkin updated_at when url does not change" do
      place = place_fixture(%{name: "The Place", slug: "the-place"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      original_updated_at = checkin.updated_at

      assert {:ok, _} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => place.name,
                   "latitude" => 51.5,
                   "longitude" => -0.1
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert Repo.reload(checkin).updated_at == original_updated_at
    end

    test "does not update checkin urls when only coordinates change" do
      place = place_fixture(%{name: "The Place", slug: "the-place"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      original_checkin_url = checkin.url

      assert {:ok, _} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => place.name,
                   "latitude" => 51.5,
                   "longitude" => -0.1
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert Repo.reload(checkin).url == original_checkin_url
    end

    test "does not update checkin urls when only osm fields change" do
      place = place_fixture(%{name: "The Place", slug: "the-place"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      original_checkin_url = checkin.url

      assert {:ok, _} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => place.name,
                   "latitude" => 40.0,
                   "longitude" => -105.0,
                   "osm_type" => "node",
                   "osm_id" => "99999"
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert Repo.reload(checkin).url == original_checkin_url
    end

    test "does not update checkins at a different place" do
      place_a = place_fixture(%{slug: "place-a"})
      place_b = place_fixture(%{slug: "place-b"})
      checkin_b = checkin_fixture(%{place_uri: place_b.uri})
      original_checkin_b_url = checkin_b.url

      assert {:ok, _} =
               Places.update_local_place(
                 place_a,
                 %{
                   "name" => "Place A Updated",
                   "latitude" => 40.0,
                   "longitude" => -105.0
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert Repo.reload(checkin_b).url == original_checkin_b_url
    end

    test "returns error changeset for blank name" do
      place = place_fixture()

      assert {:error, changeset} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => "",
                   "latitude" => 40.0,
                   "longitude" => -105.0
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert "can't be blank" in errors_on(changeset).name
    end

    test "returns error changeset for out-of-range coordinates" do
      place = place_fixture()

      assert {:error, changeset} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => "Test",
                   "latitude" => 91.0,
                   "longitude" => -105.0
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert errors_on(changeset).latitude != []
    end

    test "on error, does not update checkin urls" do
      place = place_fixture(%{slug: "the-place"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      original_url = checkin.url

      assert {:error, _changeset} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => "",
                   "latitude" => 40.0,
                   "longitude" => -105.0
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert Repo.reload(checkin).url == original_url
    end

    test "explicit slug in attrs overrides auto-generated slug from name" do
      place = place_fixture(%{name: "Old Name", slug: "old-name"})

      assert {:ok, updated} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => "New Name",
                   "latitude" => 40.0,
                   "longitude" => -105.0,
                   "slug" => "custom-slug"
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert updated.slug == "custom-slug"
      assert updated.url =~ "custom-slug"
    end

    test "updates checkin urls when slug is explicitly changed" do
      place = place_fixture(%{name: "The Place", slug: "the-place"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      assert {:ok, _} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => place.name,
                   "latitude" => 40.0,
                   "longitude" => -105.0,
                   "slug" => "renamed-place"
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      updated_checkin = Repo.reload(checkin)
      assert updated_checkin.url =~ "renamed-place"
      refute updated_checkin.url =~ "the-place"
    end

    test "returns error changeset for invalid slug" do
      place = place_fixture(%{name: "The Place", slug: "the-place"})

      assert {:error, changeset} =
               Places.update_local_place(
                 place,
                 %{
                   "name" => place.name,
                   "latitude" => 40.0,
                   "longitude" => -105.0,
                   "slug" => "Invalid Slug!"
                 },
                 &place_uri_fn/1,
                 &place_url_fn/1,
                 &checkin_uri_fn/1,
                 &checkin_url_fn/1
               )

      assert "use only lowercase letters, digits, and hyphens" in errors_on(changeset).slug
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
    test "returns places with no checkins or posts" do
      place = place_fixture(%{name: "Unlisted Nook"})

      assert [found] = Places.search_local_places("Nook")
      assert found.id == place.id
    end

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

  describe "upsert_remote_place/1" do
    test "creates a new remote place when URI is new" do
      attrs = %{
        uri: "https://remote.example/places/1",
        url: "https://remote.example/places/1",
        name: "Remote Cafe",
        latitude: 40.0,
        longitude: -105.0
      }

      assert {:ok, place} = Places.upsert_remote_place(attrs)
      assert place.uri == "https://remote.example/places/1"
      assert place.name == "Remote Cafe"
      assert place.origin == :remote
    end

    test "returns existing place when URI already exists" do
      attrs = %{
        uri: "https://remote.example/places/2",
        url: "https://remote.example/places/2",
        name: "Remote Bar",
        latitude: 40.1,
        longitude: -105.1
      }

      {:ok, first} = Places.upsert_remote_place(attrs)
      {:ok, second} = Places.upsert_remote_place(attrs)

      assert first.id == second.id
      assert Repo.aggregate(Place, :count) == 1
    end

    test "uses uri as url when url is not provided" do
      attrs = %{
        uri: "https://remote.example/places/3",
        name: "No URL Place",
        latitude: 40.2,
        longitude: -105.2
      }

      assert {:ok, place} = Places.upsert_remote_place(attrs)
      assert place.url == "https://remote.example/places/3"
    end

    test "returns error changeset when name is missing" do
      attrs = %{
        uri: "https://remote.example/places/4",
        latitude: 40.3,
        longitude: -105.3
      }

      assert {:error, changeset} = Places.upsert_remote_place(attrs)
      assert changeset.errors[:name]
    end

    test "returns error changeset when coordinates are missing" do
      attrs = %{
        uri: "https://remote.example/places/5",
        name: "No Coords"
      }

      assert {:error, changeset} = Places.upsert_remote_place(attrs)
      assert !!changeset.errors[:latitude] or !!changeset.errors[:longitude]
    end
  end
end

defmodule Revix.PlacesOsmSearchTest do
  use ExUnit.Case, async: false

  alias Revix.Places

  @moduletag :capture_log

  defp stub_capturing_query do
    test_pid = self()

    Req.Test.stub(:overpass, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:query, URI.decode_query(raw)["data"]})
      Req.Test.json(conn, %{"elements" => []})
    end)
  end

  describe "search_nearby_osm/3" do
    test "caps the search radius for coarse location fixes" do
      stub_capturing_query()
      assert {:ok, []} = Places.search_nearby_osm(40.0, -105.0, 50_000.0)

      assert_received {:query, query}
      assert query =~ "around:1000,"
    end

    test "pads the accuracy by 100 metres" do
      stub_capturing_query()
      Places.search_nearby_osm(40.0, -105.0, 300.0)

      assert_received {:query, query}
      assert query =~ "around:400,"
    end

    test "uses a 100 metre floor before padding" do
      stub_capturing_query()
      Places.search_nearby_osm(40.0, -105.0, 10.0)

      assert_received {:query, query}
      assert query =~ "around:200,"
    end

    test "returns an error when Overpass fails" do
      Req.Test.stub(:overpass, fn conn -> Plug.Conn.send_resp(conn, 504, "Gateway Timeout") end)

      assert {:error, :osm_unavailable} = Places.search_nearby_osm(40.0, -105.0, 100.0)
    end

    test "returns the parsed results when Overpass succeeds" do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "node",
              "id" => 1,
              "lat" => 40.0005,
              "lon" => -105.0005,
              "tags" => %{"name" => "Corner Cafe"}
            }
          ]
        })
      end)

      assert {:ok, [%{name: "Corner Cafe", osm_type: :node, osm_id: 1}]} =
               Places.search_nearby_osm(40.0, -105.0, 100.0)
    end
  end
end
