defmodule Revix.Workers.ProcessInboundPongWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.{People, Pings}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => activity, "person_id" => person_id}}) do
    with {:ok, person} <- People.get_local_person(person_id),
         true <- person.role == :owner do
      case Pings.create_inbound_pong(%{
             uri: activity["id"],
             actor_uri: activity["actor"],
             target_uri: person.uri,
             object_uri: activity["object"]
           }) do
        {:ok, _} ->
          :ok

        {:error, %Ecto.Changeset{errors: [{:uri, {"has already been taken", _}} | _]}} ->
          # Self-pong: outbound pong already recorded — mark it delivered
          activity["id"]
          |> Pings.get_ping_by_uri!()
          |> Pings.mark_delivered()

        {:error, _} ->
          :ok
      end

      broadcast_update()
      :ok
    else
      false ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp broadcast_update do
    Phoenix.PubSub.broadcast(Revix.PubSub, "pings", :pings_updated)
  end
end
