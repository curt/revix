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
    socket
    |> mount_current_scope(session)
    |> mount_site()
    |> continue_if_signed_in()
  end

  def on_mount(:require_owner, _params, _session, socket) do
    socket.assigns.current_scope
    |> Scope.owner?()
    |> continue_if_owner(socket)
  end

  defp continue_if_signed_in(%{assigns: %{current_scope: %Scope{}}} = socket),
    do: {:cont, socket}

  defp continue_if_signed_in(socket) do
    socket =
      socket
      |> put_flash(:error, "You must sign in to access this page.")
      |> redirect(to: ~p"/people/signin")

    {:halt, socket}
  end

  defp continue_if_owner(true, socket), do: {:cont, socket}

  defp continue_if_owner(false, socket) do
    socket =
      socket
      |> put_flash(:error, "You do not have permission to access this page.")
      |> redirect(to: ~p"/")

    {:halt, socket}
  end

  @doc """
  The scope for a LiveView session's `"person_token"`, or nil for a signed-out
  visitor or a token that no longer matches a session. Also used by LiveViews
  rendered with `live_render/3` outside a live_session.
  """
  def scope_from_session(%{"person_token" => token}) when is_binary(token) do
    token
    |> People.get_person_by_session_token()
    |> scope_for_session()
  end

  def scope_from_session(_session), do: nil

  defp scope_for_session({person, _token_inserted_at}), do: Scope.for_person(person)
  defp scope_for_session(nil), do: nil

  defp mount_current_scope(socket, session),
    do: assign(socket, :current_scope, scope_from_session(session))

  defp mount_site(socket) do
    assign(socket, :site, Sites.get_site_or_default(CanonicalRoutes.home_url()))
  end
end
