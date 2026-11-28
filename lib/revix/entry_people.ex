defmodule Revix.EntryPeople do
  import Ecto.Query
  alias Revix.Repo
  alias Revix.EntryPeople.EntryPerson
  alias Revix.Entries.Entry
  alias Revix.People.Scope

  @doc """
  The companions to store for a new entry by `author_uri`: each person once, in
  the order given, and never the author. `add_companion/3` enforces the same
  rules one at a time on existing entries.
  """
  def companion_uris(author_uri, person_uris) do
    person_uris
    |> Enum.uniq()
    |> Enum.reject(&(&1 == author_uri))
  end

  @doc """
  Adds a companion to an entry on behalf of the authenticated person (the entry author).

  - Returns {:error, :not_authorized} if the scope person is not the entry author.
  - Returns {:error, :self_companion} if the person_uri matches the scope person's own URI.
  - Returns {:ok, entry_person} if the companion was added.
  - Idempotent: if the companion already exists, returns {:ok, existing}.
  """
  def add_companion(%Scope{person: %{uri: person_uri}}, entry_uri, person_uri)
      when is_binary(entry_uri) and is_binary(person_uri),
      do: {:error, :self_companion}

  def add_companion(%Scope{person: %{uri: author_uri}}, entry_uri, person_uri)
      when is_binary(entry_uri) and is_binary(person_uri) do
    author_uri
    |> author_of?(entry_uri)
    |> add_as_author(entry_uri, person_uri)
  end

  defp add_as_author(false, _entry_uri, _person_uri), do: {:error, :not_authorized}

  defp add_as_author(true, entry_uri, person_uri) do
    entry_uri
    |> get_entry_person(person_uri)
    |> insert_unless_present(entry_uri, person_uri)
  end

  defp insert_unless_present(%EntryPerson{} = ep, _entry_uri, _person_uri), do: {:ok, ep}

  defp insert_unless_present(nil, entry_uri, person_uri) do
    %EntryPerson{}
    |> EntryPerson.create_changeset(%{
      entry_uri: entry_uri,
      person_uri: person_uri,
      type: :companion,
      origin: :local
    })
    |> Repo.insert()
    |> tap_ok(fn ep -> notifications().notify_companion_tag(ep) end)
  end

  @doc """
  Removes a companion from an entry on behalf of the authenticated person (the entry author).

  - Returns {:error, :not_authorized} if the scope person is not the entry author.
  - Returns {:error, :not_found} if no such companion association exists.
  - Returns {:ok, entry_person} on successful hard delete.
  """
  def remove_companion(%Scope{person: %{uri: author_uri}}, entry_uri, person_uri)
      when is_binary(entry_uri) and is_binary(person_uri) do
    author_uri
    |> author_of?(entry_uri)
    |> remove_as_author(entry_uri, person_uri)
  end

  defp remove_as_author(false, _entry_uri, _person_uri), do: {:error, :not_authorized}

  defp remove_as_author(true, entry_uri, person_uri) do
    entry_uri
    |> get_entry_person(person_uri)
    |> delete_if_present(entry_uri, person_uri)
  end

  defp delete_if_present(nil, _entry_uri, _person_uri), do: {:error, :not_found}

  defp delete_if_present(%EntryPerson{} = ep, entry_uri, person_uri) do
    ep
    |> Repo.delete()
    |> tap_ok(fn _ -> notifications().retract_companion_tag(entry_uri, person_uri) end)
  end

  @doc """
  Returns all companions for a given entry URI, with the person preloaded.
  """
  def get_companions_for_entry(entry_uri) do
    Repo.all(
      from ep in EntryPerson,
        where: ep.entry_uri == ^entry_uri and ep.type == ^:companion,
        order_by: [asc: ep.inserted_at],
        preload: [:person]
    )
  end

  @doc """
  Returns true if the given person_uri is a companion of the entry.
  Returns false if person_uri is nil.
  """
  def companion_of?(nil, _entry_uri), do: false

  def companion_of?(person_uri, entry_uri) do
    Repo.exists?(
      from ep in EntryPerson,
        where:
          ep.entry_uri == ^entry_uri and ep.person_uri == ^person_uri and
            ep.type == ^:companion
    )
  end

  @doc """
  Returns a map of %{entry_uri => count} for companions, given a list of entry URIs.
  URIs with zero companions are not included in the map.
  """
  def count_companions_by_entry_uris([]), do: %{}

  def count_companions_by_entry_uris(uris) do
    Repo.all(
      from ep in EntryPerson,
        where: ep.entry_uri in ^uris and ep.type == ^:companion,
        group_by: ep.entry_uri,
        select: {ep.entry_uri, count()}
    )
    |> Map.new()
  end

  # Private helpers

  defp get_entry_person(entry_uri, person_uri) do
    Repo.one(
      from ep in EntryPerson,
        where:
          ep.entry_uri == ^entry_uri and ep.person_uri == ^person_uri and
            ep.type == ^:companion
    )
  end

  defp author_of?(author_uri, entry_uri) do
    Repo.exists?(from e in Entry, where: e.uri == ^entry_uri and e.author_uri == ^author_uri)
  end

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(result, _fun), do: result

  defp notifications, do: Application.get_env(:revix, :notifications_impl, Revix.Notifications)
end
