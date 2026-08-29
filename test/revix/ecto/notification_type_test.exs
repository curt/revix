defmodule Revix.Ecto.NotificationTypeTest do
  use ExUnit.Case, async: true

  alias Revix.Ecto.NotificationType

  @values [:owner_entry, :followed_entry, :reply, :like, :registration]

  describe "cast/1" do
    test "casts valid atoms" do
      for value <- @values do
        assert NotificationType.cast(value) == {:ok, value}
      end
    end

    test "rejects invalid values" do
      assert NotificationType.cast(:comment) == :error
      assert NotificationType.cast("like") == :error
      assert NotificationType.cast(nil) == :error
    end
  end

  describe "load/1" do
    test "loads valid strings" do
      for value <- @values do
        assert NotificationType.load(Atom.to_string(value)) == {:ok, value}
      end
    end

    test "rejects invalid strings" do
      assert NotificationType.load("comment") == :error
      assert NotificationType.load("") == :error
      assert NotificationType.load(nil) == :error
    end
  end

  describe "dump/1" do
    test "dumps valid atoms to strings" do
      for value <- @values do
        assert NotificationType.dump(value) == {:ok, Atom.to_string(value)}
      end
    end

    test "rejects invalid values" do
      assert NotificationType.dump(:comment) == :error
      assert NotificationType.dump("like") == :error
      assert NotificationType.dump(nil) == :error
    end
  end

  describe "values/0" do
    test "returns all notification types" do
      assert NotificationType.values() == @values
    end
  end
end
