defmodule Revix.WebfingerTest do
  use Revix.DataCase, async: true

  import Ecto.Query
  alias Revix.Webfinger
  import Revix.PeopleFixtures

  defp person_with_username do
    person = person_fixture()
    username = "user#{System.unique_integer([:positive])}"

    Revix.Repo.update_all(
      from(p in Revix.People.Person, where: p.id == ^person.id),
      set: [username: username]
    )

    %{person | username: username}
  end

  describe "get_webfinger/2" do
    test "returns person and canonical resource for valid acct:name@host" do
      person = person_with_username()
      resource = "acct:#{person.username}@localhost"

      assert {:ok, {returned_person, canonical}} = Webfinger.get_webfinger(resource, "localhost")
      assert returned_person.id == person.id
      assert canonical == resource
    end

    test "accepts bare acct:name without host" do
      person = person_with_username()
      resource = "acct:#{person.username}"

      assert {:ok, {returned_person, _canonical}} = Webfinger.get_webfinger(resource, "localhost")
      assert returned_person.id == person.id
    end

    test "returns bad_request when resource has no acct: prefix" do
      assert {:error, :bad_request} =
               Webfinger.get_webfinger("https://example.com/alice", "localhost")
    end

    test "returns bad_request when host does not match" do
      person = person_with_username()
      resource = "acct:#{person.username}@wrong.host"

      assert {:error, :bad_request} = Webfinger.get_webfinger(resource, "localhost")
    end

    test "returns not_found when person does not exist" do
      assert {:error, :not_found} = Webfinger.get_webfinger("acct:nobody@localhost", "localhost")
    end
  end
end
