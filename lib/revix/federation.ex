defmodule Revix.Federation do
  require Logger

  @activity_type "application/activity+json"

  def fetch_actor(uri) do
    opts = req_opts(headers: [{"accept", @activity_type}])

    case Req.get(uri, opts) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, map} when is_map(map) -> {:ok, map}
          _ -> {:error, {:http_error, 200}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def resolve_inbox(actor_uri) do
    with {:ok, actor} <- fetch_actor(actor_uri) do
      case actor["inbox"] do
        inbox when is_binary(inbox) -> {:ok, inbox}
        _ -> {:error, :no_inbox}
      end
    end
  end

  def deliver(activity_json, inbox_url, actor) do
    body = Jason.encode!(activity_json)
    uri = URI.parse(inbox_url)
    date = format_date()
    digest = "SHA-256=" <> (:crypto.hash(:sha256, body) |> Base.encode64())

    headers_to_sign = %{
      "(request-target)" => "post #{uri.path}",
      "host" => uri.host,
      "date" => date,
      "digest" => digest,
      "content-type" => "application/activity+json"
    }

    key_id = "#{actor.uri}#key"

    with {:ok, private_key} <- decode_private_key(actor.private_key) do
      signature = HTTPSignatures.sign(private_key, key_id, headers_to_sign)

      req_headers = [
        {"host", uri.host},
        {"date", date},
        {"digest", digest},
        {"content-type", "application/activity+json"},
        {"signature", signature}
      ]

      opts = req_opts(headers: req_headers, body: body)

      case Req.post(inbox_url, opts) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok

        {:ok, %{status: status}} ->
          {:error, {:http_error, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp decode_private_key(pem) when is_binary(pem) do
    case X509.PrivateKey.from_pem(pem) do
      {:ok, key} -> {:ok, key}
      _ -> {:error, :invalid_private_key}
    end
  end

  defp format_date do
    Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S GMT")
  end

  defp req_opts(extra_opts) do
    plug = Application.get_env(:revix, :federation_req_plug)
    base = [decode_body: true, retry: false]

    if plug do
      Keyword.put(base, :plug, plug) ++ extra_opts
    else
      base ++ extra_opts
    end
  end
end
