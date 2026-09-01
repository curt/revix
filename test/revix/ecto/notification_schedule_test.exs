defmodule Revix.Ecto.NotificationScheduleTest do
  use ExUnit.Case, async: true

  alias Revix.Ecto.NotificationSchedule

  describe "cast/1" do
    test "casts valid atoms" do
      for value <- [:hourly, :daily, :weekly, :monthly, :none] do
        assert NotificationSchedule.cast(value) == {:ok, value}
      end
    end

    test "rejects invalid values" do
      assert NotificationSchedule.cast(:yearly) == :error
      assert NotificationSchedule.cast("daily") == :error
      assert NotificationSchedule.cast(nil) == :error
    end
  end

  describe "load/1" do
    test "loads valid strings" do
      assert NotificationSchedule.load("hourly") == {:ok, :hourly}
      assert NotificationSchedule.load("daily") == {:ok, :daily}
      assert NotificationSchedule.load("weekly") == {:ok, :weekly}
      assert NotificationSchedule.load("monthly") == {:ok, :monthly}
      assert NotificationSchedule.load("none") == {:ok, :none}
    end

    test "rejects invalid strings" do
      assert NotificationSchedule.load("yearly") == :error
      assert NotificationSchedule.load("") == :error
      assert NotificationSchedule.load(nil) == :error
    end
  end

  describe "dump/1" do
    test "dumps valid atoms to strings" do
      assert NotificationSchedule.dump(:hourly) == {:ok, "hourly"}
      assert NotificationSchedule.dump(:daily) == {:ok, "daily"}
      assert NotificationSchedule.dump(:weekly) == {:ok, "weekly"}
      assert NotificationSchedule.dump(:monthly) == {:ok, "monthly"}
      assert NotificationSchedule.dump(:none) == {:ok, "none"}
    end

    test "rejects invalid values" do
      assert NotificationSchedule.dump(:yearly) == :error
      assert NotificationSchedule.dump("daily") == :error
      assert NotificationSchedule.dump(nil) == :error
    end
  end

  describe "values/0" do
    test "returns all valid cadences" do
      assert NotificationSchedule.values() == [:hourly, :daily, :weekly, :monthly, :none]
    end
  end
end
