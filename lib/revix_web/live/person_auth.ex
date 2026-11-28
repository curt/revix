defmodule RevixWeb.Live.PersonAuth do
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]
  use RevixWeb, :verified_routes

  alias Revix.People
  alias Revix.People.Scope
  alias Revix.Sites
  alias RevixWeb.CanonicalRoutes

  @doc """
  on_mount callbacks for LiveViews.

  - `:load_current_scope` — for public pages: always continues, assigns `current_scope` (nil when unauthenticated)
  - `:require_authenticated_person` — requires authentication, halts with redirect if unauthenticated
  - `:require_owner` — after `:require_authenticated_person`, halts with redirect unless the
    person is the site owner (mirrors `RevixWeb.PersonAuth.require_role/2`)

  The first two also assign `:site`, so every LiveView has it available without a
  separate lookup (mirrors `RevixWeb.Plugs.LoadSite` for controller-rendered pages).
  """
  def on_mount(:load_current_scope, _params, session, socket) do
    {:cont, socket |> mount_current_scope(session) |> mount_site()}
  end

  def on_mount(:require_authenticated_person, _params, session, socket) do
    socket = socket |> mount_current_scope(session) |> mount_site()

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

  def on_mount(:require_owner, _params, _session, socket) do
    socket.assigns.current_scope
    |> Scope.owner?()
    |> continue_if_owner(socket)
  end

  defp continue_if_owner(true, socket), do: {:cont, socket}

  defp continue_if_owner(false, socket) do
    socket =
      socket
      |> put_flash(:error, "You do not have permission to access this page.")
      |> redirect(to: ~p"/")

    {:halt, socket}
  end

  defp mount_current_scope(socket, session) do
    case session["person_token"] && People.get_person_by_session_token(session["person_token"]) do
      {person, _token_inserted_at} ->
        assign(socket, :current_scope, Scope.for_person(person))

      _ ->
        assign(socket, :current_scope, nil)
    end
  end

  defp mount_site(socket) do
    assign(socket, :site, Sites.get_site_or_default(CanonicalRoutes.home_url()))
  end
end
