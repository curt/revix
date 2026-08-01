defmodule Revix.Sites do
  alias Revix.Repo
  alias Revix.Sites.Site
  alias Revix.Snippet

  @default_title "Revix"
  @default_description "Revix is a federated place to log check-ins and share posts."
  @page_title_description_max 60

  @doc """
  Returns the site row for the given endpoint, or `nil` if none exists.
  """
  def get_site(endpoint) when is_binary(endpoint) do
    Repo.get(Site, endpoint)
  end

  @doc """
  Returns the site row for the given endpoint, falling back to the built-in
  defaults (title and description) when no row exists or the title is blank.
  """
  def get_site_or_default(endpoint) when is_binary(endpoint) do
    case get_site(endpoint) do
      %Site{title: title} = site when is_binary(title) and title != "" -> site
      _ -> default_site(endpoint)
    end
  end

  @doc """
  Creates or updates the site row for the given endpoint.

  Returns `{:ok, site} | {:error, changeset}`.
  """
  def update_site(endpoint, attrs) when is_binary(endpoint) do
    %Site{endpoint: endpoint}
    |> Site.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:title, :description, :updated_at]},
      conflict_target: :endpoint
    )
  end

  @doc """
  Renders a site's Markdown description to HTML.

  Rendered on the fly rather than stored, since every site row is local —
  unlike entries, there is no remote-origin case where the HTML is known
  but the Markdown source isn't.
  """
  def description_html(%Site{description: nil}), do: nil

  def description_html(%Site{description: description}) do
    {:ok, html, _} = Earmark.as_html(description, compact_output: true)
    html
  end

  @doc """
  Builds the `<title>` tag content for the home page: the site title, plus a
  truncated snippet of the description when one is present.
  """
  def page_title(%Site{title: title, description: nil}), do: title

  def page_title(%Site{title: title, description: description}) do
    "#{title} · #{Snippet.snippify(description, @page_title_description_max)}"
  end

  defp default_site(endpoint) do
    %Site{endpoint: endpoint, title: @default_title, description: @default_description}
  end
end
