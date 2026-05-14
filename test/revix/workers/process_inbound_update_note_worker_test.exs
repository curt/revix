defmodule Revix.Workers.ProcessInboundUpdateNoteWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.ProcessInboundUpdateNoteWorker
  alias Revix.Entries
  alias Revix.Entries.Entry
  alias Revix.Follows

  import Revix.PeopleFixtures
  import Revix.EntriesFixtures

  @actor_uri "https://remote.example.com/users/alice"
  @note_uri "https://remote.example.com/users/alice/notes/abc123"

  defp base_note(opts \\ []) do
    %{
      "id" => @note_uri,
      "type" => "Note",
      "content" => Keyword.get(opts, :content, "<p>Original</p>"),
      "inReplyTo" => Keyword.get(opts, :in_reply_to),
      "context" => Keyword.get(opts, :context),
      "published" => "2026-05-14T10:00:00Z"
    }
  end

  defp base_activity(note) do
    %{
      "type" => "Update",
      "id" => "#{@actor_uri}/activities/1",
      "actor" => @actor_uri,
      "object" => note
    }
  end

  defp perform(activity, person_id) do
    perform_job(ProcessInboundUpdateNoteWorker, %{
      "activity" => activity,
      "person_id" => person_id
    })
  end

  describe "perform/1" do
    test "updates an existing remote entry when context is a local entry" do
      person = person_fixture()
      checkin = checkin_fixture()

      {:ok, existing} =
        Entries.create_inbound_note(%{
          uri: @note_uri,
          url: @note_uri,
          author_uri: @actor_uri,
          content: "<p>Original</p>",
          in_reply_to_uri: checkin.uri,
          context: checkin.uri,
          published_at_utc: ~U[2026-05-14 10:00:00Z]
        })

      Entries.subscribe_to_context(checkin.uri)

      note = base_note(content: "<p>Updated!</p>", in_reply_to: checkin.uri, context: checkin.uri)
      activity = base_activity(note)

      assert :ok = perform(activity, person.id)

      updated = Repo.get!(Entry, existing.id)
      assert updated.content == "<p>Updated!</p>"

      assert_received {:comment_updated, _}
    end

    test "creates entry when not found (upsert path)" do
      person = person_fixture()
      checkin = checkin_fixture()

      note = base_note(in_reply_to: checkin.uri, context: checkin.uri)
      activity = base_activity(note)

      assert :ok = perform(activity, person.id)
      assert Repo.get_by!(Entry, uri: @note_uri).origin == :remote
    end

    test "upsert broadcasts :comment_created when entry did not exist" do
      person = person_fixture()
      checkin = checkin_fixture()

      Entries.subscribe_to_context(checkin.uri)

      note = base_note(in_reply_to: checkin.uri, context: checkin.uri)
      activity = base_activity(note)

      assert :ok = perform(activity, person.id)
      assert_received {:comment_created, _}
    end

    test "persists when actor is followed by a local user (no local context)" do
      follower = person_fixture()
      scope = person_scope_fixture(follower)
      {:ok, _} = Follows.follow(scope, @actor_uri)

      note = base_note()
      activity = base_activity(note)

      assert :ok = perform(activity, follower.id)
      assert Repo.get_by!(Entry, uri: @note_uri).origin == :remote
    end

    test "silently ignores if no local context and actor not followed by any local user" do
      person = person_fixture()

      note =
        base_note(
          in_reply_to: "https://remote.example.com/foreign",
          context: "https://remote.example.com/foreign"
        )

      activity = base_activity(note)

      assert :ok = perform(activity, person.id)
      assert is_nil(Repo.get_by(Entry, uri: @note_uri))
    end

    test "silently ignores update to a local-origin entry" do
      person = person_fixture()
      checkin = checkin_fixture()

      # Use the checkin's URI as the note URI — it's local-origin
      note = %{
        base_note()
        | "id" => checkin.uri,
          "inReplyTo" => checkin.uri,
          "context" => checkin.uri
      }

      activity = base_activity(note)

      assert :ok = perform(activity, person.id)

      # The checkin must still exist and be unchanged
      assert Repo.get_by!(Entry, uri: checkin.uri).origin == :local
    end

    test "returns error when object is not a map" do
      person = person_fixture()

      activity = %{
        "type" => "Update",
        "id" => "#{@actor_uri}/activities/1",
        "actor" => @actor_uri,
        "object" => @note_uri
      }

      assert {:error, :invalid_activity} = perform(activity, person.id)
    end

    test "returns error when object has no id" do
      person = person_fixture()

      activity = %{
        "type" => "Update",
        "id" => "#{@actor_uri}/activities/1",
        "actor" => @actor_uri,
        "object" => %{"type" => "Note", "content" => "x"}
      }

      assert {:error, :invalid_activity} = perform(activity, person.id)
    end
  end
end
