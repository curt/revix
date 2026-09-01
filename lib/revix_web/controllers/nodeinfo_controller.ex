defmodule RevixWeb.NodeInfoController do
  use RevixWeb, :controller

  alias Revix.Entries
  alias Revix.People
  alias Revix.Sites
  alias RevixWeb.CanonicalRoutes

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
    site = Sites.get_site_or_default(CanonicalRoutes.home_url())

    %{
      version: version,
      software: software_map(),
      protocols: ["activitypub"],
      services: %{inbound: [], outbound: ["atom1.0", "rss2.0"]},
      openRegistrations: false,
      usage: %{
        users: %{total: People.count_local_people()},
        localPosts: Entries.count_local_published_entries(),
        localComments: Entries.count_local_comments()
      },
      metadata: %{
        nodeName: site.title,
        nodeDescription: site.description
      }
    }
  end

  defp software_map do
    %{
      name: "Revix",
      version: to_string(Application.spec(:revix, :vsn)),
      repository: Application.get_env(:revix, :nodeinfo)[:repository],
      homepage: CanonicalRoutes.home_url()
    }
  end
end
