defmodule RevixWeb.SitemapController do
  use Phoenix.Controller, formats: [:html, :xml]

  use Phoenix.VerifiedRoutes,
    endpoint: RevixWeb.Endpoint,
    router: RevixWeb.Router,
    statics: RevixWeb.static_paths()

  alias Revix.Entries
  alias Revix.Places

  def index(conn, _params) do
    conn
    |> put_format("xml")
    |> put_resp_content_type("application/xml")
    |> render(:index,
      places_url: url(conn, ~p"/sitemap/places.xml"),
      checkins_url: url(conn, ~p"/sitemap/checkins.xml"),
      posts_url: url(conn, ~p"/sitemap/posts.xml")
    )
  end

  def places(conn, _params) do
    entries =
      Enum.map(Places.get_local_places_for_sitemap(), fn place ->
        {RevixWeb.CanonicalRoutes.place_url(place), place.updated_at}
      end)

    render_urlset(conn, entries)
  end

  def checkins(conn, _params) do
    entries =
      Enum.map(Entries.get_recent_checkins(nil), fn checkin ->
        {RevixWeb.CanonicalRoutes.checkin_url(checkin), checkin.updated_at}
      end)

    render_urlset(conn, entries)
  end

  def posts(conn, _params) do
    entries =
      Enum.map(Entries.get_recent_posts(nil), fn post ->
        {RevixWeb.CanonicalRoutes.post_url(post), post.updated_at}
      end)

    render_urlset(conn, entries)
  end

  defp render_urlset(conn, entries) do
    conn
    |> put_format("xml")
    |> put_resp_content_type("application/xml")
    |> render(:urlset, entries: entries)
  end
end
