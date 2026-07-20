defmodule RevixWeb.ImageHelpersTest do
  use ExUnit.Case, async: true

  alias RevixWeb.ImageHelpers

  describe "dimension_attrs/2" do
    test "returns width/height for a matching version" do
      image = %{dimensions: [%{version: :large, width: 1200, height: 600}]}
      assert ImageHelpers.dimension_attrs(image, :large) == [width: 1200, height: 600]
    end

    test "returns [] when the version has no matching row" do
      image = %{dimensions: [%{version: :large, width: 1200, height: 600}]}
      assert ImageHelpers.dimension_attrs(image, :medium) == []
    end

    test "returns [] when dimensions is an empty list" do
      image = %{dimensions: []}
      assert ImageHelpers.dimension_attrs(image, :large) == []
    end

    test "returns [] when dimensions is not loaded" do
      image = %{dimensions: %Ecto.Association.NotLoaded{}}
      assert ImageHelpers.dimension_attrs(image, :large) == []
    end
  end
end
