defmodule RevixWeb.PageController do
  use RevixWeb, :controller

  alias Revix.ActivityFeed
  alias Revix.Places
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
      og = StructuredData.home_og()

      conn
      |> assign(:head_links, [%{rel: "canonical", href: CanonicalRoutes.home_url()}])
      |> assign(:head_meta, og)
      |> assign(:twitter_meta, StructuredData.twitter_card(og))
      |> render(:home,
        activities: activities,
        page_title: "Revix",
        meta_description: "Revix is a federated place to log check-ins and share posts."
      )
    end
  end

  defp geo_features(places) do
    Enum.map(places, fn p ->
      Map.merge(p.coordinates, %{properties: %{name: p.name, url: p.url}})
    end)
  end
end
