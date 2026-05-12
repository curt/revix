defmodule Revix.Workers.ProcessInboundCreateNoteWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.Entries
  alias Revix.Entries.Entry

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => activity, "person_id" => _person_id}}) do
    note = activity["object"]
    actor_uri = activity["actor"]

    with true <- is_map(note),
         note_uri when is_binary(note_uri) <- note["id"],
         actor_uri when is_binary(actor_uri) <- actor_uri do
      if local_context?(note) do
        persist_and_broadcast(note, actor_uri)
      else
        :ok
      end
    else
      _ -> {:error, :invalid_activity}
    end
  end

  # Returns true if the note's context or inReplyTo resolves to a local entry.
  # Isolated here so the acceptance criteria can be broadened in a future pass.
  defp local_context?(note) do
    [note["context"], note["inReplyTo"]]
    |> Enum.filter(&is_binary/1)
    |> Enum.any?(fn uri ->
      case Entries.get_entry_by_uri(uri) do
        {:ok, %Entry{origin: :local}} -> true
        _ -> false
      end
    end)
  end

  defp persist_and_broadcast(note, actor_uri) do
    case Entries.create_inbound_note(%{
           uri: note["id"],
           url: note["url"] || note["id"],
           author_uri: actor_uri,
           content: note["content"],
           in_reply_to_uri: note["inReplyTo"],
           context: note["context"],
           published_at_utc: parse_datetime(note["published"])
         }) do
      {:ok, saved_note} ->
        broadcast_note(saved_note)
        :ok

      {:error, %Ecto.Changeset{errors: [{:uri, {"has already been taken", _}} | _]}} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp broadcast_note(%Entry{context: context_uri} = note) when is_binary(context_uri) do
    Phoenix.PubSub.broadcast(Revix.PubSub, "context:#{context_uri}", {:comment_created, note})
  end

  defp broadcast_note(_), do: :ok

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
