defmodule RevixWeb.FeedController do
  use Phoenix.Controller, formats: [:html, :json, :atom, :rss]

  use Gettext, backend: RevixWeb.Gettext
  import Plug.Conn

  alias Revix.ActivityFeed
  alias Revix.Sites
  alias RevixWeb.CanonicalRoutes
  alias RevixWeb.FeedActivity

  def index(conn, _params), do: render_site_feed(conn, :atom)

  def rss(conn, _params), do: render_site_feed(conn, :rss)

  defp render_site_feed(conn, format) do
    limit = Application.get_env(:revix, :home)[:activity_limit] || 50
    activities = ActivityFeed.build_feed_activities(nil, limit)
    site = Sites.get_site_or_default(CanonicalRoutes.home_url())

    render_feed(conn, format, activities, site_feed_meta(site, format))
  end

  defp site_feed_meta(site, format) do
    feed_url = RevixWeb.Endpoint.url() <> feed_path(format)

    %{
      feed_title: "#{site.title} — activity",
      feed_subtitle: "Posts, check-ins, and likes",
      feed_id: feed_url,
      feed_self_url: feed_url,
      feed_alternate_url: RevixWeb.Endpoint.url()
    }
  end

  defp feed_path(:atom), do: "/feed.atom"
  defp feed_path(:rss), do: "/feed.rss"

  # Shared render step for the site and per-person feeds (see
  # `RevixWeb.PersonFeedController`). `meta` carries the five per-feed assigns
  # (feed_title/feed_subtitle/feed_id/feed_self_url/feed_alternate_url).
  def render_feed(conn, format, activities, meta) do
    updated_at = feed_updated_at(activities)

    conn
    |> put_format(to_string(format))
    |> put_view(feed_view(format))
    |> put_resp_content_type(content_type(format))
    |> render(:index, Map.merge(meta, %{activities: activities, updated_at: updated_at}))
  end

  defp feed_view(:atom), do: RevixWeb.FeedATOM
  defp feed_view(:rss), do: RevixWeb.FeedRSS

  defp content_type(:atom), do: "application/atom+xml"
  defp content_type(:rss), do: "application/rss+xml"

  defp feed_updated_at(activities) do
    activities
    |> Enum.map(fn {_, item} -> FeedActivity.effective_updated(item) end)
    |> Enum.max(DateTime, fn -> DateTime.utc_now() end)
  end
end
