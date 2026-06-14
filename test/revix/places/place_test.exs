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

  describe "update_situation_changeset/2" do
    setup do
      place = %Place{
        id: "aaaaaaaaaaa",
        name: "Test Place",
        coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326},
        slug: "test-place"
      }

      {:ok, place: place}
    end

    test "valid with country only", %{place: place} do
      changeset = Place.update_situation_changeset(place, %{"country" => "us"})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :country) == "us"
      assert Ecto.Changeset.get_field(changeset, :city) == nil
      assert Ecto.Changeset.get_field(changeset, :secondary) == nil
    end

    test "valid with country and city", %{place: place} do
      changeset =
        Place.update_situation_changeset(place, %{"country" => "us", "city" => "scottsdale"})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :city) == "scottsdale"
    end

    test "valid with country, city, and secondary", %{place: place} do
      changeset =
        Place.update_situation_changeset(place, %{
          "country" => "us",
          "city" => "scottsdale",
          "secondary" => "az"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :secondary) == "az"
    end

    test "valid with all fields nil (clears situation)", %{place: place} do
      place = %{place | country: "us", city: "scottsdale", secondary: "az"}

      changeset =
        Place.update_situation_changeset(place, %{
          "country" => "",
          "city" => "",
          "secondary" => ""
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :country) == nil
      assert Ecto.Changeset.get_change(changeset, :city) == nil
      assert Ecto.Changeset.get_change(changeset, :secondary) == nil
    end

    test "normalizes country to lowercase", %{place: place} do
      changeset = Place.update_situation_changeset(place, %{"country" => "US"})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :country) == "us"
    end

    test "normalizes city to slugified form", %{place: place} do
      changeset =
        Place.update_situation_changeset(place, %{"country" => "fr", "city" => "Saint-Étienne"})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :city) == "saint-etienne"
    end

    test "normalizes secondary to slugified form", %{place: place} do
      changeset =
        Place.update_situation_changeset(place, %{
          "country" => "us",
          "city" => "phoenix",
          "secondary" => "New Mexico"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :secondary) == "new-mexico"
    end

    test "invalid: country must be exactly 2 characters", %{place: place} do
      changeset = Place.update_situation_changeset(place, %{"country" => "usa"})
      refute changeset.valid?
      assert "must be 2 characters" in errors_on(changeset).country
    end

    test "invalid: country must be lowercase letters only", %{place: place} do
      changeset = Place.update_situation_changeset(place, %{"country" => "u1"})
      refute changeset.valid?
      assert "must be two lowercase letters" in errors_on(changeset).country
    end

    test "invalid: city without country", %{place: place} do
      changeset = Place.update_situation_changeset(place, %{"city" => "phoenix"})
      refute changeset.valid?
      assert "requires country to be set" in errors_on(changeset).city
    end

    test "invalid: secondary without city", %{place: place} do
      changeset =
        Place.update_situation_changeset(place, %{"country" => "us", "secondary" => "az"})

      refute changeset.valid?
      assert "requires country and city to be set" in errors_on(changeset).secondary
    end

    test "invalid: secondary without country", %{place: place} do
      changeset = Place.update_situation_changeset(place, %{"secondary" => "az"})
      refute changeset.valid?
      assert "requires country and city to be set" in errors_on(changeset).secondary
    end
  end

  describe "update_slug_changeset/2" do
    setup do
      place = %Place{
        slug: "old-slug",
        coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
      }

      {:ok, place: place}
    end

    test "valid slug is accepted", %{place: place} do
      changeset = Place.update_slug_changeset(place, %{"slug" => "my-cool-place"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :slug) == "my-cool-place"
    end

    test "single word slug is accepted", %{place: place} do
      changeset = Place.update_slug_changeset(place, %{"slug" => "starbucks"})
      assert changeset.valid?
    end

    test "slug with digits is accepted", %{place: place} do
      changeset = Place.update_slug_changeset(place, %{"slug" => "place42"})
      assert changeset.valid?
    end

    test "empty slug fails required validation", %{place: place} do
      changeset = Place.update_slug_changeset(place, %{"slug" => ""})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).slug
    end

    test "missing slug fails required validation when struct has nil slug" do
      changeset = Place.update_slug_changeset(%Place{slug: nil}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).slug
    end

    test "missing slug does not fail when struct already has a slug", %{place: place} do
      changeset = Place.update_slug_changeset(place, %{})
      assert changeset.valid?
    end

    test "slug with uppercase letters fails format validation", %{place: place} do
      changeset = Place.update_slug_changeset(place, %{"slug" => "My-Place"})
      refute changeset.valid?
      assert "use only lowercase letters, digits, and hyphens" in errors_on(changeset).slug
    end

    test "slug with spaces fails format validation", %{place: place} do
      changeset = Place.update_slug_changeset(place, %{"slug" => "my place"})
      refute changeset.valid?
      assert "use only lowercase letters, digits, and hyphens" in errors_on(changeset).slug
    end

    test "slug with leading hyphen fails format validation", %{place: place} do
      changeset = Place.update_slug_changeset(place, %{"slug" => "-my-place"})
      refute changeset.valid?
      assert "use only lowercase letters, digits, and hyphens" in errors_on(changeset).slug
    end

    test "slug with trailing hyphen fails format validation", %{place: place} do
      changeset = Place.update_slug_changeset(place, %{"slug" => "my-place-"})
      refute changeset.valid?
      assert "use only lowercase letters, digits, and hyphens" in errors_on(changeset).slug
    end

    test "slug over 200 characters fails length validation", %{place: place} do
      long_slug = String.duplicate("a", 201)
      changeset = Place.update_slug_changeset(place, %{"slug" => long_slug})
      refute changeset.valid?
      assert "should be at most 200 character(s)" in errors_on(changeset).slug
    end

    test "accepts a changeset as first argument", %{place: place} do
      changeset =
        place
        |> Place.create_changeset(%{"name" => "Test", "latitude" => 40.0, "longitude" => -105.0})
        |> Place.update_slug_changeset(%{"slug" => "custom-slug"})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :slug) == "custom-slug"
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
