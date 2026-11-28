defmodule RevixWeb.NoteController do
  use RevixWeb, :controller

  alias Revix.Entries
  alias Revix.Entries.Entry
  alias Revix.Repo

  action_fallback RevixWeb.FallbackController

  def show(conn, %{"id" => id}) do
    with {:ok, note} <- Entries.get_comment_with_author(id) do
      show_by_format(conn, note, get_format(conn))
    end
  end

  defp show_by_format(conn, %{tombstoned_at: ts} = note, "activity") when not is_nil(ts) do
    activity(conn, to_tombstone_activity(note), status: 410)
  end

  defp show_by_format(conn, note, "activity") do
    activity(conn, to_note_activity(note))
  end

  defp show_by_format(conn, note, _format) do
    with {:ok, checkin} <- get_context_checkin(note) do
      checkin = Repo.preload(checkin, :place)
      redirect(conn, to: "#{checkin_path(checkin)}#comment-#{note.id}")
    end
  end

  defp get_context_checkin(%{type: :note} = note), do: walk_to_checkin(note.in_reply_to_uri)
  defp get_context_checkin(checkin), do: {:ok, checkin}

  defp walk_to_checkin(nil), do: {:error, :not_found}

  defp walk_to_checkin(uri) do
    case Entries.get_entry_by_uri(uri) do
      {:ok, %Entry{type: :checkin} = checkin} -> {:ok, checkin}
      {:ok, %Entry{in_reply_to_uri: parent_uri}} -> walk_to_checkin(parent_uri)
      other -> other
    end
  end
end
