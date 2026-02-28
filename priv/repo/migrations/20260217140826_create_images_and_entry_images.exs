defmodule Revix.Repo.Migrations.CreateImagesAndEntryImages do
  use Ecto.Migration

  def change do
    create table(:images, primary_key: false) do
      add :id, :char, primary_key: true, null: false, size: 11
      add :file, :text, null: false
      add :alt, :text
      add :caption, :text
      add :caption_html, :text
      add :content_type, :text
      add :original_filename, :text
      add :author_uri, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:images, [:author_uri])

    create table(:entry_images, primary_key: false) do
      add :id, :char, primary_key: true, null: false, size: 11

      add :entry_id, references(:entries, type: :char, on_delete: :delete_all),
        null: false,
        size: 11

      add :image_id, references(:images, type: :char, on_delete: :delete_all),
        null: false,
        size: 11

      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:entry_images, [:entry_id, :image_id])
    create index(:entry_images, [:entry_id, :position])
  end
end
