defmodule RevixWeb.PersonFeedController do
  use Phoenix.Controller, formats: [:atom, :rss]

  use Phoenix.VerifiedRoutes,
    endpoint: RevixWeb.Endpoint,
    router: RevixWeb.Router,
    statics: RevixWeb.static_paths()

  import Plug.Conn

  alias Revix.ActivityFeed
  alias Revix.People
  alias Revix.Sites
  alias RevixWeb.CanonicalRoutes
  alias RevixWeb.FeedController

  def atom(conn, %{"id" => id}), do: render_person_feed(conn, id, :atom)

  def rss(conn, %{"id" => id}), do: render_person_feed(conn, id, :rss)

  defp render_person_feed(conn, id, format) do
    case People.get_local_person(id) do
      {:ok, person} -> render_for_person(conn, person, format)
      {:error, :not_found} -> send_resp(conn, 404, "Not Found")
    end
  end

  defp render_for_person(conn, person, format) do
    limit = Application.get_env(:revix, :home)[:activity_limit] || 50
    activities = ActivityFeed.build_person_activities(person, nil, limit)
    site = Sites.get_site_or_default(CanonicalRoutes.home_url())

    FeedController.render_feed(conn, format, activities, person_feed_meta(person, site, format))
  end

  defp person_feed_meta(person, site, format) do
    name = person.display_name || person.username
    feed_url = person_feed_url(person.id, format)

    %{
      feed_title: "#{name} — #{site.title}",
      feed_subtitle: "Posts, check-ins, and likes by #{name}",
      feed_id: feed_url,
      feed_self_url: feed_url,
      feed_alternate_url: CanonicalRoutes.person_url(person)
    }
  end

  defp person_feed_url(id, :atom), do: CanonicalRoutes.person_feed_atom_url(id)
  defp person_feed_url(id, :rss), do: CanonicalRoutes.person_feed_rss_url(id)
end
