defmodule Revix.EntryPlaces do
  import Ecto.Query
  alias Revix.Repo
  alias Revix.EntryPlaces.EntryPlace

  def add_place(entry_uri, place_uri)
      when is_binary(entry_uri) and is_binary(place_uri) do
    case get_entry_place(entry_uri, place_uri) do
      nil ->
        %EntryPlace{}
        |> EntryPlace.create_changeset(%{entry_uri: entry_uri, place_uri: place_uri})
        |> Repo.insert()

      %EntryPlace{} = ep ->
        {:ok, ep}
    end
  end

  def remove_place(entry_uri, place_uri)
      when is_binary(entry_uri) and is_binary(place_uri) do
    case get_entry_place(entry_uri, place_uri) do
      nil -> {:error, :not_found}
      %EntryPlace{} = ep -> Repo.delete(ep)
    end
  end

  def get_places_for_entry(entry_uri) do
    Repo.all(
      from ep in EntryPlace,
        where: ep.entry_uri == ^entry_uri,
        order_by: [asc: ep.inserted_at],
        preload: [:place]
    )
  end

  def place_of?(place_uri, entry_uri) do
    Repo.exists?(
      from ep in EntryPlace,
        where: ep.entry_uri == ^entry_uri and ep.place_uri == ^place_uri
    )
  end

  defp get_entry_place(entry_uri, place_uri) do
    Repo.one(
      from ep in EntryPlace,
        where: ep.entry_uri == ^entry_uri and ep.place_uri == ^place_uri
    )
  end
end
