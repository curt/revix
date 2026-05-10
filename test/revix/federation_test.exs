defmodule Revix.FederationTest do
  use Revix.DataCase, async: false

  alias Revix.Federation
  alias Revix.FederationFixtures

  setup do
    Req.Test.stub(:federation, fn conn ->
      case conn.request_path do
        "/users/alice" ->
          Req.Test.json(conn, FederationFixtures.remote_actor_map())

        "/users/alice/inbox" ->
          conn
          |> Plug.Conn.put_resp_header("content-type", "text/plain")
          |> Plug.Conn.send_resp(202, "")

        _ ->
          Plug.Conn.send_resp(conn, 404, "not found")
      end
    end)

    :ok
  end

  describe "fetch_actor/1" do
    test "returns actor map on success" do
      {:ok, actor} = Federation.fetch_actor(FederationFixtures.remote_actor_uri())
      assert actor["type"] == "Person"
      assert actor["preferredUsername"] == "alice"
    end

    test "returns error on non-200 response" do
      assert {:error, {:http_error, 404}} =
               Federation.fetch_actor("https://remote.example.com/missing")
    end

    test "returns error on transport failure" do
      Req.Test.stub(:federation, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, _} = Federation.fetch_actor(FederationFixtures.remote_actor_uri())
    end
  end

  describe "resolve_inbox/1" do
    test "returns inbox URL from actor document" do
      assert {:ok, inbox} = Federation.resolve_inbox(FederationFixtures.remote_actor_uri())
      assert inbox == FederationFixtures.remote_inbox_url()
    end

    test "returns error when actor has no inbox" do
      Req.Test.stub(:federation, fn conn ->
        Req.Test.json(conn, %{
          "id" => "https://remote.example.com/users/alice",
          "type" => "Person"
        })
      end)

      assert {:error, :no_inbox} = Federation.resolve_inbox(FederationFixtures.remote_actor_uri())
    end
  end

  describe "deliver/3" do
    test "posts activity to inbox and returns :ok" do
      person = Revix.PeopleFixtures.person_fixture()

      person_with_keys = %{person | private_key: FederationFixtures.private_key_pem()}

      activity = %{
        "@context" => "https://www.w3.org/ns/activitystreams",
        "type" => "Ping",
        "id" => "#{person.uri}/ping/abc",
        "actor" => person.uri,
        "to" => FederationFixtures.remote_actor_uri()
      }

      assert :ok =
               Federation.deliver(
                 activity,
                 FederationFixtures.remote_inbox_url(),
                 person_with_keys
               )
    end
  end
end
