defmodule Revix.Workers.ProcessInboundPingWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.{People, Pings}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => activity, "person_id" => person_id}}) do
    with {:ok, person} <- People.get_local_person(person_id),
         true <- person.role == :owner,
         {:ok, ping} <- store_inbound_ping(activity, person) do
      enqueue_pong(ping, person)
      :ok
    else
      false ->
        # Not the owner — silently discard
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp store_inbound_ping(activity, person) do
    case Pings.create_inbound_ping(%{
           uri: activity["id"],
           actor_uri: activity["actor"],
           target_uri: person.uri,
           object_uri: nil
         }) do
      {:ok, ping} ->
        {:ok, ping}

      {:error, %Ecto.Changeset{errors: [{:uri, {"has already been taken", _}} | _]}} ->
        # Self-ping: the outbound ping already has this URI — reuse it
        {:ok, Pings.get_ping_by_uri!(activity["id"])}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp enqueue_pong(ping, person) do
    id = Revix.Ecto.Base58Id.autogenerate()
    pong_uri = "#{person.uri}/pong/#{id}"

    {:ok, pong} =
      Pings.create_outbound_pong(person.uri, ping.actor_uri, pong_uri, ping.uri)

    %{pong_id: pong.id}
    |> Revix.Workers.DeliverPongWorker.new()
    |> Oban.insert()
  end
end
