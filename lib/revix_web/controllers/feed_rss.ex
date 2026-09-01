defmodule RevixWeb.FeedRSS do
  use RevixWeb, :html

  import RevixWeb.FeedActivity

  embed_templates "feed_rss/*"

  # RSS <guid> — the stable entry/like URI. Checkins/posts use their canonical
  # URL (also a permalink); likes get the compound object+like id, which is not
  # a resolvable URL.
  def feed_entry_guid({:checkin, entry}), do: entry.uri
  def feed_entry_guid({:post, entry}), do: entry.uri
  def feed_entry_guid({:like, like}), do: "#{like.object_uri}#like-#{like.id}"

  def feed_entry_permalink?({:checkin, _}), do: "true"
  def feed_entry_permalink?({:post, _}), do: "true"
  def feed_entry_permalink?({:like, _}), do: "false"

  # The timestamp an RSS <pubDate> should carry: the same value the Atom feed
  # puts in <updated>, minus the ISO-8601 formatting.
  def feed_entry_pub_datetime({:checkin, entry}), do: effective_updated(entry)
  def feed_entry_pub_datetime({:post, entry}), do: effective_updated(entry)
  def feed_entry_pub_datetime({:like, like}), do: like.published_at_utc

  # RFC 822 / RFC 1123 date. `Calendar.strftime/2` uses English day/month
  # abbreviations regardless of locale, so this is spec-safe. Input is a UTC
  # DateTime.
  def format_rss_datetime(nil), do: ""

  def format_rss_datetime(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
  end
end
