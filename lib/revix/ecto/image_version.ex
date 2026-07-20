defmodule Revix.Ecto.ImageVersion do
  use Ecto.Type

  def type, do: :string

  def cast(:large), do: {:ok, :large}
  def cast(:medium), do: {:ok, :medium}
  def cast(_), do: :error

  def load("large"), do: {:ok, :large}
  def load("medium"), do: {:ok, :medium}
  def load(_), do: :error

  def dump(:large), do: {:ok, "large"}
  def dump(:medium), do: {:ok, "medium"}
  def dump(_), do: :error

  def values, do: [:large, :medium]
end
