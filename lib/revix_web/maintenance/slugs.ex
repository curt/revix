defmodule RevixWeb.Maintenance.Slugs do
  import Ecto.Query

  alias Revix.Repo
  alias Revix.Places.Place

  def populate_slugs(:places) do
    Repo.all(
      from p in Place,
        where: p.origin == :local and is_nil(p.slug),
        select: %{
          id: p.id,
          name: p.name,
          slug: p.slug
        }
    )
    |> Enum.each(&process_place/1)
  end

  defp process_place(place) do
    new_slug = Place.slugify(place.name)

    IO.puts("PLACE #{place.id} NAME --> #{place.name} SLUG --> #{new_slug}")

    Repo.update_all(
      from(p in Place, where: p.id == ^place.id),
      set: [slug: new_slug]
    )
  end
end
