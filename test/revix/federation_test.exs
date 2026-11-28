defmodule Revix.FederationTest do
  use Revix.DataCase, async: false

  alias Revix.Federation
  alias Revix.FederationFixtures

  setup do
    FederationFixtures.stub_remote_server()
    :ok
  end

  describe "fetch_actor/1" do
    test "refuses to fetch an actor from a private address" do
      Req.Test.stub(:federation, fn _conn -> flunk("request should not be sent") end)

      assert Federation.fetch_actor("https://169.254.169.254/latest/meta-data") ==
               {:error, :unsafe_url}
    end

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

    test "does not ask the remote server for a compressed response" do
      test_pid = self()

      Req.Test.stub(:federation, fn conn ->
        send(test_pid, {:accept_encoding, Plug.Conn.get_req_header(conn, "accept-encoding")})
        Req.Test.json(conn, FederationFixtures.remote_actor_map())
      end)

      assert {:ok, _actor} = Federation.fetch_actor(FederationFixtures.remote_actor_uri())
      assert_received {:accept_encoding, []}
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
    test "refuses to deliver to an inbox on a private address" do
      Req.Test.stub(:federation, fn _conn -> flunk("request should not be sent") end)

      person = %{
        Revix.PeopleFixtures.person_fixture()
        | private_key: FederationFixtures.private_key_pem()
      }

      assert Federation.deliver(%{"type" => "Ping"}, "https://internal.example/inbox", person) ==
               {:error, :unsafe_url}
    end

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
