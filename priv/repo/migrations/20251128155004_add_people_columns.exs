defmodule Revix.Repo.Migrations.AddPeopleColumns do
  use Ecto.Migration

  def change do
    alter table(:people) do
      add :origin, :text, null: false
      add :uri, :text, null: false
      add :url, :text, null: false
      add :username, :citext
      add :display_name, :text
      add :summary, :text
      add :public_key, :text
      add :private_key, :text
      add :icon, :text
      add :icon_media_type, :text
      add :image, :text
      add :image_media_type, :text
      add :site_title, :text
      add :site_tag, :text
      add :site_text, :text
    end

    create index(:people, [:uri], unique: true)

    create index(:people, [:username], unique: true)
  end
end
