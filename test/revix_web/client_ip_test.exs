defmodule RevixWeb.ClientIpTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias RevixWeb.ClientIp

  defp conn_from(remote_ip, forwarded \\ []) do
    conn = %{conn(:get, "/") | remote_ip: remote_ip}

    Enum.reduce(forwarded, conn, fn value, c ->
      %{c | req_headers: c.req_headers ++ [{"x-forwarded-for", value}]}
    end)
  end

  test "uses the address the local proxy appended to X-Forwarded-For" do
    conn = conn_from({127, 0, 0, 1}, ["198.51.100.9, 203.0.113.7"])
    assert ClientIp.get(conn) == {203, 0, 113, 7}
  end

  test "trusts a proxy on a private network, such as a Docker bridge" do
    assert ClientIp.get(conn_from({172, 18, 0, 1}, ["203.0.113.7"])) == {203, 0, 113, 7}
  end

  test "reads the last of several X-Forwarded-For headers" do
    conn = conn_from({127, 0, 0, 1}, ["198.51.100.9", "203.0.113.7"])
    assert ClientIp.get(conn) == {203, 0, 113, 7}
  end

  test "parses an IPv6 client address" do
    assert ClientIp.get(conn_from({127, 0, 0, 1}, ["2001:db8::5"])) ==
             {0x2001, 0xDB8, 0, 0, 0, 0, 0, 5}
  end

  test "ignores X-Forwarded-For from a public address, which could be forged" do
    assert ClientIp.get(conn_from({198, 51, 100, 1}, ["203.0.113.7"])) == {198, 51, 100, 1}
  end

  test "falls back to the peer address when the header is missing or unparseable" do
    assert ClientIp.get(conn_from({127, 0, 0, 1})) == {127, 0, 0, 1}
    assert ClientIp.get(conn_from({127, 0, 0, 1}, ["not-an-ip"])) == {127, 0, 0, 1}
  end
end
