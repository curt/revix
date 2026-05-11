defmodule RevixWeb.PlaceController do
  use RevixWeb, :controller

  alias Revix.Entries
  alias Revix.Likes
  alias Revix.Places

  action_fallback RevixWeb.FallbackController

  def index(conn, _) do
    places = Places.get_local_places()
    index_by_format(conn, places, get_format(conn))
  end

  defp index_by_format(conn, places, "geo"), do: geo(conn, index_geo_features(places))

  defp index_by_format(conn, places, _), do: render(conn, places: places)

  defp index_geo_features(places) do
    Enum.map(places, fn p ->
      Map.merge(p.coordinates, %{properties: %{name: p.name, url: p.url}})
    end)
  end

  def show(conn, %{"id" => id} = params) do
    with {:ok, place} <- Places.get_local_place(id) do
      nearby = Places.get_local_places_near(place)
      checkins = Entries.get_local_checkins_for_place(place)
      posts = Entries.get_local_posts_for_place(place)
      show_by_format(conn, place, checkins, posts, nearby, params["slug"], get_format(conn))
    end
  end

  defp show_by_format(conn, place, _checkins, _posts, _nearby, _, "activity"),
    do: activity(conn, to_place_activity(place))

  defp show_by_format(conn, place, _checkins, _posts, nearby, _, "geo"),
    do: geo(conn, show_geo_features(place, nearby))

  defp show_by_format(conn, place, _checkins, _posts, _nearby, slug, _) when place.slug != slug,
    do: redirect(conn, to: place_path(place))

  defp show_by_format(conn, place, checkins, posts, nearby, _, _) do
    uris = Enum.map(checkins, & &1.uri)
    like_counts = Likes.count_active_likes_by_object_uris(uris)

    render(conn,
      place: place,
      checkins: checkins,
      posts: posts,
      nearby: nearby,
      like_counts: like_counts
    )
  end

  defp show_geo_features(place, nearby) do
    [
      Map.merge(place.coordinates, %{properties: %{name: place.name, url: place.url, focus: true}})
      | Enum.map(nearby, fn n ->
          Map.merge(n.place.coordinates, %{properties: %{name: n.place.name, url: n.place.url}})
        end)
    ]
  end

  def search(conn, %{"lat" => lat_str, "lon" => lon_str} = params) do
    accuracy_str = params["accuracy"] || "0"

    with {lat, ""} <- Float.parse(lat_str),
         {lon, ""} <- Float.parse(lon_str),
         {accuracy, _} <- Float.parse(accuracy_str) do
      db_results = Places.search_nearby_db(lat, lon, accuracy)
      osm_results = Places.search_nearby_osm(lat, lon, accuracy)
      json(conn, Places.merge_place_results(db_results, osm_results))
    else
      _ -> json(conn, [])
    end
  end
end
