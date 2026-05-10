defmodule Revix.Workers.ProcessInboundPingWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.ProcessInboundPingWorker
  alias Revix.{Pings, People}

  import Revix.PeopleFixtures

  setup do
    Req.Test.stub(:federation, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/plain")
      |> Plug.Conn.send_resp(202, "")
    end)

    :ok
  end

  describe "perform/1" do
    test "stores inbound ping and enqueues pong for owner" do
      person = person_fixture()
      {:ok, _} = People.set_person_role(person, :owner)
      person = People.get_person!(person.id)

      activity = %{
        "type" => "Ping",
        "id" => "https://remote.example.com/users/alice/ping/xyz",
        "actor" => "https://remote.example.com/users/alice",
        "to" => person.uri
      }

      assert :ok =
               perform_job(ProcessInboundPingWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      pings = Pings.list_recent()
      assert Enum.any?(pings, &(&1.uri == activity["id"] and &1.direction == :inbound))
    end

    test "handles self-ping: reuses existing outbound ping and enqueues pong" do
      person = person_fixture()
      {:ok, _} = People.set_person_role(person, :owner)
      person = People.get_person!(person.id)

      ping_uri = "#{person.uri}/ping/selftest"
      {:ok, _outbound} = Pings.create_outbound_ping(person.uri, person.uri, ping_uri)

      activity = %{
        "type" => "Ping",
        "id" => ping_uri,
        "actor" => person.uri,
        "to" => person.uri
      }

      assert :ok =
               perform_job(ProcessInboundPingWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      pings = Pings.list_recent()
      assert length(Enum.filter(pings, &(&1.uri == ping_uri))) == 1
      assert Enum.any?(pings, &(&1.type == :pong and &1.direction == :outbound))
    end

    test "silently drops ping for non-owner" do
      person = person_fixture()

      activity = %{
        "type" => "Ping",
        "id" => "https://remote.example.com/users/alice/ping/xyz",
        "actor" => "https://remote.example.com/users/alice",
        "to" => person.uri
      }

      assert :ok =
               perform_job(ProcessInboundPingWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      assert [] = Pings.list_recent()
    end
  end
end
