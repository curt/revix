defmodule Revix.PingsTest do
  use Revix.DataCase, async: false

  import Ecto.Query

  alias Revix.Pings
  alias Revix.Pings.Ping

  import Revix.PeopleFixtures

  setup do
    Req.Test.stub(:federation, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/plain")
      |> Plug.Conn.send_resp(202, "")
    end)

    :ok
  end

  @actor_uri "http://localhost:4000/people/abc123"
  @target_uri "https://remote.example.com/users/alice"
  @ping_uri "http://localhost:4000/people/abc123/ping/xyz"
  @pong_uri "https://remote.example.com/users/alice/pong/uvw"

  describe "create_outbound_ping/3" do
    test "creates a pending outbound ping" do
      {:ok, ping} = Pings.create_outbound_ping(@actor_uri, @target_uri, @ping_uri)

      assert ping.type == :ping
      assert ping.direction == :outbound
      assert ping.status == :pending
      assert ping.actor_uri == @actor_uri
      assert ping.target_uri == @target_uri
      assert ping.uri == @ping_uri
      assert is_nil(ping.object_uri)
    end
  end

  describe "create_inbound_ping/1" do
    test "creates a pending inbound ping" do
      {:ok, ping} =
        Pings.create_inbound_ping(%{
          uri: @ping_uri,
          actor_uri: @target_uri,
          target_uri: @actor_uri,
          object_uri: nil
        })

      assert ping.type == :ping
      assert ping.direction == :inbound
      assert ping.status == :pending
    end
  end

  describe "create_outbound_pong/4" do
    test "creates a pending outbound pong referencing the original ping" do
      {:ok, pong} = Pings.create_outbound_pong(@actor_uri, @target_uri, @pong_uri, @ping_uri)

      assert pong.type == :pong
      assert pong.direction == :outbound
      assert pong.status == :pending
      assert pong.object_uri == @ping_uri
    end
  end

  describe "create_inbound_pong/1" do
    test "creates a delivered inbound pong" do
      {:ok, pong} =
        Pings.create_inbound_pong(%{
          uri: @pong_uri,
          actor_uri: @target_uri,
          target_uri: @actor_uri,
          object_uri: @ping_uri
        })

      assert pong.type == :pong
      assert pong.direction == :inbound
      assert pong.status == :delivered
      assert pong.object_uri == @ping_uri
    end
  end

  describe "mark_delivered/1" do
    test "updates status to delivered" do
      {:ok, ping} = Pings.create_outbound_ping(@actor_uri, @target_uri, @ping_uri)
      {:ok, updated} = Pings.mark_delivered(ping)

      assert updated.status == :delivered
    end
  end

  describe "mark_failed/2" do
    test "updates status to failed and stores error" do
      {:ok, ping} = Pings.create_outbound_ping(@actor_uri, @target_uri, @ping_uri)
      {:ok, updated} = Pings.mark_failed(ping, "connection refused")

      assert updated.status == :failed
      assert updated.error == "connection refused"
    end
  end

  describe "list_recent/1" do
    test "returns pings ordered by inserted_at desc" do
      {:ok, first} = Pings.create_outbound_ping(@actor_uri, @target_uri, "#{@ping_uri}/1")

      # Bump inserted_at for the second ping to ensure ordering
      Revix.Repo.update_all(
        from(p in Ping, where: p.id == ^first.id),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -5, :second)]
      )

      {:ok, second} =
        Pings.create_outbound_ping(@actor_uri, @target_uri, "#{@ping_uri}/2")

      pings = Pings.list_recent()
      ids = Enum.map(pings, & &1.id)

      assert second.id in ids
      assert first.id in ids
      assert Enum.find_index(ids, &(&1 == second.id)) < Enum.find_index(ids, &(&1 == first.id))
    end

    test "limits results" do
      for i <- 1..5 do
        Pings.create_outbound_ping(@actor_uri, @target_uri, "#{@ping_uri}/#{i}")
      end

      assert length(Pings.list_recent(3)) == 3
    end
  end

  describe "purge_older_than/1" do
    test "deletes pings older than the given days" do
      {:ok, old_ping} = Pings.create_outbound_ping(@actor_uri, @target_uri, "#{@ping_uri}/old")

      past = DateTime.add(DateTime.utc_now(), -10 * 86_400, :second)

      Revix.Repo.update_all(
        from(p in Ping, where: p.id == ^old_ping.id),
        set: [inserted_at: past]
      )

      {:ok, fresh} = Pings.create_outbound_ping(@actor_uri, @target_uri, "#{@ping_uri}/new")

      {:ok, count} = Pings.purge_older_than(7)

      assert count == 1
      assert Revix.Repo.get(Ping, fresh.id)
      refute Revix.Repo.get(Ping, old_ping.id)
    end
  end

  describe "send_ping/3" do
    test "creates a ping and enqueues delivery for an owner" do
      person = person_fixture()
      {:ok, _} = Revix.People.set_person_role(person, :owner)
      person = Revix.People.get_person!(person.id)
      scope = Revix.People.Scope.for_person(person)

      uri_fn = fn id -> "#{person.uri}/ping/#{id}" end

      assert {:ok, ping} = Pings.send_ping(scope, @target_uri, uri_fn)
      assert ping.type == :ping
      assert ping.status in [:pending, :delivered, :failed]
    end

    test "returns unauthorized for non-owner" do
      person = person_fixture()
      scope = Revix.People.Scope.for_person(person)

      uri_fn = fn id -> "http://localhost:4000/ping/#{id}" end

      assert {:error, :unauthorized} = Pings.send_ping(scope, @target_uri, uri_fn)
    end
  end
end
