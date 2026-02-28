defmodule Revix.Repo.Migrations.AddRoleToPeople do
  use Ecto.Migration

  def change do
    alter table(:people) do
      add :role, :text, null: false, default: "user"
    end

    create constraint(:people, :valid_role, check: "role IN ('user', 'owner')")
  end
end
