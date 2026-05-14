defmodule Revix.Workers.ProcessInboundUndoFollowWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.ProcessInboundUndoFollowWorker
  alias Revix.Follows.Follow

  import Revix.PeopleFixtures

  @follower_uri "https://remote.example.com/users/alice"
  @follow_uri "https://remote.example.com/users/alice/follows/abc123"

  defp insert_active_follow(following_uri) do
    id = Revix.Ecto.Base58Id.autogenerate()

    %Follow{id: id}
    |> Follow.create_changeset(%{
      uri: @follow_uri,
      follower_uri: @follower_uri,
      following_uri: following_uri,
      origin: :remote,
      accepted_at: DateTime.utc_now(:second)
    })
    |> Repo.insert!()
  end

  describe "perform/1 with string URI object" do
    test "sets unfollowed_at when object is the follow URI" do
      person = person_fixture()
      insert_active_follow(person.uri)

      activity = %{
        "type" => "Undo",
        "id" => @follow_uri <> "#undo",
        "actor" => @follower_uri,
        "object" => @follow_uri
      }

      assert :ok =
               perform_job(ProcessInboundUndoFollowWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      follow = Repo.get_by!(Follow, uri: @follow_uri)
      assert follow.unfollowed_at != nil
    end
  end

  describe "perform/1 with map object containing id" do
    test "sets unfollowed_at when object is a map with id" do
      person = person_fixture()
      insert_active_follow(person.uri)

      activity = %{
        "type" => "Undo",
        "id" => @follow_uri <> "#undo",
        "actor" => @follower_uri,
        "object" => %{
          "type" => "Follow",
          "id" => @follow_uri,
          "actor" => @follower_uri,
          "object" => person.uri
        }
      }

      assert :ok =
               perform_job(ProcessInboundUndoFollowWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      follow = Repo.get_by!(Follow, uri: @follow_uri)
      assert follow.unfollowed_at != nil
    end
  end

  describe "perform/1 with map object without id" do
    test "sets unfollowed_at when object has actor+object but no id" do
      person = person_fixture()
      insert_active_follow(person.uri)

      activity = %{
        "type" => "Undo",
        "id" => @follow_uri <> "#undo",
        "actor" => @follower_uri,
        "object" => %{
          "type" => "Follow",
          "actor" => @follower_uri,
          "object" => person.uri
        }
      }

      assert :ok =
               perform_job(ProcessInboundUndoFollowWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      follow = Repo.get_by!(Follow, uri: @follow_uri)
      assert follow.unfollowed_at != nil
    end
  end

  describe "perform/1 idempotency" do
    test "returns :ok when follow is not found (already undone or never existed)" do
      person = person_fixture()

      activity = %{
        "type" => "Undo",
        "id" => "https://remote.example.com/undo/unknown",
        "actor" => @follower_uri,
        "object" => "https://remote.example.com/follows/unknown"
      }

      assert :ok =
               perform_job(ProcessInboundUndoFollowWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })
    end
  end
end
