defmodule RevixWeb.EntryLikeLive do
  use RevixWeb, :live_view

  alias Revix.Entries
  alias Revix.Likes
  alias Revix.People
  alias Revix.People.Scope

  @impl true
  def mount(_params, session, socket) do
    entry_uri = session["entry_uri"]
    entry_author_uri = session["entry_author_uri"]
    scope = mount_current_scope(session)

    if connected?(socket) do
      Entries.subscribe_to_context(entry_uri)
    end

    likes = Likes.get_active_likes_for_entry(entry_uri)

    socket =
      socket
      |> assign(:entry_uri, entry_uri)
      |> assign(:entry_author_uri, entry_author_uri)
      |> assign(:current_scope, scope)
      |> assign(:timezone, nil)
      |> assign_like_state(likes, scope, entry_author_uri)

    {:ok, socket}
  end

  @impl true
  def handle_event("set_timezone", %{"timezone" => tz}, socket) do
    {:noreply, assign(socket, :timezone, tz)}
  end

  @impl true
  def handle_event("like", _params, socket) do
    scope = socket.assigns.current_scope
    entry_uri = socket.assigns.entry_uri
    tz = socket.assigns.timezone || "Etc/UTC"

    uri_fn = &RevixWeb.CanonicalRoutes.like_uri/1

    case Likes.like_entry(scope, entry_uri, tz, uri_fn, entry_uri) do
      {:ok, _} -> {:noreply, socket}
      {:error, :self_like} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not like entry.")}
    end
  end

  @impl true
  def handle_event("unlike", _params, socket) do
    scope = socket.assigns.current_scope
    entry_uri = socket.assigns.entry_uri

    case Likes.unlike_entry(scope, entry_uri, entry_uri) do
      {:ok, _} -> {:noreply, socket}
      {:error, _} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:entry_liked, entry_uri, _liker_uri}, socket)
      when entry_uri == socket.assigns.entry_uri do
    {:noreply, reload_likes(socket)}
  end

  @impl true
  def handle_info({:entry_unliked, entry_uri, _liker_uri}, socket)
      when entry_uri == socket.assigns.entry_uri do
    {:noreply, reload_likes(socket)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp reload_likes(socket) do
    likes = Likes.get_active_likes_for_entry(socket.assigns.entry_uri)

    assign_like_state(
      socket,
      likes,
      socket.assigns.current_scope,
      socket.assigns.entry_author_uri
    )
  end

  defp assign_like_state(socket, likes, scope, entry_author_uri) do
    person_uri = scope && scope.person.uri
    liked = person_uri && Enum.any?(likes, &(&1.author_uri == person_uri))
    can_like = not is_nil(person_uri) and person_uri != entry_author_uri

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
