defmodule Revix.Repo.Migrations.CreateLikes do
  use Ecto.Migration

  def change do
    create table(:likes, primary_key: false) do
      add :id, :char, primary_key: true, null: false, size: 11
      add :author_uri, :text, null: false
      add :object_uri, :text, null: false
      add :origin, :text, null: false, default: "local"
      add :published_at_utc, :utc_datetime, null: false
      add :published_at_local, :naive_datetime, null: false
      add :published_tz, :text, null: false
      # Soft delete: set when unliked, cleared on re-like. UTC only, no local/tz needed.
      add :unliked_at, :utc_datetime, null: true

      timestamps()
    end

    create unique_index(:likes, [:author_uri, :object_uri])
    create index(:likes, [:object_uri])
    create index(:likes, [:author_uri])
  end
end
