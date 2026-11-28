defmodule Revix.Federation.SafeHttp do
  @moduledoc """
  HTTP requests to URLs that came from remote servers or users.

  Federation hands us URLs we didn't choose: an inbound signature's `keyId`,
  an actor's `inbox` and `icon`, a note's attachments. Before each request
  (and each redirect hop) the URL must be https and its host must resolve
  only to public addresses, so nobody can point the server at localhost, the
  cloud metadata service, or the internal network.

  Redirects are followed by hand, up to three hops, so each one is checked; POSTs
  never follow redirects. A host could still change its DNS answer between
  this check and the connection (DNS rebinding); pinning the resolved
  address would close that gap.
  """

  @max_redirects 3
  @redirect_statuses [301, 302, 303, 307, 308]

  def get(url, opts), do: get(url, opts, @max_redirects)

  def post(url, opts) do
    with :ok <- check_url(url) do
      Req.post(url, Keyword.put(opts, :redirect, false))
    end
  end

  def check_url(url) when is_binary(url) do
    url
    |> URI.parse()
    |> check_uri()
  end

  def check_url(_url), do: {:error, :unsafe_url}

  defp get(_url, _opts, -1), do: {:error, :too_many_redirects}

  defp get(url, opts, hops_left) do
    with :ok <- check_url(url),
         {:ok, response} <- Req.get(url, Keyword.put(opts, :redirect, false)) do
      follow(response, url, opts, hops_left)
    end
  end

  defp follow(%Req.Response{status: status} = response, url, opts, hops_left)
       when status in @redirect_statuses do
    response
    |> Req.Response.get_header("location")
    |> follow_location(response, url, opts, hops_left)
  end

  defp follow(response, _url, _opts, _hops_left), do: {:ok, response}

  defp follow_location([location | _], _response, url, opts, hops_left),
    do: get(url |> URI.merge(location) |> URI.to_string(), opts, hops_left - 1)

  defp follow_location([], response, _url, _opts, _hops_left), do: {:ok, response}

  defp check_uri(%URI{scheme: "https", host: host}) when is_binary(host) and host != "" do
    host
    |> addresses()
    |> all_public()
  end

  defp check_uri(_uri), do: {:error, :unsafe_url}

  defp addresses(host) do
    host
    |> String.to_charlist()
    |> :inet.parse_address()
    |> literal_or_resolved(host)
  end

  defp literal_or_resolved({:ok, ip}, _host), do: {:ok, [ip]}
  defp literal_or_resolved({:error, :einval}, host), do: resolver().resolve(host)

  defp all_public({:ok, [_ | _] = ips}),
    do: ok_if_public(Enum.all?(ips, &Revix.IpAddress.public?/1))

  defp all_public(_unresolved), do: {:error, :unsafe_url}

  defp ok_if_public(true), do: :ok
  defp ok_if_public(false), do: {:error, :unsafe_url}

  defp resolver, do: Application.get_env(:revix, :dns_resolver, __MODULE__.InetResolver)

  defmodule InetResolver do
    @moduledoc false

    def resolve(host) do
      charlist = String.to_charlist(host)

      [:inet, :inet6]
      |> Enum.flat_map(&lookup(charlist, &1))
      |> found()
    end

    defp lookup(host, family), do: host |> :inet.getaddrs(family) |> ips()

    defp ips({:ok, ips}), do: ips
    defp ips({:error, _reason}), do: []

    defp found([]), do: {:error, :nxdomain}
    defp found(ips), do: {:ok, ips}
  end
end
