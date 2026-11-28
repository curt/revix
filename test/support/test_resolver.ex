defmodule Revix.TestResolver do
  @moduledoc """
  DNS stand-in for tests: a few named hosts resolve to private or missing
  addresses so SSRF checks can be exercised, and everything else resolves to a
  public documentation address without touching the network.
  """

  def resolve("internal.example"), do: {:ok, [{10, 0, 0, 5}]}
  def resolve("mixed.example"), do: {:ok, [{93, 184, 216, 34}, {192, 168, 1, 1}]}
  def resolve("v6-internal.example"), do: {:ok, [{0xFD00, 0, 0, 0, 0, 0, 0, 1}]}
  def resolve("nowhere.example"), do: {:error, :nxdomain}
  def resolve(_host), do: {:ok, [{93, 184, 216, 34}]}
end
