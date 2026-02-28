defmodule Revix.Repo.Migrations.AddEncryptedPrivateKey do
  use Ecto.Migration

  def change do
    alter table(:people) do
      add :encrypted_private_key, :binary
    end
  end
end
