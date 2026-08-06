defmodule RevixWeb.HomeFeedLive do
  use RevixWeb, :live_view

  alias Revix.ActivityFeed
  alias Revix.Entries
  alias Revix.Likes
  alias Revix.Sites
  alias RevixWeb.Live.ActivityFeedHelpers, as: Helpers

  on_mount {RevixWeb.Live.PersonAuth, :require_authenticated_person}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    limit = Application.get_env(:revix, :home)[:activity_limit] || 50

    if connected?(socket) do
      Entries.subscribe_to_feed()
    end

    {activities, has_more} = ActivityFeed.build_feed_activities(scope, nil, limit)
    site = socket.assigns.site

    {:ok,
     socket
     |> assign(:activities, activities)
     |> assign(:limit, limit)
     |> assign(:cursor, Helpers.next_cursor(activities, nil))
     |> assign(:has_more, has_more)
     |> assign(:description_html, Sites.description_html(site))
     |> assign(:page_title, Sites.page_title(site))
     |> assign(:meta_description, site.description)}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    %{current_scope: scope, activities: activities, cursor: cursor, limit: page_size} =
      socket.assigns

    {new_activities, has_more} = ActivityFeed.build_feed_activities(scope, cursor, page_size)

    {:noreply,
     socket
     |> assign(:activities, activities ++ new_activities)
     |> assign(:cursor, Helpers.next_cursor(new_activities, cursor))
     |> assign(:has_more, has_more)}
  end

  @impl true
  def handle_info({:checkin_created, checkin}, socket) do
    case Entries.get_local_checkin(checkin.id) do
      {:ok, full_checkin} ->
        {:noreply, prepend_activity(socket, {:checkin, full_checkin})}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:post_created, post}, socket) do
    case Entries.get_local_post(post.id) do
      {:ok, full_post} ->
        {:noreply, prepend_activity(socket, {:post, full_post})}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:like_created, like}, socket) do
    scope = socket.assigns.current_scope

    if show_like?(like, scope) do
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

    if show_comment?(comment, scope) do
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
