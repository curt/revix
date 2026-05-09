defmodule Revix.Ecto.Direction do
  use Ecto.Type

  def type, do: :string

  def cast(:inbound), do: {:ok, :inbound}
  def cast(:outbound), do: {:ok, :outbound}
  def cast(_), do: :error

  def load("inbound"), do: {:ok, :inbound}
  def load("outbound"), do: {:ok, :outbound}
  def load(_), do: :error

  def dump(:inbound), do: {:ok, "inbound"}
  def dump(:outbound), do: {:ok, "outbound"}
  def dump(_), do: :error

  def values, do: [:inbound, :outbound]
end
