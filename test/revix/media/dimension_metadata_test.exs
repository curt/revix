defmodule Revix.Media.DimensionMetadataTest do
  use ExUnit.Case, async: true

  alias Revix.Media.DimensionMetadata

  describe "parse/1" do
    test "reads width and height from lowercase S3 metadata headers" do
      headers = [{"x-amz-meta-width", "1200"}, {"x-amz-meta-height", "900"}]
      assert DimensionMetadata.parse(headers) == {:ok, 1200, 900}
    end

    test "matches header names case-insensitively" do
      headers = [
        {"Content-Type", "image/jpeg"},
        {"X-Amz-Meta-Width", "800"},
        {"X-AMZ-META-HEIGHT", "600"}
      ]

      assert DimensionMetadata.parse(headers) == {:ok, 800, 600}
    end

    test "returns :error when the width header is missing" do
      assert DimensionMetadata.parse([{"x-amz-meta-height", "900"}]) == :error
    end

    test "returns :error when the height header is missing" do
      assert DimensionMetadata.parse([{"x-amz-meta-width", "1200"}]) == :error
    end

    test "returns :error for a non-numeric width" do
      headers = [{"x-amz-meta-width", "wide"}, {"x-amz-meta-height", "900"}]
      assert DimensionMetadata.parse(headers) == :error
    end

    test "returns :error for a width with trailing characters" do
      headers = [{"x-amz-meta-width", "1200px"}, {"x-amz-meta-height", "900"}]
      assert DimensionMetadata.parse(headers) == :error
    end

    test "returns :error for a height with trailing characters" do
      headers = [{"x-amz-meta-width", "1200"}, {"x-amz-meta-height", "900px"}]
      assert DimensionMetadata.parse(headers) == :error
    end

    test "returns :error for an empty header list" do
      assert DimensionMetadata.parse([]) == :error
    end
  end
end
