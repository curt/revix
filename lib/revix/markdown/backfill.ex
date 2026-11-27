defmodule Revix.Markdown.Backfill do
  @moduledoc """
  Re-sanitizes HTML stored before `Revix.Markdown` sanitized its output.

  Called from a data migration. It works on table names rather than schemas so
  later schema changes can't break the migration. Only rows whose HTML actually
  changes are written.
  """

  import Ecto.Query

  alias Revix.Repo

  @columns [entries: :content_html, places: :content_html, images: :caption_html]

  def run do
    Map.new(@columns, fn {table, field} -> {table, sanitize_column(table, field)} end)
  end

  defp sanitize_column(table, field) do
    table
    |> Atom.to_string()
    |> stored_html(field)
    |> Enum.count(&rewrite_if_unsafe(table, field, &1))
  end

  defp stored_html(table, field) do
    Repo.all(
      from(r in table,
        where: not is_nil(field(r, ^field)),
        select: {r.id, field(r, ^field)}
      )
    )
  end

  defp rewrite_if_unsafe(table, field, {id, html}) do
    rewrite(table, field, id, html, Revix.Markdown.sanitize(html))
  end

  defp rewrite(_table, _field, _id, html, html), do: false

  defp rewrite(table, field, id, _html, safe) do
    Repo.update_all(
      from(r in Atom.to_string(table), where: r.id == ^id),
      set: [{field, safe}]
    )

    true
  end
end
