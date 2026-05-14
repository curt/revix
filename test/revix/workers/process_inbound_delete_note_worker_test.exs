defmodule Revix.Workers.ProcessInboundDeleteNoteWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.ProcessInboundDeleteNoteWorker
  alias Revix.Entries
  alias Revix.Entries.Entry

  import Revix.PeopleFixtures
  import Revix.EntriesFixtures

  @actor_uri "https://remote.example.com/users/alice"
  @note_uri "https://remote.example.com/users/alice/notes/abc123"

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
    perform_job(ProcessInboundDeleteNoteWorker, %{
      "activity" => %{
        "type" => "Delete",
        "id" => "#{actor_uri}/activities/del1",
        "actor" => actor_uri,
        "object" => object
      },
      "person_id" => person_fixture().id
    })
  end

  describe "perform/1" do
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

    test "returns :ok when actor does not match entry author_uri" do
      insert_remote_note()

      assert :ok = perform(@note_uri, "https://remote.example.com/users/mallory")
      assert Repo.get_by!(Entry, uri: @note_uri).origin == :remote
    end

    test "returns :ok when entry is local-origin" do
      checkin = checkin_fixture()

      assert :ok = perform(checkin.uri)
      assert Repo.get_by!(Entry, uri: checkin.uri).origin == :local
    end

    test "returns error when object URI cannot be extracted" do
      assert {:error, :invalid_activity} = perform(%{"type" => "Tombstone"})
    end

    test "returns error when object is nil" do
      assert {:error, :invalid_activity} = perform(nil)
    end

    test "broadcasts :comment_deleted when entry is deleted" do
      insert_remote_note()
      checkin = checkin_fixture()

      {:ok, note_with_context} =
        Entries.create_inbound_note(%{
          uri: "#{@note_uri}/ctx",
          url: "#{@note_uri}/ctx",
          author_uri: @actor_uri,
          content: "<p>Hello</p>",
          context: checkin.uri,
          in_reply_to_uri: checkin.uri,
          published_at_utc: ~U[2026-05-14 10:00:00Z]
        })

      Entries.subscribe_to_context(checkin.uri)

      assert :ok = perform("#{@note_uri}/ctx")
      assert_received {:comment_deleted, _}
      assert is_nil(Repo.get_by(Entry, uri: note_with_context.uri))
    end
  end
end
