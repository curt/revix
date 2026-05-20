defmodule RevixWeb.Live.PersonAuth do
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]
  use RevixWeb, :verified_routes

  alias Revix.People
  alias Revix.People.Scope

  @doc """
  on_mount callbacks for LiveViews.

  - `:load_current_scope` — for public pages: always continues, assigns `current_scope` (nil when unauthenticated)
  - `:require_authenticated_person` — requires authentication, halts with redirect if unauthenticated
  """
  def on_mount(:load_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:require_authenticated_person, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.person do
      {:cont, socket}
    else
      socket =
        socket
        |> put_flash(:error, "You must sign in to access this page.")
        |> redirect(to: ~p"/people/signin")

      {:halt, socket}
    end
  end

  defp mount_current_scope(socket, session) do
    case session["person_token"] && People.get_person_by_session_token(session["person_token"]) do
      {person, _token_inserted_at} ->
        assign(socket, :current_scope, Scope.for_person(person))

      _ ->
        assign(socket, :current_scope, nil)
    end
  end
end
