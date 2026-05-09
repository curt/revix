defmodule Revix.Workers.DeliverPingWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.{Federation, People, Pings}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ping_id" => id}}) do
    ping = Pings.get_ping!(id)

    with {:ok, actor} <- People.get_local_person_by_uri(ping.actor_uri),
         {:ok, inbox_url} <- Federation.resolve_inbox(ping.target_uri),
         :ok <- Federation.deliver(build_activity(ping), inbox_url, actor) do
      {:ok, _} = Pings.mark_delivered(ping)
      broadcast_update()
      :ok
    else
      {:error, reason} ->
        {:ok, _} = Pings.mark_failed(ping, inspect(reason))
        broadcast_update()
        :discard
    end
  end

  defp build_activity(ping) do
    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "type" => "Ping",
      "id" => ping.uri,
      "actor" => ping.actor_uri,
      "to" => ping.target_uri
    }
  end

  defp broadcast_update do
    Phoenix.PubSub.broadcast(Revix.PubSub, "pings", :pings_updated)
  end
end
