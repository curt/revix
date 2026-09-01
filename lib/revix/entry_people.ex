defmodule Revix.EntryPeople do
  import Ecto.Query
  alias Revix.Repo
  alias Revix.EntryPeople.EntryPerson
  alias Revix.Entries.Entry
  alias Revix.People.Scope

  @doc """
  Adds a companion to an entry on behalf of the authenticated person (the entry author).

  - Returns {:error, :not_authorized} if the scope person is not the entry author.
  - Returns {:error, :self_companion} if the person_uri matches the scope person's own URI.
  - Returns {:ok, entry_person} if the companion was added.
  - Idempotent: if the companion already exists, returns {:ok, existing}.
  """
  def add_companion(%Scope{} = scope, entry_uri, person_uri)
      when is_binary(entry_uri) and is_binary(person_uri) do
    author_uri = scope.person.uri

    cond do
      author_uri == person_uri ->
        {:error, :self_companion}

      not author_of?(author_uri, entry_uri) ->
        {:error, :not_authorized}

      true ->
        case get_entry_person(entry_uri, person_uri) do
          nil ->
            attrs = %{
              entry_uri: entry_uri,
              person_uri: person_uri,
              type: :companion,
              origin: :local
            }

            %EntryPerson{}
            |> EntryPerson.create_changeset(attrs)
            |> Repo.insert()
            |> tap_ok(fn ep -> notifications().notify_companion_tag(ep) end)

          %EntryPerson{} = ep ->
            {:ok, ep}
        end
    end
  end

  @doc """
  Removes a companion from an entry on behalf of the authenticated person (the entry author).

  - Returns {:error, :not_authorized} if the scope person is not the entry author.
  - Returns {:error, :not_found} if no such companion association exists.
  - Returns {:ok, entry_person} on successful hard delete.
  """
  def remove_companion(%Scope{} = scope, entry_uri, person_uri)
      when is_binary(entry_uri) and is_binary(person_uri) do
    author_uri = scope.person.uri

    if not author_of?(author_uri, entry_uri) do
      {:error, :not_authorized}
    else
      case get_entry_person(entry_uri, person_uri) do
        nil ->
          {:error, :not_found}

        %EntryPerson{} = ep ->
          ep
          |> Repo.delete()
          |> tap_ok(fn _ -> notifications().retract_companion_tag(entry_uri, person_uri) end)
      end
    end
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
