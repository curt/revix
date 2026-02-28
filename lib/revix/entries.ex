defmodule Revix.Entries do
  import Ecto.Query
  import Geo.PostGIS
  alias Revix.Repo
  alias Revix.Entries.Entry
  alias Revix.Media.EntryImage
  alias Revix.People.Person
  alias Revix.Places.Place

  def get_local_checkins() do
    Entry
    |> local_checkins()
    |> order_by_recency()
    |> with_checkin_preloads()
    |> Repo.all()
  end

  def get_recent_checkins(limit \\ 50) do
    Entry
    |> local_checkins()
    |> order_by_recency()
    |> maybe_limit(limit)
    |> with_checkin_preloads()
    |> Repo.all()
  end

  def get_recent_checkins_for_person(%Person{} = person, opts \\ []) do
    Entry
    |> local_checkins()
    |> where([e], e.author_uri == ^person.uri)
    |> order_by_recency()
    |> maybe_limit(Keyword.get(opts, :limit, 50))
    |> with_checkin_preloads()
    |> Repo.all()
  end

  def get_local_checkins_for_place(%Place{} = place) do
    Entry
    |> local_checkins()
    |> where([e], e.place_uri == ^place.uri)
    |> order_by_recency()
    |> with_checkin_preloads()
    |> Repo.all()
  end

  def get_local_checkin(id) do
    Entry
    |> local_checkins()
    |> where([e], e.id == ^id)
    |> with_checkin_preloads()
    |> Repo.one()
    |> entry_ok_or_not_found()
  end

  def change_checkin(attrs \\ %{}) do
    Entry.checkin_changeset(%Entry{}, attrs)
  end

  def change_checkin_for_update(%Entry{} = entry) do
    Entry.update_checkin_changeset(entry, %{})
  end

  def change_checkin_for_update(%Entry{} = entry, attrs) do
    Entry.update_checkin_changeset(entry, attrs)
  end

  def update_local_checkin(%Entry{} = entry, attrs) do
    entry
    |> Entry.update_checkin_changeset(attrs)
    |> Repo.update()
  end

  def create_local_checkin(scope, %Place{} = place, attrs, uri_fn, url_fn) do
    id = Revix.Ecto.Base58Id.autogenerate()

    %Entry{
      id: id,
      type: :checkin,
      origin: :local,
      uri: uri_fn.(id),
      url: url_fn.(id, place.slug),
      author_uri: scope.person.uri,
      place_uri: place.uri
    }
    |> Entry.checkin_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a local checkin and, within the same transaction, inserts EntryPerson
  records for each URI in `companion_uris`.

  The LiveView is responsible for deduplication and ensuring no self-companions
  are present before calling this function.
  """
  def create_local_checkin_with_companions(scope, place, attrs, uri_fn, url_fn, companion_uris) do
    Repo.transaction(fn ->
      case create_local_checkin(scope, place, attrs, uri_fn, url_fn) do
        {:ok, checkin} ->
          Enum.each(companion_uris, fn person_uri ->
            %Revix.EntryPeople.EntryPerson{}
            |> Revix.EntryPeople.EntryPerson.create_changeset(%{
              entry_uri: checkin.uri,
              person_uri: person_uri,
              type: :companion,
              origin: :local
            })
            |> Repo.insert!()
          end)

          checkin

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def get_entry_by_uri(uri) do
    entry_ok_or_not_found(Repo.one(from e in Entry, where: e.uri == ^uri))
  end

  def create_comment(scope, checkin, attrs, uri_fn, url_fn) do
    id = Revix.Ecto.Base58Id.autogenerate()
    max_length = comment_max_length(scope)

    %Entry{
      id: id,
      type: :note,
      origin: :local,
      uri: uri_fn.(id),
      url: url_fn.(id),
      author_uri: scope.person.uri,
      in_reply_to_uri: checkin.uri,
      context: checkin.context
    }
    |> Entry.comment_changeset(attrs)
    |> then(fn cs ->
      if max_length,
        do: Ecto.Changeset.validate_length(cs, :content, max: max_length),
        else: cs
    end)
    |> Repo.insert()
  end

  def comment_max_length(%{role: :owner}), do: nil

  def comment_max_length(_scope),
    do: Application.get_env(:revix, :entry)[:comment_max_length] || 2000

  def get_comments_for_entry(object_uri) do
    Repo.all(
      from e in Entry,
        where: e.in_reply_to_uri == ^object_uri and e.type == :note and e.origin == :local,
        order_by: [asc: e.published_at_utc],
        preload: [:author]
    )
  end

  def get_comment(id) do
    entry_ok_or_not_found(Repo.one(from e in Entry, where: e.id == ^id and e.type == :note))
  end

  def change_comment_for_update(%Entry{} = entry) do
    Entry.update_comment_changeset(entry, %{})
  end

  def update_comment(%Entry{} = entry, attrs) do
    entry
    |> Entry.update_comment_changeset(attrs)
    |> Repo.update()
  end

  def delete_comment(%Entry{} = entry) do
    Repo.delete(entry)
  end

  def get_recent_comments(limit \\ 50) do
    Entry
    |> local_comments()
    |> order_by_published()
    |> maybe_limit(limit)
    |> with_comment_preloads()
    |> Repo.all()
  end

  def get_recent_comments_for_person(%Person{} = person, opts \\ []) do
    Entry
    |> local_comments()
    |> where([e], e.author_uri == ^person.uri)
    |> order_by_published()
    |> maybe_limit(Keyword.get(opts, :limit, 50))
    |> with_comment_preloads()
    |> Repo.all()
  end

  @doc """
  Backfills the timezone and local datetimes for checkins within a given radius
  whose timezone is currently "Etc/UTC". Intended for one-off admin use from IEx.

  Source can be a `%Place{}` (uses its coordinates) or a `{lat, lon}` tuple.
  Radius defaults to 20,000 metres (20 km).

  Returns `{:ok, updated_count}` or `{:error, :invalid_timezone}`.

  ## Examples

      iex> Revix.Entries.backfill_timezone(place, "America/New_York")
      {:ok, 5}

      iex> Revix.Entries.backfill_timezone({40.7128, -74.0060}, "America/New_York", radius: 10_000)
      {:ok, 3}
  """
  def backfill_timezone(source, timezone, opts \\ []) do
    if timezone not in Tzdata.zone_list() do
      {:error, :invalid_timezone}
    else
      radius = Keyword.get(opts, :radius, 20_000)
      center = resolve_center(source)

      entries =
        Repo.all(
          from e in Entry,
            join: p in Place,
            on: e.place_uri == p.uri,
            where: e.type == :checkin,
            where: e.origin == :local,
            where: e.starts_tz == "Etc/UTC",
            where: st_dwithin_in_meters(p.coordinates, ^center, ^radius)
        )

      Repo.transaction(fn ->
        Enum.reduce(entries, 0, fn entry, count ->
          fields = backfill_fields(entry, timezone)
          entry |> Ecto.Changeset.change(fields) |> Repo.update!()
          count + 1
        end)
      end)
    end
  end

  defp resolve_center(%Place{coordinates: coords}), do: coords

  defp resolve_center({lat, lon}),
    do: %Geo.Point{coordinates: {lon, lat}, srid: 4326}

  defp backfill_fields(entry, timezone) do
    %{starts_tz: timezone, published_tz: timezone}
    |> maybe_put_starts_local(entry, timezone)
    |> maybe_put_published_local(entry, timezone)
    |> maybe_put_ends_local(entry, timezone)
  end

  defp maybe_put_starts_local(fields, %{starts_at_utc: nil}, _tz), do: fields

  defp maybe_put_starts_local(fields, entry, tz) do
    Map.put(
      fields,
      :starts_at_local,
      entry.starts_at_utc |> DateTime.shift_zone!(tz) |> DateTime.to_naive()
    )
  end

  defp maybe_put_published_local(fields, %{published_at_utc: nil}, _tz), do: fields

  defp maybe_put_published_local(fields, entry, tz) do
    Map.put(
      fields,
      :published_at_local,
      entry.published_at_utc |> DateTime.shift_zone!(tz) |> DateTime.to_naive()
    )
  end

  defp maybe_put_ends_local(fields, %{ends_at_utc: nil}, _tz), do: fields

  defp maybe_put_ends_local(fields, entry, tz) do
    fields
    |> Map.put(
      :ends_at_local,
      entry.ends_at_utc |> DateTime.shift_zone!(tz) |> DateTime.to_naive()
    )
    |> Map.put(:ends_tz, tz)
  end

  defp maybe_limit(query, limit) when is_integer(limit), do: limit(query, ^limit)

  defp maybe_limit(query, _limit), do: query

  defp local_checkins(query) do
    where(query, [e], e.origin == :local and e.type == :checkin)
  end

  defp local_comments(query) do
    where(query, [e], e.type == :note and e.origin == :local)
  end

  defp order_by_recency(query) do
    order_by(query, [e], desc: e.starts_at_utc)
  end

  defp order_by_published(query) do
    order_by(query, [e], desc: e.published_at_utc)
  end

  defp with_checkin_preloads(query) do
    preloads = [
      :author,
      :place,
      companions: [:person],
      entry_images: ordered_entry_images_query()
    ]

    preload(query, ^preloads)
  end

  defp with_comment_preloads(query) do
    preload(query, [:author, in_reply_to: :place])
  end

  defp ordered_entry_images_query do
    from(ei in EntryImage, order_by: [asc: ei.position], preload: [:image])
  end

  defp entry_ok_or_not_found(%Entry{} = entry), do: {:ok, entry}

  defp entry_ok_or_not_found(nil), do: {:error, :not_found}
end
