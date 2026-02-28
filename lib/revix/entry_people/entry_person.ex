defmodule Revix.EntryPeople.EntryPerson do
  use Revix.Schema
  import Ecto.Changeset
  alias Revix.Ecto.EntryPeopleType
  alias Revix.Ecto.Origin
  alias Revix.Entries.Entry
  alias Revix.People.Person

  schema "entry_people" do
    field :entry_uri, :string
    field :person_uri, :string
    field :type, EntryPeopleType, default: :companion
    field :origin, Origin, default: :local

    has_one :entry, Entry, foreign_key: :uri, references: :entry_uri
    has_one :person, Person, foreign_key: :uri, references: :person_uri

    timestamps()
  end

  def create_changeset(entry_person, attrs) do
    entry_person
    |> cast(attrs, [:entry_uri, :person_uri, :type, :origin])
    |> validate_required([:entry_uri, :person_uri, :type, :origin])
    |> unique_constraint([:entry_uri, :person_uri, :type])
  end
end
