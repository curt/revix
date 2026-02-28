defmodule Revix.Repo.Migrations.ChangePlacesNameCollation do
  use Ecto.Migration

  def up do
    drop index(:places, [:name])
    execute "ALTER TABLE places ALTER COLUMN name TYPE text COLLATE \"und-x-icu\""
    create index(:places, [:name])
  end

  def down do
    drop index(:places, [:name])
    execute "ALTER TABLE places ALTER COLUMN name TYPE text COLLATE \"default\""
    create index(:places, [:name])
  end
end
