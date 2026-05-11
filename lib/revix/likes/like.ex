defmodule Revix.Likes.Like do
  use Revix.Schema
  import Ecto.Changeset
  alias Revix.Ecto.Origin
  alias Revix.People.Person

  schema "likes" do
    field :like_uri, :string
    field :author_uri, :string
    field :object_uri, :string
    field :origin, Origin
    field :published_at_utc, :utc_datetime
    field :published_at_local, :naive_datetime
    field :published_tz, :string
    # Soft delete: set when unliked, cleared on re-like. UTC only, no local/tz needed.
    field :unliked_at, :utc_datetime

    # Virtual field: the liked object entry, populated for activity feed display
    field :object, :map, virtual: true

    has_one :author, Person, foreign_key: :uri, references: :author_uri

    timestamps()
  end

  def active?(%__MODULE__{unliked_at: nil}), do: true
  def active?(_), do: false

  def create_changeset(like, attrs) do
    like
    |> cast(attrs, [
      :like_uri,
      :author_uri,
      :object_uri,
      :origin,
      :published_at_utc,
      :published_at_local,
      :published_tz
    ])
    |> validate_required([
      :like_uri,
      :author_uri,
      :object_uri,
      :origin,
      :published_at_utc,
      :published_at_local,
      :published_tz
    ])
    |> unique_constraint(:like_uri)
    |> unique_constraint([:author_uri, :object_uri])
  end

  def unlike_changeset(like) do
    change(like, unliked_at: DateTime.utc_now(:second))
  end

  def re_like_changeset(like, attrs) do
    like
    |> cast(attrs, [:published_at_utc, :published_at_local, :published_tz])
    |> validate_required([:published_at_utc, :published_at_local, :published_tz])
    |> put_change(:unliked_at, nil)
  end
end
