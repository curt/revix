defmodule Revix.Entries.Inbound do
  @moduledoc """
  Notes and checkins received from other servers over ActivityPub: creating,
  updating, and deleting them on behalf of their remote author.
  """
  alias Revix.Repo
  alias Revix.Entries.Entry
  import Revix.Entries.Events

  def create_inbound_note(attrs) do
    %Entry{type: :note, origin: :remote}
    |> Entry.inbound_note_changeset(attrs)
    |> Repo.insert()
    |> tap_ok(fn note -> notifications().notify_reply(note) end)
  end

  def create_inbound_checkin(attrs) do
    %Entry{type: :checkin, origin: :remote}
    |> Entry.inbound_note_changeset(attrs)
    |> Repo.insert()
  end

  def update_inbound_note(uri, actor_uri, attrs) when is_binary(uri) and is_binary(actor_uri) do
    case Revix.Entries.get_entry_by_uri(uri) do
      {:ok, %Entry{origin: :remote, author_uri: ^actor_uri} = entry} ->
        entry
        |> Entry.inbound_note_changeset(attrs)
        |> Repo.update()
        |> tap_ok(&broadcast_context(&1.context, {:comment_updated, &1}))

      {:ok, %Entry{origin: :remote}} ->
        {:error, :not_owner}

      {:error, :not_found} ->
        create_inbound_note(attrs)
        |> tap_ok(&broadcast_context(&1.context, {:comment_created, &1}))

      {:ok, %Entry{origin: :local}} ->
        {:error, :not_remote}
    end
  end

  def delete_inbound_note(uri, actor_uri) when is_binary(uri) and is_binary(actor_uri) do
    uri
    |> Revix.Entries.get_entry_by_uri()
    |> delete_own_inbound_note(actor_uri)
  end

  defp delete_own_inbound_note(
         {:ok, %Entry{origin: :remote, author_uri: actor_uri} = entry},
         actor_uri
       ) do
    with {:ok, deleted} <- Repo.delete(entry) do
      broadcast_context(deleted.context, {:comment_deleted, deleted.id})
      notifications().retract_entry_notifications([deleted.uri])
      {:ok, deleted}
    end
  end

  # Missing, local, or someone else's: nothing for this actor to delete.
  defp delete_own_inbound_note(_lookup, _actor_uri), do: :ok
end
