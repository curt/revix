defmodule Revix.Likes.LikeTest do
  use ExUnit.Case, async: true

  alias Revix.Likes.Like

  describe "active?/1" do
    test "returns true when unliked_at is nil" do
      assert Like.active?(%Like{unliked_at: nil})
    end

    test "returns false when unliked_at is set" do
      refute Like.active?(%Like{unliked_at: ~U[2024-01-01 00:00:00Z]})
    end
  end

  describe "unlike_changeset/1" do
    test "sets unliked_at to a recent UTC datetime" do
      like = %Like{unliked_at: nil}
      cs = Like.unlike_changeset(like)
      assert cs.valid?
      unliked_at = Ecto.Changeset.get_change(cs, :unliked_at)
      assert %DateTime{} = unliked_at
      assert DateTime.diff(DateTime.utc_now(), unliked_at) < 5
    end
  end

  describe "re_like_changeset/2" do
    test "clears unliked_at and updates published fields" do
      like = %Like{
        unliked_at: ~U[2024-01-01 00:00:00Z],
        published_at_utc: nil,
        published_at_local: nil,
        published_tz: nil
      }

      attrs = %{
        published_at_utc: ~U[2025-03-01 12:00:00Z],
        published_at_local: ~N[2025-03-01 06:00:00],
        published_tz: "America/Denver"
      }

      cs = Like.re_like_changeset(like, attrs)
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :unliked_at) == nil
      assert Ecto.Changeset.get_change(cs, :published_at_utc) == attrs.published_at_utc
      assert Ecto.Changeset.get_change(cs, :published_tz) == "America/Denver"
    end

    test "is invalid when required published fields are missing" do
      like = %Like{unliked_at: ~U[2024-01-01 00:00:00Z]}
      cs = Like.re_like_changeset(like, %{})
      refute cs.valid?
    end
  end
end
