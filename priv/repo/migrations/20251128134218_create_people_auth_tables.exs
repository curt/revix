defmodule Revix.Repo.Migrations.CreatePeopleAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:people, primary_key: false) do
      add :id, :char, primary_key: true, null: false, size: 11
      add :email, :citext, null: false
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:people, [:email])

    create table(:people_tokens, primary_key: false) do
      add :id, :char, primary_key: true, null: false, size: 11

      add :person_id, references(:people, type: :char, on_delete: :delete_all),
        null: false,
        size: 11

      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:people_tokens, [:person_id])
    create unique_index(:people_tokens, [:context, :token])
  end
end
