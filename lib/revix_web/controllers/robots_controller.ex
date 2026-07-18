defmodule RevixWeb.RobotsController do
  use RevixWeb, :controller

  def index(conn, _params) do
    body = """
    User-agent: *
    Allow: /

    Sitemap: #{url(conn, ~p"/sitemap.xml")}
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end
end
