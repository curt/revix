defmodule Revix.ActivityFeed do
  alias Revix.Entries
  alias Revix.Likes

  @doc """
  Builds the home activity feed for the given scope and limit.

  When scope is nil (unauthenticated), comments are excluded entirely and likes
  on notes (comments/replies) are filtered out. Remote likes are also excluded.
  """
  def build_feed_activities(nil, limit) do
    checkins = Entries.get_recent_checkins(limit)
    posts = Entries.get_recent_posts(limit)
    likes = Likes.get_recent_likes(limit, include_remote: false) |> Enum.reject(&note_like?/1)

    assemble(
      [checkin: checkins, post: posts, like: likes],
      limit
    )
  end

  def build_feed_activities(scope, limit) do
    checkins = Entries.get_recent_checkins(limit)
    posts = Entries.get_recent_posts(limit)
    likes = Likes.get_recent_likes(limit, include_remote: true)
    comments = Entries.get_recent_comments_for_feed(limit, include_replies: true)
    drafts = get_drafts_for_scope(scope)

    assemble(
      [checkin: checkins, post: posts, like: likes, comment: comments, draft: drafts],
      limit
    )
  end

  @doc """
  Builds one cursor-paginated page of the home activity feed.

  `cursor` is nil for the first page, or the `activity_timestamp/1` of the last
  activity on the previous page. Returns `{activities, has_more?}`. Drafts are
  only included on the first page (`cursor == nil`) since they are not a
  realistic pagination target and would otherwise be re-fetched on every page.
  """
  def build_feed_activities(scope, cursor, page_size) do
    probe = page_size + 1
    checkins = Entries.get_recent_checkins(probe, before: cursor)
    posts = Entries.get_recent_posts(probe, before: cursor)
    likes = Likes.get_recent_likes(probe, include_remote: true, before: cursor)
    comments = Entries.get_recent_comments_for_feed(probe, include_replies: true, before: cursor)
    drafts = if is_nil(cursor), do: get_drafts_for_scope(scope), else: []

    assemble_page(
      [checkin: checkins, post: posts, like: likes, comment: comments, draft: drafts],
      page_size
    )
  end

  @doc """
  Builds the activity feed for a specific person and scope.

  When scope is nil (unauthenticated), comments are excluded entirely and likes
  on notes are filtered out. When authenticated, all activity is included.
  """
  def build_person_activities(person, nil, limit) do
    checkins = Entries.get_recent_checkins_for_person(person, limit)
    posts = Entries.get_recent_posts_for_person(person, limit)

    likes =
      Likes.get_recent_likes_for_person(person, limit) |> Enum.reject(&note_like?/1)

    assemble(
      [checkin: checkins, post: posts, like: likes],
      limit
    )
  end

  def build_person_activities(person, scope, limit) do
    checkins = Entries.get_recent_checkins_for_person(person, limit)
    posts = Entries.get_recent_posts_for_person(person, limit)
    likes = Likes.get_recent_likes_for_person(person, limit)

    comments =
      Entries.get_recent_comments_for_person_feed(person, limit, include_replies: true)

    drafts = get_person_drafts_for_scope(person, scope)

    assemble(
      [checkin: checkins, post: posts, like: likes, comment: comments, draft: drafts],
      limit
    )
  end

  @doc """
  Builds one cursor-paginated page of a person's activity feed.

  See `build_feed_activities/3` for the cursor/return-value contract.
  """
  def build_person_activities(person, scope, cursor, page_size) do
    probe = page_size + 1
    checkins = Entries.get_recent_checkins_for_person(person, probe, before: cursor)
    posts = Entries.get_recent_posts_for_person(person, probe, before: cursor)
    likes = Likes.get_recent_likes_for_person(person, probe, before: cursor)

    comments =
      Entries.get_recent_comments_for_person_feed(person, probe,
        include_replies: true,
        before: cursor
      )

    drafts = if is_nil(cursor), do: get_person_drafts_for_scope(person, scope), else: []

    assemble_page(
      [checkin: checkins, post: posts, like: likes, comment: comments, draft: drafts],
      page_size
    )
  end

  @doc """
  Sorts a flat list of activity tuples by `activity_timestamp/1`, descending.
  """
  def group_activities(activities) do
    Enum.sort_by(activities, &activity_timestamp/1, {:desc, DateTime})
  end

  @doc """
  Slices `page_size` activities off the front of a grouped/sorted activity list,
  returning `{page, has_more?}`. Expects the list to have been fetched with a
  probe size of `page_size + 1` so the presence of that extra item indicates
  whether more activity exists beyond this page.
  """
  def take_page(activities, page_size) do
    {page, rest} = Enum.split(activities, page_size)
    {page, rest != []}
  end

  @doc """
  Returns the effective sort timestamp for an activity tuple, used both to sort
  the feed and as the cursor value for the next page.
  """
  def activity_timestamp({:checkin, e}),
    do: e.starts_at_utc || e.published_at_utc || e.updated_at

  def activity_timestamp({:post, e}), do: e.published_at_utc || e.updated_at
  def activity_timestamp({:draft, e}), do: e.updated_at
  def activity_timestamp({:comment, e}), do: e.published_at_utc || e.updated_at
  def activity_timestamp({:like, l}), do: l.published_at_utc || l.updated_at

  # Walk the in_reply_to chain to find the URI of the root entry (checkin or post).
  # A comment's root is its in_reply_to when that entry is not a note (i.e. a checkin or post).
  # A reply's root is found by walking up one more level.
  # Falls back to in_reply_to_uri when the chain isn't preloaded (e.g. inbound federation).
  def comment_root_uri(nil), do: nil
  def comment_root_uri(%{in_reply_to: %{type: type, uri: uri}}) when type != :note, do: uri
  def comment_root_uri(%{in_reply_to: %{type: :note} = parent}), do: comment_root_uri(parent)

  def comment_root_uri(%{in_reply_to_uri: uri}) when is_binary(uri),
    do: resolve_root_uri_from_uri(uri)

  def comment_root_uri(_), do: nil

  def comment_root(%{in_reply_to: %{type: type} = entry}) when type != :note, do: entry
  def comment_root(%{in_reply_to: %{type: :note} = parent}), do: comment_root(parent)

  def comment_root(%{in_reply_to_uri: uri}) when is_binary(uri),
    do: resolve_root_entry_from_uri(uri)

  def comment_root(%{in_reply_to: nil}), do: nil
  def comment_root(_), do: nil

  # Tags each `{fetched_list}` in `sources` (a keyword list of `tag: list` pairs)
  # into `{tag, item}` tuples, concatenates, sorts by timestamp, and takes the
  # first `limit` activities. Shared by all non-paginated feed builders.
  defp assemble(sources, limit) do
    sources
    |> tag_and_concat()
    |> group_activities()
    |> Enum.take(limit)
  end

  # Same as `assemble/2` but returns `{page, has_more?}` via `take_page/2`,
  # for the cursor-paginated feed builders.
  defp assemble_page(sources, page_size) do
    sources
    |> tag_and_concat()
    |> group_activities()
    |> take_page(page_size)
  end

  defp tag_and_concat(sources) do
    Enum.flat_map(sources, fn {tag, items} -> Enum.map(items, &{tag, &1}) end)
  end

  defp note_like?(%{object: %{type: :note}}), do: true
  defp note_like?(_), do: false

  defp resolve_root_uri_from_uri(uri) do
    case Entries.get_entry_by_uri(uri) do
      {:ok, %{type: :note} = entry} -> comment_root_uri(entry)
      {:ok, %{uri: resolved_uri}} -> resolved_uri
      _ -> uri
    end
  end

  defp resolve_root_entry_from_uri(uri) do
    case Entries.get_entry_by_uri_with_place(uri) do
      {:ok, %{type: :note} = entry} -> comment_root(entry)
      {:ok, entry} -> entry
      _ -> nil
    end
  end

  defp get_drafts_for_scope(%{person: person}) when not is_nil(person),
    do:
      Entries.get_draft_posts_for_person(person) ++ Entries.get_draft_checkins_for_person(person)

  defp get_drafts_for_scope(_), do: []

  defp get_person_drafts_for_scope(person, %{person: %{uri: uri}}) when uri == person.uri,
    do:
      Entries.get_draft_posts_for_person(person) ++
        Entries.get_draft_checkins_for_person(person)

  defp get_person_drafts_for_scope(_person, _scope), do: []
end
