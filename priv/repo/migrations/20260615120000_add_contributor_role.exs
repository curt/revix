defmodule Revix.Repo.Migrations.AddContributorRole do
  use Ecto.Migration

  def up do
    drop constraint(:people, :valid_role)
    create constraint(:people, :valid_role, check: "role IN ('user', 'contributor', 'owner')")
  end

  def down do
    drop constraint(:people, :valid_role)
    create constraint(:people, :valid_role, check: "role IN ('user', 'owner')")
  end
end
