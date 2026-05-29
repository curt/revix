defmodule Revix.Repo.Migrations.AddModifiedAtUtcToEntries do
  use Ecto.Migration

  def change do
    alter table(:entries) do
      add :modified_at_utc, :utc_datetime
    end

    create index(:entries, [:modified_at_utc])
  end
end
