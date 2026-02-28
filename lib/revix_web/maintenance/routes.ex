defmodule RevixWeb.Maintenance.Routes do
  import Ecto.Query

  alias Revix.Repo
  alias Revix.Places.Place
  alias Revix.Entries.Entry
  alias Revix.Likes.Like
  alias Revix.EntryPeople.EntryPerson

  import RevixWeb.CanonicalRoutes

  def rebuild_canonical_routes(:places) do
    Repo.all(
      from p in Place,
        where: p.origin == :local,
        select: %{
          id: p.id,
          slug: p.slug,
          uri: p.uri,
          url: p.url
        }
    )
    |> Enum.each(&process_place/1)
  end

  def rebuild_canonical_routes(:checkins) do
    Repo.all(
      from e in Entry,
        join: p in assoc(e, :place),
        where: e.origin == :local and e.type == :checkin,
        select: %{
          id: e.id,
          place: %{slug: p.slug},
          uri: e.uri,
          url: e.url
        }
    )
    |> Enum.each(&process_checkin/1)
  end

  defp process_place(place) do
    new_uri = place_uri(place)
    new_url = place_url(place)

    IO.puts("PLACE #{place.id} URI --> #{place.uri} --> #{new_uri}")
    IO.puts("PLACE #{place.id} URL --> #{place.url} --> #{new_url}")

    Repo.update_all(
      from(p in Place, where: p.id == ^place.id),
      set: [uri: new_uri, url: new_url]
    )

    process_place_entries(place.uri, new_uri)
  end

  defp process_place_entries(uri, new_uri) do
    Repo.all(
      from e in Entry,
        where: e.origin == :local and e.type == :checkin and e.place_uri == ^uri
    )
    |> Enum.each(fn x -> process_place_entry(x, new_uri) end)
  end

  defp process_place_entry(entry, new_uri) do
    IO.puts("CHECKIN #{entry.id} PLACE URI --> #{entry.place_uri} --> #{new_uri}")

    Repo.update_all(
      from(e in Entry, where: e.id == ^entry.id),
      set: [place_uri: new_uri]
    )
  end

  defp process_checkin(checkin) do
    new_uri = checkin_uri(checkin)
    new_url = checkin_url(checkin)

    IO.puts("CHECKIN #{checkin.id} URI --> #{checkin.uri} --> #{new_uri}")
    IO.puts("CHECKIN #{checkin.id} URL --> #{checkin.url} --> #{new_url}")

    Repo.update_all(
      from(e in Entry, where: e.id == ^checkin.id),
      set: [uri: new_uri, url: new_url]
    )

    process_checkin_replies(checkin.uri, new_uri)
    process_checkin_likes(checkin.uri, new_uri)
    process_checkin_companions(checkin.uri, new_uri)
  end

  defp process_checkin_replies(uri, new_uri) do
    Repo.all(
      from e in Entry,
        where: e.origin == :local and e.in_reply_to_uri == ^uri
    )
    |> Enum.each(fn x -> process_checkin_reply(x, new_uri) end)
  end

  defp process_checkin_reply(reply, new_uri) do
    IO.puts("REPLY #{reply.id} IN REPLY TO URI --> #{reply.in_reply_to_uri} --> #{new_uri}")

    Repo.update_all(
      from(e in Entry, where: e.id == ^reply.id),
      set: [in_reply_to_uri: new_uri]
    )
  end

  defp process_checkin_likes(uri, new_uri) do
    Repo.all(
      from l in Like,
        where: l.origin == :local and l.object_uri == ^uri
    )
    |> Enum.each(fn x -> process_checkin_like(x, new_uri) end)
  end

  defp process_checkin_like(like, new_uri) do
    IO.puts("LIKE #{like.id} OBJECT URI --> #{like.object_uri} --> #{new_uri}")

    Repo.update_all(
      from(l in Like, where: l.id == ^like.id),
      set: [object_uri: new_uri]
    )
  end

  defp process_checkin_companions(uri, new_uri) do
    Repo.all(
      from ep in EntryPerson,
        where: ep.entry_uri == ^uri
    )
    |> Enum.each(fn x -> process_checkin_companion(x, new_uri) end)
  end

  defp process_checkin_companion(companion, new_uri) do
    IO.puts("COMPANION #{companion.id} ENTRY URI --> #{companion.entry_uri} --> #{new_uri}")

    Repo.update_all(
      from(ep in EntryPerson, where: ep.id == ^companion.id),
      set: [entry_uri: new_uri]
    )
  end
end
