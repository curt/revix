defmodule Revix.Ecto.PingType do
  use Ecto.Type

  def type, do: :string

  def cast(:ping), do: {:ok, :ping}
  def cast(:pong), do: {:ok, :pong}
  def cast(_), do: :error

  def load("ping"), do: {:ok, :ping}
  def load("pong"), do: {:ok, :pong}
  def load(_), do: :error

  def dump(:ping), do: {:ok, "ping"}
  def dump(:pong), do: {:ok, "pong"}
  def dump(_), do: :error

  def values, do: [:ping, :pong]
end
