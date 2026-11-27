defmodule Revix.Repo.Migrations.SanitizeStoredHtml do
  use Ecto.Migration

  # Rows written before Revix.Markdown sanitized its output may hold script
  # tags or javascript: links. Sanitizing is lossy only for unsafe markup, so
  # there is nothing to restore on rollback.
  def up do
    Revix.Markdown.Backfill.run()
  end

  def down, do: :ok
end
