defmodule Revix.Repo.Migrations.CreateImageDimensions do
  use Ecto.Migration

  def change do
    create table(:image_dimensions, primary_key: false) do
      add :id, :char, primary_key: true, null: false, size: 11

      add :image_id, references(:images, type: :char, on_delete: :delete_all),
        null: false,
        size: 11

      add :version, :text, null: false
      add :width, :integer, null: false
      add :height, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:image_dimensions, [:image_id, :version])
  end
end
