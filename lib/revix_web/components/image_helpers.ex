defmodule RevixWeb.ImageHelpers do
  @moduledoc """
  Looks up persisted per-version image dimensions (`Revix.Media.ImageDimension`)
  for use as `width`/`height` `<img>` attributes.

  Returns `[]` when no matching row exists — e.g. before capture completes on
  a brand-new upload, or before a backfill runs for images that predate this
  feature — so callers degrade gracefully to a plain `src`-only `<img>`.
  """

  def dimension_attrs(%{dimensions: dimensions}, version) when is_list(dimensions) do
    case Enum.find(dimensions, &(&1.version == version)) do
      nil -> []
      dim -> [width: dim.width, height: dim.height]
    end
  end

  def dimension_attrs(_image, _version), do: []
end
