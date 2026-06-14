defmodule Revix.PlacesFixtures do
  alias Revix.Repo
  alias Revix.Places.Place

  import RevixWeb.CanonicalRoutes

  def place_fixture(attrs \\ %{}) do
    id = Revix.Ecto.Base58Id.autogenerate()
    default_name = "Place #{id}"
    name = attrs[:name] || attrs["name"] || default_name

    slug =
      cond do
        Map.has_key?(attrs, :slug) -> attrs[:slug]
        Map.has_key?(attrs, "slug") -> attrs["slug"]
        true -> Place.slugify(name)
      end

    {:ok, place} =
      %Place{}
      |> Ecto.Changeset.change(
        Map.merge(
          %{
            id: id,
            uri: place_uri(id),
            url: place_url(id, slug),
            name: default_name,
            slug: slug,
            origin: :local,
            coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
          },
          attrs
        )
      )
      |> Repo.insert()

    place
  end
end
