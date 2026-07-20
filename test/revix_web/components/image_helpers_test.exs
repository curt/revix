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

  describe "srcset_attrs/1" do
    defp image_with_dimensions(dimensions) do
      %{
        id: "iiiiiiiiiii",
        file: %{file_name: "test.jpg", updated_at: ~U[2026-01-01 00:00:00Z]},
        dimensions: dimensions
      }
    end

    test "returns srcset/sizes when both :medium and :large are captured" do
      image =
        image_with_dimensions([
          %{version: :large, width: 1200, height: 600},
          %{version: :medium, width: 800, height: 400}
        ])

      attrs = ImageHelpers.srcset_attrs(image)

      assert attrs[:sizes] == "(max-width: 800px) 100vw, 800px"
      assert attrs[:srcset] =~ "medium.jpg 800w"
      assert attrs[:srcset] =~ "large.jpg 1200w"

      # medium (narrower) should come before large (wider) in the srcset list
      medium_index = :binary.match(attrs[:srcset], "800w") |> elem(0)
      large_index = :binary.match(attrs[:srcset], "1200w") |> elem(0)
      assert medium_index < large_index
    end

    test "returns [] when dimensions is an empty list (zero rows / no capture yet)" do
      image = image_with_dimensions([])
      assert ImageHelpers.srcset_attrs(image) == []
    end

    test "returns [] when dimensions is not loaded" do
      image = %{
        id: "iiiiiiiiiii",
        file: %{file_name: "test.jpg"},
        dimensions: %Ecto.Association.NotLoaded{}
      }

      assert ImageHelpers.srcset_attrs(image) == []
    end

    test "returns [] when only :medium is captured (partial capture)" do
      image = image_with_dimensions([%{version: :medium, width: 800, height: 400}])
      assert ImageHelpers.srcset_attrs(image) == []
    end

    test "returns [] when only :large is captured (partial capture)" do
      image = image_with_dimensions([%{version: :large, width: 1200, height: 600}])
      assert ImageHelpers.srcset_attrs(image) == []
    end
  end
end
