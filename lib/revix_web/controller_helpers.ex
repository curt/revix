defmodule RevixWeb.Controller.Helpers do
  use RevixWeb, :verified_routes

  def activity(conn, data, opts \\ []) do
    conn
    |> Plug.Conn.put_resp_content_type("application/activity+json")
    |> Plug.Conn.put_status(Keyword.get(opts, :status, 200))
    |> Phoenix.Controller.json(Revix.ActivityPub.contextify(data))
  end

  def geo(conn, data) do
    conn
    |> Plug.Conn.put_resp_content_type("application/geo+json")
    |> Phoenix.Controller.json(
      Geo.JSON.Encoder.encode!(%Geo.GeometryCollection{geometries: data}, feature: true)
    )
  end

  @doc """
  Assigns a page's Open Graph tags and the Twitter card built from them.
  """
  def assign_social_meta(conn, og) do
    conn
    |> Plug.Conn.assign(:head_meta, og)
    |> Plug.Conn.assign(:twitter_meta, RevixWeb.StructuredData.twitter_card(og))
  end

  @doc """
  The response for a deleted (tombstoned) entry: an ActivityStreams Tombstone
  with 410 for ActivityPub clients, and `{:error, :tombstoned}` (also 410, via
  the fallback controller) for every other format.
  """
  def tombstoned(conn, entry, "activity"),
    do: activity(conn, Revix.ActivityPub.to_tombstone_activity(entry), status: 410)

  def tombstoned(_conn, _entry, _format), do: {:error, :tombstoned}

  @doc """
  Re-runs image transforms for a checkin or post looked up by the caller, and
  redirects with a flash saying how it went.
  """
  def retransform_entry_images(conn, {:ok, %{tombstoned_at: ts}}, kind) when not is_nil(ts) do
    conn
    |> Phoenix.Controller.put_flash(:error, "#{entry_label(kind)} has been deleted.")
    |> Phoenix.Controller.redirect(to: entry_index_path(kind))
  end

  def retransform_entry_images(conn, {:ok, entry}, kind) do
    Revix.Media.retransform_images_for_entry(entry.id)

    conn
    |> Phoenix.Controller.put_flash(:info, "Photos re-transformed.")
    |> Phoenix.Controller.redirect(to: entry_show_path(kind, entry.id))
  end

  def retransform_entry_images(conn, {:error, _reason}, kind) do
    conn
    |> Phoenix.Controller.put_flash(:error, "#{entry_label(kind)} not found.")
    |> Phoenix.Controller.redirect(to: entry_index_path(kind))
  end

  defp entry_label(:checkin), do: "Checkin"
  defp entry_label(:post), do: "Post"

  defp entry_index_path(:checkin), do: ~p"/checkins"
  defp entry_index_path(:post), do: ~p"/posts"

  defp entry_show_path(:checkin, id), do: ~p"/checkins/#{id}"
  defp entry_show_path(:post, id), do: ~p"/posts/#{id}"
end
