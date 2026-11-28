defmodule RevixWeb.Plugs.ContentSecurityPolicyTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias RevixWeb.Plugs.ContentSecurityPolicy

  defp run(socket_origin \\ "wss://revix.example") do
    opts = ContentSecurityPolicy.init(socket_origin: fn -> socket_origin end)
    conn(:get, "/") |> ContentSecurityPolicy.call(opts)
  end

  defp directives(conn) do
    [policy] = get_resp_header(conn, "content-security-policy")

    policy
    |> String.split(";", trim: true)
    |> Map.new(fn directive ->
      [name | sources] = directive |> String.trim() |> String.split(" ")
      {name, sources}
    end)
  end

  test "assigns a nonce and allows only that nonce for inline scripts" do
    conn = run()
    nonce = conn.assigns.csp_nonce

    assert byte_size(nonce) >= 22
    assert directives(conn)["script-src"] == ["'self'", "'nonce-#{nonce}'"]
  end

  test "uses a fresh nonce on every request" do
    refute run().assigns.csp_nonce == run().assigns.csp_nonce
  end

  test "allows the LiveView socket origin for connections" do
    assert directives(run("ws://revix.example:4321"))["connect-src"] == [
             "'self'",
             "ws://revix.example:4321"
           ]
  end

  test "locks down everything else" do
    d = directives(run())

    assert d["default-src"] == ["'self'"]
    assert d["style-src"] == ["'self'"]
    assert d["img-src"] == ["'self'", "data:", "blob:", "https:"]
    assert d["object-src"] == ["'none'"]
    assert d["base-uri"] == ["'self'"]
    assert d["form-action"] == ["'self'"]
    assert d["frame-ancestors"] == ["'self'"]
  end

  test "socket_origin/1 maps https to wss and http to ws" do
    assert ContentSecurityPolicy.socket_origin(URI.parse("https://revix.example")) ==
             "wss://revix.example:443"

    assert ContentSecurityPolicy.socket_origin(URI.parse("http://localhost:4000")) ==
             "ws://localhost:4000"
  end

  # In prod, Plug.Builder runs init/1 at compile time and escapes the result
  # into the router, so the default options must be escapable.
  test "default options can be embedded in a compiled pipeline" do
    opts = ContentSecurityPolicy.init([])

    assert Macro.escape(opts) |> Code.eval_quoted() |> elem(0) == opts
  end

  test "derives the socket origin from the endpoint url by default" do
    opts = ContentSecurityPolicy.init([])
    conn = conn(:get, "/") |> ContentSecurityPolicy.call(opts)
    %URI{scheme: scheme, host: host, port: port} = RevixWeb.Endpoint.struct_url()
    ws = if scheme == "https", do: "wss", else: "ws"

    assert List.last(directives(conn)["connect-src"]) == "#{ws}://#{host}:#{port}"
  end
end
