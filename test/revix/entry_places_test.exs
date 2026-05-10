defmodule Revix.EntryPlacesTest do
  use Revix.DataCase

  alias Revix.EntryPlaces

  import Revix.PlacesFixtures
  import Revix.EntriesFixtures

  describe "add_place/2" do
    test "creates an entry_place association" do
      post = post_fixture()
      place = place_fixture()

      assert {:ok, ep} = EntryPlaces.add_place(post.uri, place.uri)
      assert ep.entry_uri == post.uri
      assert ep.place_uri == place.uri
    end

    test "is idempotent — returns existing record on duplicate" do
      post = post_fixture()
      place = place_fixture()

      {:ok, first} = EntryPlaces.add_place(post.uri, place.uri)
      {:ok, second} = EntryPlaces.add_place(post.uri, place.uri)

      assert first.id == second.id
    end

    test "allows the same place on different entries" do
      post_a = post_fixture()
      post_b = post_fixture()
      place = place_fixture()

      assert {:ok, _} = EntryPlaces.add_place(post_a.uri, place.uri)
      assert {:ok, _} = EntryPlaces.add_place(post_b.uri, place.uri)
    end

    test "allows multiple places on the same entry" do
      post = post_fixture()
      place_a = place_fixture()
      place_b = place_fixture()

      assert {:ok, _} = EntryPlaces.add_place(post.uri, place_a.uri)
      assert {:ok, _} = EntryPlaces.add_place(post.uri, place_b.uri)
    end
  end

  describe "remove_place/2" do
    test "removes an existing association" do
      post = post_fixture()
      place = place_fixture()

      {:ok, _} = EntryPlaces.add_place(post.uri, place.uri)
      assert {:ok, _} = EntryPlaces.remove_place(post.uri, place.uri)
      refute EntryPlaces.place_of?(place.uri, post.uri)
    end

    test "returns :not_found when no association exists" do
      post = post_fixture()
      place = place_fixture()

      assert {:error, :not_found} = EntryPlaces.remove_place(post.uri, place.uri)
    end

    test "removing one place leaves others intact" do
      post = post_fixture()
      place_a = place_fixture()
      place_b = place_fixture()

      EntryPlaces.add_place(post.uri, place_a.uri)
      EntryPlaces.add_place(post.uri, place_b.uri)
      EntryPlaces.remove_place(post.uri, place_a.uri)

      refute EntryPlaces.place_of?(place_a.uri, post.uri)
      assert EntryPlaces.place_of?(place_b.uri, post.uri)
    end
  end

  describe "get_places_for_entry/1" do
    test "returns places in insertion order" do
      post = post_fixture()
      place_a = place_fixture()
      place_b = place_fixture()

      EntryPlaces.add_place(post.uri, place_a.uri)
      EntryPlaces.add_place(post.uri, place_b.uri)

      results = EntryPlaces.get_places_for_entry(post.uri)
      assert length(results) == 2
      assert hd(results).place_uri == place_a.uri
    end

    test "returns empty list when no places attached" do
      post = post_fixture()
      assert [] = EntryPlaces.get_places_for_entry(post.uri)
    end

    test "preloads the place association" do
      post = post_fixture()
      place = place_fixture(%{name: "Loaded Place"})
      EntryPlaces.add_place(post.uri, place.uri)

      [ep] = EntryPlaces.get_places_for_entry(post.uri)
      assert ep.place.name == "Loaded Place"
    end

    test "does not return places for other entries" do
      post_a = post_fixture()
      post_b = post_fixture()
      place = place_fixture()

      EntryPlaces.add_place(post_a.uri, place.uri)

      assert [] = EntryPlaces.get_places_for_entry(post_b.uri)
    end
  end

  describe "place_of?/2" do
    test "returns true when associated" do
      post = post_fixture()
      place = place_fixture()
      EntryPlaces.add_place(post.uri, place.uri)

      assert EntryPlaces.place_of?(place.uri, post.uri)
    end

    test "returns false when not associated" do
      post = post_fixture()
      place = place_fixture()

      refute EntryPlaces.place_of?(place.uri, post.uri)
    end

    test "returns false after removal" do
      post = post_fixture()
      place = place_fixture()
      EntryPlaces.add_place(post.uri, place.uri)
      EntryPlaces.remove_place(post.uri, place.uri)

      refute EntryPlaces.place_of?(place.uri, post.uri)
    end
  end
end
