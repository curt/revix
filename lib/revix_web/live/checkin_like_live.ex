defmodule RevixWeb.CheckinLikeLive do
  use RevixWeb, :live_view

  alias Revix.Entries
  alias Revix.Likes
  alias Revix.People
  alias Revix.People.Scope

  @impl true
  def mount(_params, session, socket) do
    checkin_uri = session["checkin_uri"]
    checkin_author_uri = session["checkin_author_uri"]
    scope = mount_current_scope(session)

    if connected?(socket) do
      Entries.subscribe_to_context(checkin_uri)
    end

    likes = Likes.get_active_likes_for_entry(checkin_uri)

    socket =
      socket
      |> assign(:checkin_uri, checkin_uri)
      |> assign(:checkin_author_uri, checkin_author_uri)
      |> assign(:current_scope, scope)
      |> assign(:timezone, nil)
      |> assign_like_state(likes, scope, checkin_author_uri)

    {:ok, socket}
  end

  @impl true
  def handle_event("set_timezone", %{"timezone" => tz}, socket) do
    {:noreply, assign(socket, :timezone, tz)}
  end

  @impl true
  def handle_event("like", _params, socket) do
    scope = socket.assigns.current_scope
    checkin_uri = socket.assigns.checkin_uri
    tz = socket.assigns.timezone || "Etc/UTC"

    case Likes.like_entry(scope, checkin_uri, tz, checkin_uri) do
      {:ok, _} -> {:noreply, socket}
      {:error, :self_like} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not like checkin.")}
    end
  end

  @impl true
  def handle_event("unlike", _params, socket) do
    scope = socket.assigns.current_scope
    checkin_uri = socket.assigns.checkin_uri

    case Likes.unlike_entry(scope, checkin_uri, checkin_uri) do
      {:ok, _} -> {:noreply, socket}
      {:error, _} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:entry_liked, checkin_uri, _liker_uri}, socket)
      when checkin_uri == socket.assigns.checkin_uri do
    {:noreply, reload_likes(socket)}
  end

  @impl true
  def handle_info({:entry_unliked, checkin_uri, _liker_uri}, socket)
      when checkin_uri == socket.assigns.checkin_uri do
    {:noreply, reload_likes(socket)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp reload_likes(socket) do
    likes = Likes.get_active_likes_for_entry(socket.assigns.checkin_uri)

    assign_like_state(
      socket,
      likes,
      socket.assigns.current_scope,
      socket.assigns.checkin_author_uri
    )
  end

  defp assign_like_state(socket, likes, scope, checkin_author_uri) do
    person_uri = scope && scope.person.uri
    liked = person_uri && Enum.any?(likes, &(&1.author_uri == person_uri))
    can_like = not is_nil(person_uri) and person_uri != checkin_author_uri

    socket
    |> assign(:likes, likes)
    |> assign(:liked, liked)
    |> assign(:can_like, can_like)
  end

  defp mount_current_scope(session) do
    case session["person_token"] && People.get_person_by_session_token(session["person_token"]) do
      {person, _token_inserted_at} -> Scope.for_person(person)
      _ -> nil
    end
  end
end
