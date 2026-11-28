defmodule RevixWeb.Plugs.ForwardedProtoTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias RevixWeb.Plugs.ForwardedProto

  defp call(remote_ip, headers) do
    conn = %{conn(:get, "http://app.example/") | remote_ip: remote_ip}

    headers
    |> Enum.reduce(conn, fn {k, v}, c -> put_req_header(c, k, v) end)
    |> ForwardedProto.call(ForwardedProto.init([]))
  end

  test "takes the scheme from X-Forwarded-Proto sent by a local proxy" do
    conn = call({127, 0, 0, 1}, [{"x-forwarded-proto", "https"}])
    assert conn.scheme == :https
    assert conn.port == 443
  end

  test "takes the scheme from X-Forwarded-Proto sent by a private-network proxy" do
    assert call({10, 0, 0, 7}, [{"x-forwarded-proto", "https"}]).scheme == :https
  end

  test "ignores X-Forwarded-Proto from a public client" do
    assert call({93, 184, 216, 34}, [{"x-forwarded-proto", "https"}]).scheme == :http
  end

  test "never takes the host or port from forwarded headers" do
    conn =
      call({127, 0, 0, 1}, [
        {"x-forwarded-host", "evil.example"},
        {"x-forwarded-port", "8443"}
      ])

    assert conn.host == "app.example"
    assert conn.port == 80
  end
end
