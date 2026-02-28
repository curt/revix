defmodule Revix.Ecto.EncryptedBinary do
  use Cloak.Ecto.Binary, vault: Revix.Vault
end
