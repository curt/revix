defmodule Revix.FollowsTest do
  use Revix.DataCase, async: true

  import Revix.PeopleFixtures

  alias Revix.Follows
  alias Revix.Follows.Follow

  setup do
    scope = person_scope_fixture()
    %{scope: scope}
  end

  describe "follow/2" do
    test "creates a new follow record", %{scope: scope} do
      target_uri = "https://remote.example.com/users/alice"

      assert {:ok, %Follow{} = follow} = Follows.follow(scope, target_uri)
      assert follow.follower_uri == scope.person.uri
      assert follow.following_uri == target_uri
      assert follow.origin == :local
      assert is_nil(follow.unfollowed_at)
      assert String.starts_with?(follow.uri, "tag:")
    end

    test "returns {:error, :self_follow} when following self", %{scope: scope} do
      assert {:error, :self_follow} = Follows.follow(scope, scope.person.uri)
    end

    test "is idempotent when already following", %{scope: scope} do
      target_uri = "https://remote.example.com/users/alice"
      {:ok, original} = Follows.follow(scope, target_uri)
      {:ok, again} = Follows.follow(scope, target_uri)
      assert original.id == again.id
    end

    test "re-follows after unfollowing", %{scope: scope} do
      target_uri = "https://remote.example.com/users/alice"
      {:ok, follow} = Follows.follow(scope, target_uri)
      {:ok, _} = Follows.unfollow(scope, target_uri)
      {:ok, refollowed} = Follows.follow(scope, target_uri)
      assert refollowed.id == follow.id
      assert is_nil(refollowed.unfollowed_at)
    end

    test "enqueues a DeliverFollowWorker", %{scope: scope} do
      target_uri = "https://remote.example.com/users/alice"
      {:ok, follow} = Follows.follow(scope, target_uri)

      assert_enqueued(
        worker: Revix.Workers.DeliverFollowWorker,
        args: %{"follow_id" => follow.id}
      )
    end
  end

  describe "unfollow/2" do
    test "soft-deletes an active follow", %{scope: scope} do
      target_uri = "https://remote.example.com/users/alice"
      {:ok, _} = Follows.follow(scope, target_uri)
      assert {:ok, %Follow{} = follow} = Follows.unfollow(scope, target_uri)
      assert follow.unfollowed_at != nil
    end

    test "returns {:error, :not_found} when not following", %{scope: scope} do
      assert {:error, :not_found} =
               Follows.unfollow(scope, "https://remote.example.com/users/nobody")
    end

    test "returns {:error, :not_found} after already unfollowing", %{scope: scope} do
      target_uri = "https://remote.example.com/users/alice"
      {:ok, _} = Follows.follow(scope, target_uri)
      {:ok, _} = Follows.unfollow(scope, target_uri)
      assert {:error, :not_found} = Follows.unfollow(scope, target_uri)
    end

    test "enqueues a DeliverUndoFollowWorker", %{scope: scope} do
      target_uri = "https://remote.example.com/users/alice"
      {:ok, follow} = Follows.follow(scope, target_uri)
      {:ok, _} = Follows.unfollow(scope, target_uri)

      assert_enqueued(
        worker: Revix.Workers.DeliverUndoFollowWorker,
        args: %{"follow_id" => follow.id}
      )
    end
  end

  describe "accept_follow/1" do
    test "sets accepted_at on a pending follow", %{scope: scope} do
      local_uri = scope.person.uri
      Application.put_env(:revix, :follows, auto_accept: false)

      on_exit(fn -> Application.put_env(:revix, :follows, auto_accept: true) end)

      {:ok, follow} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/1",
          follower_uri: "https://remote.example.com/users/alice",
          following_uri: local_uri
        })

      assert is_nil(follow.accepted_at)
      assert {:ok, accepted} = Follows.accept_follow(follow.id)
      assert accepted.accepted_at != nil
    end

    test "returns {:error, :not_found} for unknown id" do
      nonexistent = Revix.Ecto.Base58Id.autogenerate()
      assert {:error, :not_found} = Follows.accept_follow(nonexistent)
    end
  end

  describe "upsert_inbound_follow/1 with auto_accept: true (default)" do
    test "creates a follow with accepted_at set", %{scope: scope} do
      {:ok, follow} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/1",
          follower_uri: "https://remote.example.com/users/alice",
          following_uri: scope.person.uri
        })

      assert follow.origin == :remote
      assert follow.accepted_at != nil
      assert is_nil(follow.unfollowed_at)
    end

    test "enqueues a DeliverAcceptFollowWorker", %{scope: scope} do
      {:ok, follow} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/1",
          follower_uri: "https://remote.example.com/users/alice",
          following_uri: scope.person.uri
        })

      assert_enqueued(
        worker: Revix.Workers.DeliverAcceptFollowWorker,
        args: %{"follow_id" => follow.id}
      )
    end

    test "is idempotent for active follow (same uri)", %{scope: scope} do
      attrs = %{
        uri: "https://remote.example.com/follows/1",
        follower_uri: "https://remote.example.com/users/alice",
        following_uri: scope.person.uri
      }

      {:ok, first} = Follows.upsert_inbound_follow(attrs)
      {:ok, second} = Follows.upsert_inbound_follow(attrs)
      assert first.id == second.id
    end

    test "re-follows after unfollowed, sets accepted_at again", %{scope: scope} do
      attrs = %{
        uri: "https://remote.example.com/follows/1",
        follower_uri: "https://remote.example.com/users/alice",
        following_uri: scope.person.uri
      }

      {:ok, original} = Follows.upsert_inbound_follow(attrs)
      Follows.undo_inbound_follow(attrs.uri)
      {:ok, refollowed} = Follows.upsert_inbound_follow(attrs)
      assert refollowed.id == original.id
      assert refollowed.accepted_at != nil
      assert is_nil(refollowed.unfollowed_at)
    end
  end

  describe "upsert_inbound_follow/1 with auto_accept: false" do
    setup do
      Application.put_env(:revix, :follows, auto_accept: false)
      on_exit(fn -> Application.put_env(:revix, :follows, auto_accept: true) end)
      :ok
    end

    test "creates a follow with accepted_at nil (pending)", %{scope: scope} do
      {:ok, follow} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/2",
          follower_uri: "https://remote.example.com/users/bob",
          following_uri: scope.person.uri
        })

      assert is_nil(follow.accepted_at)
    end

    test "does not enqueue a DeliverAcceptFollowWorker", %{scope: scope} do
      {:ok, _follow} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/2",
          follower_uri: "https://remote.example.com/users/bob",
          following_uri: scope.person.uri
        })

      refute_enqueued(worker: Revix.Workers.DeliverAcceptFollowWorker)
    end
  end

  describe "undo_inbound_follow/1 by URI" do
    test "sets unfollowed_at on an active follow", %{scope: scope} do
      {:ok, follow} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/1",
          follower_uri: "https://remote.example.com/users/alice",
          following_uri: scope.person.uri
        })

      assert {:ok, undone} = Follows.undo_inbound_follow(follow.uri)
      assert undone.unfollowed_at != nil
    end

    test "returns {:error, :not_found} for unknown URI" do
      assert {:error, :not_found} =
               Follows.undo_inbound_follow("https://remote.example.com/follows/unknown")
    end
  end

  describe "undo_inbound_follow/2 by pair" do
    test "sets unfollowed_at by follower/following pair", %{scope: scope} do
      follower_uri = "https://remote.example.com/users/alice"

      {:ok, _} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/1",
          follower_uri: follower_uri,
          following_uri: scope.person.uri
        })

      assert {:ok, undone} = Follows.undo_inbound_follow(follower_uri, scope.person.uri)
      assert undone.unfollowed_at != nil
    end

    test "returns {:error, :not_found} for unknown pair" do
      assert {:error, :not_found} =
               Follows.undo_inbound_follow(
                 "https://remote.example.com/users/nobody",
                 "https://local.example.com/people/nobody"
               )
    end
  end

  describe "get_followers_for_person/2" do
    test "returns accepted+active followers", %{scope: scope} do
      {:ok, _} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/1",
          follower_uri: "https://remote.example.com/users/alice",
          following_uri: scope.person.uri
        })

      followers = Follows.get_followers_for_person(scope.person.uri)
      assert length(followers) == 1
    end

    test "excludes pending followers (auto_accept: false)", %{scope: scope} do
      Application.put_env(:revix, :follows, auto_accept: false)

      on_exit(fn -> Application.put_env(:revix, :follows, auto_accept: true) end)

      {:ok, _} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/1",
          follower_uri: "https://remote.example.com/users/alice",
          following_uri: scope.person.uri
        })

      assert Follows.get_followers_for_person(scope.person.uri) == []
    end

    test "excludes unfollowed", %{scope: scope} do
      {:ok, follow} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/1",
          follower_uri: "https://remote.example.com/users/alice",
          following_uri: scope.person.uri
        })

      Follows.undo_inbound_follow(follow.uri)
      assert Follows.get_followers_for_person(scope.person.uri) == []
    end
  end

  describe "get_following_for_person/2" do
    test "returns active follows", %{scope: scope} do
      {:ok, _} = Follows.follow(scope, "https://remote.example.com/users/alice")
      following = Follows.get_following_for_person(scope.person.uri)
      assert length(following) == 1
    end

    test "excludes unfollowed", %{scope: scope} do
      target_uri = "https://remote.example.com/users/alice"
      {:ok, _} = Follows.follow(scope, target_uri)
      {:ok, _} = Follows.unfollow(scope, target_uri)
      assert Follows.get_following_for_person(scope.person.uri) == []
    end
  end

  describe "get_pending_followers_for_person/1" do
    test "returns followers with nil accepted_at and nil unfollowed_at", %{scope: scope} do
      Application.put_env(:revix, :follows, auto_accept: false)
      on_exit(fn -> Application.put_env(:revix, :follows, auto_accept: true) end)

      {:ok, _} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/1",
          follower_uri: "https://remote.example.com/users/alice",
          following_uri: scope.person.uri
        })

      pending = Follows.get_pending_followers_for_person(scope.person.uri)
      assert length(pending) == 1
    end

    test "excludes accepted followers", %{scope: scope} do
      {:ok, _} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/1",
          follower_uri: "https://remote.example.com/users/alice",
          following_uri: scope.person.uri
        })

      assert Follows.get_pending_followers_for_person(scope.person.uri) == []
    end
  end

  describe "follower_of?/2" do
    test "returns true for accepted+active follow", %{scope: scope} do
      {:ok, _} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/1",
          follower_uri: "https://remote.example.com/users/alice",
          following_uri: scope.person.uri
        })

      assert Follows.follower_of?("https://remote.example.com/users/alice", scope.person.uri)
    end

    test "returns false for nil follower" do
      assert Follows.follower_of?(nil, "https://example.com/users/bob") == false
    end

    test "returns false for pending follow (auto_accept: false)", %{scope: scope} do
      Application.put_env(:revix, :follows, auto_accept: false)
      on_exit(fn -> Application.put_env(:revix, :follows, auto_accept: true) end)

      {:ok, _} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/1",
          follower_uri: "https://remote.example.com/users/alice",
          following_uri: scope.person.uri
        })

      refute Follows.follower_of?("https://remote.example.com/users/alice", scope.person.uri)
    end

    test "returns false after unfollowing", %{scope: scope} do
      {:ok, follow} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/1",
          follower_uri: "https://remote.example.com/users/alice",
          following_uri: scope.person.uri
        })

      Follows.undo_inbound_follow(follow.uri)
      refute Follows.follower_of?("https://remote.example.com/users/alice", scope.person.uri)
    end
  end

  describe "following?/2" do
    test "returns true for active follow", %{scope: scope} do
      target_uri = "https://remote.example.com/users/alice"
      {:ok, _} = Follows.follow(scope, target_uri)
      assert Follows.following?(scope.person.uri, target_uri)
    end

    test "returns false for nil follower" do
      assert Follows.following?(nil, "https://example.com/users/alice") == false
    end

    test "returns false after unfollowing", %{scope: scope} do
      target_uri = "https://remote.example.com/users/alice"
      {:ok, _} = Follows.follow(scope, target_uri)
      {:ok, _} = Follows.unfollow(scope, target_uri)
      refute Follows.following?(scope.person.uri, target_uri)
    end
  end

  describe "count_followers/1 and count_following/1" do
    test "counts accepted followers correctly", %{scope: scope} do
      assert Follows.count_followers(scope.person.uri) == 0

      {:ok, _} =
        Follows.upsert_inbound_follow(%{
          uri: "https://remote.example.com/follows/1",
          follower_uri: "https://remote.example.com/users/alice",
          following_uri: scope.person.uri
        })

      assert Follows.count_followers(scope.person.uri) == 1
    end

    test "counts active following correctly", %{scope: scope} do
      assert Follows.count_following(scope.person.uri) == 0
      {:ok, _} = Follows.follow(scope, "https://remote.example.com/users/alice")
      assert Follows.count_following(scope.person.uri) == 1
    end
  end
end
