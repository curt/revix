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

  def slugify(name) when is_binary(name) do
    Slug.slugify(name)
  end

  def slugify(_), do: ""
end
