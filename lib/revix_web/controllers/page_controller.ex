defmodule RevixWeb.PageController do
  use RevixWeb, :controller

  alias Revix.ActivityFeed
  alias Revix.Places
  alias Revix.Sites
  alias RevixWeb.CanonicalRoutes
  alias RevixWeb.StructuredData

  def index(conn, _params) do
    case get_format(conn) do
      "geo" ->
        places = Places.get_local_places()
        geo(conn, geo_features(places))

      _ ->
        render_home(conn)
    end
  end

  defp render_home(conn) do
    if conn.assigns.current_scope && conn.assigns.current_scope.person do
      Phoenix.LiveView.Controller.live_render(conn, RevixWeb.HomeFeedLive, [])
    else
      limit = Application.get_env(:revix, :home)[:activity_limit] || 50
      activities = ActivityFeed.build_feed_activities(nil, limit)
      site = conn.assigns.site
      og = StructuredData.home_og(site.title, site.description)

      conn
      |> assign(:head_links, [%{rel: "canonical", href: CanonicalRoutes.home_url()}])
      |> assign(:head_meta, og)
      |> assign(:twitter_meta, StructuredData.twitter_card(og))
      |> assign(:json_ld, StructuredData.home_json_ld(site.title, site.description))
      |> render(:home,
        activities: activities,
        description_html: Sites.description_html(site),
        page_title: Sites.page_title(site),
        meta_description: site.description
      )
    end
  end

  defp geo_features(places) do
    Enum.map(places, fn p ->
      Map.merge(p.coordinates, %{properties: %{name: p.name, url: p.url}})
    end)
  end
end
