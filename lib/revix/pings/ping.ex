defmodule Revix.Pings.Ping do
  use Revix.Schema
  import Ecto.Changeset

  schema "pings" do
    field :uri, :string
    field :type, Revix.Ecto.PingType
    field :direction, Revix.Ecto.Direction
    field :actor_uri, :string
    field :target_uri, :string
    field :object_uri, :string
    field :status, Revix.Ecto.PingStatus, default: :pending
    field :error, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(ping, attrs) do
    ping
    |> cast(attrs, [
      :uri,
      :type,
      :direction,
      :actor_uri,
      :target_uri,
      :object_uri,
      :status,
      :error
    ])
    |> validate_required([:uri, :type, :direction, :actor_uri, :target_uri, :status])
    |> unique_constraint(:uri)
  end
end
