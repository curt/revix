defmodule Revix.Repo.Migrations.AddObanJobs do
  use Ecto.Migration

  def up, do: Oban.Migrations.up(version: 14)
  def down, do: Oban.Migrations.down(version: 1)
end
