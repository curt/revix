defmodule Revix.Workers.ProcessInboundDeleteWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.ProcessInboundDeleteWorker
  alias Revix.Entries
  alias Revix.Entries.Entry
  alias Revix.EntryPeople.EntryPerson
  alias Revix.Follows.Follow
  alias Revix.Likes
  alias Revix.Likes.Like
  alias Revix.People
  alias Revix.People.Person
  alias Revix.Repo

  import Revix.PeopleFixtures
  import Revix.EntriesFixtures

  @actor_uri "https://remote.example.com/users/alice"
  @note_uri "https://remote.example.com/users/alice/notes/abc123"

  defp remote_person_attrs(uri) do
    %{
      uri: uri,
      public_key: "fake-key",
      username: "alice",
      display_name: "Alice"
    }
  end

  defp insert_remote_person do
    {:ok, person} = People.upsert_remote_person(remote_person_attrs(@actor_uri))
    person
  end

  defp insert_remote_note(uri \\ @note_uri, actor_uri \\ @actor_uri) do
    {:ok, entry} =
      Entries.create_inbound_note(%{
        uri: uri,
        url: uri,
        author_uri: actor_uri,
        content: "<p>Hello</p>",
        published_at_utc: ~U[2026-05-14 10:00:00Z]
      })

    entry
  end

  defp perform(object, actor_uri \\ @actor_uri) do
    perform_job(ProcessInboundDeleteWorker, %{
      "activity" => %{
        "type" => "Delete",
        "id" => "#{actor_uri}/activities/del1",
        "actor" => actor_uri,
        "object" => object
      },
      "person_id" => person_fixture().id
    })
  end

  describe "person deletion" do
    test "self-delete of remote person removes person from DB" do
      insert_remote_person()

      assert :ok = perform(@actor_uri)
      assert is_nil(Repo.get_by(Person, uri: @actor_uri))
    end

    test "cascade: entries authored by person are deleted" do
      insert_remote_person()
      insert_remote_note()

      assert :ok = perform(@actor_uri)
      assert is_nil(Repo.get_by(Entry, uri: @note_uri))
    end

    test "cascade: likes authored by person are deleted" do
      insert_remote_person()

      Likes.upsert_inbound_like(%{
        author_uri: @actor_uri,
        object_uri: "https://example.com/entries/xyz",
        like_uri: "#{@actor_uri}/likes/1"
      })

      assert :ok = perform(@actor_uri)
      assert is_nil(Repo.get_by(Like, author_uri: @actor_uri))
    end

    test "cascade: follows where person is follower are deleted" do
      insert_remote_person()

      Revix.Follows.upsert_inbound_follow(%{
        uri: "#{@actor_uri}/follows/1",
        follower_uri: @actor_uri,
        following_uri: "https://local.example.com/people/123"
      })

      assert :ok = perform(@actor_uri)
      refute Repo.exists?(from f in Follow, where: f.follower_uri == ^@actor_uri)
    end

    test "cascade: follows where person is being followed are deleted" do
      insert_remote_person()
      local = person_fixture()

      Revix.Follows.upsert_inbound_follow(%{
        uri: "#{local.uri}/follows/1",
        follower_uri: local.uri,
        following_uri: @actor_uri
      })

      assert :ok = perform(@actor_uri)
      refute Repo.exists?(from f in Follow, where: f.following_uri == ^@actor_uri)
    end

    test "cascade: entry_people rows for person are deleted" do
      insert_remote_person()
      local = person_fixture()
      checkin = checkin_fixture(%{author_uri: local.uri})

      Repo.insert!(%EntryPerson{
        id: Revix.Ecto.Base58Id.autogenerate(),
        entry_uri: checkin.uri,
        person_uri: @actor_uri,
        type: :companion,
        origin: :remote
      })

      assert :ok = perform(@actor_uri)
      refute Repo.exists?(from ep in EntryPerson, where: ep.person_uri == ^@actor_uri)
    end

    test "non-self-delete (actor != object URI) leaves person intact" do
      insert_remote_person()

      other_actor = "https://remote.example.com/users/mallory"
      assert :ok = perform(@actor_uri, other_actor)
      assert Repo.get_by(Person, uri: @actor_uri)
    end

    test "local person targeted is not deleted" do
      local = person_fixture()
      assert :ok = perform(local.uri)
      assert Repo.get_by(Person, uri: local.uri)
    end
  end

  describe "entry deletion" do
    test "hard-deletes a remote entry when object is a plain URI string" do
      insert_remote_note()

      assert :ok = perform(@note_uri)
      assert is_nil(Repo.get_by(Entry, uri: @note_uri))
    end

    test "hard-deletes a remote entry when object is a Tombstone map with id" do
      insert_remote_note()

      tombstone = %{"type" => "Tombstone", "id" => @note_uri}

      assert :ok = perform(tombstone)
      assert is_nil(Repo.get_by(Entry, uri: @note_uri))
    end

    test "returns :ok when entry not found (idempotent)" do
      assert :ok = perform(@note_uri)
    end

    test "returns :ok when actor does not match entry author_uri (no deletion)" do
      insert_remote_note()

      assert :ok = perform(@note_uri, "https://remote.example.com/users/mallory")
      assert Repo.get_by!(Entry, uri: @note_uri).origin == :remote
    end

    test "does not delete a local entry" do
      checkin = checkin_fixture()

      assert :ok = perform(checkin.uri)
      assert Repo.get_by!(Entry, uri: checkin.uri).origin == :local
    end

    test "returns :ok for unknown URI (idempotent)" do
      assert :ok = perform("https://remote.example.com/unknown/999")
    end
  end

  describe "invalid activity" do
    test "returns error when object cannot be extracted" do
      assert {:error, :invalid_activity} = perform(nil)
    end

    test "returns error when actor is nil" do
      assert {:error, :invalid_activity} =
               perform_job(ProcessInboundDeleteWorker, %{
                 "activity" => %{
                   "type" => "Delete",
                   "id" => "https://remote.example.com/activities/x",
                   "actor" => nil,
                   "object" => @note_uri
                 },
                 "person_id" => person_fixture().id
               })
    end
  end
end
