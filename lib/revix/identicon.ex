defmodule Revix.Identicon do
  @moduledoc """
  Generates GitHub-style identicon PNGs from an identifier string.

  The identicon is a 5x5 symmetric grid of colored squares, deterministically
  derived from an MD5 hash of the identifier. The output is a valid PNG binary
  with no external dependencies — encoding uses Erlang's `:crypto`, `:zlib`,
  and `:erlang.crc32`.
  """

  @max_size 256
  @grid_size 5
  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>
  @background {230, 230, 230}

  @doc """
  Generates a square PNG identicon for the given identifier.

  Returns PNG binary data. The `size` parameter specifies the image dimension
  in pixels (clamped to a maximum of #{@max_size}). The actual image dimension
  will be rounded down to the nearest multiple of #{@grid_size}.
  """
  @spec generate(String.t(), pos_integer()) :: binary()
  def generate(identifier, size \\ 128)

  def generate(identifier, size) when is_binary(identifier) and is_integer(size) and size > 0 do
    size = min(size, @max_size)
    cell_size = div(size, @grid_size)
    image_size = cell_size * @grid_size

    <<r, g, b, rest::binary>> = :crypto.hash(:md5, identifier)

    grid = build_grid(rest)
    pixels = render_pixels(grid, {r, g, b}, cell_size, image_size)
    encode_png(pixels, image_size)
  end

  # Builds a 5x5 symmetric boolean grid from hash bytes.
  # Each row has 3 independent cells (columns 0, 1, 2); columns 3 and 4
  # mirror columns 1 and 0 respectively. A byte is "filled" if even.
  defp build_grid(hash_bytes) do
    (hash_bytes <> <<0, 0>>)
    |> :binary.bin_to_list()
    |> Enum.take(15)
    |> Enum.map(&(rem(&1, 2) == 0))
    |> Enum.chunk_every(3)
    |> Enum.map(fn [a, b, c] -> [a, b, c, b, a] end)
  end

  # Renders the grid as raw RGB pixel data with PNG scanline filter bytes.
  defp render_pixels(grid, color, cell_size, image_size) do
    {bg_r, bg_g, bg_b} = @background
    {fg_r, fg_g, fg_b} = color

    for row <- grid, into: <<>> do
      scanline =
        for filled <- row, into: <<>> do
          pixel = if filled, do: <<fg_r, fg_g, fg_b>>, else: <<bg_r, bg_g, bg_b>>
          :binary.copy(pixel, cell_size)
        end

      # Pad scanline to image_size pixels if cell_size * grid_size < image_size
      padded = pad_scanline(scanline, image_size * 3)

      # Each scanline is prefixed with filter byte 0 (None)
      row_with_filter = <<0, padded::binary>>
      :binary.copy(row_with_filter, cell_size)
    end
  end

  defp pad_scanline(scanline, target_bytes) when byte_size(scanline) >= target_bytes, do: scanline

  defp pad_scanline(scanline, target_bytes) do
    padding = target_bytes - byte_size(scanline)
    {bg_r, bg_g, bg_b} = @background
    scanline <> :binary.copy(<<bg_r, bg_g, bg_b>>, div(padding, 3))
  end

  # Encodes raw pixel data as a minimal valid PNG.
  defp encode_png(pixel_data, image_size) do
    ihdr_data = <<
      image_size::32,
      image_size::32,
      8,
      2,
      0,
      0,
      0
    >>

    compressed = :zlib.compress(pixel_data)

    @png_signature <>
      png_chunk("IHDR", ihdr_data) <>
      png_chunk("IDAT", compressed) <>
      png_chunk("IEND", <<>>)
  end

  defp png_chunk(type, data) do
    crc = :erlang.crc32(<<type::binary, data::binary>>)
    <<byte_size(data)::32, type::binary, data::binary, crc::32>>
  end
end
