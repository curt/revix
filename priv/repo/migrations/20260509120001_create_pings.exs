defmodule Revix.Repo.Migrations.CreatePings do
  use Ecto.Migration

  def change do
    create table(:pings, primary_key: false) do
      add :id, :char, primary_key: true, null: false, size: 11
      add :uri, :text, null: false
      add :type, :text, null: false
      add :direction, :text, null: false
      add :actor_uri, :text, null: false
      add :target_uri, :text, null: false
      add :object_uri, :text, null: true
      add :status, :text, null: false, default: "pending"
      add :error, :text, null: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pings, [:uri])
    create index(:pings, [:actor_uri])
    create index(:pings, [:target_uri])
    create index(:pings, [:object_uri])
    create index(:pings, [:inserted_at])
  end
end
