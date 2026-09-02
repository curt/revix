defmodule RevixWeb.PersonFeedLive do
  use RevixWeb, :live_view

  alias Revix.ActivityFeed
  alias Revix.Entries
  alias Revix.Follows
  alias Revix.Likes
  alias Revix.People
  alias RevixWeb.Live.ActivityFeedHelpers, as: Helpers

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
    can_follow = scope.person.uri != person.uri and person.origin == :local

    if connected?(socket) do
      Entries.subscribe_to_feed()
      if can_follow, do: Follows.subscribe_to_follows(person.uri)
    end

    {activities, has_more} = ActivityFeed.build_person_activities(person, scope, nil, limit)

    {:ok,
     assign(socket,
       person: person,
       activities: activities,
       limit: limit,
       cursor: Helpers.next_cursor(activities, nil),
       has_more: has_more,
       can_follow: can_follow,
       following?: can_follow and Follows.following?(scope.person.uri, person.uri)
     )}
  end

  @impl true
  def handle_event("follow", _params, socket) do
    %{current_scope: scope, person: person} = socket.assigns

    case Follows.follow(scope, person.uri) do
      {:ok, _follow} ->
        {:noreply, assign(socket, :following?, true)}

      {:error, _reason} ->
        name = person.display_name || person.username || "this person"
        {:noreply, put_flash(socket, :error, "Could not follow #{name}.")}
    end
  end

  @impl true
  def handle_event("unfollow", _params, socket) do
    %{current_scope: scope, person: person} = socket.assigns

    # {:error, :not_found} (already unfollowed elsewhere) is not an error to the
    # viewer — the desired end state is "not following", which we now reflect.
    case Follows.unfollow(scope, person.uri) do
      {:error, %Ecto.Changeset{}} ->
        name = person.display_name || person.username || "this person"
        {:noreply, put_flash(socket, :error, "Could not unfollow #{name}.")}

      _ok_or_not_found ->
        {:noreply, assign(socket, :following?, false)}
    end
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    %{
      current_scope: scope,
      person: person,
      activities: activities,
      cursor: cursor,
      limit: page_size
    } = socket.assigns

    {new_activities, has_more} =
      ActivityFeed.build_person_activities(person, scope, cursor, page_size)

    {:noreply,
     socket
     |> assign(:activities, activities ++ new_activities)
     |> assign(:cursor, Helpers.next_cursor(new_activities, cursor))
     |> assign(:has_more, has_more)}
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
        full_like -> {:noreply, prepend_activity(socket, {:like, full_like})}
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
          {:noreply, prepend_activity(socket, {:comment, full_comment})}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:follows_updated, socket) do
    %{current_scope: scope, person: person} = socket.assigns
    {:noreply, assign(socket, :following?, Follows.following?(scope.person.uri, person.uri))}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp show_like?(_like, _scope), do: true

  defp show_comment?(_comment, _scope), do: true

  defp prepend_activity(socket, activity) do
    new_activities =
      [activity | socket.assigns.activities]
      |> ActivityFeed.group_activities()
      |> Enum.take(loaded_count(socket) + 1)

    assign(socket, :activities, new_activities)
  end

  defp loaded_count(socket), do: length(socket.assigns.activities)
end
