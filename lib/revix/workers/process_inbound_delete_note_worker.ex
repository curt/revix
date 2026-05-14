defmodule Revix.Workers.ProcessInboundDeleteNoteWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.Entries

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => activity, "person_id" => _person_id}}) do
    object_uri = extract_object_uri(activity["object"])
    actor_uri = activity["actor"]

    with uri when is_binary(uri) <- object_uri,
         actor_uri when is_binary(actor_uri) <- actor_uri do
      case Entries.delete_inbound_note(uri, actor_uri) do
        {:ok, _} -> :ok
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> {:error, :invalid_activity}
    end
  end

  defp extract_object_uri(uri) when is_binary(uri), do: uri
  defp extract_object_uri(%{"id" => id}) when is_binary(id), do: id
  defp extract_object_uri(_), do: nil
end
