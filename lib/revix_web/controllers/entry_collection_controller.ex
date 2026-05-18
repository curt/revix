defmodule RevixWeb.EntryCollectionController do
  use RevixWeb, :controller

  alias Revix.Entries
  alias Revix.Likes

  action_fallback RevixWeb.FallbackController

  def likes(conn, %{"id" => id}) do
    with {:ok, entry} <- Entries.get_entry(id) do
      likes = Likes.get_active_likes_for_entry(entry.uri)
      items = Enum.map(likes, & &1.like_uri)

      activity(conn, %{
        "type" => "OrderedCollection",
        "id" => request_url(conn),
        "totalItems" => length(items),
        "orderedItems" => items
      })
    end
  end

  def replies(conn, %{"id" => id}) do
    with {:ok, entry} <- Entries.get_entry(id) do
      replies = Entries.get_comments_for_entry(entry.uri)
      items = Enum.map(replies, & &1.uri)

      activity(conn, %{
        "type" => "OrderedCollection",
        "id" => request_url(conn),
        "totalItems" => length(items),
        "orderedItems" => items
      })
    end
  end
end
