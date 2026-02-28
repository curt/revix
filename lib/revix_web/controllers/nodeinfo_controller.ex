defmodule RevixWeb.NodeInfoController do
  use RevixWeb, :controller

  def well_known(conn, _) do
    json(conn, %{links: [well_known_map("2.0"), well_known_map("2.1")]})
  end

  def version(conn, %{"version" => version = "2.0"}) do
    json(conn, version_map(version))
  end

  def version(conn, %{"version" => version = "2.1"}) do
    json(conn, version_map(version))
  end

  defp well_known_map(version) do
    %{
      href: url(~p"/nodeinfo/#{version}"),
      rel: "http://nodeinfo.diaspora.software/ns/schema/#{version}"
    }
  end

  defp version_map(version) do
    %{
      version: version,
      software: %{
        name: "Revix",
        version: "pre-alpha"
      },
      protocols: ["activitypub"],
      services: %{inbound: [], outbound: ["rss2.0"]},
      openRegistrations: false
    }
  end
end
