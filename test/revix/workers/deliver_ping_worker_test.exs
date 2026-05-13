defmodule Revix.Workers.DeliverPingWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.DeliverPingWorker
  alias Revix.{Pings, People}

  import Revix.PeopleFixtures
  import Revix.FederationFixtures

  setup do
    stub_remote_server()
    :ok
  end

  describe "perform/1" do
    test "marks ping as delivered on success" do
      person = person_fixture()
      {:ok, _} = People.set_person_role(person, :owner)
      person = People.get_person!(person.id)
      person = %{person | private_key: private_key_pem()}

      ping_uri = "#{person.uri}/ping/abc"

      {:ok, outbound_ping} =
        Pings.create_outbound_ping(person.uri, remote_actor_uri(), ping_uri)

      assert :ok = perform_job(DeliverPingWorker, %{"ping_id" => outbound_ping.id})

      assert Pings.get_ping!(outbound_ping.id).status == :delivered
    end

    test "marks ping as failed and returns :discard on delivery error" do
      person = person_fixture()
      {:ok, _} = People.set_person_role(person, :owner)
      person = People.get_person!(person.id)
      person = %{person | private_key: private_key_pem()}

      Req.Test.stub(:federation, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      ping_uri = "#{person.uri}/ping/def"

      {:ok, outbound_ping} =
        Pings.create_outbound_ping(person.uri, remote_actor_uri(), ping_uri)

      assert :discard = perform_job(DeliverPingWorker, %{"ping_id" => outbound_ping.id})

      assert Pings.get_ping!(outbound_ping.id).status == :failed
    end
  end
end
