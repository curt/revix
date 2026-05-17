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

  def get_local_posts_for_place(%Place{} = place) do
    Entry
    |> local_posts()
    |> join(:inner, [e], ep in Revix.EntryPlaces.EntryPlace, on: ep.entry_uri == e.uri)
    |> where([e, ep], ep.place_uri == ^place.uri)
    |> order_by_published()
    |> with_post_preloads()
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

  def change_checkin(role, attrs \\ %{}) do
    Entry.checkin_changeset(%Entry{}, attrs, role)
  end

  def change_checkin_for_update(%Entry{} = entry, role \\ :user) do
    Entry.update_checkin_changeset(entry, %{}, role)
  end

  def change_checkin_for_update(%Entry{} = entry, attrs, role) do
    Entry.update_checkin_changeset(entry, attrs, role)
  end

  def update_local_checkin(%Entry{} = entry, attrs, role \\ :user) do
    entry
    |> Entry.update_checkin_changeset(attrs, role)
    |> Repo.update()
    |> tap_ok(&enqueue_deliver_entry(&1, "Update"))
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
    |> Entry.checkin_changeset(attrs, scope.role)
    |> Repo.insert()
    |> tap_ok(&enqueue_deliver_entry(&1, "Create"))
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

  def get_recent_posts(limit \\ 50) do
    Entry
    |> local_posts()
    |> order_by_published()
    |> maybe_limit(limit)
    |> with_post_preloads()
    |> Repo.all()
  end

  def get_recent_posts_for_person(%Person{} = person, opts \\ []) do
    Entry
    |> local_posts()
    |> where([e], e.author_uri == ^person.uri)
    |> order_by_published()
    |> maybe_limit(Keyword.get(opts, :limit, 50))
    |> with_post_preloads()
    |> Repo.all()
  end

  def get_local_post(id) do
    Entry
    |> local_posts()
    |> where([e], e.id == ^id)
    |> with_post_preloads()
    |> Repo.one()
    |> entry_ok_or_not_found()
  end

  def change_post(role, attrs \\ %{}) do
    Entry.post_changeset(%Entry{}, attrs, role)
  end

  def change_post_for_update(%Entry{} = entry, role \\ :user) do
    Entry.update_post_changeset(entry, %{}, role)
  end

  def change_post_for_update(%Entry{} = entry, attrs, role) do
    Entry.update_post_changeset(entry, attrs, role)
  end

  def update_local_post(%Entry{} = entry, attrs, role, url_fn) do
    changeset = Entry.update_post_changeset(entry, attrs, role)

    post_pseudo = %{
      id: entry.id,
      published_at_local: Ecto.Changeset.get_field(changeset, :published_at_local),
      name: Ecto.Changeset.get_field(changeset, :name)
    }

    changeset
    |> Ecto.Changeset.put_change(:url, url_fn.(post_pseudo))
    |> Repo.update()
    |> tap_ok(&enqueue_deliver_entry(&1, "Update"))
  end

  def create_local_post(scope, attrs, uri_fn, url_fn) do
    id = Revix.Ecto.Base58Id.autogenerate()

    changeset =
      %Entry{
        id: id,
        type: :post,
        origin: :local,
        uri: uri_fn.(id),
        url: url_fn.(%{id: id}),
        author_uri: scope.person.uri
      }
      |> Entry.post_changeset(attrs, scope.role)

    post_pseudo = %{
      id: id,
      published_at_local: Ecto.Changeset.get_field(changeset, :published_at_local),
      name: Ecto.Changeset.get_field(changeset, :name)
    }

    changeset
    |> Ecto.Changeset.put_change(:url, url_fn.(post_pseudo))
    |> Repo.insert()
    |> tap_ok(&enqueue_deliver_entry(&1, "Create"))
  end

  def create_local_post_with_companions(
        scope,
        attrs,
        uri_fn,
        url_fn,
        companion_uris,
        place_uris \\ []
      ) do
    Repo.transaction(fn ->
      case create_local_post(scope, attrs, uri_fn, url_fn) do
        {:ok, post} ->
          Enum.each(companion_uris, fn person_uri ->
            %Revix.EntryPeople.EntryPerson{}
            |> Revix.EntryPeople.EntryPerson.create_changeset(%{
              entry_uri: post.uri,
              person_uri: person_uri,
              type: :companion,
              origin: :local
            })
            |> Repo.insert!()
          end)

          Enum.each(place_uris, fn place_uri ->
            %Revix.EntryPlaces.EntryPlace{}
            |> Revix.EntryPlaces.EntryPlace.create_changeset(%{
              entry_uri: post.uri,
              place_uri: place_uri
            })
            |> Repo.insert!()
          end)

          post

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def get_entry_by_uri(uri) do
    Entry
    |> where([e], e.uri == ^uri)
    |> Repo.one()
    |> entry_ok_or_not_found()
  end

  def get_entry_context_uri(object_uri) do
    case Repo.get_by(Entry, uri: object_uri) do
      %Entry{context: context} when is_binary(context) -> context
      %Entry{uri: uri} -> uri
      nil -> nil
    end
  end

  def subscribe_to_context(context_uri) do
    Phoenix.PubSub.subscribe(Revix.PubSub, "context:#{context_uri}")
  end

  def create_comment(scope, checkin, attrs, uri_fn, url_fn) do
    id = Revix.Ecto.Base58Id.autogenerate()
    max_length = comment_max_length(scope)

    result =
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

    with {:ok, comment} <- result do
      comment = Repo.preload(comment, :author)
      broadcast_context(checkin.context, {:comment_created, comment})
      enqueue_deliver_entry(comment, "Create")
      {:ok, comment}
    end
  end

  def create_reply(scope, parent_comment, attrs, uri_fn, url_fn) do
    id = Revix.Ecto.Base58Id.autogenerate()
    max_length = comment_max_length(scope)
    context_uri = parent_comment.context || parent_comment.in_reply_to_uri

    result =
      %Entry{
        id: id,
        type: :note,
        origin: :local,
        uri: uri_fn.(id),
        url: url_fn.(id),
        author_uri: scope.person.uri,
        in_reply_to_uri: parent_comment.uri,
        context: context_uri
      }
      |> Entry.comment_changeset(attrs)
      |> then(fn cs ->
        if max_length,
          do: Ecto.Changeset.validate_length(cs, :content, max: max_length),
          else: cs
      end)
      |> Repo.insert()

    with {:ok, reply} <- result do
      reply = Repo.preload(reply, :author)
      broadcast_context(context_uri, {:comment_created, reply})
      enqueue_deliver_entry(reply, "Create")
      {:ok, reply}
    end
  end

  def create_inbound_note(attrs) do
    %Entry{type: :note, origin: :remote}
    |> Entry.inbound_note_changeset(attrs)
    |> Repo.insert()
  end

  def create_inbound_checkin(attrs) do
    %Entry{type: :checkin, origin: :remote}
    |> Entry.inbound_note_changeset(attrs)
    |> Repo.insert()
  end

  def update_inbound_note(uri, attrs) when is_binary(uri) do
    case get_entry_by_uri(uri) do
      {:ok, %Entry{origin: :remote} = entry} ->
        entry
        |> Entry.inbound_note_changeset(attrs)
        |> Repo.update()
        |> tap_ok(&broadcast_context(&1.context, {:comment_updated, &1}))

      {:error, :not_found} ->
        create_inbound_note(attrs)
        |> tap_ok(&broadcast_context(&1.context, {:comment_created, &1}))

      {:ok, %Entry{origin: :local}} ->
        {:error, :not_remote}
    end
  end

  def delete_inbound_note(uri, actor_uri) when is_binary(uri) and is_binary(actor_uri) do
    case get_entry_by_uri(uri) do
      {:ok, %Entry{origin: :remote, author_uri: ^actor_uri} = entry} ->
        result = Repo.delete(entry)

        with {:ok, deleted} <- result do
          broadcast_context(deleted.context, {:comment_deleted, deleted.id})
          {:ok, deleted}
        end

      {:error, :not_found} ->
        :ok

      _ ->
        :ok
    end
  end

  def comment_max_length(%{role: :owner}), do: nil

  def comment_max_length(_scope),
    do: Application.get_env(:revix, :entry)[:comment_max_length] || 2000

  def get_comment_tree(%Entry{uri: checkin_uri, context: context_uri}) do
    all =
      Repo.all(
        from e in Entry,
          where:
            e.type == :note and
              (e.context == ^context_uri or e.context == ^checkin_uri or
                 e.in_reply_to_uri == ^checkin_uri),
          order_by: [asc: e.published_at_utc],
          preload: [:author, in_reply_to: :author]
      )

    by_parent = Enum.group_by(all, & &1.in_reply_to_uri)
    top_level = Map.get(by_parent, checkin_uri, [])

    Enum.map(top_level, fn comment ->
      direct_replies = Map.get(by_parent, comment.uri, [])
      replies = Enum.flat_map(direct_replies, &[&1 | collect_descendants(&1, by_parent)])
      {comment, replies}
    end)
  end

  defp collect_descendants(entry, by_parent) do
    children = Map.get(by_parent, entry.uri, [])
    children ++ Enum.flat_map(children, &collect_descendants(&1, by_parent))
  end

  def get_comments_for_entry(object_uri) do
    Repo.all(
      from e in Entry,
        where: e.in_reply_to_uri == ^object_uri and e.type == :note and e.origin == :local,
        order_by: [asc: e.published_at_utc],
        preload: [:author]
    )
  end

  def get_comment(id) do
    Entry
    |> where([e], e.id == ^id and e.type == :note)
    |> Repo.one()
    |> entry_ok_or_not_found()
  end

  def get_comment_with_author(id) do
    Entry
    |> where([e], e.id == ^id and e.type == :note)
    |> preload([:author, entry_images: ^ordered_entry_images_query()])
    |> Repo.one()
    |> entry_ok_or_not_found()
  end

  def change_comment_for_update(%Entry{} = entry) do
    Entry.update_comment_changeset(entry, %{})
  end

  def update_comment(%Entry{} = entry, attrs) do
    result =
      entry
      |> Entry.update_comment_changeset(attrs)
      |> Repo.update()

    with {:ok, updated} <- result do
      broadcast_context(updated.context, {:comment_updated, updated})
      enqueue_deliver_entry(updated, "Update")
      {:ok, updated}
    end
  end

  def delete_comment(%Entry{} = entry) do
    result = Repo.delete(entry)

    with {:ok, deleted} <- result do
      broadcast_context(deleted.context, {:comment_deleted, deleted.id})
      enqueue_deliver_entry(deleted, "Delete")
      {:ok, deleted}
    end
  end

  defp broadcast_context(context_uri, event) do
    Phoenix.PubSub.broadcast(Revix.PubSub, "context:#{context_uri}", event)
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

  defp local_posts(query) do
    where(query, [e], e.origin == :local and e.type == :post)
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
    preload(query, [:author, in_reply_to: [:author, :place]])
  end

  defp with_post_preloads(query) do
    preloads = [
      :author,
      companions: [:person],
      entry_places: [:place],
      entry_images: ordered_entry_images_query()
    ]

    preload(query, ^preloads)
  end

  defp ordered_entry_images_query do
    from(ei in EntryImage, order_by: [asc: ei.position], preload: [:image])
  end

  def checkin_display_content(%{content: content, content_html: html} = checkin)
      when is_binary(content) and content != "" do
    if String.trim(content) != "",
      do: html || content,
      else: checkin_display_content(%{checkin | content: nil})
  end

  def checkin_display_content(checkin) do
    place =
      get_in(checkin, [Access.key(:place), Access.key(:name)]) ||
        Map.get(checkin, :name) ||
        "somewhere"

    checkin_place_time_string(place, checkin_time_string(checkin))
  end

  defp checkin_time_string(%{starts_at_local: local, starts_tz: tz})
       when not is_nil(local) and not is_nil(tz) do
    formatted_time = local |> DateTime.from_naive!(tz) |> Calendar.strftime("%H:%M %Z")
    "#{Calendar.strftime(local, "%Y-%m-%d")} #{formatted_time}"
  end

  defp checkin_time_string(%{starts_at_utc: utc}) when not is_nil(utc) do
    Calendar.strftime(utc, "%Y-%m-%d %H:%M UTC")
  end

  defp checkin_time_string(_), do: nil

  defp checkin_place_time_string(place, nil), do: "Checked into #{place}."
  defp checkin_place_time_string(place, time), do: "Checked into #{place} #{time}."

  defp entry_ok_or_not_found(%Entry{} = entry), do: {:ok, entry}

  defp entry_ok_or_not_found(nil), do: {:error, :not_found}

  defp enqueue_deliver_entry(entry, type) do
    %{"entry_id" => entry.id, "activity_type" => type}
    |> Revix.Workers.DeliverEntryWorker.new()
    |> Oban.insert()
  end

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(result, _fun), do: result
end
