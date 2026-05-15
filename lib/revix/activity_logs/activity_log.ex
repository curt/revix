defmodule Revix.ActivityLogs.ActivityLog do
  use Revix.Schema
  import Ecto.Changeset

  schema "activity_logs" do
    field :direction, Revix.Ecto.Direction
    field :activity_type, :string
    field :object_type, :string
    field :actor_uri, :string
    field :activity_uri, :string
    field :body, :string
    field :status, :string
    field :request_id, :string

    timestamps()
  end

  def create_changeset(log, attrs) do
    log
    |> cast(attrs, [
      :direction,
      :activity_type,
      :object_type,
      :actor_uri,
      :activity_uri,
      :body,
      :status,
      :request_id
    ])
    |> validate_required([:direction, :activity_type, :actor_uri, :activity_uri, :body, :status])
  end
end
