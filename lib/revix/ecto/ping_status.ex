defmodule Revix.Ecto.PingStatus do
  use Ecto.Type

  def type, do: :string

  def cast(:pending), do: {:ok, :pending}
  def cast(:delivered), do: {:ok, :delivered}
  def cast(:failed), do: {:ok, :failed}
  def cast(_), do: :error

  def load("pending"), do: {:ok, :pending}
  def load("delivered"), do: {:ok, :delivered}
  def load("failed"), do: {:ok, :failed}
  def load(_), do: :error

  def dump(:pending), do: {:ok, "pending"}
  def dump(:delivered), do: {:ok, "delivered"}
  def dump(:failed), do: {:ok, "failed"}
  def dump(_), do: :error

  def values, do: [:pending, :delivered, :failed]
end
