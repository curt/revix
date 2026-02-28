defmodule Revix.Places.PlaceTest do
  use Revix.DataCase

  alias Revix.Places.Place

  describe "create_changeset/2" do
    test "valid changeset with required fields" do
      changeset =
        Place.create_changeset(%Place{}, %{name: "Test Place", latitude: 40.0, longitude: -105.0})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :name) == "Test Place"
      assert Ecto.Changeset.get_field(changeset, :slug) == "test-place"

      assert %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326} =
               Ecto.Changeset.get_field(changeset, :coordinates)
    end

    test "valid changeset with OSM fields" do
      changeset =
        Place.create_changeset(%Place{}, %{
          name: "Café Latte",
          latitude: 48.8566,
          longitude: 2.3522,
          osm_type: :node,
          osm_id: 12345
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :osm_type) == :node
      assert Ecto.Changeset.get_field(changeset, :osm_id) == 12345
    end

    test "requires name" do
      changeset = Place.create_changeset(%Place{}, %{latitude: 40.0, longitude: -105.0})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires latitude" do
      changeset = Place.create_changeset(%Place{}, %{name: "Test", longitude: -105.0})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).latitude
    end

    test "requires longitude" do
      changeset = Place.create_changeset(%Place{}, %{name: "Test", latitude: 40.0})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).longitude
    end

    test "validates latitude range" do
      changeset =
        Place.create_changeset(%Place{}, %{name: "Test", latitude: 91.0, longitude: 0.0})

      refute changeset.valid?
      assert "must be less than or equal to 90" in errors_on(changeset).latitude

      changeset =
        Place.create_changeset(%Place{}, %{name: "Test", latitude: -91.0, longitude: 0.0})

      refute changeset.valid?
      assert "must be greater than or equal to -90" in errors_on(changeset).latitude
    end

    test "validates longitude range" do
      changeset =
        Place.create_changeset(%Place{}, %{name: "Test", latitude: 0.0, longitude: 181.0})

      refute changeset.valid?
      assert "must be less than or equal to 180" in errors_on(changeset).longitude

      changeset =
        Place.create_changeset(%Place{}, %{name: "Test", latitude: 0.0, longitude: -181.0})

      refute changeset.valid?
      assert "must be greater than or equal to -180" in errors_on(changeset).longitude
    end

    test "does not cast programmatic fields" do
      changeset =
        Place.create_changeset(%Place{}, %{
          name: "Test",
          latitude: 40.0,
          longitude: -105.0,
          id: "injected_id",
          uri: "injected_uri",
          url: "injected_url",
          origin: :remote
        })

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :id)
      refute Ecto.Changeset.get_change(changeset, :uri)
      refute Ecto.Changeset.get_change(changeset, :url)
      refute Ecto.Changeset.get_change(changeset, :origin)
    end
  end

  describe "slugify/1" do
    test "converts to lowercase and replaces non-alphanumeric with hyphens" do
      assert Place.slugify("Hello World") == "hello-world"
    end

    test "trims leading and trailing hyphens" do
      assert Place.slugify("  Hello  ") == "hello"
    end

    test "handles special characters" do
      assert Place.slugify("Café & Bäckerei") == "cafe-backerei"
    end

    test "collapses multiple hyphens" do
      assert Place.slugify("foo---bar") == "foo-bar"
    end

    test "returns empty string for nil" do
      assert Place.slugify(nil) == ""
    end
  end
end
