defmodule Revix.Workers.ProcessInboundUpdateNoteWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.Entries
  alias Revix.Follows
  alias Revix.Workers.InboundNoteHelpers

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => activity, "person_id" => _person_id}}) do
    note = activity["object"]
    actor_uri = activity["actor"]

    with true <- is_map(note),
         note_uri when is_binary(note_uri) <- note["id"],
         actor_uri when is_binary(actor_uri) <- actor_uri do
      if InboundNoteHelpers.local_context?(note) or Follows.followed_by_any_local?(actor_uri) do
        update_and_normalize(note_uri, InboundNoteHelpers.extract_note_attrs(note, actor_uri))
      else
        :ok
      end
    else
      _ -> {:error, :invalid_activity}
    end
  end

  def perform(%Oban.Job{}), do: {:error, :invalid_activity}

  defp update_and_normalize(uri, attrs) do
    case Entries.update_inbound_note(uri, attrs) do
      {:ok, _} -> :ok
      {:error, :not_remote} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
