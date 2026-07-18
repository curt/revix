defmodule RevixWeb.PageController do
  use RevixWeb, :controller

  alias Revix.ActivityFeed
  alias Revix.Places

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
      render(conn, :home, activities: activities, page_title: "Revix")
    end
  end

  defp geo_features(places) do
    Enum.map(places, fn p ->
      Map.merge(p.coordinates, %{properties: %{name: p.name, url: p.url}})
    end)
  end
end
