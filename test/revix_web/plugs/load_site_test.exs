defmodule RevixWeb.Plugs.LoadSiteTest do
  use Revix.DataCase, async: true

  import Plug.Test

  alias Revix.Sites
  alias RevixWeb.CanonicalRoutes
  alias RevixWeb.Plugs.LoadSite

  defp run(conn) do
    LoadSite.call(conn, LoadSite.init([]))
  end

  test "assigns the default site when no site row exists" do
    conn = conn(:get, "/") |> run()
    assert conn.assigns.site.title == "Revix"
  end

  test "assigns the configured site when a site row exists" do
    Sites.update_site(CanonicalRoutes.home_url(), %{title: "My Site", description: "Custom"})

    conn = conn(:get, "/") |> run()
    assert conn.assigns.site.title == "My Site"
    assert conn.assigns.site.description == "Custom"
  end
end
