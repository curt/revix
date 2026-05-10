defmodule Revix.EntryPlaces.EntryPlace do
  use Revix.Schema
  import Ecto.Changeset
  alias Revix.Entries.Entry
  alias Revix.Places.Place

  schema "entry_places" do
    field :entry_uri, :string
    field :place_uri, :string

    has_one :entry, Entry, foreign_key: :uri, references: :entry_uri
    has_one :place, Place, foreign_key: :uri, references: :place_uri

    timestamps()
  end

  def create_changeset(entry_place, attrs) do
    entry_place
    |> cast(attrs, [:entry_uri, :place_uri])
    |> validate_required([:entry_uri, :place_uri])
    |> unique_constraint([:entry_uri, :place_uri])
  end
end
