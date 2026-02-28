defmodule Revix.Ecto.RoleTest do
  use ExUnit.Case, async: true

  alias Revix.Ecto.Role

  describe "cast/1" do
    test "casts valid atoms" do
      assert Role.cast(:user) == {:ok, :user}
      assert Role.cast(:owner) == {:ok, :owner}
    end

    test "rejects invalid values" do
      assert Role.cast(:admin) == :error
      assert Role.cast("user") == :error
      assert Role.cast(nil) == :error
    end
  end

  describe "load/1" do
    test "loads valid strings from database" do
      assert Role.load("user") == {:ok, :user}
      assert Role.load("owner") == {:ok, :owner}
    end

    test "rejects invalid strings" do
      assert Role.load("admin") == :error
      assert Role.load("") == :error
      assert Role.load(nil) == :error
    end
  end

  describe "dump/1" do
    test "dumps valid atoms to strings" do
      assert Role.dump(:user) == {:ok, "user"}
      assert Role.dump(:owner) == {:ok, "owner"}
    end

    test "rejects invalid values" do
      assert Role.dump(:admin) == :error
      assert Role.dump("user") == :error
      assert Role.dump(nil) == :error
    end
  end

  describe "values/0" do
    test "returns all valid roles" do
      assert Role.values() == [:user, :owner]
    end
  end
end
