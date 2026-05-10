defmodule Revix.Repo.Migrations.RelaxUsernameUniquenessToLocal do
  use Ecto.Migration

  def up do
    drop_if_exists index(:people, [:username], unique: true, name: :people_username_index)

    create index(:people, [:username],
             unique: true,
             where: "origin = 'local'",
             name: :people_username_index
           )
  end

  def down do
    drop_if_exists index(:people, [:username],
                     unique: true,
                     where: "origin = 'local'",
                     name: :people_username_index
                   )

    create index(:people, [:username], unique: true, name: :people_username_index)
  end
end
