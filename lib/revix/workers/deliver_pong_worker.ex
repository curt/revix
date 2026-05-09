defmodule Revix.Workers.DeliverPongWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.{Federation, People, Pings}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"pong_id" => id}}) do
    pong = Pings.get_ping!(id)

    with {:ok, actor} <- People.get_local_person_by_uri(pong.actor_uri),
         {:ok, inbox_url} <- Federation.resolve_inbox(pong.target_uri),
         :ok <- Federation.deliver(build_activity(pong), inbox_url, actor) do
      {:ok, _} = Pings.mark_delivered(pong)
      broadcast_update()
      :ok
    else
      {:error, reason} ->
        {:ok, _} = Pings.mark_failed(pong, inspect(reason))
        broadcast_update()
        :discard
    end
  end

  defp build_activity(pong) do
    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "type" => "Pong",
      "id" => pong.uri,
      "actor" => pong.actor_uri,
      "to" => pong.target_uri,
      "object" => pong.object_uri
    }
  end

  defp broadcast_update do
    Phoenix.PubSub.broadcast(Revix.PubSub, "pings", :pings_updated)
  end
end
