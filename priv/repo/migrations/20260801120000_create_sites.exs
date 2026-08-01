defmodule Revix.Repo.Migrations.CreateSites do
  use Ecto.Migration

  def change do
    create table(:sites, primary_key: false) do
      add :endpoint, :text, primary_key: true, null: false
      add :title, :text
      add :description, :text

      timestamps(type: :utc_datetime)
    end
  end
end
