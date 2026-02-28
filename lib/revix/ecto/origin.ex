defmodule Revix.Ecto.Origin do
  use Ecto.Type

  def type, do: :string

  def cast(:local), do: {:ok, :local}
  def cast(:remote), do: {:ok, :remote}
  def cast(_), do: :error

  def load("local"), do: {:ok, :local}
  def load("remote"), do: {:ok, :remote}
  def load(_), do: :error

  def dump(:local), do: {:ok, "local"}
  def dump(:remote), do: {:ok, "remote"}
  def dump(_), do: :error

  def values, do: [:local, :remote]
end
