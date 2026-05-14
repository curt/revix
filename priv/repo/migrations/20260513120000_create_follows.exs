defmodule Revix.Repo.Migrations.CreateFollows do
  use Ecto.Migration

  def change do
    create table(:follows, primary_key: false) do
      add :id, :char, primary_key: true, null: false, size: 11
      add :uri, :text, null: false
      add :follower_uri, :text, null: false
      add :following_uri, :text, null: false
      add :origin, :text, null: false, default: "local"
      add :accepted_at, :utc_datetime
      add :unfollowed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:follows, [:uri])
    create unique_index(:follows, [:follower_uri, :following_uri])
    create index(:follows, [:follower_uri])
    create index(:follows, [:following_uri])
  end
end
