defmodule Revix.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :char, primary_key: true, null: false, size: 11
      add :recipient_uri, :text, null: false
      add :type, :text, null: false
      add :subject_uri, :text, null: false
      add :actor_uri, :text
      add :summary, :text, null: false
      add :url, :text
      add :sent_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:notifications, [:recipient_uri, :sent_at])
    create index(:notifications, [:inserted_at])
    create unique_index(:notifications, [:recipient_uri, :type, :subject_uri])
  end
end
