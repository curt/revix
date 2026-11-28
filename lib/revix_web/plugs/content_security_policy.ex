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

  # In prod, init/1 runs at compile time and its result is escaped into the
  # router, so the default must not be an anonymous function.
  @impl Plug
  def init(opts), do: Keyword.get(opts, :socket_origin)

  @impl Plug
  def call(conn, socket_origin) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy(nonce, resolve(socket_origin)))
  end

  defp resolve(nil), do: socket_origin(RevixWeb.Endpoint.struct_url())
  defp resolve(socket_origin), do: socket_origin.()

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

  @doc "The websocket origin (scheme, host, and port) for an endpoint URL."
  def socket_origin(%URI{scheme: scheme, host: host, port: port}),
    do: "#{socket_scheme(scheme)}://#{host}:#{port}"

  defp socket_scheme("https"), do: "wss"
  defp socket_scheme(_), do: "ws"
end
