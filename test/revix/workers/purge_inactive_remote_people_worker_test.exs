defmodule Revix.Workers.PurgeInactiveRemotePeopleWorkerTest do
  use Revix.DataCase, async: true

  import Ecto.Query
  import Revix.PeopleFixtures

  alias Revix.People
  alias Revix.People.Person
  alias Revix.Entries.Entry
  alias Revix.Likes.Like
  alias Revix.EntryPeople.EntryPerson
  alias Revix.Pings.Ping
  alias Revix.Workers.PurgeInactiveRemotePeopleWorker

  defp unique_remote_uri,
    do: "https://remote.example.com/users/#{System.unique_integer([:positive])}"

  defp create_remote_person do
    {:ok, person} = People.upsert_remote_person(%{uri: unique_remote_uri()})
    person
  end

  defp backdate_person(person, hours_ago) do
    past = DateTime.add(DateTime.utc_now(), -hours_ago * 3_600, :second)
    Repo.update_all(from(p in Person, where: p.id == ^person.id), set: [inserted_at: past])
  end

  defp insert_entry(author_uri) do
    id = Revix.Ecto.Base58Id.autogenerate()
    now = DateTime.utc_now(:second)

    Repo.insert!(%Entry{
      id: id,
      uri: "https://remote.example.com/notes/#{id}",
      url: "https://remote.example.com/notes/#{id}",
      type: :note,
      origin: :remote,
      author_uri: author_uri,
      published_at_utc: now,
      published_at_local: DateTime.to_naive(now),
      published_tz: "UTC"
    })
  end

  defp insert_like(author_uri, opts \\ []) do
    id = Revix.Ecto.Base58Id.autogenerate()
    now = DateTime.utc_now(:second)

    Repo.insert!(%Like{
      id: id,
      like_uri: "https://remote.example.com/likes/#{id}",
      author_uri: author_uri,
      object_uri: "https://example.com/entries/some-entry",
      origin: :remote,
      published_at_utc: now,
      published_at_local: DateTime.to_naive(now),
      published_tz: "UTC",
      unliked_at: Keyword.get(opts, :unliked_at)
    })
  end

  defp insert_entry_person(person_uri) do
    id = Revix.Ecto.Base58Id.autogenerate()

    Repo.insert!(%EntryPerson{
      id: id,
      entry_uri: "https://example.com/entries/some-entry",
      person_uri: person_uri,
      type: :companion,
      origin: :remote
    })
  end

  defp insert_ping(actor_uri) do
    id = Revix.Ecto.Base58Id.autogenerate()

    Repo.insert!(%Ping{
      id: id,
      uri: "https://remote.example.com/pings/#{id}",
      type: :ping,
      direction: :inbound,
      actor_uri: actor_uri,
      target_uri: "https://localhost:4000/people/somelocalperson",
      status: :delivered
    })
  end

  describe "perform/1" do
    test "deletes old remote person with no activity" do
      person = create_remote_person()
      backdate_person(person, 25)

      assert :ok = perform_job(PurgeInactiveRemotePeopleWorker, %{})

      refute Repo.get(Person, person.id)
    end

    test "does not delete old remote person who authored an entry" do
      person = create_remote_person()
      insert_entry(person.uri)
      backdate_person(person, 25)

      assert :ok = perform_job(PurgeInactiveRemotePeopleWorker, %{})

      assert Repo.get(Person, person.id)
    end

    test "does not delete old remote person with an active like" do
      person = create_remote_person()
      insert_like(person.uri)
      backdate_person(person, 25)

      assert :ok = perform_job(PurgeInactiveRemotePeopleWorker, %{})

      assert Repo.get(Person, person.id)
    end

    test "does not delete old remote person with only an unliked like" do
      person = create_remote_person()
      insert_like(person.uri, unliked_at: DateTime.utc_now(:second))
      backdate_person(person, 25)

      assert :ok = perform_job(PurgeInactiveRemotePeopleWorker, %{})

      assert Repo.get(Person, person.id)
    end

    test "does not delete old remote person tagged as companion" do
      person = create_remote_person()
      insert_entry_person(person.uri)
      backdate_person(person, 25)

      assert :ok = perform_job(PurgeInactiveRemotePeopleWorker, %{})

      assert Repo.get(Person, person.id)
    end

    test "does not delete old remote person who sent a ping" do
      person = create_remote_person()
      insert_ping(person.uri)
      backdate_person(person, 25)

      assert :ok = perform_job(PurgeInactiveRemotePeopleWorker, %{})

      assert Repo.get(Person, person.id)
    end

    test "does not delete remote person within grace period with no activity" do
      person = create_remote_person()

      assert :ok = perform_job(PurgeInactiveRemotePeopleWorker, %{})

      assert Repo.get(Person, person.id)
    end

    test "does not delete local person with no activity past threshold" do
      person = unconfirmed_person_fixture()

      past = DateTime.add(DateTime.utc_now(), -25 * 3_600, :second)
      Repo.update_all(from(p in Person, where: p.id == ^person.id), set: [inserted_at: past])

      assert :ok = perform_job(PurgeInactiveRemotePeopleWorker, %{})

      assert Repo.get(Person, person.id)
    end

    test "purges only inactive old remote people among mixed set" do
      active = create_remote_person()
      insert_entry(active.uri)
      backdate_person(active, 25)

      inactive_old = create_remote_person()
      backdate_person(inactive_old, 25)

      inactive_recent = create_remote_person()

      assert :ok = perform_job(PurgeInactiveRemotePeopleWorker, %{})

      assert Repo.get(Person, active.id)
      refute Repo.get(Person, inactive_old.id)
      assert Repo.get(Person, inactive_recent.id)
    end
  end
end
