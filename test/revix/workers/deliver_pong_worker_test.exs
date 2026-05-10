defmodule Revix.Workers.DeliverPongWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.DeliverPongWorker
  alias Revix.{Pings, People}

  import Revix.PeopleFixtures
  import Revix.FederationFixtures

  setup do
    stub_remote_server()
    :ok
  end

  describe "perform/1" do
    test "marks both outbound pong and inbound ping as delivered on success" do
      person = person_fixture()
      {:ok, _} = People.set_person_role(person, :owner)
      person = People.get_person!(person.id)
      person = %{person | private_key: private_key_pem()}

      Revix.Repo.update_all(
        from(p in Revix.People.Person, where: p.id == ^person.id),
        set: [public_key: public_key_pem()]
      )

      ping_uri = "#{remote_actor_uri()}/ping/abc"
      pong_uri = "#{person.uri}/pong/xyz"

      {:ok, inbound_ping} =
        Pings.create_inbound_ping(%{
          uri: ping_uri,
          actor_uri: remote_actor_uri(),
          target_uri: person.uri
        })

      {:ok, outbound_pong} =
        Pings.create_outbound_pong(person.uri, remote_actor_uri(), pong_uri, ping_uri)

      assert :ok = perform_job(DeliverPongWorker, %{"pong_id" => outbound_pong.id})

      assert Pings.get_ping!(outbound_pong.id).status == :delivered
      assert Pings.get_ping!(inbound_ping.id).status == :delivered
    end

    test "marks both outbound pong and inbound ping as failed on delivery error" do
      person = person_fixture()
      {:ok, _} = People.set_person_role(person, :owner)
      person = People.get_person!(person.id)
      person = %{person | private_key: private_key_pem()}

      Req.Test.stub(:federation, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      ping_uri = "#{remote_actor_uri()}/ping/abc"
      pong_uri = "#{person.uri}/pong/xyz"

      {:ok, inbound_ping} =
        Pings.create_inbound_ping(%{
          uri: ping_uri,
          actor_uri: remote_actor_uri(),
          target_uri: person.uri
        })

      {:ok, outbound_pong} =
        Pings.create_outbound_pong(person.uri, remote_actor_uri(), pong_uri, ping_uri)

      assert :discard = perform_job(DeliverPongWorker, %{"pong_id" => outbound_pong.id})

      assert Pings.get_ping!(outbound_pong.id).status == :failed
      assert Pings.get_ping!(inbound_ping.id).status == :failed
    end
  end
end
