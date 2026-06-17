defmodule Revix.Ecto.Role do
  use Ecto.Type

  def type, do: :string

  def cast(:user), do: {:ok, :user}
  def cast(:contributor), do: {:ok, :contributor}
  def cast(:owner), do: {:ok, :owner}
  def cast(_), do: :error

  def load("user"), do: {:ok, :user}
  def load("contributor"), do: {:ok, :contributor}
  def load("owner"), do: {:ok, :owner}
  def load(_), do: :error

  def dump(:user), do: {:ok, "user"}
  def dump(:contributor), do: {:ok, "contributor"}
  def dump(:owner), do: {:ok, "owner"}
  def dump(_), do: :error

  def values, do: [:user, :contributor, :owner]
end
