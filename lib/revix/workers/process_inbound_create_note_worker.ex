defmodule Revix.Workers.ProcessInboundCreateNoteWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.Entries
  alias Revix.Entries.Entry
  alias Revix.Follows
  alias Revix.Workers.InboundNoteHelpers

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => activity, "person_id" => _person_id}}) do
    note = activity["object"]
    actor_uri = activity["actor"]

    with true <- is_map(note),
         note_uri when is_binary(note_uri) <- note["id"],
         actor_uri when is_binary(actor_uri) <- actor_uri do
      # Accepts if the note replies to a local entry OR the actor is followed by a local user.
      if InboundNoteHelpers.local_context?(note) or Follows.followed_by_any_local?(actor_uri) do
        persist_and_broadcast(note, actor_uri)
      else
        :ok
      end
    else
      _ -> {:error, :invalid_activity}
    end
  end

  defp persist_and_broadcast(note, actor_uri) do
    case Entries.create_inbound_note(InboundNoteHelpers.extract_note_attrs(note, actor_uri)) do
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
end
