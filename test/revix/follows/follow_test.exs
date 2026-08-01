defmodule Revix.Follows.FollowTest do
  use ExUnit.Case, async: true

  alias Revix.Follows.Follow

  defp base_follow do
    %Follow{
      id: "abc12345678",
      uri: "https://example.com/follows/1",
      follower_uri: "https://remote.example.com/users/alice",
      following_uri: "https://local.example.com/people/bob",
      origin: :remote
    }
  end

  describe "accept_changeset/1" do
    test "sets accepted_at to current UTC time" do
      cs = Follow.accept_changeset(base_follow())
      assert cs.valid?
      assert %DateTime{} = Ecto.Changeset.get_change(cs, :accepted_at)
    end
  end

  describe "reject_changeset/1" do
    test "sets rejected_at to current UTC time" do
      cs = Follow.reject_changeset(base_follow())
      assert cs.valid?
      assert %DateTime{} = Ecto.Changeset.get_change(cs, :rejected_at)
    end
  end

  describe "unfollow_changeset/1" do
    test "sets unfollowed_at to current UTC time" do
      cs = Follow.unfollow_changeset(base_follow())
      assert cs.valid?
      assert %DateTime{} = Ecto.Changeset.get_change(cs, :unfollowed_at)
    end
  end

  describe "refollow_changeset/1" do
    test "clears unfollowed_at, accepted_at, and rejected_at" do
      follow = %{
        base_follow()
        | unfollowed_at: ~U[2026-01-01 00:00:00Z],
          accepted_at: ~U[2026-01-01 00:00:00Z],
          rejected_at: ~U[2026-01-01 00:00:00Z]
      }

      cs = Follow.refollow_changeset(follow)
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :unfollowed_at) == nil
      assert Ecto.Changeset.get_change(cs, :accepted_at) == nil
      assert Ecto.Changeset.get_change(cs, :rejected_at) == nil
    end
  end

  describe "active?/1" do
    test "returns true when unfollowed_at and rejected_at are nil" do
      assert Follow.active?(%Follow{unfollowed_at: nil, rejected_at: nil})
    end

    test "returns false when unfollowed_at is set" do
      refute Follow.active?(%Follow{unfollowed_at: ~U[2026-01-01 00:00:00Z], rejected_at: nil})
    end

    test "returns false when rejected_at is set" do
      refute Follow.active?(%Follow{unfollowed_at: nil, rejected_at: ~U[2026-01-01 00:00:00Z]})
    end
  end
end
