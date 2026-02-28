defmodule Revix.PlacesFixtures do
  alias Revix.Repo
  alias Revix.Places.Place

  import RevixWeb.CanonicalRoutes

  def place_fixture(attrs \\ %{}) do
    id = Revix.Ecto.Base58Id.autogenerate()

    {:ok, place} =
      %Place{}
      |> Ecto.Changeset.change(
        Map.merge(
          %{
            id: id,
            uri: place_uri(id),
            url: place_url(id, attrs[:slug]),
            name: "Place #{id}",
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
