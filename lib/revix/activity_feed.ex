defmodule Revix.ActivityFeed do
  alias Revix.Entries
  alias Revix.Likes

  @doc """
  Builds the home activity feed for the given scope and limit.

  When scope is nil (unauthenticated), comments are excluded entirely and likes
  on notes (comments/replies) are filtered out. Remote likes are also excluded.
  Likes on the same object are grouped into {:like_group, group} tuples.
  """
  def build_feed_activities(nil, limit) do
    checkins = Entries.get_recent_checkins(limit)
    posts = Entries.get_recent_posts(limit)
    likes = Likes.get_recent_likes(limit, include_remote: false) |> Enum.reject(&note_like?/1)

    (Enum.map(checkins, &{:checkin, &1}) ++
       Enum.map(posts, &{:post, &1}) ++
       Enum.map(likes, &{:like, &1}))
    |> group_activities()
    |> Enum.take(limit)
  end

  def build_feed_activities(scope, limit) do
    checkins = Entries.get_recent_checkins(limit)
    posts = Entries.get_recent_posts(limit)
    likes = Likes.get_recent_likes(limit, include_remote: true)
    comments = Entries.get_recent_comments_for_feed(limit, include_replies: true)
    drafts = get_drafts_for_scope(scope)

    (Enum.map(checkins, &{:checkin, &1}) ++
       Enum.map(posts, &{:post, &1}) ++
       Enum.map(likes, &{:like, &1}) ++
       Enum.map(comments, &{:comment, &1}) ++
       Enum.map(drafts, &{:draft, &1}))
    |> group_activities()
    |> Enum.take(limit)
  end

  @doc """
  Builds the activity feed for a specific person and scope.

  When scope is nil (unauthenticated), comments are excluded entirely and likes
  on notes are filtered out. When authenticated, all activity is included.
  """
  def build_person_activities(person, nil, limit) do
    checkins = Entries.get_recent_checkins_for_person(person, limit: limit)
    likes = Likes.get_recent_likes_for_person(person, limit: limit) |> Enum.reject(&note_like?/1)

    (Enum.map(checkins, &{:checkin, &1}) ++
       Enum.map(likes, &{:like, &1}))
    |> group_activities()
    |> Enum.take(limit)
  end

  def build_person_activities(person, scope, limit) do
    checkins = Entries.get_recent_checkins_for_person(person, limit: limit)
    likes = Likes.get_recent_likes_for_person(person, limit: limit)

    comments =
      Entries.get_recent_comments_for_person_feed(person, include_replies: true, limit: limit)

    drafts = get_person_drafts_for_scope(person, scope)

    (Enum.map(checkins, &{:checkin, &1}) ++
       Enum.map(likes, &{:like, &1}) ++
       Enum.map(comments, &{:comment, &1}) ++
       Enum.map(drafts, &{:draft, &1}))
    |> group_activities()
    |> Enum.take(limit)
  end

  @doc """
  Groups {:like, like} tuples sharing the same object_uri into {:like_group, group} tuples,
  and {:comment, comment} tuples sharing the same in_reply_to_uri into {:comment_group, group}
  tuples. All other activity types pass through unchanged.
  The result is sorted by timestamp descending.
  """
  def group_activities(activities) do
    {likes, rest} = Enum.split_with(activities, fn {type, _} -> type == :like end)
    {comments, others} = Enum.split_with(rest, fn {type, _} -> type == :comment end)

    grouped_likes =
      likes
      |> Enum.group_by(fn {_type, like} -> like.object_uri end)
      |> Enum.map(fn {_object_uri, like_tuples} ->
        likes_list = Enum.map(like_tuples, &elem(&1, 1))
        sorted = Enum.sort_by(likes_list, & &1.published_at_utc, {:desc, DateTime})
        latest = hd(sorted)
        root_uri = comment_root_uri(latest.object)

        {:like_group,
         %{
           object: latest.object,
           object_uri: latest.object_uri,
           root_uri: root_uri,
           root_entry: comment_root(latest.object),
           authors: Enum.map(sorted, & &1.author) |> Enum.reject(&is_nil/1),
           latest_at: latest.published_at_utc,
           latest_published_at_local: latest.published_at_local,
           latest_published_tz: latest.published_tz,
           count: length(sorted)
         }}
      end)

    grouped_comments =
      comments
      |> Enum.group_by(fn {_type, comment} -> comment_root_uri(comment) end)
      |> Enum.map(fn {_root_uri, comment_tuples} ->
        comments_list = Enum.map(comment_tuples, &elem(&1, 1))
        sorted = Enum.sort_by(comments_list, & &1.published_at_utc, {:desc, DateTime})
        latest = hd(sorted)
        root_uri = comment_root_uri(latest)
        root = comment_root(latest)

        {:comment_group,
         %{
           root: root,
           root_uri: root_uri,
           authors:
             Enum.map(sorted, & &1.author) |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.id),
           latest_at: latest.published_at_utc,
           latest_published_at_local: latest.published_at_local,
           latest_published_tz: latest.published_tz,
           latest_comment_id: latest.id,
           count: length(sorted)
         }}
      end)

    {grouped_likes, grouped_comments} = hydrate_group_roots(grouped_likes, grouped_comments)

    (others ++ grouped_likes ++ grouped_comments)
    |> Enum.sort_by(&activity_timestamp/1, {:desc, DateTime})
  end

  defp activity_timestamp({:checkin, e}),
    do: e.starts_at_utc || e.published_at_utc || e.updated_at

  defp activity_timestamp({:post, e}), do: e.published_at_utc || e.updated_at
  defp activity_timestamp({:draft, e}), do: e.updated_at
  defp activity_timestamp({:comment, e}), do: e.published_at_utc || e.updated_at
  defp activity_timestamp({:like_group, g}), do: g.latest_at
  defp activity_timestamp({:comment_group, g}), do: g.latest_at

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

  defp hydrate_group_roots(grouped_likes, grouped_comments) do
    root_uris =
      (Enum.flat_map(grouped_likes, fn
         {:like_group, %{root_entry: nil, root_uri: uri}} when is_binary(uri) -> [uri]
         _ -> []
       end) ++
         Enum.flat_map(grouped_comments, fn
           {:comment_group, %{root: nil, root_uri: uri}} when is_binary(uri) -> [uri]
           _ -> []
         end))
      |> Enum.uniq()

    entries_by_uri =
      Entries.get_entries_by_uris(root_uris)
      |> Map.new(fn entry -> {entry.uri, entry} end)

    grouped_likes =
      Enum.map(grouped_likes, fn
        {:like_group, %{root_entry: nil, root_uri: uri} = group} ->
          {:like_group, %{group | root_entry: Map.get(entries_by_uri, uri)}}

        other ->
          other
      end)

    grouped_comments =
      Enum.map(grouped_comments, fn
        {:comment_group, %{root: nil, root_uri: uri} = group} ->
          {:comment_group, %{group | root: Map.get(entries_by_uri, uri)}}

        other ->
          other
      end)

    {grouped_likes, grouped_comments}
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
    case Entries.get_entry_by_uri(uri) do
      {:ok, %{type: :note} = entry} -> comment_root(entry)
      {:ok, entry} -> entry
      _ -> nil
    end
  end

  defp get_drafts_for_scope(%{person: person}) when not is_nil(person),
    do: Entries.get_draft_posts_for_person(person)

  defp get_drafts_for_scope(_), do: []

  defp get_person_drafts_for_scope(person, %{person: %{uri: uri}}) when uri == person.uri,
    do: Entries.get_draft_posts_for_person(person)

  defp get_person_drafts_for_scope(_person, _scope), do: []
end
