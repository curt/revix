defmodule Revix.Workers.ProcessInboundPongWorkerTest do
  use Revix.DataCase, async: true

  alias Revix.Workers.ProcessInboundPongWorker
  alias Revix.{Pings, People}

  import Revix.PeopleFixtures

  describe "perform/1" do
    test "stores inbound pong for owner" do
      person = person_fixture()
      {:ok, _} = People.set_person_role(person, :owner)
      person = People.get_person!(person.id)

      activity = %{
        "type" => "Pong",
        "id" => "https://remote.example.com/users/alice/pong/uvw",
        "actor" => "https://remote.example.com/users/alice",
        "to" => person.uri,
        "object" => "#{person.uri}/ping/abc"
      }

      assert :ok =
               perform_job(ProcessInboundPongWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      pings = Pings.list_recent()
      assert Enum.any?(pings, &(&1.uri == activity["id"] and &1.type == :pong))
    end

    test "handles self-pong: marks existing outbound pong as delivered" do
      person = person_fixture()
      {:ok, _} = People.set_person_role(person, :owner)
      person = People.get_person!(person.id)

      ping_uri = "#{person.uri}/ping/selftest"
      pong_uri = "#{person.uri}/pong/selftest"

      {:ok, _outbound_pong} =
        Pings.create_outbound_pong(person.uri, person.uri, pong_uri, ping_uri)

      activity = %{
        "type" => "Pong",
        "id" => pong_uri,
        "actor" => person.uri,
        "to" => person.uri,
        "object" => ping_uri
      }

      assert :ok =
               perform_job(ProcessInboundPongWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      pings = Pings.list_recent()
      assert length(Enum.filter(pings, &(&1.uri == pong_uri))) == 1
      pong = Enum.find(pings, &(&1.uri == pong_uri))
      assert pong.status == :delivered
    end

    test "silently drops pong for non-owner" do
      person = person_fixture()

      activity = %{
        "type" => "Pong",
        "id" => "https://remote.example.com/users/alice/pong/uvw",
        "actor" => "https://remote.example.com/users/alice",
        "to" => person.uri,
        "object" => "#{person.uri}/ping/abc"
      }

      assert :ok =
               perform_job(ProcessInboundPongWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      assert [] = Pings.list_recent()
    end

    test "returns error when person is not found" do
      activity = %{
        "type" => "Pong",
        "id" => "https://remote.example.com/users/alice/pong/uvw",
        "actor" => "https://remote.example.com/users/alice",
        "to" => "https://example.com/people/unknown",
        "object" => "https://example.com/people/unknown/ping/abc"
      }

      # Use a valid 11-char Base58 ID that doesn't exist in the DB
      assert {:error, :not_found} =
               perform_job(ProcessInboundPongWorker, %{
                 "activity" => activity,
                 "person_id" => "11111111111"
               })
    end
  end
end
