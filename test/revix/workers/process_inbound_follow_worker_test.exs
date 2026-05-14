defmodule Revix.Workers.ProcessInboundFollowWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.ProcessInboundFollowWorker
  alias Revix.Follows.Follow

  import Revix.PeopleFixtures

  @follower_uri "https://remote.example.com/users/alice"
  @follow_uri "https://remote.example.com/users/alice/follows/abc123"

  defp base_activity(following_uri) do
    %{
      "type" => "Follow",
      "id" => @follow_uri,
      "actor" => @follower_uri,
      "object" => following_uri
    }
  end

  describe "perform/1" do
    test "creates a Follow record from a valid activity" do
      person = person_fixture()

      assert :ok =
               perform_job(ProcessInboundFollowWorker, %{
                 "activity" => base_activity(person.uri),
                 "person_id" => person.id
               })

      follow = Repo.get_by!(Follow, uri: @follow_uri)
      assert follow.follower_uri == @follower_uri
      assert follow.following_uri == person.uri
      assert follow.origin == :remote
    end

    test "sets accepted_at immediately when auto_accept is true" do
      person = person_fixture()

      assert :ok =
               perform_job(ProcessInboundFollowWorker, %{
                 "activity" => base_activity(person.uri),
                 "person_id" => person.id
               })

      follow = Repo.get_by!(Follow, uri: @follow_uri)
      assert follow.accepted_at != nil
    end

    test "enqueues DeliverAcceptFollowWorker when auto_accept is true" do
      person = person_fixture()

      assert :ok =
               perform_job(ProcessInboundFollowWorker, %{
                 "activity" => base_activity(person.uri),
                 "person_id" => person.id
               })

      follow = Repo.get_by!(Follow, uri: @follow_uri)

      assert_enqueued(
        worker: Revix.Workers.DeliverAcceptFollowWorker,
        args: %{"follow_id" => follow.id}
      )
    end

    test "does not set accepted_at when auto_accept is false" do
      Application.put_env(:revix, :follows, auto_accept: false)
      on_exit(fn -> Application.put_env(:revix, :follows, auto_accept: true) end)

      person = person_fixture()

      assert :ok =
               perform_job(ProcessInboundFollowWorker, %{
                 "activity" => base_activity(person.uri),
                 "person_id" => person.id
               })

      follow = Repo.get_by!(Follow, uri: @follow_uri)
      assert is_nil(follow.accepted_at)
    end

    test "generates a tag: uri when the activity has no id" do
      person = person_fixture()
      activity = base_activity(person.uri) |> Map.delete("id")

      assert :ok =
               perform_job(ProcessInboundFollowWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      follow = Repo.one!(from f in Follow, where: f.follower_uri == ^@follower_uri)
      assert String.starts_with?(follow.uri, "tag:")
    end

    test "is idempotent for duplicate activity" do
      person = person_fixture()

      perform_job(ProcessInboundFollowWorker, %{
        "activity" => base_activity(person.uri),
        "person_id" => person.id
      })

      assert :ok =
               perform_job(ProcessInboundFollowWorker, %{
                 "activity" => base_activity(person.uri),
                 "person_id" => person.id
               })

      assert Repo.aggregate(from(f in Follow, where: f.follower_uri == ^@follower_uri), :count) ==
               1
    end

    test "returns {:error, :invalid_activity} when object is missing" do
      person = person_fixture()
      activity = %{"type" => "Follow", "id" => @follow_uri, "actor" => @follower_uri}

      assert {:error, :invalid_activity} =
               perform_job(ProcessInboundFollowWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })
    end

    test "returns {:error, :invalid_activity} when object is not a binary" do
      person = person_fixture()

      activity = %{
        "type" => "Follow",
        "id" => @follow_uri,
        "actor" => @follower_uri,
        "object" => %{"id" => person.uri}
      }

      assert {:error, :invalid_activity} =
               perform_job(ProcessInboundFollowWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })
    end
  end
end
