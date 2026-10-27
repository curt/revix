defmodule Revix.MailerProbeTest do
  use ExUnit.Case, async: false

  alias Revix.MailerProbe

  defmodule FakeSMTP do
    use GenServer

    def start_link(dialogue), do: GenServer.start_link(__MODULE__, dialogue)
    def port(pid), do: GenServer.call(pid, :port)

    @impl true
    def init(dialogue) do
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
      {:ok, port} = :inet.port(listener)

      Task.async(fn ->
        {:ok, sock} = :gen_tcp.accept(listener)
        dialogue.(sock)
        :gen_tcp.close(listener)
      end)

      {:ok, port}
    end

    @impl true
    def handle_call(:port, _from, port), do: {:reply, port, port}
  end

  setup_all do
    {cert_path, key_path} = tls_cert()

    on_exit(fn ->
      File.rm(cert_path)
      File.rm(key_path)
    end)

    %{cert: {cert_path, key_path}}
  end

  defp start_server(dialogue) do
    FakeSMTP.port(start_supervised!({FakeSMTP, dialogue}))
  end

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

  defp recv!(sock) do
    assert {:ok, line} = :gen_tcp.recv(sock, 0, 5000)
    line
  end

  defp send!(sock, data), do: assert(:ok = :gen_tcp.send(sock, data))

  test "reports a missing relay" do
    assert {:error, :relay_not_configured} = MailerProbe.check(relay: nil)
  end

  test "opens an authenticated session" do
    port =
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
  end

  test "skips auth when it is disabled" do
    port =
      start_server(fn sock ->
        send!(sock, "220 fake ESMTP\r\n")
        assert recv!(sock) =~ "EHLO"
        send!(sock, "250 fake\r\n")
        assert recv!(sock) =~ "QUIT"
        send!(sock, "221 bye\r\n")
      end)

    assert :ok = MailerProbe.check(relay: "127.0.0.1", port: port, tls: :never, auth: :never)
  end

  test "upgrades to TLS before authenticating", %{cert: {cert_path, key_path}} do
    port =
      start_server(fn sock ->
        send!(sock, "220 fake ESMTP\r\n")
        assert recv!(sock) =~ "EHLO"
        send!(sock, "250-fake\r\n250 STARTTLS\r\n")
        assert recv!(sock) =~ "STARTTLS"
        send!(sock, "220 go ahead\r\n")

        {:ok, tls} =
          :ssl.handshake(
            sock,
            [certfile: to_charlist(cert_path), keyfile: to_charlist(key_path)],
            5000
          )

        assert {:ok, <<"EHLO", _::binary>>} = :ssl.recv(tls, 0, 5000)
        :ok = :ssl.send(tls, "250-fake\r\n250 AUTH PLAIN\r\n")
        assert {:ok, <<"AUTH ", _::binary>>} = :ssl.recv(tls, 0, 5000)
        :ok = :ssl.send(tls, "235 ok\r\n")
        assert {:ok, _quit} = :ssl.recv(tls, 0, 5000)
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
  end

  test "connects with SSL when ssl is set", %{cert: {cert_path, key_path}} do
    port =
      start_server(fn sock ->
        {:ok, tls} =
          :ssl.handshake(
            sock,
            [certfile: to_charlist(cert_path), keyfile: to_charlist(key_path)],
            5000
          )

        :ok = :ssl.send(tls, "220 fake ESMTP\r\n")
        assert {:ok, <<"EHLO", _::binary>>} = :ssl.recv(tls, 0, 5000)
        :ok = :ssl.send(tls, "250 fake\r\n")
        assert {:ok, _quit} = :ssl.recv(tls, 0, 5000)
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
  end

  test "reports rejected credentials" do
    port =
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
