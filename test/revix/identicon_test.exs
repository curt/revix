defmodule Revix.IdenticonTest do
  use ExUnit.Case, async: true

  alias Revix.Identicon

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>
  @iend_crc :erlang.crc32("IEND")

  describe "generate/2" do
    test "returns valid PNG binary" do
      png = Identicon.generate("test-id")
      assert <<@png_signature, _rest::binary>> = png
    end

    test "contains IHDR as first chunk" do
      png = Identicon.generate("test-id")
      assert <<@png_signature, _len::32, "IHDR", _rest::binary>> = png
    end

    test "ends with IEND chunk" do
      png = Identicon.generate("test-id")
      assert <<_::binary-size(byte_size(png) - 12), 0::32, "IEND", @iend_crc::32>> = png
    end

    test "returns deterministic output for same input" do
      assert Identicon.generate("ABcDeFgHiJk") == Identicon.generate("ABcDeFgHiJk")
    end

    test "returns different output for different identifiers" do
      refute Identicon.generate("identifier-a") == Identicon.generate("identifier-b")
    end

    test "larger size produces more bytes" do
      small = Identicon.generate("test", 64)
      large = Identicon.generate("test", 256)
      assert byte_size(large) > byte_size(small)
    end

    test "clamps size to maximum of 256" do
      assert Identicon.generate("test", 512) == Identicon.generate("test", 256)
    end

    test "default size is 128" do
      assert Identicon.generate("test") == Identicon.generate("test", 128)
    end

    test "encodes correct image dimensions in IHDR" do
      png = Identicon.generate("test", 100)
      # div(100, 5) * 5 = 100
      <<@png_signature, _len::32, "IHDR", width::32, height::32, _rest::binary>> = png
      assert width == 100
      assert height == 100
    end

    test "rounds image dimensions to multiple of grid size" do
      png = Identicon.generate("test", 128)
      # div(128, 5) * 5 = 125
      <<@png_signature, _len::32, "IHDR", width::32, height::32, _rest::binary>> = png
      assert width == 125
      assert height == 125
    end
  end
end
