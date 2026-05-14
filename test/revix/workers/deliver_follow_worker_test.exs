defmodule Revix.Workers.DeliverFollowWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.DeliverFollowWorker
  alias Revix.Follows.Follow

  import Revix.PeopleFixtures
  import Revix.FederationFixtures

  setup do
    stub_remote_server()
    :ok
  end

  defp insert_follow(follower_uri, following_uri) do
    id = Revix.Ecto.Base58Id.autogenerate()

    %Follow{id: id}
    |> Follow.create_changeset(%{
      uri: "tag:revix,#{Date.utc_today()}:follow:#{id}",
      follower_uri: follower_uri,
      following_uri: following_uri,
      origin: :local
    })
    |> Repo.insert!()
  end

  describe "perform/1" do
    test "delivers Follow activity and returns :ok" do
      person = person_fixture()
      person = %{person | private_key: private_key_pem()}
      follow = insert_follow(person.uri, remote_actor_uri())

      assert :ok = perform_job(DeliverFollowWorker, %{"follow_id" => follow.id})
    end

    test "returns {:error, reason} on delivery failure" do
      Req.Test.stub(:federation, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      person = person_fixture()
      person = %{person | private_key: private_key_pem()}
      follow = insert_follow(person.uri, remote_actor_uri())

      assert {:error, _reason} = perform_job(DeliverFollowWorker, %{"follow_id" => follow.id})
    end

    test "builds a Follow activity with correct fields" do
      delivered = Agent.start_link(fn -> nil end) |> elem(1)

      Req.Test.stub(:federation, fn conn ->
        case conn.method do
          "POST" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            Agent.update(delivered, fn _ -> Jason.decode!(body) end)

            conn
            |> Plug.Conn.put_resp_header("content-type", "text/plain")
            |> Plug.Conn.send_resp(202, "")

          "GET" ->
            Req.Test.json(conn, remote_actor_map())
        end
      end)

      person = person_fixture()
      person = %{person | private_key: private_key_pem()}
      follow = insert_follow(person.uri, remote_actor_uri())

      :ok = perform_job(DeliverFollowWorker, %{"follow_id" => follow.id})

      activity = Agent.get(delivered, & &1)
      assert activity["type"] == "Follow"
      assert activity["id"] == follow.uri
      assert activity["actor"] == follow.follower_uri
      assert activity["object"] == follow.following_uri
    end
  end
end
