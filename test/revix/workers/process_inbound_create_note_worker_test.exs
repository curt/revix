defmodule Revix.Workers.ProcessInboundCreateNoteWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.ProcessInboundCreateNoteWorker
  alias Revix.Entries
  alias Revix.Entries.Entry
  alias Revix.Follows
  alias Revix.Repo

  import Revix.PeopleFixtures
  import Revix.EntriesFixtures

  @actor_uri "https://remote.example.com/users/alice"
  @note_uri "https://remote.example.com/users/alice/notes/abc123"

  defp base_note(in_reply_to_uri, opts \\ []) do
    context = Keyword.get(opts, :context, in_reply_to_uri)

    %{
      "id" => @note_uri,
      "type" => "Note",
      "actor" => @actor_uri,
      "content" => "<p>Hello!</p>",
      "inReplyTo" => in_reply_to_uri,
      "context" => context,
      "published" => "2026-05-12T10:00:00Z"
    }
  end

  defp base_activity(note) do
    %{
      "type" => "Create",
      "id" => "#{@actor_uri}/activities/1",
      "actor" => @actor_uri,
      "object" => note
    }
  end

  defp perform(activity, person_id) do
    perform_job(ProcessInboundCreateNoteWorker, %{
      "activity" => activity,
      "person_id" => person_id
    })
  end

  describe "perform/1" do
    test "silently ignores a note whose context and inReplyTo don't resolve to any local entry" do
      person = person_fixture()
      note = base_note("https://remote.example.com/checkins/xyz")
      activity = base_activity(note)

      assert :ok = perform(activity, person.id)
      assert Repo.get_by(Entry, uri: @note_uri) == nil
    end

    test "silently ignores a note whose context resolves to a remote entry" do
      person = person_fixture()
      remote_checkin = checkin_fixture(%{origin: :remote})
      note = base_note(remote_checkin.uri)
      activity = base_activity(note)

      assert :ok = perform(activity, person.id)
      assert Repo.get_by(Entry, uri: @note_uri) == nil
    end

    test "persists when context is a local checkin URI" do
      person = person_fixture()
      checkin = checkin_fixture()
      note = base_note(checkin.uri)
      activity = base_activity(note)

      assert :ok = perform(activity, person.id)

      saved = Repo.get_by!(Entry, uri: @note_uri)
      assert saved.type == :note
      assert saved.origin == :remote
      assert saved.author_uri == @actor_uri
      assert saved.in_reply_to_uri == checkin.uri
      assert saved.context == checkin.uri
      assert saved.published_at_utc == ~U[2026-05-12 10:00:00Z]
    end

    test "persists when only inReplyTo resolves to a local entry (no context field)" do
      person = person_fixture()
      checkin = checkin_fixture()

      note =
        base_note(checkin.uri)
        |> Map.delete("context")

      activity = base_activity(note)

      assert :ok = perform(activity, person.id)
      assert Repo.get_by!(Entry, uri: @note_uri).origin == :remote
    end

    test "is idempotent — second call with same note URI returns :ok without duplicate" do
      person = person_fixture()
      checkin = checkin_fixture()
      note = base_note(checkin.uri)
      activity = base_activity(note)

      assert :ok = perform(activity, person.id)
      assert :ok = perform(activity, person.id)

      assert Repo.aggregate(from(e in Entry, where: e.uri == ^@note_uri), :count) == 1
    end

    test "broadcasts {:comment_created, note} on the context topic when saved" do
      person = person_fixture()
      checkin = checkin_fixture()
      note = base_note(checkin.uri)
      activity = base_activity(note)

      Entries.subscribe_to_context(checkin.uri)

      assert :ok = perform(activity, person.id)

      assert_received {:comment_created, received_note}
      assert received_note.uri == @note_uri
    end

    test "does not broadcast when the note is silently ignored" do
      person = person_fixture()
      note = base_note("https://remote.example.com/checkins/foreign")
      activity = base_activity(note)

      Entries.subscribe_to_context("https://remote.example.com/checkins/foreign")

      assert :ok = perform(activity, person.id)

      refute_received {:comment_created, _}
    end

    test "returns error when object is missing" do
      person = person_fixture()

      activity = %{
        "type" => "Create",
        "id" => "#{@actor_uri}/activities/1",
        "actor" => @actor_uri
      }

      assert {:error, :invalid_activity} = perform(activity, person.id)
    end

    test "returns error when object is not a map" do
      person = person_fixture()

      activity = %{
        "type" => "Create",
        "id" => "#{@actor_uri}/activities/1",
        "actor" => @actor_uri,
        "object" => @note_uri
      }

      assert {:error, :invalid_activity} = perform(activity, person.id)
    end

    test "returns error when object has no id" do
      person = person_fixture()

      note =
        base_note("https://remote.example.com/checkins/xyz")
        |> Map.delete("id")

      activity = base_activity(note)

      assert {:error, :invalid_activity} = perform(activity, person.id)
    end

    test "persists when actor is followed by a local user (no local context)" do
      follower = person_fixture()
      scope = person_scope_fixture(follower)

      note = %{
        "id" => @note_uri,
        "type" => "Note",
        "content" => "<p>Hello from someone you follow!</p>",
        "published" => "2026-05-14T10:00:00Z"
      }

      activity = %{
        "type" => "Create",
        "id" => "#{@actor_uri}/activities/99",
        "actor" => @actor_uri,
        "object" => note
      }

      {:ok, _} = Follows.follow(scope, @actor_uri)

      assert :ok = perform(activity, follower.id)
      assert Repo.get_by!(Entry, uri: @note_uri).origin == :remote
    end

    test "Article type is accepted the same as Note" do
      person = person_fixture()
      checkin = checkin_fixture()

      note =
        base_note(checkin.uri)
        |> Map.put("type", "Article")

      activity =
        base_activity(note)
        |> Map.put("object", note)

      assert :ok = perform(activity, person.id)
      assert Repo.get_by!(Entry, uri: @note_uri).origin == :remote
    end
  end
end
