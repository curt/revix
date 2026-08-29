defmodule Revix.Notifications.Notification do
  use Revix.Schema
  import Ecto.Changeset

  alias Revix.Ecto.NotificationType

  schema "notifications" do
    field :recipient_uri, :string
    field :type, NotificationType
    field :subject_uri, :string
    field :actor_uri, :string
    field :summary, :string
    field :url, :string
    field :sent_at, :utc_datetime

    timestamps()
  end

  def create_changeset(notification, attrs) do
    notification
    |> cast(attrs, [:recipient_uri, :type, :subject_uri, :actor_uri, :summary, :url])
    |> validate_required([:recipient_uri, :type, :subject_uri, :summary])
    |> unique_constraint([:recipient_uri, :type, :subject_uri],
      name: :notifications_recipient_uri_type_subject_uri_index
    )
  end
end
