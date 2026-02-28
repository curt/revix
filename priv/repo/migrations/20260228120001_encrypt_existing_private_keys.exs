defmodule Revix.Repo.Migrations.EncryptExistingPrivateKeys do
  use Ecto.Migration

  def up do
    import Ecto.Query

    # Encrypt directly via the cipher — no vault GenServer needed, avoids
    # process name conflicts when the app supervisor is also starting.
    key = Base.decode64!(System.fetch_env!("CLOAK_KEY"))
    cipher_opts = [tag: "AES.GCM.V1", key: key]

    Revix.Repo.all(
      from(p in "people",
        where: not is_nil(p.private_key) and is_nil(p.encrypted_private_key),
        select: %{id: p.id, private_key: p.private_key}
      )
    )
    |> Enum.each(fn %{id: id, private_key: plaintext} ->
      {:ok, encrypted} = Cloak.Ciphers.AES.GCM.encrypt(plaintext, cipher_opts)

      Revix.Repo.update_all(
        from(p in "people", where: p.id == ^id),
        set: [encrypted_private_key: encrypted]
      )
    end)
  end

  def down do
    # Rolling back this migration leaves encrypted_private_key populated and
    # private_key intact. Migration 1's down drops encrypted_private_key anyway.
    :ok
  end
end
