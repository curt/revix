defmodule Revix.MediaFixtures do
  alias Revix.Repo
  alias Revix.Media.Image
  alias Revix.Media.EntryImage

  def image_fixture(attrs \\ %{}) do
    id = Revix.Ecto.Base58Id.autogenerate()

    author_uri =
      if Map.has_key?(attrs, :author_uri) do
        attrs.author_uri
      else
        person = Revix.PeopleFixtures.person_fixture()
        person.uri
      end

    {:ok, image} =
      %Image{}
      |> Ecto.Changeset.change(
        Map.merge(
          %{
            id: id,
            file: %{file_name: "test.jpg", updated_at: ~U[2026-01-01 00:00:00Z]},
            author_uri: author_uri,
            content_type: "image/jpeg",
            original_filename: "test.jpg"
          },
          attrs
        )
      )
      |> Repo.insert()

    image
  end

  def entry_image_fixture(attrs) do
    id = Revix.Ecto.Base58Id.autogenerate()

    {:ok, entry_image} =
      %EntryImage{}
      |> Ecto.Changeset.change(
        Map.merge(
          %{
            id: id,
            position: 0
          },
          attrs
        )
      )
      |> Repo.insert()

    entry_image
  end
end
