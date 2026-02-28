defmodule Revix.Webfinger do
  alias Revix.People

  def get_webfinger(resource, host) do
    with {:ok, acct} <- parse_resource(resource),
         {:ok, name} <- parse_acct(acct, host),
         {:ok, person} <- People.get_local_person_by_username(name) do
      {:ok, {person, canonical_resource(name, host)}}
    end
  end

  defp parse_resource(resource) do
    case Regex.split(~r{:}, resource, parts: 2) do
      ["acct", acct] -> {:ok, acct}
      _ -> {:error, :bad_request}
    end
  end

  defp parse_acct(acct, host) do
    case Regex.split(~r{@}, acct) do
      [name, ^host] -> {:ok, name}
      [name] -> {:ok, name}
      _ -> {:error, :bad_request}
    end
  end

  defp canonical_resource(name, host), do: "acct:#{name}@#{host}"
end
