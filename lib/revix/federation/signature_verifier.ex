defmodule Revix.Federation.SignatureVerifier do
  @behaviour HTTPSignatures.Adapter

  require Logger

  alias Revix.People
  alias Revix.Federation

  @impl true
  def fetch_public_key(conn) do
    with key_id when is_binary(key_id) <- extract_key_id(conn),
         actor_uri <- strip_key_fragment(key_id),
         {:ok, person} <- fetch_or_refresh_person(actor_uri, force_refresh: false) do
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
         {:ok, person} <- fetch_or_refresh_person(actor_uri, force_refresh: true) do
      decode_public_key(person.public_key)
    else
      err ->
        Logger.debug("SignatureVerifier.refetch_public_key failed: #{inspect(err)}")
        {:error, :key_not_found}
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

  defp fetch_or_refresh_person(actor_uri, opts) do
    force = Keyword.get(opts, :force_refresh, false)
    refresh_hours = Application.get_env(:revix, :federation)[:key_refresh_hours] || 24
    stale_cutoff = DateTime.add(DateTime.utc_now(), -refresh_hours * 3600, :second)

    case People.get_person_by_uri(actor_uri) do
      {:ok, person} when not force ->
        if DateTime.before?(person.updated_at, stale_cutoff) do
          refresh_person(actor_uri)
        else
          {:ok, person}
        end

      {:ok, _person} ->
        refresh_person(actor_uri)

      {:error, :not_found} ->
        refresh_person(actor_uri)
    end
  end

  defp refresh_person(actor_uri) do
    with {:ok, actor} <- Federation.fetch_actor(actor_uri) do
      public_key_pem =
        case actor["publicKey"] do
          %{"publicKeyPem" => pem} -> pem
          _ -> nil
        end

      attrs = %{
        uri: actor_uri,
        url: actor["url"],
        username: actor["preferredUsername"],
        display_name: actor["name"],
        public_key: public_key_pem,
        icon_url: extract_icon_url(actor)
      }

      People.upsert_remote_person(attrs)
    end
  end

  defp extract_icon_url(%{"icon" => %{"url" => url}}) when is_binary(url), do: url
  defp extract_icon_url(%{"icon" => url}) when is_binary(url), do: url
  defp extract_icon_url(_), do: nil

  defp decode_public_key(nil), do: {:error, :no_public_key}

  defp decode_public_key(pem) when is_binary(pem) do
    case X509.PublicKey.from_pem(pem) do
      {:ok, key} -> {:ok, key}
      _ -> {:error, :invalid_public_key}
    end
  end
end
