defmodule Revix.Federation.Origin do
  @moduledoc """
  Compares the origins (scheme, host, port) of federation URIs.

  A remote server may only speak for objects it hosts: an actor's `id`, or a
  note it creates, must share the origin of the URI it was fetched from or
  the actor that sent it. Otherwise one server could claim objects on
  another, including this one.
  """

  def same?(a, b) when is_binary(a) and is_binary(b) do
    same_origin(origin(a), origin(b))
  end

  def same?(_a, _b), do: false

  defp same_origin({_scheme, nil, _port}, _other), do: false
  defp same_origin(origin, origin), do: true
  defp same_origin(_origin, _other), do: false

  defp origin(uri) do
    %URI{scheme: scheme, host: host, port: port} = URI.parse(uri)
    {scheme, host && String.downcase(host), port}
  end
end
