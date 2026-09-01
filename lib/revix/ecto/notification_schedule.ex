defmodule Revix.Ecto.NotificationSchedule do
  use Ecto.Type

  def type, do: :string

  def cast(:hourly), do: {:ok, :hourly}
  def cast(:daily), do: {:ok, :daily}
  def cast(:weekly), do: {:ok, :weekly}
  def cast(:monthly), do: {:ok, :monthly}
  def cast(:none), do: {:ok, :none}
  def cast(_), do: :error

  def load("hourly"), do: {:ok, :hourly}
  def load("daily"), do: {:ok, :daily}
  def load("weekly"), do: {:ok, :weekly}
  def load("monthly"), do: {:ok, :monthly}
  def load("none"), do: {:ok, :none}
  def load(_), do: :error

  def dump(:hourly), do: {:ok, "hourly"}
  def dump(:daily), do: {:ok, "daily"}
  def dump(:weekly), do: {:ok, "weekly"}
  def dump(:monthly), do: {:ok, "monthly"}
  def dump(:none), do: {:ok, "none"}
  def dump(_), do: :error

  def values, do: [:hourly, :daily, :weekly, :monthly, :none]
end
