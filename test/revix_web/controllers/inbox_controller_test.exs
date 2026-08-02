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
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/activity+json"
    end

    test "returns 400 for malformed activity", %{conn: conn} do
      person = person_fixture()

      conn = post_to_inbox(conn, person.id, %{"type" => "Ping"})

      assert conn.status == 400
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/activity+json"
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

    test "returns 202 for valid signed Accept{Follow} activity", %{conn: conn} do
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
        "type" => "Accept",
        "id" => "#{remote_actor_uri()}/accepts/1",
        "actor" => remote_actor_uri(),
        "object" => %{
          "type" => "Follow",
          "id" => "#{person.uri}/follows/1",
          "actor" => person.uri,
          "object" => remote_actor_uri()
        }
      }

      conn = post_to_inbox(conn, person.id, activity)

      assert conn.status == 202
      assert_enqueued(worker: Revix.Workers.ProcessInboundAcceptFollowWorker)
    end

    test "returns 202 for valid signed Reject{Follow} activity", %{conn: conn} do
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
        "type" => "Reject",
        "id" => "#{remote_actor_uri()}/rejects/1",
        "actor" => remote_actor_uri(),
        "object" => %{
          "type" => "Follow",
          "id" => "#{person.uri}/follows/1",
          "actor" => person.uri,
          "object" => remote_actor_uri()
        }
      }

      conn = post_to_inbox(conn, person.id, activity)

      assert conn.status == 202
      assert_enqueued(worker: Revix.Workers.ProcessInboundRejectFollowWorker)
    end

    test "returns 202 for valid signed Update{Note} activity", %{conn: conn} do
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
        "type" => "Update",
        "id" => "#{remote_actor_uri()}/activities/upd1",
        "actor" => remote_actor_uri(),
        "object" => %{
          "type" => "Note",
          "id" => "#{remote_actor_uri()}/notes/abc123",
          "content" => "<p>Updated!</p>"
        }
      }

      conn = post_to_inbox(conn, person.id, activity)

      assert conn.status == 202
    end

    test "returns 202 for valid signed Update{Person} activity", %{conn: conn} do
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
        "type" => "Update",
        "id" => "#{remote_actor_uri()}/activities/updperson1",
        "actor" => remote_actor_uri(),
        "object" => %{
          "type" => "Person",
          "id" => remote_actor_uri()
        }
      }

      conn = post_to_inbox(conn, person.id, activity)

      assert conn.status == 202
      assert_enqueued(worker: Revix.Workers.ProcessInboundUpdateActorWorker)
    end

    test "returns 202 for valid signed Create{Event} activity", %{conn: conn} do
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
        "type" => "Create",
        "id" => "#{remote_actor_uri()}/activities/evt1",
        "actor" => remote_actor_uri(),
        "object" => %{
          "type" => "Event",
          "id" => "#{remote_actor_uri()}/events/abc123",
          "content" => "<p>A thing is happening.</p>"
        }
      }

      conn = post_to_inbox(conn, person.id, activity)

      assert conn.status == 202
    end

    test "returns 202 for valid signed Update{Event} activity", %{conn: conn} do
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
        "type" => "Update",
        "id" => "#{remote_actor_uri()}/activities/upd2",
        "actor" => remote_actor_uri(),
        "object" => %{
          "type" => "Event",
          "id" => "#{remote_actor_uri()}/events/abc123",
          "content" => "<p>Updated event.</p>"
        }
      }

      conn = post_to_inbox(conn, person.id, activity)

      assert conn.status == 202
    end

    test "returns 202 for valid signed Delete activity with plain URI object", %{conn: conn} do
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
        "type" => "Delete",
        "id" => "#{remote_actor_uri()}/activities/del1",
        "actor" => remote_actor_uri(),
        "object" => "#{remote_actor_uri()}/notes/abc123"
      }

      conn = post_to_inbox(conn, person.id, activity)

      assert conn.status == 202
    end

    test "returns 202 for valid signed Delete activity with Tombstone object", %{conn: conn} do
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
        "type" => "Delete",
        "id" => "#{remote_actor_uri()}/activities/del2",
        "actor" => remote_actor_uri(),
        "object" => %{
          "type" => "Tombstone",
          "id" => "#{remote_actor_uri()}/notes/abc123"
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

  describe "actor/signature mismatch" do
    @forged_actor_uri "https://remote.example.com/users/mallory"

    test "returns 401 for Create when signer does not match claimed actor", %{conn: conn} do
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
        "type" => "Create",
        "id" => "#{@forged_actor_uri}/activities/forged1",
        "actor" => @forged_actor_uri,
        "object" => %{
          "type" => "Note",
          "id" => "#{@forged_actor_uri}/notes/forged1",
          "content" => "<p>Forged</p>"
        }
      }

      # post_to_inbox signs with remote_actor_uri()'s key, but the activity
      # body claims a different actor — the signer and claimed actor must match.
      conn = post_to_inbox(conn, person.id, activity)

      assert conn.status == 401
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/activity+json"
    end

    test "returns 401 for Follow when signer does not match claimed actor", %{conn: conn} do
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
        "id" => "#{@forged_actor_uri}/follows/forged1",
        "actor" => @forged_actor_uri,
        "object" => person.uri
      }

      conn = post_to_inbox(conn, person.id, activity)

      assert conn.status == 401
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/activity+json"
    end

    test "does not enqueue a job or write an activity log on actor mismatch", %{conn: conn} do
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
        "id" => "#{@forged_actor_uri}/follows/forged2",
        "actor" => @forged_actor_uri,
        "object" => person.uri
      }

      post_to_inbox(conn, person.id, activity)

      assert Revix.Repo.aggregate(Revix.ActivityLogs.ActivityLog, :count) == 0
      refute_enqueued(worker: Revix.Workers.ProcessInboundFollowWorker)
    end
  end

  describe "activity log" do
    test "logs a Create{Note} activity with status 'enqueued'", %{conn: conn} do
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
        "type" => "Create",
        "id" => "#{remote_actor_uri()}/activities/log1",
        "actor" => remote_actor_uri(),
        "object" => %{
          "type" => "Note",
          "id" => "#{remote_actor_uri()}/notes/log1",
          "content" => "<p>Hello</p>"
        }
      }

      post_to_inbox(conn, person.id, activity)

      [log] = Revix.Repo.all(Revix.ActivityLogs.ActivityLog)
      assert log.direction == :inbound
      assert log.status == "enqueued"
      assert log.activity_type == "Create"
      assert log.object_type == "Note"
      assert log.actor_uri == remote_actor_uri()
      assert log.activity_uri == "#{remote_actor_uri()}/activities/log1"
      assert Jason.decode!(log.body)["type"] == "Create"
    end

    test "logs an Update{Person} activity with status 'enqueued'", %{conn: conn} do
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
        "type" => "Update",
        "id" => "#{remote_actor_uri()}/activities/log3",
        "actor" => remote_actor_uri(),
        "object" => %{
          "type" => "Person",
          "id" => remote_actor_uri()
        }
      }

      post_to_inbox(conn, person.id, activity)

      [log] = Revix.Repo.all(Revix.ActivityLogs.ActivityLog)
      assert log.status == "enqueued"
      assert log.activity_type == "Update"
      assert log.object_type == "Person"
    end

    test "logs an Accept{Follow} activity with status 'enqueued'", %{conn: conn} do
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
        "type" => "Accept",
        "id" => "#{remote_actor_uri()}/accepts/log4",
        "actor" => remote_actor_uri(),
        "object" => %{
          "type" => "Follow",
          "id" => "#{person.uri}/follows/1",
          "actor" => person.uri,
          "object" => remote_actor_uri()
        }
      }

      post_to_inbox(conn, person.id, activity)

      [log] = Revix.Repo.all(Revix.ActivityLogs.ActivityLog)
      assert log.status == "enqueued"
      assert log.activity_type == "Accept"
      assert log.object_type == "Follow"
    end

    test "logs an Announce activity with status 'unhandled'", %{conn: conn} do
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
        "id" => "#{remote_actor_uri()}/announce/log2",
        "actor" => remote_actor_uri(),
        "object" => "#{person.uri}/entries/abc"
      }

      post_to_inbox(conn, person.id, activity)

      [log] = Revix.Repo.all(Revix.ActivityLogs.ActivityLog)
      assert log.status == "unhandled"
      assert log.activity_type == "Announce"
    end

    test "does not log when signature verification fails", %{conn: conn} do
      person = person_fixture()

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "type" => "Create",
        "id" => "https://attacker.example/activities/1",
        "actor" => "https://attacker.example/users/bad",
        "object" => %{"type" => "Note", "id" => "https://attacker.example/notes/1"}
      }

      # Post without a valid signature — we bypass post_to_inbox which signs the request
      conn
      |> put_req_header("content-type", "application/activity+json")
      |> post("/people/#{person.id}/inbox", activity)

      assert Revix.Repo.aggregate(Revix.ActivityLogs.ActivityLog, :count) == 0
    end

    test "does not log when activity structure is invalid", %{conn: conn} do
      person = person_fixture()

      {:ok, _} =
        People.upsert_remote_person(%{
          uri: remote_actor_uri(),
          public_key: public_key_pem(),
          username: "alice",
          display_name: "Alice"
        })

      # Activity missing required "id" field
      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "type" => "Create",
        "actor" => remote_actor_uri()
      }

      post_to_inbox(conn, person.id, activity)

      assert Revix.Repo.aggregate(Revix.ActivityLogs.ActivityLog, :count) == 0
    end

    test "writes request_id to the log row", %{conn: conn} do
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
        "id" => "#{remote_actor_uri()}/follow/log3",
        "actor" => remote_actor_uri(),
        "object" => person.uri
      }

      post_to_inbox(conn, person.id, activity)

      [log] = Revix.Repo.all(Revix.ActivityLogs.ActivityLog)
      assert is_binary(log.request_id)
    end
  end
end
