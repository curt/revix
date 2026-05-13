defmodule RevixWeb.Controller.Helpers do
  def activity(conn, data) do
    conn
    |> Plug.Conn.put_resp_content_type("application/activity+json")
    |> Phoenix.Controller.json(Revix.ActivityPub.contextify(data))
  end

  def geo(conn, data) do
    conn
    |> Plug.Conn.put_resp_content_type("application/geo+json")
    |> Phoenix.Controller.json(
      Geo.JSON.Encoder.encode!(%Geo.GeometryCollection{geometries: data}, feature: true)
    )
  end
end
