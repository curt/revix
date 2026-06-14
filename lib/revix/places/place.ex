defmodule Revix.Places.Place do
  use Revix.Schema
  import Ecto.Changeset

  schema "places" do
    field :origin, Revix.Ecto.Origin
    field :uri, :string
    field :url, :string
    field :name, :string
    field :coordinates, Geo.PostGIS.Geometry
    field :longitude, :float, virtual: true
    field :latitude, :float, virtual: true
    field :altitude, :float
    field :slug, :string
    field :content, :string
    field :content_html, :string
    field :osm_type, Revix.Ecto.OsmElementType
    field :osm_id, :integer
    field :country, :string
    field :city, :string
    field :secondary, :string

    timestamps(type: :utc_datetime)
  end

  def create_changeset(place, attrs) do
    place
    |> cast(attrs, [:name, :latitude, :longitude, :osm_type, :osm_id])
    |> validate_required([:name, :latitude, :longitude])
    |> validate_length(:name, max: 200)
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> build_coordinates()
    |> build_slug()
  end

  defp build_coordinates(changeset) do
    lat = get_field(changeset, :latitude)
    lon = get_field(changeset, :longitude)

    if lat && lon do
      put_change(changeset, :coordinates, %Geo.Point{coordinates: {lon, lat}, srid: 4326})
    else
      changeset
    end
  end

  defp build_slug(changeset) do
    name = get_field(changeset, :name)

    if name do
      put_change(changeset, :slug, slugify(name))
    else
      changeset
    end
  end

  def update_slug_changeset(place_or_changeset, attrs) do
    place_or_changeset
    |> cast(attrs, [:slug])
    |> validate_required([:slug])
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
      message: "use only lowercase letters, digits, and hyphens"
    )
    |> validate_length(:slug, max: 200)
  end

  def update_situation_changeset(place, attrs) do
    place
    |> cast(attrs, [:country, :city, :secondary])
    |> normalize_situation_fields()
    |> validate_situation()
    |> check_constraint(:city,
      name: :city_requires_country,
      message: "requires country to be set"
    )
    |> check_constraint(:secondary,
      name: :secondary_requires_city,
      message: "requires country and city to be set"
    )
  end

  defp normalize_situation_fields(changeset) do
    changeset
    |> normalize_situation_field(:country, &String.downcase/1)
    |> normalize_situation_field(:city, &Slug.slugify/1)
    |> normalize_situation_field(:secondary, &Slug.slugify/1)
  end

  defp normalize_situation_field(changeset, field, fun) do
    case get_change(changeset, field) do
      nil -> changeset
      "" -> put_change(changeset, field, nil)
      value -> put_change(changeset, field, fun.(value))
    end
  end

  defp validate_situation(changeset) do
    changeset
    |> validate_country()
    |> validate_city_requires_country()
    |> validate_secondary_requires_city()
  end

  defp validate_country(changeset) do
    case get_field(changeset, :country) do
      nil ->
        changeset

      country ->
        validate_length(changeset, :country, is: 2, message: "must be 2 characters")
        |> then(fn cs ->
          if country =~ ~r/^[a-z]{2}$/,
            do: cs,
            else: add_error(cs, :country, "must be two lowercase letters")
        end)
    end
  end

  defp validate_city_requires_country(changeset) do
    city = get_field(changeset, :city)
    country = get_field(changeset, :country)

    if not is_nil(city) and is_nil(country) do
      add_error(changeset, :city, "requires country to be set")
    else
      changeset
    end
  end

  defp validate_secondary_requires_city(changeset) do
    secondary = get_field(changeset, :secondary)
    city = get_field(changeset, :city)
    country = get_field(changeset, :country)

    if not is_nil(secondary) and (is_nil(city) or is_nil(country)) do
      add_error(changeset, :secondary, "requires country and city to be set")
    else
      changeset
    end
  end

  def slugify(name) when is_binary(name) do
    Slug.slugify(name)
  end

  def slugify(_), do: ""
end
