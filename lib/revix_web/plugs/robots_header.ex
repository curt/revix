defmodule RevixWeb.Plugs.RobotsHeader do
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: Keyword.get(opts, :allow_index, false)

  @impl Plug
  def call(conn, allow_index) do
    register_before_send(conn, fn conn ->
      put_resp_header(conn, "x-robots-tag", robots_value(conn, allow_index))
    end)
  end

  defp robots_value(%{private: %{phoenix_format: "html"}}, true), do: "index, follow"
  defp robots_value(%{private: %{phoenix_format: "html"}}, _), do: "noindex, follow"
  defp robots_value(_, _), do: "noindex, nofollow"
end
