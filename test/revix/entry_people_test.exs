defmodule Revix.EntryPeopleTest do
  use Revix.DataCase, async: true

  import Revix.PeopleFixtures
  import Revix.EntriesFixtures
  import Revix.PlacesFixtures

  alias Revix.EntryPeople
  alias Revix.EntryPeople.EntryPerson

  setup do
    # author_scope: the person who owns the checkin
    author_scope = person_scope_fixture()
    place = place_fixture()
    checkin = checkin_fixture(%{place_uri: place.uri, author_uri: author_scope.person.uri})
    # companion_scope: a different person to add as companion
    companion_scope = person_scope_fixture()
    %{author_scope: author_scope, checkin: checkin, companion_scope: companion_scope}
  end

  describe "add_companion/3 self-companion prohibition" do
    test "returns {:error, :self_companion} when author adds themselves", %{
      author_scope: author_scope,
      checkin: checkin
    } do
      assert {:error, :self_companion} =
               EntryPeople.add_companion(author_scope, checkin.uri, author_scope.person.uri)
    end

    test "does not create a record on self-companion attempt", %{
      author_scope: author_scope,
      checkin: checkin
    } do
      EntryPeople.add_companion(author_scope, checkin.uri, author_scope.person.uri)
      assert EntryPeople.get_companions_for_entry(checkin.uri) == []
    end
  end

  describe "add_companion/3 authorization" do
    test "returns {:error, :not_authorized} when non-author tries to add a companion", %{
      checkin: checkin,
      companion_scope: companion_scope
    } do
      third_person = person_fixture()

      assert {:error, :not_authorized} =
               EntryPeople.add_companion(companion_scope, checkin.uri, third_person.uri)
    end

    test "allows the entry author to add a companion", %{
      author_scope: author_scope,
      checkin: checkin,
      companion_scope: companion_scope
    } do
      assert {:ok, %EntryPerson{}} =
               EntryPeople.add_companion(author_scope, checkin.uri, companion_scope.person.uri)
    end
  end

  describe "add_companion/3" do
    test "creates an entry_person record with correct fields", %{
      author_scope: author_scope,
      checkin: checkin,
      companion_scope: companion_scope
    } do
      assert {:ok, ep} =
               EntryPeople.add_companion(author_scope, checkin.uri, companion_scope.person.uri)

      assert ep.entry_uri == checkin.uri
      assert ep.person_uri == companion_scope.person.uri
      assert ep.type == :companion
      assert ep.origin == :local
    end

    test "is idempotent when companion already exists", %{
      author_scope: author_scope,
      checkin: checkin,
      companion_scope: companion_scope
    } do
      {:ok, first} =
        EntryPeople.add_companion(author_scope, checkin.uri, companion_scope.person.uri)

      {:ok, second} =
        EntryPeople.add_companion(author_scope, checkin.uri, companion_scope.person.uri)

      assert first.id == second.id
      assert length(EntryPeople.get_companions_for_entry(checkin.uri)) == 1
    end
  end

  describe "remove_companion/3" do
    test "removes the companion record (hard delete)", %{
      author_scope: author_scope,
      checkin: checkin,
      companion_scope: companion_scope
    } do
      {:ok, _} =
        EntryPeople.add_companion(author_scope, checkin.uri, companion_scope.person.uri)

      assert {:ok, %EntryPerson{}} =
               EntryPeople.remove_companion(
                 author_scope,
                 checkin.uri,
                 companion_scope.person.uri
               )

      assert EntryPeople.get_companions_for_entry(checkin.uri) == []
    end

    test "returns {:error, :not_found} when companion does not exist", %{
      author_scope: author_scope,
      checkin: checkin,
      companion_scope: companion_scope
    } do
      assert {:error, :not_found} =
               EntryPeople.remove_companion(
                 author_scope,
                 checkin.uri,
                 companion_scope.person.uri
               )
    end

    test "returns {:error, :not_authorized} when non-author tries to remove", %{
      checkin: checkin,
      companion_scope: companion_scope
    } do
      third_person = person_fixture()

      assert {:error, :not_authorized} =
               EntryPeople.remove_companion(
                 companion_scope,
                 checkin.uri,
                 third_person.uri
               )
    end
  end

  describe "companion_of?/2" do
    test "returns true when person is a companion", %{
      author_scope: author_scope,
      checkin: checkin,
      companion_scope: companion_scope
    } do
      {:ok, _} =
        EntryPeople.add_companion(author_scope, checkin.uri, companion_scope.person.uri)

      assert EntryPeople.companion_of?(companion_scope.person.uri, checkin.uri) == true
    end

    test "returns false when person is not a companion", %{
      checkin: checkin,
      companion_scope: companion_scope
    } do
      assert EntryPeople.companion_of?(companion_scope.person.uri, checkin.uri) == false
    end

    test "returns false after companion is removed", %{
      author_scope: author_scope,
      checkin: checkin,
      companion_scope: companion_scope
    } do
      {:ok, _} =
        EntryPeople.add_companion(author_scope, checkin.uri, companion_scope.person.uri)

      {:ok, _} =
        EntryPeople.remove_companion(author_scope, checkin.uri, companion_scope.person.uri)

      assert EntryPeople.companion_of?(companion_scope.person.uri, checkin.uri) == false
    end

    test "returns false for nil person_uri", %{checkin: checkin} do
      assert EntryPeople.companion_of?(nil, checkin.uri) == false
    end
  end

  describe "get_companions_for_entry/1" do
    test "returns empty list when no companions exist", %{checkin: checkin} do
      assert EntryPeople.get_companions_for_entry(checkin.uri) == []
    end

    test "returns companions with preloaded person", %{
      author_scope: author_scope,
      checkin: checkin,
      companion_scope: companion_scope
    } do
      {:ok, _} =
        EntryPeople.add_companion(author_scope, checkin.uri, companion_scope.person.uri)

      [ep] = EntryPeople.get_companions_for_entry(checkin.uri)
      assert %Revix.People.Person{} = ep.person
      assert ep.person.uri == companion_scope.person.uri
    end

    test "does not return companions of other entries", %{
      author_scope: author_scope,
      checkin: checkin,
      companion_scope: companion_scope
    } do
      place = place_fixture()

      other_checkin =
        checkin_fixture(%{place_uri: place.uri, author_uri: author_scope.person.uri})

      {:ok, _} =
        EntryPeople.add_companion(author_scope, other_checkin.uri, companion_scope.person.uri)

      assert EntryPeople.get_companions_for_entry(checkin.uri) == []
    end
  end

  describe "count_companions_by_entry_uris/1" do
    test "returns empty map for empty list" do
      assert EntryPeople.count_companions_by_entry_uris([]) == %{}
    end

    test "returns counts for entries with companions", %{
      author_scope: author_scope,
      checkin: checkin
    } do
      companion1 = person_fixture()
      companion2 = person_fixture()
      place = place_fixture()

      other_checkin =
        checkin_fixture(%{place_uri: place.uri, author_uri: author_scope.person.uri})

      {:ok, _} = EntryPeople.add_companion(author_scope, checkin.uri, companion1.uri)
      {:ok, _} = EntryPeople.add_companion(author_scope, checkin.uri, companion2.uri)
      {:ok, _} = EntryPeople.add_companion(author_scope, other_checkin.uri, companion1.uri)

      counts =
        EntryPeople.count_companions_by_entry_uris([checkin.uri, other_checkin.uri])

      assert counts[checkin.uri] == 2
      assert counts[other_checkin.uri] == 1
    end

    test "does not include entries with no companions", %{
      author_scope: author_scope,
      checkin: checkin
    } do
      place = place_fixture()

      empty_checkin =
        checkin_fixture(%{place_uri: place.uri, author_uri: author_scope.person.uri})

      companion = person_fixture()
      {:ok, _} = EntryPeople.add_companion(author_scope, checkin.uri, companion.uri)

      counts =
        EntryPeople.count_companions_by_entry_uris([checkin.uri, empty_checkin.uri])

      assert counts[checkin.uri] == 1
      refute Map.has_key?(counts, empty_checkin.uri)
    end
  end
end
