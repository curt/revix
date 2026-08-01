defmodule Revix.FederationFixtures do
  @moduledoc """
  Static test RSA key pair for deterministic HTTP signature tests.

  Keys were generated once with X509.PrivateKey.new_rsa(2048) and are
  embedded here so tests don't depend on runtime key generation.
  """

  @private_key_pem """
  -----BEGIN RSA PRIVATE KEY-----
  MIIEowIBAAKCAQEAvqBh7n6KaBXDBZtq7yWJ0M6no5AbMu9Qg1BlxDmoMkIm9VIZ
  HonAxrrLTZKpYfa3lDRwYhrMHr3EfT4jVUSQNlOy2npnU+Wtgg2xI6zrMGmq01Ft
  Asya93WEj7iHMHf8dV6llnr5E1RnKq/zpkmGMtdItIjyqDiqJt0lGi6nadg1DFd/
  hfjkLdRNQvwI5u9WF+3/0GkPxHZIu5Y2mtFat3UjTH0OWIudRoxKHtgTgyp7TMIM
  oe8aA8Ow0MV6fbJLJjSwm4ODgAzuO5VYyRyKtDzJaTfmiGnE+nWz3OWvKHTDZfM+
  oTLUp7Cz9ryLzzCTJ/H56qdXaUM9dltRjHNrRQIDAQABAoIBAALPPn+YngXF3lY4
  kcVSY7swCeCmA39HGi7D8lVc9oQ+coW2maKtgT8clS8Al0kCQnc8z57j32LLmrgF
  gK6ldaJWA6KR38XTh9tibsbZv1dQaLa3x5gdN7fSeQCc8GHP6ZNkRfisuXuQs1A5
  1X47rVlApYnC+UqZQolomdROiuP13SbKxhAxU6fj4SsZ+cPP/qguTtlQdDigw9UI
  nJ/peGvFKMKLP3G5aDFV95nrSDlKUnHG22g309Lj5p3dvQb0rOu+LN661LxpgfTE
  sRs1v/Z8ltFZDp2BSgxoS1aJyPuA4kUCeyS7K/h0FZhHs7XVrLJJxT2tAoHzqzgI
  VsGKSRkCgYEA/vHs3tOswDSBaQvvB5SASL9pxFFGEZzT/1RQFPXsCy89EB76SY9I
  3fLzESx0QqF1bJemthTVq+cQnQgdM4fT/CnYZkjQ/I+NUT0iXvfNnXdObAScPzCw
  IsryobEJJUA6yPB0jo04r5hksYZmCTVTCEuh8HDmMeb2RfKpEe2gkMkCgYEAv2pS
  XxDESO7Hgz1wj4CRsPUMzhJe5yneSHwpAIffGsVarQUXWFQnzWAOj3z9MCn7oGfF
  Cwp8eaZNerj+Fn8JHzw1QZ/KdJZ0hEt3494zVuxvgolTghbLk0qnP80q9gIlljdd
  08d5xWTMvJJ+IprpcEdfbF6LUXhymbpHHuYVoJ0CgYBWVjNzWpfcF2vj2Si/lmjD
  Oh9lXmiuOkAI7dKY5pdjSkIRnYwBMUbp8wahwD42+lq7xbetXezmZD/aDg9ljhAa
  C0m/idVMUoj3BA8Jvj2hn++s4PrQ43oirjvwyfVg6hl+RwAR7n1N6fvfqrYPVEGk
  Q4i51mH+cEricUUUTzbbEQKBgQCXPyOnClCOcF4lTT7LpQN5l6dujQWAEo0ZKUIc
  sT+Qn7BuVj+EA7sPhH780f4dOI8ix9viRX7lgIpoFhRvIiHLFH/gQqpuRRP8FMW+
  v6xBWsEhm/DoMarZz3sn5q2zhS696zGwTUXiuysrNXWFUnJxzXOQ5YOf9FRZM99O
  gu9D4QKBgC5sgfcaXOxj8EnsjyJDSrdmAF7OqGmXWWDMbNl84Xw9IIzEJ5Cm3zTy
  VcmFY+ocBGVACkY8f7FuAmK8qwrnhE1Pi9lrC0o3lMllazhbh0IEMFz7OqOBREAc
  B9Xuc9ZCdA+MupS0eXUA5zdmuVIf0VL7tEnVniyWnwVWj3R45Kyr
  -----END RSA PRIVATE KEY-----
  """

  @public_key_pem """
  -----BEGIN PUBLIC KEY-----
  MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvqBh7n6KaBXDBZtq7yWJ
  0M6no5AbMu9Qg1BlxDmoMkIm9VIZHonAxrrLTZKpYfa3lDRwYhrMHr3EfT4jVUSQ
  NlOy2npnU+Wtgg2xI6zrMGmq01FtAsya93WEj7iHMHf8dV6llnr5E1RnKq/zpkmG
  MtdItIjyqDiqJt0lGi6nadg1DFd/hfjkLdRNQvwI5u9WF+3/0GkPxHZIu5Y2mtFa
  t3UjTH0OWIudRoxKHtgTgyp7TMIMoe8aA8Ow0MV6fbJLJjSwm4ODgAzuO5VYyRyK
  tDzJaTfmiGnE+nWz3OWvKHTDZfM+oTLUp7Cz9ryLzzCTJ/H56qdXaUM9dltRjHNr
  RQIDAQAB
  -----END PUBLIC KEY-----
  """

  def private_key_pem, do: @private_key_pem
  def public_key_pem, do: @public_key_pem

  def private_key do
    {:ok, key} = X509.PrivateKey.from_pem(@private_key_pem)
    key
  end

  def public_key do
    {:ok, key} = X509.PublicKey.from_pem(@public_key_pem)
    key
  end

  def remote_actor_uri, do: "https://remote.example.com/users/alice"
  def remote_inbox_url, do: "https://remote.example.com/users/alice/inbox"

  # Minimal 1×1 RGB PNG — valid magic bytes, accepted by ExImageInfo as :png
  @minimal_png Base.decode64!(
                 "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVQI12P4z8AAAAACAAHiIbwzAAAAAElFTkSuQmCC"
               )

  def minimal_png, do: @minimal_png

  def stub_remote_server do
    Req.Test.stub(:federation, fn conn ->
      case conn.request_path do
        "/users/alice" ->
          Req.Test.json(conn, remote_actor_map())

        "/users/alice/inbox" ->
          conn
          |> Plug.Conn.put_resp_header("content-type", "text/plain")
          |> Plug.Conn.send_resp(202, "")

        "/users/alice/avatar.png" ->
          conn
          |> Plug.Conn.put_resp_header("content-type", "image/png")
          |> Plug.Conn.send_resp(200, @minimal_png)

        _ ->
          Plug.Conn.send_resp(conn, 404, "not found")
      end
    end)
  end

  def stub_actor(uri \\ remote_actor_uri(), overrides \\ %{}) do
    actor = Map.merge(remote_actor_map(uri), overrides)

    Req.Test.stub(:federation, fn conn ->
      Req.Test.json(conn, actor)
    end)
  end

  def stub_actor_not_found do
    Req.Test.stub(:federation, fn conn ->
      Plug.Conn.send_resp(conn, 404, "not found")
    end)
  end

  def remote_actor_map(uri \\ remote_actor_uri()) do
    %{
      "id" => uri,
      "type" => "Person",
      "preferredUsername" => "alice",
      "name" => "Alice Example",
      "inbox" => "#{uri}/inbox",
      "outbox" => "#{uri}/outbox",
      "icon" => %{
        "type" => "Image",
        "mediaType" => "image/png",
        "url" => "#{uri}/avatar.png"
      },
      "publicKey" => %{
        "id" => "#{uri}#key",
        "owner" => uri,
        "publicKeyPem" => @public_key_pem
      }
    }
  end

  def sign_headers(headers, key_id, private_key \\ nil) do
    pk = private_key || private_key()
    HTTPSignatures.sign(pk, key_id, headers)
  end

  def signed_conn(conn, actor_uri \\ remote_actor_uri()) do
    body = conn.assigns[:raw_body] || ""
    date = Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S GMT")
    digest = "SHA-256=" <> (:crypto.hash(:sha256, body) |> Base.encode64())
    # Use a fixed host so signing and verification agree; "host" req_header
    # overrides conn.host for Plug.Conn header map lookups.
    host = "www.example.com"
    key_id = "#{actor_uri}#key"

    headers = %{
      "(request-target)" => "post #{conn.request_path}",
      "host" => host,
      "date" => date,
      "digest" => digest
    }

    signature = sign_headers(headers, key_id)

    # Inject host into req_headers directly — put_req_header refuses "host"
    # (Plug guards it), but HTTPSignatures reads from req_headers map.
    conn
    |> Map.put(:host, host)
    |> Map.update!(:req_headers, &[{"host", host} | &1])
    |> Plug.Conn.put_req_header("date", date)
    |> Plug.Conn.put_req_header("digest", digest)
    |> Plug.Conn.put_req_header("signature", signature)
  end
end
