defmodule RevixWeb.Live.EntryHelpersTest do
  use Revix.DataCase, async: true

  import Revix.PeopleFixtures
  import RevixWeb.Live.EntryHelpers

  describe "search_companions/2" do
    test "returns empty list for empty query" do
      assert search_companions("", "https://example.com/people/abc") == []
    end

    test "returns matching people for non-empty query" do
      person = person_fixture()

      {:ok, person} =
        Revix.People.update_person_display_name(person, %{display_name: "HelperTest"})

      other = person_fixture()

      results = search_companions("HelperTest", other.uri)
      uris = Enum.map(results, & &1.uri)
      assert person.uri in uris
    end

    test "excludes the person with exclude_uri" do
      person = person_fixture()

      {:ok, person} =
        Revix.People.update_person_display_name(person, %{display_name: "ExcludeMe"})

      results = search_companions("ExcludeMe", person.uri)
      uris = Enum.map(results, & &1.uri)
      refute person.uri in uris
    end
  end

  describe "normalize_person/1" do
    test "returns a map with uri, display_name, username, avatar_url" do
      person = person_fixture()
      result = normalize_person(person)

      assert result.uri == person.uri
      assert Map.has_key?(result, :display_name)
      assert Map.has_key?(result, :username)
      assert Map.has_key?(result, :avatar_url)
      assert is_binary(result.avatar_url)
    end
  end
end
