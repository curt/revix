defmodule RevixWeb.SitemapXML do
  use RevixWeb, :html

  embed_templates "sitemap_xml/*"

  def format_lastmod(%DateTime{} = dt), do: dt |> DateTime.to_date() |> Date.to_iso8601()
end
