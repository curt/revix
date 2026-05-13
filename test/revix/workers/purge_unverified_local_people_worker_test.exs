defmodule Revix.Workers.PurgeUnverifiedLocalPeopleWorkerTest do
  use Revix.DataCase, async: true

  import Ecto.Query
  import Revix.PeopleFixtures

  alias Revix.People
  alias Revix.People.{Person, PersonToken}
  alias Revix.Workers.PurgeUnverifiedLocalPeopleWorker

  defp backdate_person(person, days_ago) do
    past = DateTime.add(DateTime.utc_now(), -days_ago * 86_400, :second)
    Repo.update_all(from(p in Person, where: p.id == ^person.id), set: [inserted_at: past])
  end

  describe "perform/1" do
    test "deletes unconfirmed local person past grace period" do
      person = unconfirmed_person_fixture()
      backdate_person(person, 8)

      assert :ok = perform_job(PurgeUnverifiedLocalPeopleWorker, %{})

      refute Repo.get(Person, person.id)
    end

    test "does not delete confirmed local person past grace period" do
      person = person_fixture()
      backdate_person(person, 8)

      assert :ok = perform_job(PurgeUnverifiedLocalPeopleWorker, %{})

      assert Repo.get(Person, person.id)
    end

    test "does not delete unconfirmed local person within grace period" do
      person = unconfirmed_person_fixture()

      assert :ok = perform_job(PurgeUnverifiedLocalPeopleWorker, %{})

      assert Repo.get(Person, person.id)
    end

    test "does not delete remote person with no confirmed_at past grace period" do
      {:ok, person} =
        People.upsert_remote_person(%{uri: "https://remote.example.com/users/alice"})

      backdate_person(person, 8)

      assert :ok = perform_job(PurgeUnverifiedLocalPeopleWorker, %{})

      assert Repo.get(Person, person.id)
    end

    test "deletes associated tokens when person is deleted" do
      person = unconfirmed_person_fixture()
      People.generate_person_session_token(person)
      assert Repo.get_by(PersonToken, person_id: person.id)

      backdate_person(person, 8)

      assert :ok = perform_job(PurgeUnverifiedLocalPeopleWorker, %{})

      refute Repo.get(Person, person.id)
      refute Repo.get_by(PersonToken, person_id: person.id)
    end

    test "purges only eligible people and returns correct count" do
      old1 = unconfirmed_person_fixture()
      old2 = unconfirmed_person_fixture()
      recent = unconfirmed_person_fixture()

      backdate_person(old1, 8)
      backdate_person(old2, 8)

      assert :ok = perform_job(PurgeUnverifiedLocalPeopleWorker, %{})

      refute Repo.get(Person, old1.id)
      refute Repo.get(Person, old2.id)
      assert Repo.get(Person, recent.id)
    end
  end
end
