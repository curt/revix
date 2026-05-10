defmodule Revix.Pings do
  import Ecto.Query, warn: false

  alias Revix.Repo
  alias Revix.Pings.Ping

  def create_outbound_ping(actor_uri, target_uri, ping_uri) do
    %Ping{}
    |> Ping.changeset(%{
      uri: ping_uri,
      type: :ping,
      direction: :outbound,
      actor_uri: actor_uri,
      target_uri: target_uri,
      status: :pending
    })
    |> Repo.insert()
  end

  def create_inbound_ping(attrs) do
    %Ping{}
    |> Ping.changeset(Map.merge(attrs, %{type: :ping, direction: :inbound, status: :pending}))
    |> Repo.insert()
  end

  def create_inbound_pong(attrs) do
    %Ping{}
    |> Ping.changeset(Map.merge(attrs, %{type: :pong, direction: :inbound, status: :delivered}))
    |> Repo.insert()
  end

  def create_outbound_pong(actor_uri, target_uri, pong_uri, object_uri) do
    %Ping{}
    |> Ping.changeset(%{
      uri: pong_uri,
      type: :pong,
      direction: :outbound,
      actor_uri: actor_uri,
      target_uri: target_uri,
      object_uri: object_uri,
      status: :pending
    })
    |> Repo.insert()
  end

  def mark_delivered(%Ping{} = ping) do
    ping
    |> Ping.changeset(%{status: :delivered})
    |> Repo.update()
  end

  def mark_failed(%Ping{} = ping, reason) when is_binary(reason) do
    ping
    |> Ping.changeset(%{status: :failed, error: reason})
    |> Repo.update()
  end

  def get_ping!(id), do: Repo.get!(Ping, id)

  def get_ping_by_uri!(uri), do: Repo.get_by!(Ping, uri: uri)

  def list_recent(limit \\ 50) do
    Ping
    |> order_by([p], desc: p.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def purge_older_than(days) when is_integer(days) and days > 0 do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    {count, _} =
      Ping
      |> where([p], p.inserted_at < ^cutoff)
      |> Repo.delete_all()

    {:ok, count}
  end

  def send_ping(scope, target_actor_uri, uri_fn) do
    if scope.person.role == :owner do
      id = Revix.Ecto.Base58Id.autogenerate()
      ping_uri = uri_fn.(id)

      with {:ok, ping} <- create_outbound_ping(scope.person.uri, target_actor_uri, ping_uri) do
        %{ping_id: ping.id}
        |> Revix.Workers.DeliverPingWorker.new()
        |> Oban.insert()

        {:ok, ping}
      end
    else
      {:error, :unauthorized}
    end
  end
end
