defmodule Revix.Media.DimensionMetadata do
  @moduledoc """
  Reads image dimensions back from the `x-amz-meta-width`/`x-amz-meta-height`
  object metadata that `Revix.Uploaders.Image.s3_object_headers/2` writes.
  """

  def parse(headers) do
    meta = Map.new(headers, fn {k, v} -> {String.downcase(k), v} end)

    with width when width != nil <- meta["x-amz-meta-width"],
         height when height != nil <- meta["x-amz-meta-height"],
         {w, ""} <- Integer.parse(width),
         {h, ""} <- Integer.parse(height) do
      {:ok, w, h}
    else
      _ -> :error
    end
  end
end
