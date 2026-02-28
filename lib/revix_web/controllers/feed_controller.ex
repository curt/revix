defmodule RevixWeb.FeedController do
  use Phoenix.Controller, formats: [:html, :json, :atom]

  use Phoenix.VerifiedRoutes,
    endpoint: RevixWeb.Endpoint,
    router: RevixWeb.Router,
    statics: RevixWeb.static_paths()

  use Gettext, backend: RevixWeb.Gettext
  import Plug.Conn

  alias Revix.Entries
  alias Revix.Likes

  def index(conn, _params) do
    limit = Application.get_env(:revix, :home)[:activity_limit] || 50

    checkins = Entries.get_recent_checkins(limit)
    likes = Likes.get_recent_likes(limit)
    comments = Entries.get_recent_comments(limit)

    activities =
      (Enum.map(checkins, &{:checkin, &1}) ++
         Enum.map(likes, &{:like, &1}) ++
         Enum.map(comments, &{:comment, &1}))
      |> Enum.sort_by(fn {_, item} -> item.published_at_utc end, {:desc, DateTime})
      |> Enum.take(limit)

    updated_at =
      case activities do
        [{_, item} | _] -> item.published_at_utc
        [] -> DateTime.utc_now()
      end

    conn
    |> put_format("atom")
    |> put_resp_content_type("application/atom+xml")
    |> render(:index,
      activities: activities,
      updated_at: updated_at,
      feed_url: url(conn, ~p"/feed.atom"),
      site_url: RevixWeb.Endpoint.url()
    )
  end
end
