defmodule Revix.Repo.Migrations.AddOsmToPlaces do
  use Ecto.Migration

  def change do
    alter table(:places) do
      add :osm_type, :text
      add :osm_id, :bigint
    end
  end
end
