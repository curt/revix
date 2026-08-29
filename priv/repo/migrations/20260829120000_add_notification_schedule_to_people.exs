defmodule Revix.Repo.Migrations.AddNotificationScheduleToPeople do
  use Ecto.Migration

  def change do
    alter table(:people) do
      add :notification_schedule, :text, null: false, default: "daily"
    end
  end
end
