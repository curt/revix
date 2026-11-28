defmodule RevixWeb.Plugs.ForwardedProto do
  @moduledoc """
  Takes the request scheme from `X-Forwarded-Proto`, but only when the peer
  is a loopback or private address: the reverse proxy Revix runs behind (see
  DEPLOYMENT.md). From any other peer the header is ignored.

  The host and port are never taken from forwarded headers. URLs are built
  from the endpoint's configured URL instead, so a client can't put its own
  host into them.
  """
  @behaviour Plug

  @impl true
  def init(opts), do: Plug.RewriteOn.init([:x_forwarded_proto] ++ opts)

  @impl true
  def call(%Plug.Conn{remote_ip: peer} = conn, rewrite_on) do
    peer
    |> Revix.IpAddress.public?()
    |> rewrite(conn, rewrite_on)
  end

  defp rewrite(true, conn, _rewrite_on), do: conn
  defp rewrite(false, conn, rewrite_on), do: Plug.RewriteOn.call(conn, rewrite_on)
end
