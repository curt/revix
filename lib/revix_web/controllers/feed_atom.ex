defmodule RevixWeb.FeedATOM do
  use RevixWeb, :html

  import RevixWeb.FeedActivity

  embed_templates "feed_atom/*"

  def format_atom_datetime(nil), do: ""
  def format_atom_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  def feed_entry_id({:checkin, entry}), do: entry.uri
  def feed_entry_id({:post, entry}), do: entry.uri
  def feed_entry_id({:like, like}), do: "#{like.object_uri}#like-#{like.id}"

  def feed_entry_updated({:checkin, entry}), do: format_atom_datetime(effective_updated(entry))
  def feed_entry_updated({:post, entry}), do: format_atom_datetime(effective_updated(entry))
  def feed_entry_updated({:like, like}), do: format_atom_datetime(like.published_at_utc)
end
