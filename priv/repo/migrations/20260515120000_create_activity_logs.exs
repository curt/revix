defmodule Revix.Repo.Migrations.CreateActivityLogs do
  use Ecto.Migration

  def change do
    create table(:activity_logs, primary_key: false) do
      add :id, :char, primary_key: true, null: false, size: 11
      add :direction, :text, null: false
      add :activity_type, :text, null: false
      add :object_type, :text, null: true
      add :actor_uri, :text, null: false
      add :activity_uri, :text, null: false
      add :body, :text, null: false
      add :status, :text, null: false
      add :request_id, :text, null: true

      timestamps()
    end

    create index(:activity_logs, [:actor_uri])
    create index(:activity_logs, [:activity_uri])
    create index(:activity_logs, [:request_id])
    create index(:activity_logs, [:direction, :inserted_at])
  end
end
