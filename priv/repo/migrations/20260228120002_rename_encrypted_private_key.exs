defmodule Revix.Repo.Migrations.RenameEncryptedPrivateKey do
  use Ecto.Migration

  def up do
    alter table(:people) do
      remove :private_key
    end

    rename table(:people), :encrypted_private_key, to: :private_key
  end

  def down do
    rename table(:people), :private_key, to: :encrypted_private_key

    alter table(:people) do
      add :private_key, :text
    end
  end
end
