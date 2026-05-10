defmodule Revix.Workers.PurgePingsWorkerTest do
  use Revix.DataCase, async: true

  alias Revix.Workers.PurgePingsWorker
  alias Revix.Pings
  alias Revix.Pings.Ping

  @actor_uri "http://localhost:4000/people/abc123"
  @target_uri "https://remote.example.com/users/alice"

  describe "perform/1" do
    test "purges pings older than retention_days" do
      {:ok, old} = Pings.create_outbound_ping(@actor_uri, @target_uri, "http://x/ping/old")

      past = DateTime.add(DateTime.utc_now(), -10 * 86_400, :second)

      Revix.Repo.update_all(
        from(p in Ping, where: p.id == ^old.id),
        set: [inserted_at: past]
      )

      {:ok, fresh} = Pings.create_outbound_ping(@actor_uri, @target_uri, "http://x/ping/new")

      assert :ok = perform_job(PurgePingsWorker, %{})

      assert Revix.Repo.get(Ping, fresh.id)
      refute Revix.Repo.get(Ping, old.id)
    end
  end
end
