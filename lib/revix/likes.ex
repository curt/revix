defmodule Revix.Likes do
  import Ecto.Query
  alias Revix.Repo
  alias Revix.Likes.Like
  alias Revix.People.Person
  alias Revix.People.Scope
  alias Revix.Entries.Entry

  @doc """
  Likes an entry on behalf of the authenticated person.

  `uri_fn` is a 1-arity function called with the generated like ID to produce
  the canonical like URI (e.g. `fn id -> "https://example.com/likes/\#{id}" end`).

  - Returns {:error, :self_like} if the person is the author of the object.
  - If no like record exists, creates a new one.
  - If a like record exists but was unliked, re-likes it (clears unliked_at, updates published_at).
  - If a like record exists and is active, returns it unchanged (idempotent).
  """
  def like_entry(%Scope{} = scope, object_uri, timezone, uri_fn)
      when is_binary(timezone) and is_function(uri_fn, 1) do
    author_uri = scope.person.uri

    if self_like?(author_uri, object_uri) do
      {:error, :self_like}
    else
      do_like_entry(author_uri, object_uri, timezone, uri_fn)
    end
  end

  defp do_like_entry(author_uri, object_uri, timezone, uri_fn) do
    now_utc = DateTime.utc_now(:second)
    now_local = DateTime.shift_zone!(now_utc, timezone) |> DateTime.to_naive()

    re_like_attrs = %{
      published_at_utc: now_utc,
      published_at_local: now_local,
      published_tz: timezone
    }

    case get_like(author_uri, object_uri) do
      nil ->
        id = Revix.Ecto.Base58Id.autogenerate()

        attrs =
          Map.merge(re_like_attrs, %{
            like_uri: uri_fn.(id),
            author_uri: author_uri,
            object_uri: object_uri,
            origin: :local
          })

        %Like{id: id}
        |> Like.create_changeset(attrs)
        |> Repo.insert()

      %Like{unliked_at: nil} = like ->
        {:ok, like}

      %Like{} = like ->
        like
        |> Like.re_like_changeset(re_like_attrs)
        |> Repo.update()
    end
  end

  @doc """
  Unlikes an entry on behalf of the authenticated person.

  Sets unliked_at to the current UTC datetime. Returns {:error, :not_found} if
  there is no active like for this author/object pair.
  """
  def unlike_entry(%Scope{} = scope, object_uri) do
    author_uri = scope.person.uri

    case get_active_like(author_uri, object_uri) do
      nil ->
        {:error, :not_found}

      %Like{} = like ->
        like
        |> Like.unlike_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Returns all active (non-unliked) likes for a given object URI, with authors preloaded.
  """
  def get_active_likes_for_entry(object_uri) do
    Repo.all(
      from l in Like,
        where: l.object_uri == ^object_uri and is_nil(l.unliked_at),
        order_by: [desc: l.published_at_utc],
        preload: [:author]
    )
  end

  @doc """
  Returns true if the given author_uri has an active (non-unliked) like on the given object_uri.
  Returns false if author_uri is nil.
  """
  def liked_by?(nil, _object_uri), do: false

  def liked_by?(author_uri, object_uri) do
    Repo.exists?(
      from l in Like,
        where:
          l.author_uri == ^author_uri and l.object_uri == ^object_uri and is_nil(l.unliked_at)
    )
  end

  @doc """
  Returns the count of active (non-unliked) likes for a given object URI.
  """
  def count_active_likes(object_uri) do
    Repo.one(
      from l in Like,
        where: l.object_uri == ^object_uri and is_nil(l.unliked_at),
        select: count()
    )
  end

  @doc """
  Returns a map of %{object_uri => [like, ...]} for active likes, given a list of object URIs.
  Likes have :author preloaded. URIs with zero likes are not included in the map.
  """
  def get_active_likes_by_object_uris([]), do: %{}

  def get_active_likes_by_object_uris(uris) do
    Repo.all(
      from l in Like,
        where: l.object_uri in ^uris and is_nil(l.unliked_at),
        order_by: [desc: l.published_at_utc],
        preload: [:author]
    )
    |> Enum.group_by(& &1.object_uri)
  end

  @doc """
  Returns a map of %{object_uri => count} for active likes, given a list of object URIs.
  URIs with zero likes are not included in the map.
  """
  def count_active_likes_by_object_uris([]), do: %{}

  def count_active_likes_by_object_uris(uris) do
    Repo.all(
      from l in Like,
        where: l.object_uri in ^uris and is_nil(l.unliked_at),
        group_by: l.object_uri,
        select: {l.object_uri, count()}
    )
    |> Map.new()
  end

  @doc """
  Returns recent active likes for the activity feed, ordered by published_at_utc descending.
  Authors are preloaded. The liked object entry (if local) is also preloaded via :object.
  """
  def get_recent_likes(limit \\ 50) do
    Like
    |> active_likes()
    |> order_likes_by_recency()
    |> limit(^limit)
    |> with_like_preloads()
    |> Repo.all()
    |> enrich_with_objects()
  end

  @doc """
  Returns recent active likes by the given person, ordered by published_at_utc descending.
  Authors are preloaded. The liked object entry (if local) is also preloaded via :object.
  """
  def get_recent_likes_for_person(%Person{} = person, opts \\ []) do
    Like
    |> active_likes()
    |> where([l], l.author_uri == ^person.uri)
    |> order_likes_by_recency()
    |> maybe_limit(Keyword.get(opts, :limit, 50))
    |> with_like_preloads()
    |> Repo.all()
    |> enrich_with_objects()
  end

  @doc """
  Likes an entry and broadcasts the event on the given context topic.

  `uri_fn` is a 1-arity function called with the generated like ID to produce
  the canonical like URI. `context_uri` is the checkin URI (the `context` field
  of the liked entry).
  """
  def like_entry(%Scope{} = scope, object_uri, timezone, uri_fn, context_uri)
      when is_binary(timezone) and is_function(uri_fn, 1) and is_binary(context_uri) do
    result = like_entry(scope, object_uri, timezone, uri_fn)

    with {:ok, like} <- result do
      broadcast_context(context_uri, {:entry_liked, object_uri, scope.person.uri})
      {:ok, like}
    end
  end

  @doc """
  Unlikes an entry and broadcasts the event on the given context topic.
  """
  def unlike_entry(%Scope{} = scope, object_uri, context_uri) when is_binary(context_uri) do
    result = unlike_entry(scope, object_uri)

    with {:ok, like} <- result do
      broadcast_context(context_uri, {:entry_unliked, object_uri, scope.person.uri})
      {:ok, like}
    end
  end

  @doc """
  Records an inbound Like from a remote actor, handling re-likes correctly.

  If no like exists for the author/object pair, inserts a new one. If a like
  exists but was unliked, re-likes it (clears unliked_at, updates published_at).
  If an active like already exists, returns it unchanged (idempotent).

  Expects a map with `:author_uri`, `:object_uri`, and `:like_uri`.
  Returns `{:ok, like}` or `{:error, changeset}`.
  """
  def upsert_inbound_like(%{author_uri: author_uri, object_uri: object_uri, like_uri: like_uri}) do
    now_utc = DateTime.utc_now(:second)
    now_local = NaiveDateTime.utc_now(:second)

    attrs = %{
      like_uri: like_uri,
      author_uri: author_uri,
      object_uri: object_uri,
      origin: :remote,
      published_at_utc: now_utc,
      published_at_local: now_local,
      published_tz: "UTC"
    }

    case get_like(author_uri, object_uri) do
      nil ->
        id = Revix.Ecto.Base58Id.autogenerate()

        %Like{id: id}
        |> Like.create_changeset(attrs)
        |> Repo.insert()

      %Like{unliked_at: nil} = like ->
        {:ok, like}

      %Like{} = like ->
        re_like_attrs = Map.take(attrs, [:published_at_utc, :published_at_local, :published_tz])

        like
        |> Like.re_like_changeset(re_like_attrs)
        |> Repo.update()
    end
  end

  @doc """
  Soft-deletes an inbound Like looked up by its canonical URI.

  Returns `{:ok, like}` or `{:error, :not_found}`.
  """
  def undo_inbound_like(like_uri) when is_binary(like_uri) do
    case Repo.one(from l in Like, where: l.like_uri == ^like_uri and is_nil(l.unliked_at)) do
      nil -> {:error, :not_found}
      %Like{} = like -> like |> Like.unlike_changeset() |> Repo.update()
    end
  end

  @doc """
  Soft-deletes an inbound Like looked up by author URI and object URI.

  Used as a fallback when the Undo activity's nested object has no `id`.
  Returns `{:ok, like}` or `{:error, :not_found}`.
  """
  def undo_inbound_like(author_uri, object_uri) do
    case get_active_like(author_uri, object_uri) do
      nil -> {:error, :not_found}
      %Like{} = like -> like |> Like.unlike_changeset() |> Repo.update()
    end
  end

  # Private helpers

  defp broadcast_context(context_uri, event) do
    Phoenix.PubSub.broadcast(Revix.PubSub, "context:#{context_uri}", event)
  end

  defp active_likes(query), do: where(query, [l], is_nil(l.unliked_at))

  defp order_likes_by_recency(query), do: order_by(query, [l], desc: l.published_at_utc)

  defp with_like_preloads(query), do: preload(query, [:author])

  defp maybe_limit(query, limit) when is_integer(limit), do: limit(query, ^limit)
  defp maybe_limit(query, _), do: query

  defp enrich_with_objects(likes) do
    object_uris = likes |> Enum.map(& &1.object_uri) |> Enum.uniq()

    entries =
      Repo.all(from e in Entry, where: e.uri in ^object_uris, preload: [:place])
      |> Map.new(fn e -> {e.uri, e} end)

    Enum.map(likes, fn like -> Map.put(like, :object, Map.get(entries, like.object_uri)) end)
  end

  defp get_like(author_uri, object_uri) do
    Repo.one(
      from l in Like,
        where: l.author_uri == ^author_uri and l.object_uri == ^object_uri
    )
  end

  defp get_active_like(author_uri, object_uri) do
    Repo.one(
      from l in Like,
        where:
          l.author_uri == ^author_uri and l.object_uri == ^object_uri and is_nil(l.unliked_at)
    )
  end

  defp self_like?(author_uri, object_uri) do
    Repo.exists?(from e in Entry, where: e.uri == ^object_uri and e.author_uri == ^author_uri)
  end
end
