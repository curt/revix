defmodule Revix.Ecto.NotificationType do
  use Ecto.Type

  def type, do: :string

  def cast(:owner_entry), do: {:ok, :owner_entry}
  def cast(:followed_entry), do: {:ok, :followed_entry}
  def cast(:companion_tag), do: {:ok, :companion_tag}
  def cast(:reply), do: {:ok, :reply}
  def cast(:like), do: {:ok, :like}
  def cast(:registration), do: {:ok, :registration}
  def cast(_), do: :error

  def load("owner_entry"), do: {:ok, :owner_entry}
  def load("followed_entry"), do: {:ok, :followed_entry}
  def load("companion_tag"), do: {:ok, :companion_tag}
  def load("reply"), do: {:ok, :reply}
  def load("like"), do: {:ok, :like}
  def load("registration"), do: {:ok, :registration}
  def load(_), do: :error

  def dump(:owner_entry), do: {:ok, "owner_entry"}
  def dump(:followed_entry), do: {:ok, "followed_entry"}
  def dump(:companion_tag), do: {:ok, "companion_tag"}
  def dump(:reply), do: {:ok, "reply"}
  def dump(:like), do: {:ok, "like"}
  def dump(:registration), do: {:ok, "registration"}
  def dump(_), do: :error

  def values,
    do: [:owner_entry, :followed_entry, :companion_tag, :reply, :like, :registration]
end
