defmodule Revix.Follows.Follow do
  use Revix.Schema
  import Ecto.Changeset
  alias Revix.Ecto.Origin

  schema "follows" do
    field :uri, :string
    field :follower_uri, :string
    field :following_uri, :string
    field :origin, Origin
    field :accepted_at, :utc_datetime
    field :rejected_at, :utc_datetime
    field :unfollowed_at, :utc_datetime

    timestamps()
  end

  def create_changeset(follow, attrs) do
    follow
    |> cast(attrs, [:uri, :follower_uri, :following_uri, :origin, :accepted_at])
    |> validate_required([:uri, :follower_uri, :following_uri, :origin])
    |> unique_constraint(:uri)
    |> unique_constraint([:follower_uri, :following_uri])
  end

  def accept_changeset(follow) do
    change(follow, accepted_at: DateTime.utc_now(:second))
  end

  def reject_changeset(follow) do
    change(follow, rejected_at: DateTime.utc_now(:second))
  end

  def unfollow_changeset(follow) do
    change(follow, unfollowed_at: DateTime.utc_now(:second))
  end

  def refollow_changeset(follow) do
    change(follow, unfollowed_at: nil, accepted_at: nil, rejected_at: nil)
  end

  def active?(%__MODULE__{unfollowed_at: nil, rejected_at: nil}), do: true
  def active?(_), do: false
end
