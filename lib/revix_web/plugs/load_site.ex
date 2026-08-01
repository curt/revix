defmodule RevixWeb.Plugs.LoadSite do
  @behaviour Plug

  import Plug.Conn

  alias Revix.Sites
  alias RevixWeb.CanonicalRoutes

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    assign(conn, :site, Sites.get_site_or_default(CanonicalRoutes.home_url()))
  end
end
