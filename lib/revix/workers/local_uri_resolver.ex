defmodule Revix.Workers.LocalUriResolver do
  alias Revix.Entries

  # Update this list when a new entry type is added
  @local_entry_route_prefixes ~w[checkins notes posts]

  def resolve(nil), do: nil

  def resolve(value) when is_binary(value) do
    do_resolve(Entries.get_entry_by_uri(value), value)
  end

  defp do_resolve({:ok, %{uri: uri}}, _value), do: uri

  @base58_alphabet "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

  defp do_resolve({:error, :not_found}, value) do
    case extract_local_entry_id(value) do
      nil -> value
      id -> resolve_by_id(Entries.get_entry(id), value)
    end
  end

  defp resolve_by_id({:ok, %{uri: uri}}, _fallback), do: uri
  defp resolve_by_id({:error, :not_found}, fallback), do: fallback

  defp extract_local_entry_id(url) do
    local_host = Application.get_env(:revix, RevixWeb.Endpoint)[:url][:host]

    case URI.parse(url) do
      %URI{host: ^local_host, path: "/" <> rest} ->
        case String.split(rest, "/") do
          [type, id | _] when type in @local_entry_route_prefixes ->
            if valid_base58_id?(id), do: id, else: nil

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp valid_base58_id?(id) do
    String.length(id) == 11 and
      String.graphemes(id) |> Enum.all?(&String.contains?(@base58_alphabet, &1))
  end
end
