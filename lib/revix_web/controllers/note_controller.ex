defmodule RevixWeb.NoteController do
  use RevixWeb, :controller

  alias Revix.Entries
  alias Revix.Entries.Entry
  alias Revix.Repo

  action_fallback RevixWeb.FallbackController

  @max_thread_depth 50

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
    with {:ok, root} <- walk_to_root(note.in_reply_to_uri, @max_thread_depth) do
      redirect(conn, to: "#{thread_path(root)}#comment-#{note.id}")
    end
  end

  # Comments live on checkin and post pages. Federated notes can form cycles or
  # very long chains, so the walk gives up after @max_thread_depth lookups.
  defp walk_to_root(nil, _hops_left), do: {:error, :not_found}
  defp walk_to_root(_uri, 0), do: {:error, :not_found}

  defp walk_to_root(uri, hops_left) do
    uri
    |> Entries.get_entry_by_uri()
    |> root_or_parent(hops_left - 1)
  end

  defp root_or_parent({:ok, %Entry{type: type} = root}, _hops_left)
       when type in [:checkin, :post],
       do: {:ok, root}

  defp root_or_parent({:ok, %Entry{in_reply_to_uri: parent_uri}}, hops_left),
    do: walk_to_root(parent_uri, hops_left)

  defp root_or_parent(error, _hops_left), do: error

  defp thread_path(%Entry{type: :checkin} = checkin),
    do: checkin |> Repo.preload(:place) |> checkin_path()

  defp thread_path(%Entry{type: :post} = post), do: post_path(post)
end
