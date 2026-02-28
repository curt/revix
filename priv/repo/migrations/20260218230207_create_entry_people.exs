defmodule Revix.Repo.Migrations.CreateEntryPeople do
  use Ecto.Migration

  def change do
    create table(:entry_people, primary_key: false) do
      add :id, :char, primary_key: true, null: false, size: 11
      add :entry_uri, :text, null: false
      add :person_uri, :text, null: false
      add :type, :text, null: false, default: "companion"
      add :origin, :text, null: false, default: "local"

      timestamps()
    end

    create unique_index(:entry_people, [:entry_uri, :person_uri, :type])
    create index(:entry_people, [:entry_uri])
    create index(:entry_people, [:person_uri])
  end
end
