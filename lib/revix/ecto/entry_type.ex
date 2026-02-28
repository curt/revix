defmodule Revix.Ecto.EntryType do
  use Ecto.Type

  def type, do: :string

  def cast(:post), do: {:ok, :post}
  def cast(:note), do: {:ok, :note}
  def cast(:checkin), do: {:ok, :checkin}
  def cast(:event), do: {:ok, :event}
  def cast(_), do: :error

  def load("post"), do: {:ok, :post}
  def load("note"), do: {:ok, :note}
  def load("checkin"), do: {:ok, :checkin}
  def load("event"), do: {:ok, :event}
  def load(_), do: :error

  def dump(:post), do: {:ok, "post"}
  def dump(:note), do: {:ok, "note"}
  def dump(:checkin), do: {:ok, "checkin"}
  def dump(:event), do: {:ok, "event"}
  def dump(_), do: :error

  def values, do: [:post, :note, :checkin, :event]
end
