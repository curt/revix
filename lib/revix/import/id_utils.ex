defmodule Revix.Import.IdUtils do
  @alphabet "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
  @base String.length(@alphabet)

  @doc """
  Generates a deterministic 11-character Base58 Revix ID from a source system's
  string identifier. Mirrors the logic in generate_id_from_guid.sql:
  SHA256(source_id) → first 8 bytes → Base58 → left-pad to 11 chars with '1'.
  """
  def generate_id(source_id) when is_binary(source_id) do
    :crypto.hash(:sha256, source_id)
    |> binary_part(0, 8)
    |> encode()
  end

  defp encode(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.reduce(0, fn byte, acc -> acc * 256 + byte end)
    |> encode_base58([])
    |> String.pad_leading(11, String.at(@alphabet, 0))
  end

  defp encode_base58(0, acc), do: Enum.join(acc)

  defp encode_base58(num, acc) do
    encode_base58(div(num, @base), [String.at(@alphabet, rem(num, @base)) | acc])
  end
end
