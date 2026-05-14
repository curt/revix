defmodule RevixWeb.InboxControllerTest do
  use RevixWeb.ConnCase, async: false

  import Revix.PeopleFixtures
  import Revix.FederationFixtures

  alias Revix.People

  setup do
    Req.Test.stub(:federation, fn conn ->
      Req.Test.json(conn, remote_actor_map())
    end)

    :ok
  end

  defp build_ping_activity(actor_uri, target_uri) do
    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "type" => "Ping",
      "id" => "#{actor_uri}/ping/test123",
      "actor" => actor_uri,
      "to" => target_uri
    }
  end

  defp post_to_inbox(conn, person_id, body_map) do
    body = Jason.encode!(body_map)
    path = "/people/#{person_id}/inbox"

    # Build a Plug.Test conn directly with the binary body so that
    # RawBodyReader stores the exact bytes for Digest verification.
    inner_conn =
      :post
      |> Plug.Test.conn(path, body)
      |> Map.put(:host, "www.example.com")
      |> Map.update!(:req_headers, &[{"host", "www.example.com"} | &1])
      |> Plug.Conn.put_req_header("content-type", "application/activity+json")
      |> Plug.Conn.put_req_header("accept", "application/activity+json")

    # Compute digest from the real body bytes
    digest = "SHA-256=" <> (:crypto.hash(:sha256, body) |> Base.encode64())
    date = Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S GMT")
    key_id = "#{remote_actor_uri()}#key"

    headers_to_sign = %{
      "(request-target)" => "post #{path}",
      "host" => "www.example.com",
      "date" => date,
      "digest" => digest
    }

    signature = sign_headers(headers_to_sign, key_id)

    signed =
      inner_conn
      |> Plug.Conn.put_req_header("date", date)
      |> Plug.Conn.put_req_header("digest", digest)
      |> Plug.Conn.put_req_header("signature", signature)

    # Carry over the session from the outer test conn (for sandbox access)
    signed = %{signed | secret_key_base: conn.secret_key_base}

    RevixWeb.Endpoint.call(signed, [])
  end

  describe "POST /people/:id/inbox" do
    test "returns 404 for unknown person", %{conn: conn} do
      conn = post_to_inbox(conn, "unknownid", build_ping_activity(remote_actor_uri(), "http://x"))
      assert conn.status == 404
    end

    test "returns 400 for malformed activity", %{conn: conn} do
      person = person_fixture()

      conn = post_to_inbox(conn, person.id, %{"type" => "Ping"})

      assert conn.status == 400
    end

    test "returns 202 for valid signed Ping to owner", %{conn: conn} do
      person = person_fixture()
      {:ok, _} = People.set_person_role(person, :owner)
      person = People.get_person!(person.id)

      {:ok, _} =
        People.upsert_remote_person(%{
          uri: remote_actor_uri(),
          public_key: public_key_pem(),
          username: "alice",
          display_name: "Alice"
        })

      activity = build_ping_activity(remote_actor_uri(), person.uri)

      conn = post_to_inbox(conn, person.id, activity)

      assert conn.status == 202
    end

    test "returns 202 for valid signed Pong", %{conn: conn} do
      person = person_fixture()
      {:ok, _} = People.set_person_role(person, :owner)
      person = People.get_person!(person.id)

      {:ok, _} =
        People.upsert_remote_person(%{
          uri: remote_actor_uri(),
          public_key: public_key_pem(),
          username: "alice",
          display_name: "Alice"
        })

      pong_activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "type" => "Pong",
        "id" => "#{remote_actor_uri()}/pong/abc",
        "actor" => remote_actor_uri(),
        "to" => person.uri,
        "object" => "#{person.uri}/ping/xyz"
      }

      conn = post_to_inbox(conn, person.id, pong_activity)

      assert conn.status == 202
    end

    test "returns 202 for valid signed Like activity", %{conn: conn} do
      person = person_fixture()

      {:ok, _} =
        People.upsert_remote_person(%{
          uri: remote_actor_uri(),
          public_key: public_key_pem(),
          username: "alice",
          display_name: "Alice"
        })

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "type" => "Like",
        "id" => "#{remote_actor_uri()}/likes/abc123",
        "actor" => remote_actor_uri(),
        "object" => "#{person.uri}/entries/xyz"
      }

      conn = post_to_inbox(conn, person.id, activity)

      assert conn.status == 202
    end

    test "returns 202 for valid signed Undo Like activity", %{conn: conn} do
      person = person_fixture()

      {:ok, _} =
        People.upsert_remote_person(%{
          uri: remote_actor_uri(),
          public_key: public_key_pem(),
          username: "alice",
          display_name: "Alice"
        })

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "type" => "Undo",
        "id" => "#{remote_actor_uri()}/undo/1",
        "actor" => remote_actor_uri(),
        "object" => %{
          "type" => "Like",
          "id" => "#{remote_actor_uri()}/likes/abc123",
          "actor" => remote_actor_uri(),
          "object" => "#{person.uri}/entries/xyz"
        }
      }

      conn = post_to_inbox(conn, person.id, activity)

      assert conn.status == 202
    end

    test "returns 202 for valid signed Follow activity", %{conn: conn} do
      person = person_fixture()

      {:ok, _} =
        People.upsert_remote_person(%{
          uri: remote_actor_uri(),
          public_key: public_key_pem(),
          username: "alice",
          display_name: "Alice"
        })

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "type" => "Follow",
        "id" => "#{remote_actor_uri()}/follows/abc",
        "actor" => remote_actor_uri(),
        "object" => person.uri
      }

      conn = post_to_inbox(conn, person.id, activity)

      assert conn.status == 202
    end

    test "returns 202 for valid signed Undo Follow activity", %{conn: conn} do
      person = person_fixture()

      {:ok, _} =
        People.upsert_remote_person(%{
          uri: remote_actor_uri(),
          public_key: public_key_pem(),
          username: "alice",
          display_name: "Alice"
        })

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "type" => "Undo",
        "id" => "#{remote_actor_uri()}/undo/follow/1",
        "actor" => remote_actor_uri(),
        "object" => %{
          "type" => "Follow",
          "id" => "#{remote_actor_uri()}/follows/abc",
          "actor" => remote_actor_uri(),
          "object" => person.uri
        }
      }

      conn = post_to_inbox(conn, person.id, activity)

      assert conn.status == 202
    end

    test "accepts unknown activity types without error", %{conn: conn} do
      person = person_fixture()

      {:ok, _} =
        People.upsert_remote_person(%{
          uri: remote_actor_uri(),
          public_key: public_key_pem(),
          username: "alice",
          display_name: "Alice"
        })

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "type" => "Announce",
        "id" => "#{remote_actor_uri()}/announce/123",
        "actor" => remote_actor_uri(),
        "object" => "#{person.uri}/entries/abc"
      }

      conn = post_to_inbox(conn, person.id, activity)

      assert conn.status == 202
    end
  end
end
