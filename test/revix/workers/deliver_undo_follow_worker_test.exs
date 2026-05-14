defmodule Revix.Workers.DeliverUndoFollowWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.DeliverUndoFollowWorker
  alias Revix.Follows.Follow

  import Revix.PeopleFixtures
  import Revix.FederationFixtures

  setup do
    stub_remote_server()
    :ok
  end

  defp insert_unfollowed(follower_uri, following_uri) do
    id = Revix.Ecto.Base58Id.autogenerate()

    %Follow{id: id}
    |> Follow.create_changeset(%{
      uri: "tag:revix,#{Date.utc_today()}:follow:#{id}",
      follower_uri: follower_uri,
      following_uri: following_uri,
      origin: :local
    })
    |> Repo.insert!()
    |> Follow.unfollow_changeset()
    |> Repo.update!()
  end

  describe "perform/1" do
    test "delivers Undo{Follow} activity and returns :ok" do
      person = person_fixture()
      person = %{person | private_key: private_key_pem()}
      follow = insert_unfollowed(person.uri, remote_actor_uri())

      assert :ok = perform_job(DeliverUndoFollowWorker, %{"follow_id" => follow.id})
    end

    test "builds an Undo{Follow} activity with correct nested structure" do
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
      follow = insert_unfollowed(person.uri, remote_actor_uri())

      :ok = perform_job(DeliverUndoFollowWorker, %{"follow_id" => follow.id})

      activity = Agent.get(delivered, & &1)
      assert activity["type"] == "Undo"
      assert activity["actor"] == follow.follower_uri
      assert activity["object"]["type"] == "Follow"
      assert activity["object"]["id"] == follow.uri
      assert activity["object"]["actor"] == follow.follower_uri
      assert activity["object"]["object"] == follow.following_uri
    end
  end
end
