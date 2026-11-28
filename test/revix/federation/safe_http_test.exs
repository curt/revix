defmodule Revix.Federation.SafeHttpTest do
  use ExUnit.Case, async: true

  alias Revix.Federation.SafeHttp

  describe "check_url/1" do
    test "allows an https URL on a public host" do
      assert SafeHttp.check_url("https://remote.example.com/users/alice") == :ok
    end

    test "rejects non-https schemes" do
      for url <- [
            "http://remote.example.com/x",
            "ftp://remote.example.com/x",
            "file:///etc/passwd"
          ] do
        assert SafeHttp.check_url(url) == {:error, :unsafe_url}, url
      end
    end

    test "rejects URLs with no host" do
      assert SafeHttp.check_url("https:///x") == {:error, :unsafe_url}
      assert SafeHttp.check_url("not a url") == {:error, :unsafe_url}
      assert SafeHttp.check_url(nil) == {:error, :unsafe_url}
    end

    test "rejects literal private, loopback, link-local and reserved IPv4 addresses" do
      for ip <- ~w(127.0.0.1 10.1.2.3 172.16.0.1 172.31.255.255 192.168.0.1 169.254.169.254
                   100.64.0.1 0.0.0.0 224.0.0.1 255.255.255.255 198.18.0.1 192.0.0.8) do
        assert SafeHttp.check_url("https://#{ip}/x") == {:error, :unsafe_url}, ip
      end
    end

    test "allows literal public IPv4 addresses just outside private ranges" do
      for ip <- ~w(172.15.255.255 172.32.0.1 100.63.255.255 100.128.0.1 198.17.255.255 198.20.0.1) do
        assert SafeHttp.check_url("https://#{ip}/x") == :ok, ip
      end
    end

    test "rejects loopback, unique-local, link-local, multicast and mapped IPv6" do
      for ip <- ~w(::1 :: fd00::1 fc00::1 fe80::1 ff02::1 ::ffff:127.0.0.1 ::ffff:10.0.0.1) do
        assert SafeHttp.check_url("https://[#{ip}]/x") == {:error, :unsafe_url}, ip
      end
    end

    test "allows a public IPv6 address and a mapped public IPv4 one" do
      assert SafeHttp.check_url("https://[2606:4700::1111]/x") == :ok
      assert SafeHttp.check_url("https://[::ffff:93.184.216.34]/x") == :ok
    end

    test "rejects hostnames that resolve to a private address" do
      assert SafeHttp.check_url("https://internal.example/x") == {:error, :unsafe_url}
      assert SafeHttp.check_url("https://v6-internal.example/x") == {:error, :unsafe_url}
    end

    test "rejects a hostname if any of its addresses is private" do
      assert SafeHttp.check_url("https://mixed.example/x") == {:error, :unsafe_url}
    end

    test "rejects hostnames that don't resolve" do
      assert SafeHttp.check_url("https://nowhere.example/x") == {:error, :unsafe_url}
    end
  end

  describe "get/2" do
    test "does not send a request to an unsafe URL" do
      plug = fn conn -> flunk("request should not be sent to #{conn.host}") end
      assert SafeHttp.get("https://internal.example/x", plug: plug) == {:error, :unsafe_url}
    end

    test "performs the request for a safe URL" do
      plug = fn conn -> Req.Test.json(conn, %{"ok" => true}) end

      assert {:ok, %{status: 200, body: %{"ok" => true}}} =
               SafeHttp.get("https://remote.example.com/x", plug: plug)
    end

    test "follows a redirect to a safe URL" do
      plug = fn
        %{request_path: "/start"} = conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "https://remote.example.com/end")
          |> Plug.Conn.send_resp(302, "")

        %{request_path: "/end"} = conn ->
          Req.Test.json(conn, %{"at" => "end"})
      end

      assert {:ok, %{status: 200, body: %{"at" => "end"}}} =
               SafeHttp.get("https://remote.example.com/start", plug: plug)
    end

    test "resolves a relative redirect against the current URL" do
      plug = fn
        %{request_path: "/start"} = conn ->
          conn |> Plug.Conn.put_resp_header("location", "/end") |> Plug.Conn.send_resp(301, "")

        %{request_path: "/end"} = conn ->
          Req.Test.json(conn, %{"at" => "end"})
      end

      assert {:ok, %{status: 200}} = SafeHttp.get("https://remote.example.com/start", plug: plug)
    end

    test "refuses a redirect to an unsafe URL" do
      plug = fn
        %{host: "remote.example.com"} = conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "https://169.254.169.254/latest")
          |> Plug.Conn.send_resp(302, "")

        conn ->
          flunk("followed the redirect to #{conn.host}")
      end

      assert SafeHttp.get("https://remote.example.com/x", plug: plug) == {:error, :unsafe_url}
    end

    test "gives up after too many redirects" do
      plug = fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "https://remote.example.com/again")
        |> Plug.Conn.send_resp(302, "")
      end

      assert SafeHttp.get("https://remote.example.com/x", plug: plug) ==
               {:error, :too_many_redirects}
    end

    test "follows up to three redirects but not a fourth" do
      # /hops/N redirects N more times before answering.
      plug = fn %{path_info: ["hops", n]} = conn ->
        case String.to_integer(n) do
          0 ->
            Req.Test.json(conn, %{"done" => true})

          n ->
            conn
            |> Plug.Conn.put_resp_header("location", "/hops/#{n - 1}")
            |> Plug.Conn.send_resp(302, "")
        end
      end

      assert {:ok, %{status: 200}} = SafeHttp.get("https://remote.example.com/hops/3", plug: plug)

      assert SafeHttp.get("https://remote.example.com/hops/4", plug: plug) ==
               {:error, :too_many_redirects}
    end

    test "returns a redirect without a location as-is" do
      plug = fn conn -> Plug.Conn.send_resp(conn, 302, "") end
      assert {:ok, %{status: 302}} = SafeHttp.get("https://remote.example.com/x", plug: plug)
    end
  end

  describe "InetResolver" do
    test "resolves localhost from the hosts file" do
      assert {:ok, ips} = SafeHttp.InetResolver.resolve("localhost")
      assert {127, 0, 0, 1} in ips
    end

    test "reports a name that can't resolve" do
      assert SafeHttp.InetResolver.resolve("revix-test.invalid") == {:error, :nxdomain}
    end
  end

  describe "post/2" do
    test "does not send a request to an unsafe URL" do
      plug = fn _conn -> flunk("request should not be sent") end

      assert SafeHttp.post("https://10.0.0.1/inbox", plug: plug, body: "{}") ==
               {:error, :unsafe_url}
    end

    test "does not follow redirects" do
      plug = fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "https://remote.example.com/other")
        |> Plug.Conn.send_resp(307, "")
      end

      assert {:ok, %{status: 307}} =
               SafeHttp.post("https://remote.example.com/inbox", plug: plug, body: "{}")
    end
  end

  describe "stub option" do
    test "get/2 sends through the Req.Test stub named by an app config key" do
      Req.Test.stub(:federation, fn conn -> Req.Test.json(conn, %{"via" => "stub"}) end)

      assert {:ok, %{status: 200, body: %{"via" => "stub"}}} =
               SafeHttp.get("https://remote.example.com/x", stub: :federation_req_plug)
    end

    test "post/2 sends through the Req.Test stub named by an app config key" do
      Req.Test.stub(:federation, fn conn -> Req.Test.json(conn, %{"method" => conn.method}) end)

      assert {:ok, %{body: %{"method" => "POST"}}} =
               SafeHttp.post("https://remote.example.com/inbox",
                 body: "{}",
                 stub: :federation_req_plug
               )
    end

    test "a redirect is followed through the same stub" do
      Req.Test.stub(:federation, fn
        %{request_path: "/start"} = conn ->
          conn |> Plug.Conn.put_resp_header("location", "/end") |> Plug.Conn.send_resp(302, "")

        conn ->
          Req.Test.json(conn, %{"at" => conn.request_path})
      end)

      assert {:ok, %{body: %{"at" => "/end"}}} =
               SafeHttp.get("https://remote.example.com/start", stub: :federation_req_plug)
    end
  end
end
