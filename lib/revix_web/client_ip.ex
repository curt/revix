defmodule RevixWeb.ClientIp do
  @moduledoc """
  The client's IP address, for per-client limits.

  Revix runs behind a reverse proxy (see DEPLOYMENT.md), so `conn.remote_ip`
  is the proxy's address. When the peer is a loopback or private address, the
  right-most `X-Forwarded-For` entry is used: that is the one the proxy
  appended, while entries to its left come from the client and can be forged.
  A request from a public peer is taken at face value.
  """

  def get(%Plug.Conn{remote_ip: peer} = conn) do
    peer
    |> Revix.IpAddress.public?()
    |> client_ip(conn)
  end

  defp client_ip(true, conn), do: conn.remote_ip

  defp client_ip(false, conn) do
    conn
    |> Plug.Conn.get_req_header("x-forwarded-for")
    |> List.last("")
    |> String.split(",")
    |> List.last()
    |> String.trim()
    |> String.to_charlist()
    |> :inet.parse_address()
    |> parsed_or(conn.remote_ip)
  end

  defp parsed_or({:ok, ip}, _peer), do: ip
  defp parsed_or({:error, _reason}, peer), do: peer
end
