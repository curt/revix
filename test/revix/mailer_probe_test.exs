defmodule Revix.MailerProbeTest do
  use ExUnit.Case, async: false

  alias Revix.MailerConfig
  alias Revix.MailerProbe

  setup_all do
    {cert_path, key_path} = tls_cert()

    on_exit(fn ->
      File.rm(cert_path)
      File.rm(key_path)
    end)

    %{cert: {cert_path, key_path}}
  end

  # Starts a one-connection fake SMTP server whose dialogue runs in a Task
  # linked to the test process, so a failed assertion inside the dialogue fails
  # the test. Callers must `await_server/1` after the probe returns.
  defp start_server(dialogue) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listener)

    server =
      Task.async(fn ->
        {:ok, sock} = :gen_tcp.accept(listener, 5000)
        dialogue.(sock)
        :gen_tcp.close(listener)
      end)

    {port, server}
  end

  defp await_server(server), do: Task.await(server, 5000)

  defp tls_cert do
    key = X509.PrivateKey.new_ec(:secp256r1)
    cert = X509.Certificate.self_signed(key, "/C=US/O=Revix/CN=localhost", template: :root_ca)

    dir = Path.join(System.tmp_dir!(), "revix_mailer_probe_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    cert_path = Path.join(dir, "cert.pem")
    key_path = Path.join(dir, "key.pem")
    File.write!(cert_path, X509.Certificate.to_pem(cert))
    File.write!(key_path, X509.PrivateKey.to_pem(key))
    {cert_path, key_path}
  end

  defp server_tls_opts({cert_path, key_path}) do
    [certfile: to_charlist(cert_path), keyfile: to_charlist(key_path)]
  end

  defp recv!(sock) do
    assert {:ok, line} = :gen_tcp.recv(sock, 0, 5000)
    line
  end

  defp send!(sock, data), do: assert(:ok = :gen_tcp.send(sock, data))

  describe "check/1" do
    test "reports a missing relay" do
      assert {:error, :relay_not_configured} = MailerProbe.check(relay: nil)
    end

    test "opens an authenticated session" do
      {port, server} =
        start_server(fn sock ->
          send!(sock, "220 fake ESMTP\r\n")
          assert recv!(sock) =~ "EHLO"
          send!(sock, "250-fake\r\n250 AUTH PLAIN\r\n")
          assert "AUTH " <> _ = recv!(sock)
          send!(sock, "235 ok\r\n")
          assert recv!(sock) =~ "QUIT"
          send!(sock, "221 bye\r\n")
        end)

      assert :ok =
               MailerProbe.check(
                 relay: "127.0.0.1",
                 port: port,
                 tls: :never,
                 auth: :always,
                 username: "user",
                 password: "pass"
               )

      await_server(server)
    end

    test "skips auth when it is disabled" do
      {port, server} =
        start_server(fn sock ->
          send!(sock, "220 fake ESMTP\r\n")
          assert recv!(sock) =~ "EHLO"
          send!(sock, "250 fake\r\n")
          assert recv!(sock) =~ "QUIT"
          send!(sock, "221 bye\r\n")
        end)

      assert :ok = MailerProbe.check(relay: "127.0.0.1", port: port, tls: :never, auth: :never)
      await_server(server)
    end

    test "upgrades to TLS before authenticating", %{cert: cert} do
      {port, server} =
        start_server(fn sock ->
          send!(sock, "220 fake ESMTP\r\n")
          assert recv!(sock) =~ "EHLO"
          send!(sock, "250-fake\r\n250 STARTTLS\r\n")
          assert recv!(sock) =~ "STARTTLS"
          send!(sock, "220 go ahead\r\n")

          {:ok, tls} = :ssl.handshake(sock, server_tls_opts(cert), 5000)

          assert {:ok, <<"EHLO", _::binary>>} = :ssl.recv(tls, 0, 5000)
          :ok = :ssl.send(tls, "250-fake\r\n250 AUTH PLAIN\r\n")
          assert {:ok, <<"AUTH ", _::binary>>} = :ssl.recv(tls, 0, 5000)
          :ok = :ssl.send(tls, "235 ok\r\n")
          assert {:ok, <<"QUIT", _::binary>>} = :ssl.recv(tls, 0, 5000)
          :ok = :ssl.send(tls, "221 bye\r\n")
        end)

      assert :ok =
               MailerProbe.check(
                 relay: "127.0.0.1",
                 port: port,
                 tls: :if_available,
                 tls_options: [verify: :verify_none],
                 auth: :always,
                 username: "user",
                 password: "pass"
               )

      await_server(server)
    end

    test "rejects an untrusted certificate with the default verifying config", %{cert: cert} do
      {port, server} =
        start_server(fn sock ->
          send!(sock, "220 fake ESMTP\r\n")
          assert recv!(sock) =~ "EHLO"
          send!(sock, "250-fake\r\n250 STARTTLS\r\n")
          assert recv!(sock) =~ "STARTTLS"
          send!(sock, "220 go ahead\r\n")
          assert {:error, _reason} = :ssl.handshake(sock, server_tls_opts(cert), 5000)
        end)

      opts =
        MailerConfig.smtp_config(%{
          "SMTP_HOST" => "localhost",
          "SMTP_PORT" => Integer.to_string(port),
          "SMTP_TLS" => "always",
          "SMTP_AUTH" => "never",
          "SMTP_RETRIES" => "1"
        })

      assert {:error, _, _} = MailerProbe.check(opts)
      await_server(server)
    end

    test "connects with SSL when ssl is set", %{cert: cert} do
      {port, server} =
        start_server(fn sock ->
          {:ok, tls} = :ssl.handshake(sock, server_tls_opts(cert), 5000)

          :ok = :ssl.send(tls, "220 fake ESMTP\r\n")
          assert {:ok, <<"EHLO", _::binary>>} = :ssl.recv(tls, 0, 5000)
          :ok = :ssl.send(tls, "250 fake\r\n")
          assert {:ok, <<"QUIT", _::binary>>} = :ssl.recv(tls, 0, 5000)
          :ok = :ssl.send(tls, "221 bye\r\n")
        end)

      assert :ok =
               MailerProbe.check(
                 relay: "127.0.0.1",
                 port: port,
                 ssl: true,
                 sockopts: [verify: :verify_none],
                 auth: :never
               )

      await_server(server)
    end

    test "reports rejected credentials" do
      {port, server} =
        start_server(fn sock ->
          send!(sock, "220 fake ESMTP\r\n")
          assert recv!(sock) =~ "EHLO"
          send!(sock, "250-fake\r\n250 AUTH PLAIN\r\n")
          assert "AUTH " <> _ = recv!(sock)
          send!(sock, "535 bad credentials\r\n")
        end)

      assert {:error, :no_more_hosts, {:permanent_failure, _, :auth_failed}} =
               MailerProbe.check(
                 relay: "127.0.0.1",
                 port: port,
                 tls: :never,
                 auth: :always,
                 username: "user",
                 password: "wrong"
               )

      await_server(server)
    end

    test "times out on a relay that accepts but never answers" do
      test_pid = self()

      {port, server} =
        start_server(fn _sock ->
          send(test_pid, :accepted)

          receive do
            :release -> :ok
          after
            5000 -> flunk("server was never released")
          end
        end)

      assert {:error, :timeout} =
               MailerProbe.check(relay: "127.0.0.1", port: port, tls: :never, probe_timeout: 200)

      assert_received :accepted
      send(server.pid, :release)
      await_server(server)
    end

    test "reports connection refused" do
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
      {:ok, port} = :inet.port(listener)
      :ok = :gen_tcp.close(listener)

      assert {:error, :retries_exceeded, {:network_failure, _, {:error, :econnrefused}}} =
               MailerProbe.check(relay: "127.0.0.1", port: port, tls: :never)
    end

    test "reports unresolved hostnames" do
      assert {:error, :retries_exceeded, {:network_failure, _, {:error, :nxdomain}}} =
               MailerProbe.check(relay: "probe-nonexistent.invalid", tls: :never)
    end
  end

  describe "startup_check/2" do
    test "is a no-op when the startup check is not enabled" do
      assert :ok = MailerProbe.startup_check(nil, fn _ -> flunk("probe should not run") end)
    end

    test "passes the SMTP config to the probe and returns :ok on success" do
      smtp = [relay: "smtp.example.com"]
      test_pid = self()

      check = fn opts ->
        send(test_pid, {:probed, opts})
        :ok
      end

      assert :ok = MailerProbe.startup_check(smtp, check)
      assert_received {:probed, ^smtp}
    end

    test "returns an error tuple when the probe fails" do
      assert {:error, {:smtp_startup_check_failed, {:error, :boom}}} =
               MailerProbe.startup_check([relay: "smtp.example.com"], fn _ -> {:error, :boom} end)
    end
  end
end
