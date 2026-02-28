defmodule Revix.Repo.Migrations.AddPlacesIndexName do
  use Ecto.Migration

  def change do
    create index(:places, [:name])
  end
end
