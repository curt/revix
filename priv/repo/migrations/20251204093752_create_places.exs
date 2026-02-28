defmodule Revix.Repo.Migrations.CreatePlaces do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS postgis", ""

    create table(:places, primary_key: false) do
      add :id, :char, primary_key: true, null: false, size: 11
      add :name, :text, null: false
      add :coordinates, :"geography(point, 4326)", null: false
      add :origin, :text, null: false
      add :uri, :text, null: false
      add :url, :text, null: false
      add :summary, :text
      add :summary_html, :text
      add :content, :text
      add :content_html, :text
      add :slug, :text

      timestamps(type: :utc_datetime)
    end

    create index(:places, [:uri], unique: true)

    create index(:places, [:coordinates], using: :gist)
  end
end
