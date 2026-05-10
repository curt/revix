defmodule Revix.Repo.Migrations.CreateEntryPlaces do
  use Ecto.Migration

  def change do
    create table(:entry_places, primary_key: false) do
      add :id, :char, primary_key: true, null: false, size: 11
      add :entry_uri, :text, null: false
      add :place_uri, :text, null: false

      timestamps()
    end

    create unique_index(:entry_places, [:entry_uri, :place_uri])
    create index(:entry_places, [:entry_uri])
    create index(:entry_places, [:place_uri])
  end
end
