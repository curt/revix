defmodule RevixWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Sets a Content-Security-Policy header and assigns `:csp_nonce` for the
  root layout's inline script.

  Scripts are limited to same-origin files and the per-request nonce, so
  injected markup can't run inline handlers or `javascript:` URLs. Images may
  come from any https host because Markdown and federated posts embed remote
  images (custom emoji, for example), and images can't run script.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: Keyword.get(opts, :socket_origin, &endpoint_socket_origin/0)

  @impl Plug
  def call(conn, socket_origin) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy(nonce, socket_origin.()))
  end

  defp policy(nonce, socket_origin) do
    [
      "default-src 'self'",
      "script-src 'self' 'nonce-#{nonce}'",
      "style-src 'self'",
      "img-src 'self' data: blob: https:",
      "connect-src 'self' #{socket_origin}",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'",
      "frame-ancestors 'self'"
    ]
    |> Enum.join("; ")
  end

  defp endpoint_socket_origin, do: socket_origin(RevixWeb.Endpoint.struct_url())

  @doc "The websocket origin (scheme, host, and port) for an endpoint URL."
  def socket_origin(%URI{scheme: scheme, host: host, port: port}),
    do: "#{socket_scheme(scheme)}://#{host}:#{port}"

  defp socket_scheme("https"), do: "wss"
  defp socket_scheme(_), do: "ws"
end
