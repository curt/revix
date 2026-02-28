defmodule Revix.Vault do
  use Cloak.Vault, otp_app: :revix

  @impl GenServer
  def init(config) do
    if Keyword.has_key?(config, :ciphers) do
      # Static config already set (e.g. config/test.exs) — use it as-is.
      {:ok, config}
    else
      {:ok,
       Keyword.put(config, :ciphers,
         default: {
           Cloak.Ciphers.AES.GCM,
           tag: "AES.GCM.V1", key: Base.decode64!(System.fetch_env!("CLOAK_KEY"))
         }
       )}
    end
  end
end
