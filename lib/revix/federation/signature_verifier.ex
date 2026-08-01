defmodule Revix.Federation.SignatureVerifier do
  @behaviour HTTPSignatures.Adapter

  require Logger

  alias Revix.People

  @impl true
  def fetch_public_key(conn) do
    with key_id when is_binary(key_id) <- extract_key_id(conn),
         actor_uri <- strip_key_fragment(key_id),
         {:ok, person} <- People.get_or_fetch_person_by_uri(actor_uri) do
      decode_public_key(person.public_key)
    else
      err ->
        Logger.debug("SignatureVerifier.fetch_public_key failed: #{inspect(err)}")
        {:error, :key_not_found}
    end
  end

  @impl true
  def refetch_public_key(conn) do
    with key_id when is_binary(key_id) <- extract_key_id(conn),
         actor_uri <- strip_key_fragment(key_id),
         {:ok, person} <- People.get_or_fetch_person_by_uri(actor_uri, force_refresh: true) do
      decode_public_key(person.public_key)
    else
      err ->
        Logger.debug("SignatureVerifier.refetch_public_key failed: #{inspect(err)}")
        {:error, :key_not_found}
    end
  end

  def verified_key_id(conn) do
    case extract_key_id(conn) do
      key_id when is_binary(key_id) -> {:ok, strip_key_fragment(key_id)}
      _ -> {:error, :no_signature}
    end
  end

  defp extract_key_id(conn) do
    headers = Enum.into(conn.req_headers, %{})
    sig_header = headers["signature"] || ""
    parsed = HTTPSignatures.split_signature(sig_header)
    parsed["keyId"]
  end

  defp strip_key_fragment(key_id) do
    case URI.parse(key_id) do
      %URI{fragment: nil} -> key_id
      %URI{} = uri -> URI.to_string(%{uri | fragment: nil})
    end
  end

  defp decode_public_key(nil), do: {:error, :no_public_key}

  defp decode_public_key(pem) when is_binary(pem) do
    case X509.PublicKey.from_pem(pem) do
      {:ok, key} -> {:ok, key}
      _ -> {:error, :invalid_public_key}
    end
  end
end
