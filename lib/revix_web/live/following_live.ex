defmodule RevixWeb.FollowingLive do
  use RevixWeb, :live_view

  alias Revix.{Follows, People}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Follows.subscribe_to_follows(scope.person.uri)
    end

    {:ok,
     socket
     |> assign(:tab, :following)
     |> assign(:target_uri, "")
     |> load_follows()}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, parse_tab(tab))}
  end

  @impl true
  def handle_event("update_target", %{"target_uri" => value}, socket) do
    {:noreply, assign(socket, :target_uri, value)}
  end

  @impl true
  def handle_event("follow", %{"target_uri" => target_uri}, socket) do
    scope = socket.assigns.current_scope

    case Follows.follow(scope, String.trim(target_uri)) do
      {:ok, _follow} ->
        {:noreply,
         socket
         |> assign(:target_uri, "")
         |> load_follows()
         |> put_flash(:info, "Follow request sent.")}

      {:error, :self_follow} ->
        {:noreply, put_flash(socket, :error, "You cannot follow yourself.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to send follow request.")}
    end
  end

  @impl true
  def handle_event("unfollow", %{"following_uri" => following_uri}, socket) do
    scope = socket.assigns.current_scope

    case Follows.unfollow(scope, following_uri) do
      {:ok, _follow} ->
        {:noreply, socket |> load_follows() |> put_flash(:info, "Unfollowed.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Follow not found.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to unfollow.")}
    end
  end

  @impl true
  def handle_event("accept", %{"follow_id" => follow_id}, socket) do
    case Follows.accept_follow(follow_id) do
      {:ok, follow} ->
        %{"follow_id" => follow.id}
        |> Revix.Workers.DeliverAcceptFollowWorker.new()
        |> Oban.insert()

        {:noreply, socket |> load_follows() |> put_flash(:info, "Follower accepted.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Follow not found.")}
    end
  end

  @impl true
  def handle_info(:follows_updated, socket) do
    {:noreply, load_follows(socket)}
  end

  defp load_follows(socket) do
    person_uri = socket.assigns.current_scope.person.uri
    following = Follows.get_following_for_person(person_uri)
    followers = Follows.get_followers_for_person(person_uri)
    pending = Follows.get_pending_followers_for_person(person_uri)

    all_uris =
      (Enum.map(following, & &1.following_uri) ++
         Enum.map(followers, & &1.follower_uri) ++
         Enum.map(pending, & &1.follower_uri))
      |> Enum.uniq()

    people = People.get_people_by_uris(all_uris)

    socket
    |> assign(:following, following)
    |> assign(:followers, followers)
    |> assign(:pending_followers, pending)
    |> assign(:people, people)
  end

  defp parse_tab("following"), do: :following
  defp parse_tab("followers"), do: :followers
  defp parse_tab("pending"), do: :pending
  defp parse_tab(_), do: :following

  attr :person, :map, default: nil
  attr :uri, :string, required: true

  defp person_link(%{person: nil} = assigns) do
    ~H"""
    <span class="font-mono text-xs text-zinc-400" title={@uri}>{@uri}</span>
    """
  end

  defp person_link(assigns) do
    ~H"""
    <a href={@person.url} class="flex items-center gap-2 min-w-0" title={@uri}>
      <div class="avatar shrink-0">
        <div class="w-6 rounded-full">
          <.avatar_image
            person={@person}
            alt={@person.display_name || @person.username || @person.id}
          />
        </div>
      </div>
      <span class="truncate text-sm">{@person.display_name || @person.username || @person.id}</span>
    </a>
    """
  end
end
