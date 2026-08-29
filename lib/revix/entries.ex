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
    |> published_checkins()
    |> order_by_recency()
    |> with_checkin_preloads()
    |> Repo.all()
  end

  def get_recent_checkins(limit \\ 50, opts \\ []) do
    Entry
    |> local_checkins()
    |> published_checkins()
    |> maybe_before_recency(Keyword.get(opts, :before))
    |> order_by_recency()
    |> maybe_limit(limit)
    |> with_checkin_preloads()
    |> Repo.all()
  end

  def get_recent_checkins_for_person(%Person{} = person, limit \\ 50, opts \\ []) do
    Entry
    |> local_checkins()
    |> published_checkins()
    |> where([e], e.author_uri == ^person.uri)
    |> maybe_before_recency(Keyword.get(opts, :before))
    |> order_by_recency()
    |> maybe_limit(limit)
    |> with_checkin_preloads()
    |> Repo.all()
  end

  def get_local_posts_for_place(%Place{} = place) do
    Entry
    |> local_posts()
    |> published_posts()
    |> join(:inner, [e], ep in Revix.EntryPlaces.EntryPlace, on: ep.entry_uri == e.uri)
    |> where([e, ep], ep.place_uri == ^place.uri)
    |> order_by_published()
    |> with_post_preloads()
    |> Repo.all()
  end

  def get_local_checkins_for_place(%Place{} = place) do
    Entry
    |> local_checkins()
    |> published_checkins()
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
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
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

  def update_local_checkin(%Entry{} = entry, attrs, role \\ :user, opts \\ []) do
    entry
    |> Entry.update_checkin_changeset(attrs, role)
    |> Repo.update()
    |> maybe_enqueue_delivery("Update", opts)
  end

  def create_local_checkin(scope, %Place{} = place, attrs, uri_fn, url_fn, opts \\ []) do
    mode = Keyword.get(opts, :mode, :publish)
    id = Revix.Ecto.Base58Id.autogenerate()

    entry = %Entry{
      id: id,
      type: :checkin,
      origin: :local,
      uri: uri_fn.(id),
      url: url_fn.(id, place.slug),
      author_uri: scope.person.uri,
      place_uri: place.uri
    }

    changeset =
      case mode do
        :draft -> Entry.draft_checkin_changeset(entry, attrs, scope.role)
        :publish -> Entry.checkin_changeset(entry, attrs, scope.role)
      end

    result = Repo.insert(changeset)

    if mode == :publish do
      result
      |> tap_ok(&broadcast_feed({:checkin_created, &1}))
      |> maybe_enqueue_delivery("Create", opts)
    else
      result
    end
  end

  @doc """
  Creates a local checkin and, within the same transaction, inserts EntryPerson
  records for each URI in `companion_uris`.

  The LiveView is responsible for deduplication and ensuring no self-companions
  are present before calling this function.
  """
  def create_local_checkin_with_companions(
        scope,
        place,
        attrs,
        uri_fn,
        url_fn,
        companion_uris,
        opts \\ []
      ) do
    Repo.transaction(fn ->
      case create_local_checkin(scope, place, attrs, uri_fn, url_fn, opts) do
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

  def get_recent_posts(limit \\ 50, opts \\ []) do
    Entry
    |> local_posts()
    |> published_posts()
    |> maybe_before_published(Keyword.get(opts, :before))
    |> order_by_published()
    |> maybe_limit(limit)
    |> with_post_preloads()
    |> Repo.all()
  end

  def get_recent_posts_for_person(%Person{} = person, limit \\ 50, opts \\ []) do
    Entry
    |> local_posts()
    |> published_posts()
    |> where([e], e.author_uri == ^person.uri)
    |> maybe_before_published(Keyword.get(opts, :before))
    |> order_by_published()
    |> maybe_limit(limit)
    |> with_post_preloads()
    |> Repo.all()
  end

  def get_draft_checkins_for_person(%Person{} = person, opts \\ []) do
    Entry
    |> local_checkins()
    |> draft_posts()
    |> where([e], e.author_uri == ^person.uri)
    |> order_by([e], desc: e.updated_at)
    |> maybe_limit(Keyword.get(opts, :limit, 50))
    |> with_checkin_preloads()
    |> Repo.all()
  end

  def get_draft_posts_for_person(%Person{} = person, opts \\ []) do
    Entry
    |> local_posts()
    |> draft_posts()
    |> where([e], e.author_uri == ^person.uri)
    |> order_by([e], desc: e.updated_at)
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
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def change_post(role, attrs \\ %{}) do
    Entry.draft_post_changeset(%Entry{}, attrs, role)
  end

  def change_post_for_update(%Entry{} = entry, role \\ :user) do
    Entry.update_post_changeset(entry, %{}, role)
  end

  def change_post_for_update(%Entry{} = entry, attrs, role) do
    Entry.update_post_changeset(entry, attrs, role)
  end

  def change_post_for_draft_update(%Entry{} = entry, attrs \\ %{}) do
    Entry.draft_post_changeset(entry, attrs, :user)
  end

  def update_draft_post(%Entry{} = entry, attrs) do
    entry
    |> Entry.draft_post_changeset(attrs, :user)
    |> Repo.update()
  end

  def update_local_post(%Entry{} = entry, attrs, role, url_fn, opts \\ []) do
    changeset = Entry.update_post_changeset(entry, attrs, role)

    post_pseudo = %{
      id: entry.id,
      published_at_local: Ecto.Changeset.get_field(changeset, :published_at_local),
      name: Ecto.Changeset.get_field(changeset, :name)
    }

    changeset
    |> Ecto.Changeset.put_change(:url, url_fn.(post_pseudo))
    |> Repo.update()
    |> maybe_enqueue_delivery("Update", opts)
  end

  def create_local_post(scope, attrs, uri_fn, url_fn, opts \\ []) do
    mode = Keyword.get(opts, :mode, :publish)
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
      |> build_create_post_changeset(attrs, scope.role, mode)

    post_pseudo = %{
      id: id,
      published_at_local: Ecto.Changeset.get_field(changeset, :published_at_local),
      name: Ecto.Changeset.get_field(changeset, :name)
    }

    changeset
    |> Ecto.Changeset.put_change(:url, url_fn.(post_pseudo))
    |> Repo.insert()
    |> maybe_enqueue_post_delivery(mode, opts)
  end

  defp build_create_post_changeset(entry, attrs, role, :draft),
    do: Entry.draft_post_changeset(entry, attrs, role)

  defp build_create_post_changeset(entry, attrs, role, :publish),
    do: Entry.publish_post_changeset(entry, attrs, role)

  defp maybe_enqueue_post_delivery({:ok, post} = result, :publish, opts) do
    broadcast_feed({:post_created, post})
    maybe_enqueue_create(post, opts)
    result
  end

  defp maybe_enqueue_post_delivery(result, _mode, _opts), do: result

  def publish_local_post(%Entry{} = entry, attrs, role, url_fn, opts \\ []) do
    changeset = Entry.publish_draft_post_changeset(entry, attrs, role)

    post_pseudo = %{
      id: entry.id,
      published_at_local: Ecto.Changeset.get_field(changeset, :published_at_local),
      name: Ecto.Changeset.get_field(changeset, :name)
    }

    changeset
    |> Ecto.Changeset.put_change(:url, url_fn.(post_pseudo))
    |> Repo.update()
    |> maybe_enqueue_delivery("Create", opts)
  end

  def create_local_post_with_companions(
        scope,
        attrs,
        uri_fn,
        url_fn,
        companion_uris,
        place_uris \\ [],
        opts \\ []
      ) do
    Repo.transaction(fn ->
      case create_local_post(scope, attrs, uri_fn, url_fn, opts) do
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

  def get_entry_by_uri_with_place(uri) do
    Entry
    |> where([e], e.uri == ^uri)
    |> preload([:place])
    |> Repo.one()
    |> entry_ok_or_not_found()
  end

  def get_entries_by_uris(uris) when is_list(uris) do
    uris =
      uris
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    case uris do
      [] ->
        []

      _ ->
        Entry
        |> where([e], e.uri in ^uris)
        |> preload([:place])
        |> Repo.all()
    end
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
      broadcast_feed({:comment_created, comment})
      enqueue_deliver_entry(comment, "Create")
      notifications().notify_reply(comment)
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
      broadcast_feed({:comment_created, reply})
      enqueue_deliver_entry(reply, "Create")
      notifications().notify_reply(reply)
      {:ok, reply}
    end
  end

  def create_inbound_note(attrs) do
    %Entry{type: :note, origin: :remote}
    |> Entry.inbound_note_changeset(attrs)
    |> Repo.insert()
    |> tap_ok(fn note -> notifications().notify_reply(note) end)
  end

  def create_inbound_checkin(attrs) do
    %Entry{type: :checkin, origin: :remote}
    |> Entry.inbound_note_changeset(attrs)
    |> Repo.insert()
  end

  def update_inbound_note(uri, actor_uri, attrs) when is_binary(uri) and is_binary(actor_uri) do
    case get_entry_by_uri(uri) do
      {:ok, %Entry{origin: :remote, author_uri: ^actor_uri} = entry} ->
        entry
        |> Entry.inbound_note_changeset(attrs)
        |> Repo.update()
        |> tap_ok(&broadcast_context(&1.context, {:comment_updated, &1}))

      {:ok, %Entry{origin: :remote}} ->
        {:error, :not_owner}

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
    Repo.all(
      from e in Entry,
        where:
          e.type == :note and
            (e.context == ^context_uri or e.context == ^checkin_uri or
               e.in_reply_to_uri == ^checkin_uri),
        order_by: [asc: e.published_at_utc],
        preload: [:author, in_reply_to: :author, entry_images: ^ordered_entry_images_query()]
    )
  end

  def get_comments_for_entry(object_uri) do
    Repo.all(
      from e in Entry,
        where: e.in_reply_to_uri == ^object_uri and e.type == :note and e.origin == :local,
        order_by: [asc: e.published_at_utc],
        preload: [:author]
    )
  end

  def get_entry(id) do
    Entry
    |> where([e], e.id == ^id)
    |> Repo.one()
    |> entry_ok_or_not_found()
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def get_comment(id) do
    Entry
    |> where([e], e.id == ^id and e.type == :note)
    |> Repo.one()
    |> entry_ok_or_not_found()
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def get_comment_with_author(id) do
    Entry
    |> where([e], e.id == ^id and e.type == :note)
    |> preload([:author, entry_images: ^ordered_entry_images_query()])
    |> Repo.one()
    |> entry_ok_or_not_found()
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def get_comment_for_feed(id) do
    Entry
    |> where([e], e.id == ^id and e.type == :note)
    |> with_comment_preloads()
    |> Repo.one()
    |> entry_ok_or_not_found()
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
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

  def publish_local_checkin(%Entry{} = entry, opts \\ []) do
    entry
    |> Entry.publish_checkin_changeset()
    |> Repo.update()
    |> tap_ok(&broadcast_feed({:checkin_created, &1}))
    |> maybe_enqueue_delivery("Create", opts)
  end

  def delete_entry(%Entry{} = entry) do
    entry = Repo.preload(entry, entry_images: [:image])

    Enum.each(entry.entry_images, fn ei ->
      Revix.Media.remove_image_from_entry(entry.id, ei.image_id)
    end)

    Repo.delete_all(from(ep in Revix.EntryPeople.EntryPerson, where: ep.entry_uri == ^entry.uri))

    result = Repo.delete(entry)

    with {:ok, deleted} <- result do
      if not is_nil(deleted.published_at_utc) do
        enqueue_deliver_entry(deleted, "Delete")
      end

      {:ok, deleted}
    end
  end

  def tombstone_entry(%Entry{type: :note} = entry), do: do_tombstone_entry(entry)

  def tombstone_entry(%Entry{published_at_utc: nil}), do: {:error, :not_published}

  def tombstone_entry(%Entry{} = entry), do: do_tombstone_entry(entry)

  defp do_tombstone_entry(%Entry{} = entry) do
    result =
      entry
      |> Entry.tombstone_changeset()
      |> Repo.update()

    with {:ok, tombstoned} <- result do
      broadcast_context(tombstoned.context, {:comment_tombstoned, tombstoned.id})
      enqueue_deliver_entry(tombstoned, "Delete")
      {:ok, tombstoned}
    end
  end

  defp broadcast_context(context_uri, event) do
    Phoenix.PubSub.broadcast(Revix.PubSub, "context:#{context_uri}", event)
  end

  defp broadcast_feed(event) do
    Phoenix.PubSub.broadcast(Revix.PubSub, "feed", event)
  end

  def subscribe_to_feed do
    Phoenix.PubSub.subscribe(Revix.PubSub, "feed")
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

  def get_recent_comments_for_feed(limit \\ 50, opts \\ []) do
    include_replies = Keyword.get(opts, :include_replies, false)

    Entry
    |> local_comments()
    |> maybe_exclude_replies(include_replies)
    |> maybe_before_published(Keyword.get(opts, :before))
    |> order_by_published()
    |> maybe_limit(limit)
    |> with_comment_preloads()
    |> Repo.all()
  end

  def get_recent_comments_for_person_feed(%Person{} = person, limit \\ 50, opts \\ []) do
    include_replies = Keyword.get(opts, :include_replies, false)

    Entry
    |> local_comments()
    |> where([e], e.author_uri == ^person.uri)
    |> maybe_exclude_replies(include_replies)
    |> maybe_before_published(Keyword.get(opts, :before))
    |> order_by_published()
    |> maybe_limit(limit)
    |> with_comment_preloads()
    |> Repo.all()
  end

  defp maybe_exclude_replies(query, true), do: query

  defp maybe_exclude_replies(query, false) do
    join(query, :left, [e], parent in Entry, on: parent.uri == e.in_reply_to_uri)
    |> where([e, parent], is_nil(parent.id) or parent.type != :note)
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

  defp maybe_before_recency(query, %DateTime{} = before),
    do: where(query, [e], e.starts_at_utc < ^before)

  defp maybe_before_recency(query, _before), do: query

  defp maybe_before_published(query, %DateTime{} = before),
    do: where(query, [e], e.published_at_utc < ^before)

  defp maybe_before_published(query, _before), do: query

  defp local_checkins(query) do
    where(query, [e], e.origin == :local and e.type == :checkin)
  end

  defp local_comments(query) do
    where(query, [e], e.type == :note and e.origin == :local and is_nil(e.tombstoned_at))
  end

  defp local_posts(query) do
    where(query, [e], e.origin == :local and e.type == :post)
  end

  defp published_posts(query) do
    where(query, [e], not is_nil(e.published_at_utc) and is_nil(e.tombstoned_at))
  end

  defp published_checkins(query) do
    where(query, [e], not is_nil(e.published_at_utc) and is_nil(e.tombstoned_at))
  end

  defp draft_posts(query), do: where(query, [e], is_nil(e.published_at_utc))

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
    preload(query, [:author, in_reply_to: [:author, :place, in_reply_to: [:author, :place]]])
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
    from(ei in EntryImage, order_by: [asc: ei.position], preload: [image: :dimensions])
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

  # Single chokepoint for outbound federation delivery. Every publish path lands
  # here exactly once (LiveView flows call it after their transaction commits via
  # `enqueue_delivery/2`; simpler flows via `maybe_enqueue_create/3`), so the
  # subscriber-notification trigger lives here too.
  defp enqueue_deliver_entry(entry, type) do
    %{"entry_id" => entry.id, "activity_type" => type}
    |> Revix.Workers.DeliverEntryWorker.new()
    |> Oban.insert()

    maybe_notify_new_entry(entry, type)
  end

  def enqueue_delivery(%Entry{} = entry, type), do: enqueue_deliver_entry(entry, type)

  defp maybe_enqueue_delivery({:ok, entry} = result, type, opts) do
    maybe_enqueue_create(entry, opts, type)
    result
  end

  defp maybe_enqueue_delivery(result, _type, _opts), do: result

  defp maybe_enqueue_create(entry, opts, type \\ "Create") do
    if Keyword.get(opts, :enqueue_delivery, true), do: enqueue_deliver_entry(entry, type)
  end

  # Subscriber notifications: only on first publication of a checkin/post.
  defp maybe_notify_new_entry(%Entry{type: type} = entry, "Create")
       when type in [:post, :checkin],
       do: notifications().notify_new_entry(entry)

  defp maybe_notify_new_entry(_entry, _type), do: :ok

  defp notifications, do: Application.get_env(:revix, :notifications_impl, Revix.Notifications)

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(result, _fun), do: result
end
