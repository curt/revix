defmodule Revix.Ecto.EntryPeopleType do
  use Ecto.Type

  def type, do: :string

  def cast(:companion), do: {:ok, :companion}
  def cast(_), do: :error

  def load("companion"), do: {:ok, :companion}
  def load(_), do: :error

  def dump(:companion), do: {:ok, "companion"}
  def dump(_), do: :error

  def values, do: [:companion]
end
