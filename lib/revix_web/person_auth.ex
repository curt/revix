defmodule RevixWeb.PersonAuth do
  use RevixWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Revix.People
  alias Revix.People.Scope

  # Make the remember me cookie valid for 14 days. This should match
  # the session validity setting in PersonToken.
  @max_cookie_age_in_days 14
  @remember_me_cookie "_revix_web_person_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]

  # How old the session token should be before a new one is issued. When a request is made
  # with a session token older than this value, then a new session token will be created
  # and the session and remember-me cookies (if set) will be updated with the new token.
  # Lowering this value will result in more tokens being created by active users. Increasing
  # it will result in less time before a session token expires for a user to get issued a new
  # token. This can be set to a value greater than `@max_cookie_age_in_days` to disable
  # the reissuing of tokens completely.
  @session_reissue_age_in_days 7

  @doc """
  Logs the person in.

  Redirects to the session's `:person_return_to` path
  or falls back to the `signed_in_path/1`.
  """
  def log_in_person(conn, person, params \\ %{}) do
    person_return_to = get_session(conn, :person_return_to)

    conn
    |> create_or_extend_session(person, params)
    |> redirect(to: person_return_to || signed_in_path(conn))
  end

  @doc """
  Logs the person out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_person(conn) do
    person_token = get_session(conn, :person_token)
    person_token && People.delete_person_session_token(person_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      RevixWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  Disconnects the live sockets of expired session tokens, such as the ones
  `Revix.People.update_person_password/2` deletes, so open LiveViews in other
  browsers don't stay signed in.
  """
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      RevixWeb.Endpoint.broadcast(person_session_topic(token), "disconnect", %{})
    end)
  end

  @doc """
  Authenticates the person by looking into the session and remember me token.

  Will reissue the session token if it is older than the configured age.
  """
  def fetch_current_scope_for_person(conn, _opts) do
    with {token, conn} <- ensure_person_token(conn),
         {person, token_inserted_at} <- People.get_person_by_session_token(token) do
      conn
      |> assign(:current_scope, Scope.for_person(person))
      |> maybe_reissue_person_session_token(person, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, Scope.for_person(nil))
    end
  end

  defp ensure_person_token(conn) do
    if token = get_session(conn, :person_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, conn |> put_token_in_session(token) |> put_session(:person_remember_me, true)}
      else
        nil
      end
    end
  end

  # Reissue the session token if it is older than the configured reissue age.
  defp maybe_reissue_person_session_token(conn, person, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, person, %{})
    else
      conn
    end
  end

  # This function is the one responsible for creating session tokens
  # and storing them safely in the session and cookies. It may be called
  # either when logging in, during sudo mode, or to renew a session which
  # will soon expire.
  #
  # When the session is created, rather than extended, the renew_session
  # function will clear the session to avoid fixation attacks. See the
  # renew_session function to customize this behaviour.
  defp create_or_extend_session(conn, person, params) do
    token = People.generate_person_session_token(person)
    remember_me = get_session(conn, :person_remember_me)

    conn
    |> renew_session(person)
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params, remember_me)
  end

  # Do not renew session if the person is already logged in
  # to prevent CSRF errors or data being lost in tabs that are still open
  defp renew_session(conn, person) when conn.assigns.current_scope.person.id == person.id do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after sign in/sign out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn, _person) do
  #       delete_csrf_token()
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn, _person) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, _),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:person_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  # The live socket id lets log_out_person/1 and disconnect_sessions/1 close
  # the LiveViews opened with this session.
  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:person_token, token)
    |> put_session(:live_socket_id, person_session_topic(token))
  end

  defp person_session_topic(token), do: "people_sessions:#{Base.url_encode64(token)}"

  @doc """
  Plug for routes that require sudo mode.
  """
  def require_sudo_mode(conn, _opts) do
    if People.sudo_mode?(conn.assigns.current_scope.person, -10) do
      conn
    else
      conn
      |> put_flash(:error, "You must re-authenticate to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/people/signin")
      |> halt()
    end
  end

  @doc """
  Plug for routes that require the person to not be authenticated.
  """
  def redirect_if_person_is_authenticated(%{assigns: %{current_scope: %Scope{}}} = conn, _opts) do
    conn |> redirect(to: signed_in_path(conn)) |> halt()
  end

  def redirect_if_person_is_authenticated(conn, _opts), do: conn

  defp signed_in_path(_conn), do: ~p"/"

  @doc """
  Plug for routes that require the person to be authenticated.
  """
  def require_authenticated_person(%{assigns: %{current_scope: %Scope{}}} = conn, _opts),
    do: conn

  def require_authenticated_person(conn, _opts) do
    conn
    |> put_flash(:error, "You must sign in to access this page.")
    |> maybe_store_return_to()
    |> redirect(to: ~p"/people/signin")
    |> halt()
  end

  @doc """
  Plug for routes that require a specific role.

  Usage in router:

      plug :require_role, :owner
  """
  def require_role(conn, role) when is_atom(role) do
    if conn.assigns.current_scope && conn.assigns.current_scope.role == role do
      conn
    else
      conn
      |> put_flash(:error, "You do not have permission to access this page.")
      |> redirect(to: signed_in_path(conn))
      |> halt()
    end
  end

  @doc """
  Remembers where to send the person after they sign in, from the sign-in page.

  An explicit `return_to` param wins (the comment section's sign-in link sets
  it). Otherwise a return path already in the session is kept, because a
  protected page that bounced here stored it and the browser still sends the
  earlier page's Referer. Failing both, a same-site Referer is used.

  Only plain local paths are stored, so this can't become an open redirect:
  `//host`, backslashes (browsers read `/\\host` as `//host`) and whitespace or
  control characters (browsers strip a tab in `/\\t/host`) are rejected.
  """
  def store_return_to(conn, %{"return_to" => path}) when is_binary(path),
    do: maybe_put_return_to(conn, path)

  def store_return_to(conn, _params) do
    conn
    |> get_session(:person_return_to)
    |> referer_fallback(conn)
  end

  defp referer_fallback(nil, conn), do: maybe_put_return_to(conn, same_site_referer_path(conn))
  defp referer_fallback(_stored, conn), do: conn

  defp same_site_referer_path(conn) do
    conn
    |> get_req_header("referer")
    |> List.first()
    |> referer_path()
  end

  defp referer_path(nil), do: nil

  defp referer_path(url) do
    url
    |> URI.parse()
    |> same_site_path(URI.parse(RevixWeb.Endpoint.url()))
  end

  defp same_site_path(%URI{scheme: scheme, host: host, port: port} = referer, %URI{
         scheme: scheme,
         host: host,
         port: port
       }),
       do: URI.to_string(%URI{path: referer.path, query: referer.query})

  defp same_site_path(_referer, _site), do: nil

  defp maybe_put_return_to(conn, path) do
    path
    |> storable_return_to?()
    |> put_return_to(conn, path)
  end

  defp put_return_to(true, conn, path), do: put_session(conn, :person_return_to, path)
  defp put_return_to(false, conn, _path), do: conn

  defp storable_return_to?("/people/signin" <> _), do: false
  defp storable_return_to?("//" <> _), do: false

  defp storable_return_to?("/" <> _ = path),
    do: not String.contains?(path, "\\") and not Regex.match?(~r/[\x00-\x20\x7F]/, path)

  defp storable_return_to?(_path), do: false

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :person_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn
end
