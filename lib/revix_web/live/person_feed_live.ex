defmodule RevixWeb.PersonFeedLive do
  use RevixWeb, :live_view

  alias Revix.ActivityFeed
  alias Revix.Entries
  alias Revix.Likes
  alias Revix.People

  on_mount {RevixWeb.Live.PersonAuth, :require_authenticated_person}

  @impl true
  def mount(_params, %{"person_id" => person_id}, socket) do
    case People.get_local_person(person_id) do
      {:ok, person} ->
        mount_for_person(socket, person)

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  defp mount_for_person(socket, person) do
    scope = socket.assigns.current_scope
    limit = Application.get_env(:revix, :home)[:activity_limit] || 50

    if connected?(socket) do
      Entries.subscribe_to_feed()
    end

    activities = ActivityFeed.build_person_activities(person, scope, limit)

    {:ok, assign(socket, person: person, activities: activities, limit: limit)}
  end

  @impl true
  def handle_info({:checkin_created, checkin}, socket) do
    if checkin.author_uri == socket.assigns.person.uri do
      case Entries.get_local_checkin(checkin.id) do
        {:ok, full_checkin} ->
          {:noreply, prepend_activity(socket, {:checkin, full_checkin})}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:post_created, post}, socket) do
    if post.author_uri == socket.assigns.person.uri do
      case Entries.get_local_post(post.id) do
        {:ok, full_post} ->
          {:noreply, prepend_activity(socket, {:post, full_post})}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:like_created, like}, socket) do
    scope = socket.assigns.current_scope

    if like.author_uri == socket.assigns.person.uri and show_like?(like, scope) do
      case Likes.get_like_with_object(like.id) do
        nil -> {:noreply, socket}
        full_like -> {:noreply, merge_like(socket, full_like)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:comment_created, comment}, socket) do
    scope = socket.assigns.current_scope

    if comment.author_uri == socket.assigns.person.uri and show_comment?(comment, scope) do
      case Entries.get_comment_for_feed(comment.id) do
        {:ok, full_comment} ->
          {:noreply, merge_comment(socket, full_comment)}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp show_like?(_like, _scope), do: true

  defp show_comment?(_comment, _scope), do: true

  defp prepend_activity(socket, activity) do
    limit = socket.assigns.limit

    new_activities =
      [activity | socket.assigns.activities]
      |> ActivityFeed.group_activities()
      |> Enum.take(limit)

    assign(socket, :activities, new_activities)
  end

  defp merge_like(socket, like) do
    limit = socket.assigns.limit
    activities = socket.assigns.activities

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
    |> then(&assign(socket, :activities, &1))
  end

  defp like_to_group(like) do
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

  defp merge_comment(socket, comment) do
    limit = socket.assigns.limit
    activities = socket.assigns.activities
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
    |> then(&assign(socket, :activities, &1))
  end

  defp comment_to_group(comment) do
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

  defp latest_datetime(a, b) do
    if DateTime.compare(a, b) == :lt, do: b, else: a
  end

  defp latest_local(g, item) do
    if DateTime.compare(g.latest_at, item.published_at_utc) == :lt,
      do: item.published_at_local,
      else: g.latest_published_at_local
  end

  defp latest_tz(g, item) do
    if DateTime.compare(g.latest_at, item.published_at_utc) == :lt,
      do: item.published_tz,
      else: g.latest_published_tz
  end

  defp latest_comment_id(g, comment) do
    if DateTime.compare(g.latest_at, comment.published_at_utc) == :lt,
      do: comment.id,
      else: g.latest_comment_id
  end
end
