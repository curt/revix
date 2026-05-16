defmodule Revix.Workers.ProcessInboundUndoLikeWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.ProcessInboundUndoLikeWorker
  alias Revix.{Entries, Likes}
  alias Revix.Likes.Like

  import Revix.PeopleFixtures
  import Revix.EntriesFixtures

  @actor_uri "https://remote.example.com/users/alice"
  @object_uri "https://example.com/entries/abc123"
  @like_uri "https://remote.example.com/users/alice/likes/xyz789"

  defp create_remote_like do
    {:ok, like} =
      Likes.upsert_inbound_like(%{
        author_uri: @actor_uri,
        object_uri: @object_uri,
        like_uri: @like_uri
      })

    like
  end

  describe "perform/1 — object as plain URI string" do
    test "soft-deletes the active like" do
      person = person_fixture()
      create_remote_like()

      activity = %{
        "type" => "Undo",
        "id" => "https://remote.example.com/users/alice/undo/1",
        "actor" => @actor_uri,
        "object" => @like_uri
      }

      assert :ok =
               perform_job(ProcessInboundUndoLikeWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      like = Repo.get_by!(Like, like_uri: @like_uri)
      refute is_nil(like.unliked_at)
    end
  end

  describe "perform/1 — object as full Like map with id" do
    test "soft-deletes the active like" do
      person = person_fixture()
      create_remote_like()

      activity = %{
        "type" => "Undo",
        "id" => "https://remote.example.com/users/alice/undo/2",
        "actor" => @actor_uri,
        "object" => %{
          "type" => "Like",
          "id" => @like_uri,
          "actor" => @actor_uri,
          "object" => @object_uri
        }
      }

      assert :ok =
               perform_job(ProcessInboundUndoLikeWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      like = Repo.get_by!(Like, like_uri: @like_uri)
      refute is_nil(like.unliked_at)
    end
  end

  describe "perform/1 — object as Like map without id (fallback by actor + object)" do
    test "soft-deletes the active like" do
      person = person_fixture()
      create_remote_like()

      activity = %{
        "type" => "Undo",
        "id" => "https://remote.example.com/users/alice/undo/3",
        "actor" => @actor_uri,
        "object" => %{
          "type" => "Like",
          "actor" => @actor_uri,
          "object" => @object_uri
        }
      }

      assert :ok =
               perform_job(ProcessInboundUndoLikeWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      like = Repo.get_by!(Like, like_uri: @like_uri)
      refute is_nil(like.unliked_at)
    end
  end

  describe "perform/1 — broadcast" do
    test "broadcasts :entry_unliked when the unliked object is a local entry" do
      person = person_fixture()
      checkin = checkin_fixture()

      {:ok, _like} =
        Likes.upsert_inbound_like(%{
          author_uri: @actor_uri,
          object_uri: checkin.uri,
          like_uri: @like_uri
        })

      activity = %{
        "type" => "Undo",
        "actor" => @actor_uri,
        "object" => @like_uri
      }

      Entries.subscribe_to_context(checkin.context)

      assert :ok =
               perform_job(ProcessInboundUndoLikeWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      checkin_uri = checkin.uri
      assert_received {:entry_unliked, ^checkin_uri, @actor_uri}
    end

    test "does not broadcast when no active like exists" do
      person = person_fixture()
      checkin = checkin_fixture()

      activity = %{
        "type" => "Undo",
        "actor" => @actor_uri,
        "object" => @like_uri
      }

      Entries.subscribe_to_context(checkin.uri)

      assert :ok =
               perform_job(ProcessInboundUndoLikeWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      refute_received {:entry_unliked, _, _}
    end
  end

  describe "perform/1 — unrecognized object format" do
    test "returns ok when object is an unrecognized shape" do
      person = person_fixture()

      activity = %{
        "type" => "Undo",
        "id" => "https://remote.example.com/users/alice/undo/0",
        "actor" => @actor_uri,
        "object" => %{"type" => "Unknown", "foo" => "bar"}
      }

      assert :ok =
               perform_job(ProcessInboundUndoLikeWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })
    end
  end

  describe "perform/1 — idempotency" do
    test "returns ok when no matching active like exists" do
      person = person_fixture()

      activity = %{
        "type" => "Undo",
        "id" => "https://remote.example.com/users/alice/undo/4",
        "actor" => @actor_uri,
        "object" => @like_uri
      }

      assert :ok =
               perform_job(ProcessInboundUndoLikeWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })
    end

    test "returns ok when like was already unliked" do
      person = person_fixture()
      like = create_remote_like()
      {:ok, _} = Likes.undo_inbound_like(like.like_uri)

      activity = %{
        "type" => "Undo",
        "id" => "https://remote.example.com/users/alice/undo/5",
        "actor" => @actor_uri,
        "object" => @like_uri
      }

      assert :ok =
               perform_job(ProcessInboundUndoLikeWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })
    end
  end
end
