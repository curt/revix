defmodule Revix.Repo.Migrations.AddAutoLocateOnCheckinToPeople do
  use Ecto.Migration

  def change do
    alter table(:people) do
      add :auto_locate_on_checkin, :boolean, null: false, default: false
    end
  end
end
