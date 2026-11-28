defmodule RevixWeb.PersonSettingsController do
  use RevixWeb, :controller

  alias Revix.People
  alias RevixWeb.PersonAuth

  import RevixWeb.PersonAuth, only: [require_sudo_mode: 2]

  plug :require_sudo_for_credentials
  plug :assign_person_changesets

  # Changing the email or password needs a recent sign-in; the display name and
  # avatar don't, so the page itself is open to any signed-in person.
  @credential_actions ~w(update_email update_password)

  defp require_sudo_for_credentials(%{params: %{"action" => action}} = conn, opts)
       when action in @credential_actions,
       do: require_sudo_mode(conn, opts)

  defp require_sudo_for_credentials(%{private: %{phoenix_action: :confirm_email}} = conn, opts),
    do: require_sudo_mode(conn, opts)

  defp require_sudo_for_credentials(conn, _opts), do: conn

  def edit(conn, _params) do
    render(conn, :edit)
  end

  def update(conn, %{"action" => "update_display_name"} = params) do
    %{"person" => person_params} = params
    person = conn.assigns.current_scope.person

    case People.update_person_display_name(person, person_params) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Display name updated successfully.")
        |> redirect(to: ~p"/people/settings")

      {:error, changeset} ->
        render(conn, :edit, display_name_changeset: changeset)
    end
  end

  def update(conn, %{"action" => "update_email"} = params) do
    %{"person" => person_params} = params
    person = conn.assigns.current_scope.person

    case People.change_person_email(person, person_params) do
      %{valid?: true} = changeset ->
        People.deliver_person_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          person.email,
          &url(~p"/people/settings/confirm/#{&1}"),
          endpoint: RevixWeb.CanonicalRoutes.home_url()
        )

        conn
        |> put_flash(
          :info,
          "A link to confirm your email change has been sent to the new address."
        )
        |> redirect(to: ~p"/people/settings")

      changeset ->
        render(conn, :edit, email_changeset: %{changeset | action: :insert})
    end
  end

  def update(conn, %{"action" => "update_password"} = params) do
    %{"person" => person_params} = params
    person = conn.assigns.current_scope.person

    case People.update_person_password(person, person_params) do
      {:ok, {person, expired_tokens}} ->
        PersonAuth.disconnect_sessions(expired_tokens)

        conn
        |> put_flash(:info, "Password updated successfully.")
        |> put_session(:person_return_to, ~p"/people/settings")
        |> PersonAuth.log_in_person(person)

      {:error, changeset} ->
        render(conn, :edit, password_changeset: changeset)
    end
  end

  def update(conn, %{"action" => "update_avatar"} = params) do
    %{"person" => person_params} = params
    person = conn.assigns.current_scope.person

    case People.update_person_avatar(person, person_params) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Avatar updated successfully.")
        |> redirect(to: ~p"/people/settings")

      {:error, changeset} ->
        render(conn, :edit, avatar_changeset: changeset)
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case People.update_person_email(conn.assigns.current_scope.person, token) do
      {:ok, _person} ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> redirect(to: ~p"/people/settings")

      {:error, _} ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: ~p"/people/settings")
    end
  end

  defp assign_person_changesets(conn, _opts) do
    person = conn.assigns.current_scope.person

    conn
    |> assign(:sudo_mode, People.sudo_mode?(person, -10))
    |> assign(:display_name_changeset, People.change_person_display_name(person))
    |> assign(:email_changeset, People.change_person_email(person))
    |> assign(:password_changeset, People.change_person_password(person))
    |> assign(:avatar_changeset, People.change_person_avatar(person, %{avatar: nil}))
  end
end
