defmodule Revix.Entries do
  import Ecto.Query
  alias Revix.Repo
  alias Revix.Entries.Entry
  alias Revix.People.Person
  alias Revix.Places.Place
  import Revix.Entries.Query
  import Revix.Entries.Events

  def get_local_checkins() do
    Entry
    |> local_checkins()
    |> published_checkins()
    |> order_by_recency()
    |> with_checkin_preloads()
    |> Repo.all()
  end

  @doc """
  Counts local published check-ins and posts (the "post-like" entry types),
  excluding drafts and tombstoned entries. Used for the NodeInfo
  `usage.localPosts` figure.
  """
  def count_local_published_entries do
    Entry
    |> where(
      [e],
      e.origin == :local and e.type in [:checkin, :post] and
        not is_nil(e.published_at_utc) and is_nil(e.tombstoned_at)
    )
    |> Repo.aggregate(:count)
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

  Each person is stored once and the author never is
  (`Revix.EntryPeople.companion_uris/2`).
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
          {checkin, insert_companions!(checkin, companion_uris)}

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> notify_companions()
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
          companions = insert_companions!(post, companion_uris)

          Enum.each(place_uris, fn place_uri ->
            %Revix.EntryPlaces.EntryPlace{}
            |> Revix.EntryPlaces.EntryPlace.create_changeset(%{
              entry_uri: post.uri,
              place_uri: place_uri
            })
            |> Repo.insert!()
          end)

          {post, companions}

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> notify_companions()
  end

  defp insert_companions!(entry, companion_uris) do
    entry.author_uri
    |> Revix.EntryPeople.companion_uris(companion_uris)
    |> Enum.map(fn person_uri ->
      %Revix.EntryPeople.EntryPerson{}
      |> Revix.EntryPeople.EntryPerson.create_changeset(%{
        entry_uri: entry.uri,
        person_uri: person_uri,
        type: :companion,
        origin: :local
      })
      |> Repo.insert!()
    end)
  end

  # Runs after the transaction commits, as tagging on edit does
  # (EntryPeople.add_companion/3). The notifier skips drafts; publishing
  # notifies their companions then.
  defp notify_companions({:ok, {entry, companions}}) do
    Enum.each(companions, fn ep -> notifications().notify_companion_tag(ep) end)
    {:ok, entry}
  end

  defp notify_companions({:error, _reason} = error), do: error

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

  @doc """
  Published entries are public; a draft is visible only to its author.
  Others get `{:error, :not_found}` so a draft's existence isn't revealed.
  """
  def authorize_view(%Entry{published_at_utc: %DateTime{}}, _scope), do: :ok

  def authorize_view(%Entry{author_uri: uri}, %{person: %{uri: uri}}), do: :ok

  def authorize_view(%Entry{}, _scope), do: {:error, :not_found}

  def get_entry(id) do
    Entry
    |> where([e], e.id == ^id)
    |> Repo.one()
    |> entry_ok_or_not_found()
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
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

  def subscribe_to_feed do
    Phoenix.PubSub.subscribe(Revix.PubSub, "feed")
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
end
