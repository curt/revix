defmodule RevixWeb.ImageHelpers do
  @moduledoc """
  Looks up persisted per-version image dimensions (`Revix.Media.ImageDimension`)
  for use as `width`/`height`/`srcset`/`sizes` `<img>` attributes.

  Returns `[]` when dimensions aren't available for a given lookup — e.g.
  before capture completes on a brand-new upload, or before a backfill runs
  for images that predate this feature — so callers degrade gracefully to a
  plain `src`-only `<img>`.
  """

  @srcset_versions [:medium, :large]

  def dimension_attrs(%{dimensions: dimensions}, version) when is_list(dimensions) do
    case Enum.find(dimensions, &(&1.version == version)) do
      nil -> []
      dim -> [width: dim.width, height: dim.height]
    end
  end

  def dimension_attrs(_image, _version), do: []

  @doc """
  Returns `srcset`/`sizes` attributes built from `:medium`/`:large`'s real
  captured widths, or `[]` if fewer than 2 candidate widths are available —
  a single-source `srcset` offers no benefit over plain `src` and could
  confuse a browser if malformed.
  """
  def srcset_attrs(%{dimensions: dimensions} = image) when is_list(dimensions) do
    case srcset_candidates(image, dimensions) do
      [] ->
        []

      [_single] ->
        []

      candidates ->
        [srcset: Enum.join(candidates, ", "), sizes: "(max-width: 800px) 100vw, 800px"]
    end
  end

  def srcset_attrs(_image), do: []

  defp srcset_candidates(image, dimensions) do
    Enum.reduce(@srcset_versions, [], fn version, acc ->
      case Enum.find(dimensions, &(&1.version == version)) do
        nil ->
          acc

        dim ->
          url = Revix.Uploaders.Image.url({image.file, image}, version)
          [~s(#{url} #{dim.width}w) | acc]
      end
    end)
    |> Enum.reverse()
  end
end
