defmodule RevixWeb.Live.ActivityFeedHelpers do
  alias Revix.ActivityFeed

  def merge_like(activities, limit, like) do
    updated =
      case Enum.find_index(activities, fn
             {:like_group, g} -> g.object_uri == like.object_uri
             _ -> false
           end) do
        nil ->
          [like_to_group(like) | activities]

        idx ->
          List.update_at(activities, idx, fn {:like_group, g} ->
            new_author = like.author
            authors = if new_author, do: [new_author | g.authors], else: g.authors

            deduped = Enum.uniq_by(authors, & &1.id)

            {:like_group,
             %{
               g
               | authors: deduped,
                 latest_at: latest_datetime(g.latest_at, like.published_at_utc),
                 latest_published_at_local: latest_local(g, like),
                 latest_published_tz: latest_tz(g, like),
                 count: length(deduped)
             }}
          end)
      end

    updated
    |> ActivityFeed.group_activities()
    |> Enum.take(limit)
  end

  def like_to_group(like) do
    authors = if like.author, do: [like.author], else: []

    {:like_group,
     %{
       object: like.object,
       object_uri: like.object_uri,
       root_entry: ActivityFeed.comment_root(like.object),
       authors: authors,
       latest_at: like.published_at_utc,
       latest_published_at_local: like.published_at_local,
       latest_published_tz: like.published_tz,
       count: 1
     }}
  end

  def merge_comment(activities, limit, comment) do
    root_uri = ActivityFeed.comment_root_uri(comment)

    updated =
      case Enum.find_index(activities, fn
             {:comment_group, g} -> g.root_uri == root_uri
             _ -> false
           end) do
        nil ->
          [comment_to_group(comment) | activities]

        idx ->
          List.update_at(activities, idx, fn {:comment_group, g} ->
            new_author = comment.author
            authors = if new_author, do: [new_author | g.authors], else: g.authors

            deduped = Enum.uniq_by(authors, & &1.id)

            {:comment_group,
             %{
               g
               | authors: deduped,
                 latest_at: latest_datetime(g.latest_at, comment.published_at_utc),
                 latest_published_at_local: latest_local(g, comment),
                 latest_published_tz: latest_tz(g, comment),
                 latest_comment_id: latest_comment_id(g, comment),
                 count: length(deduped)
             }}
          end)
      end

    updated
    |> ActivityFeed.group_activities()
    |> Enum.take(limit)
  end

  def comment_to_group(comment) do
    authors = if comment.author, do: [comment.author], else: []

    {:comment_group,
     %{
       root: ActivityFeed.comment_root(comment),
       root_uri: ActivityFeed.comment_root_uri(comment),
       authors: authors,
       latest_at: comment.published_at_utc,
       latest_published_at_local: comment.published_at_local,
       latest_published_tz: comment.published_tz,
       latest_comment_id: comment.id,
       count: 1
     }}
  end

  def latest_datetime(a, b) do
    if DateTime.compare(a, b) == :lt, do: b, else: a
  end

  def latest_local(g, item) do
    if DateTime.compare(g.latest_at, item.published_at_utc) == :lt,
      do: item.published_at_local,
      else: g.latest_published_at_local
  end

  def latest_tz(g, item) do
    if DateTime.compare(g.latest_at, item.published_at_utc) == :lt,
      do: item.published_tz,
      else: g.latest_published_tz
  end

  def latest_comment_id(g, comment) do
    if DateTime.compare(g.latest_at, comment.published_at_utc) == :lt,
      do: comment.id,
      else: g.latest_comment_id
  end

  @doc """
  Computes the next pagination cursor from a freshly-loaded page of activities,
  falling back to the current cursor when the page is empty.
  """
  def next_cursor([], cursor), do: cursor

  def next_cursor(activities, _cursor) do
    activities
    |> List.last()
    |> ActivityFeed.activity_timestamp()
  end
end
