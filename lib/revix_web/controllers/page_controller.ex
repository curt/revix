defmodule RevixWeb.PageController do
  use RevixWeb, :controller

  alias Revix.Places

  def home(conn, _params) do
    places = Places.get_local_places()
    geo(conn, geo_features(places))
  end

  defp geo_features(places) do
    Enum.map(places, fn p ->
      Map.merge(p.coordinates, %{properties: %{name: p.name, url: p.url}})
    end)
  end
end
