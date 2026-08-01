defmodule Revix.Repo.Migrations.AddRejectedAtToFollows do
  use Ecto.Migration

  def change do
    alter table(:follows) do
      add :rejected_at, :utc_datetime
    end
  end
end
