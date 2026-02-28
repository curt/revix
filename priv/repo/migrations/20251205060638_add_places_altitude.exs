defmodule Revix.Repo.Migrations.AddPlacesAltitude do
  use Ecto.Migration

  def change do
    alter table(:places) do
      add :altitude, :float
    end
  end
end
