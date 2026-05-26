defmodule Revix.Ecto.OsmElementType do
  use Ecto.Type

  def type, do: :string

  def cast("node"), do: {:ok, :node}
  def cast("way"), do: {:ok, :way}
  def cast("relation"), do: {:ok, :relation}
  def cast(value) when is_binary(value), do: :error
  def cast(:node), do: {:ok, :node}
  def cast(:way), do: {:ok, :way}
  def cast(:relation), do: {:ok, :relation}
  def cast(_), do: :error

  def load("node"), do: {:ok, :node}
  def load("way"), do: {:ok, :way}
  def load("relation"), do: {:ok, :relation}
  def load(_), do: :error

  def dump(:node), do: {:ok, "node"}
  def dump(:way), do: {:ok, "way"}
  def dump(:relation), do: {:ok, "relation"}
  def dump(_), do: :error

  def values, do: [:node, :way, :relation]
end
