defmodule RevixWeb.PageController do
  use RevixWeb, :controller

  alias Revix.Entries
  alias Revix.Likes
  alias Revix.Places

  def home(conn, _params) do
    case get_format(conn) do
      "geo" ->
        places = Places.get_local_places()
        geo(conn, geo_features(places))

      _ ->
        limit = Application.get_env(:revix, :home)[:activity_limit] || 50
        checkins = Entries.get_recent_checkins(limit)
        posts = Entries.get_recent_posts(limit)
        likes = Likes.get_recent_likes(limit)
        comments = Entries.get_recent_comments(limit)

        activities =
          (Enum.map(checkins, &{:checkin, &1}) ++
             Enum.map(posts, &{:post, &1}) ++
             Enum.map(likes, &{:like, &1}) ++
             Enum.map(comments, &{:comment, &1}))
          |> Enum.sort_by(
            fn {_, item} -> Map.from_struct(item)[:starts_at_utc] || item.published_at_utc end,
            {:desc, DateTime}
          )
          |> Enum.take(limit)

        render(conn, :home, activities: activities)
    end
  end

  defp geo_features(places) do
    Enum.map(places, fn p ->
      Map.merge(p.coordinates, %{properties: %{name: p.name, url: p.url}})
    end)
  end
end
