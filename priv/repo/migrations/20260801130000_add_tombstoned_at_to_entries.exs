defmodule Revix.Repo.Migrations.AddTombstonedAtToEntries do
  use Ecto.Migration

  def change do
    alter table(:entries) do
      add :tombstoned_at, :utc_datetime
    end
  end
end
