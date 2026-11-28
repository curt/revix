defmodule Revix.Entries.Comments do
  @moduledoc """
  Comments and replies on checkins and posts: creating, editing, and the
  queries for comment threads and feeds.
  """
  import Ecto.Query
  alias Revix.Repo
  alias Revix.Entries.Entry
  alias Revix.People.Person
  import Revix.Entries.Query
  import Revix.Entries.Events

  @doc """
  Counts local, non-tombstoned comments (notes). Used for the NodeInfo
  `usage.localComments` figure.
  """
  def count_local_comments do
    Entry
    |> local_comments()
    |> Repo.aggregate(:count)
  end

  def create_comment(scope, checkin, attrs, uri_fn, url_fn, opts \\ []) do
    create_local_note(scope, checkin.uri, checkin.context, attrs, {uri_fn, url_fn}, opts)
  end

  @doc """
  Creates a local reply to `parent_comment`. The reply joins the parent's thread
  unless `:context` names the thread to put it in, as the comment section does
  so a reply always shows on the page it was written on.
  """
  def create_reply(scope, parent_comment, attrs, uri_fn, url_fn, opts \\ []) do
    context_uri =
      Keyword.get_lazy(opts, :context, fn ->
        parent_comment.context || parent_comment.in_reply_to_uri
      end)

    create_local_note(scope, parent_comment.uri, context_uri, attrs, {uri_fn, url_fn}, [])
  end

  defp create_local_note(scope, in_reply_to_uri, context_uri, attrs, {uri_fn, url_fn}, opts) do
    id = Revix.Ecto.Base58Id.autogenerate()

    %Entry{
      id: id,
      type: :note,
      origin: :local,
      uri: uri_fn.(id),
      url: url_fn.(id),
      author_uri: scope.person.uri,
      in_reply_to_uri: in_reply_to_uri,
      context: context_uri
    }
    |> Entry.comment_changeset(attrs, Keyword.take(opts, [:allow_empty_content]))
    |> validate_comment_length(comment_max_length(scope))
    |> Repo.insert()
    |> announce_local_note(context_uri)
  end

  defp validate_comment_length(changeset, nil), do: changeset

  defp validate_comment_length(changeset, max_length),
    do: Ecto.Changeset.validate_length(changeset, :content, max: max_length)

  defp announce_local_note({:ok, note}, context_uri) do
    note = Repo.preload(note, :author)
    broadcast_context(context_uri, {:comment_created, note})
    broadcast_feed({:comment_created, note})
    enqueue_deliver_entry(note, "Create")
    notifications().notify_reply(note)
    {:ok, note}
  end

  defp announce_local_note(error, _context_uri), do: error

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
    Entry
    |> local_comments()
    |> where([e], e.in_reply_to_uri == ^object_uri)
    |> order_by([e], asc: e.published_at_utc)
    |> preload(:author)
    |> Repo.all()
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
end
