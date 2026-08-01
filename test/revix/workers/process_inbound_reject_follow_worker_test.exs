defmodule Revix.Workers.ProcessInboundRejectFollowWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Follows
  alias Revix.Follows.Follow
  alias Revix.Workers.ProcessInboundRejectFollowWorker

  import Revix.PeopleFixtures
  import Revix.FederationFixtures

  @target_uri "https://remote.example.com/users/alice"

  setup do
    stub_actor()
    scope = person_scope_fixture()
    {:ok, follow} = Follows.follow(scope, @target_uri)
    %{scope: scope, follow: follow}
  end

  defp activity(follow_uri, actor_uri) do
    %{
      "type" => "Reject",
      "id" => "#{actor_uri}/rejects/1",
      "actor" => actor_uri,
      "object" => %{
        "type" => "Follow",
        "id" => follow_uri,
        "actor" => actor_uri
      }
    }
  end

  defp perform(follow_uri, actor_uri, person_id) do
    perform_job(ProcessInboundRejectFollowWorker, %{
      "activity" => activity(follow_uri, actor_uri),
      "person_id" => person_id
    })
  end

  describe "perform/1" do
    test "sets rejected_at when the actor matches the stored following_uri", %{
      scope: scope,
      follow: follow
    } do
      assert :ok = perform(follow.uri, @target_uri, scope.person.id)

      updated = Repo.get!(Follow, follow.id)
      assert updated.rejected_at != nil
    end

    test "returns :ok and leaves rejected_at untouched when actor differs", %{
      scope: scope,
      follow: follow
    } do
      assert :ok =
               perform(follow.uri, "https://remote.example.com/users/mallory", scope.person.id)

      updated = Repo.get!(Follow, follow.id)
      assert is_nil(updated.rejected_at)
    end

    test "returns :ok for an unknown follow_uri", %{scope: scope} do
      assert :ok =
               perform(
                 "https://remote.example.com/follows/unknown",
                 @target_uri,
                 scope.person.id
               )
    end

    test "returns {:error, :invalid_activity} when the nested follow id is missing", %{
      scope: scope
    } do
      assert {:error, :invalid_activity} =
               perform_job(ProcessInboundRejectFollowWorker, %{
                 "activity" => %{
                   "type" => "Reject",
                   "id" => "#{@target_uri}/rejects/1",
                   "actor" => @target_uri,
                   "object" => %{"type" => "Follow"}
                 },
                 "person_id" => scope.person.id
               })
    end

    test "returns {:error, :invalid_activity} when object is a bare string rather than a map",
         %{scope: scope, follow: follow} do
      assert {:error, :invalid_activity} =
               perform_job(ProcessInboundRejectFollowWorker, %{
                 "activity" => %{
                   "type" => "Reject",
                   "id" => "#{@target_uri}/rejects/1",
                   "actor" => @target_uri,
                   "object" => follow.uri
                 },
                 "person_id" => scope.person.id
               })
    end

    test "returns {:error, :invalid_activity} when actor is missing", %{
      scope: scope,
      follow: follow
    } do
      assert {:error, :invalid_activity} =
               perform_job(ProcessInboundRejectFollowWorker, %{
                 "activity" => %{
                   "type" => "Reject",
                   "id" => "#{@target_uri}/rejects/1",
                   "actor" => nil,
                   "object" => %{"type" => "Follow", "id" => follow.uri}
                 },
                 "person_id" => scope.person.id
               })
    end
  end
end
