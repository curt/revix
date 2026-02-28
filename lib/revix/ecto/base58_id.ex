defmodule Revix.Ecto.Base58Id do
  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def cast(value) when is_binary(value) do
    if valid?(value) do
      {:ok, value}
    else
      :error
    end
  end

  def cast(_), do: :error

  @impl true
  def load(value) when is_binary(value), do: {:ok, value}

  @impl true
  def dump(value) when is_binary(value), do: {:ok, value}
  def dump(_), do: :error

  @impl true
  def autogenerate do
    :crypto.strong_rand_bytes(8) |> encode()
  end

  # Base58 Bitcoin alphabet
  @alphabet "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
  @base String.length(@alphabet)

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

  defp valid?(string) do
    String.length(string) == 11 and
      String.graphemes(string)
      |> Enum.all?(fn char -> String.contains?(@alphabet, char) end)
  end
end
