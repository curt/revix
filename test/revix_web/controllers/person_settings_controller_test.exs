defmodule RevixWeb.PersonSettingsControllerTest do
  use RevixWeb.ConnCase, async: true

  alias Revix.People
  import Revix.PeopleFixtures

  setup :register_and_log_in_person

  describe "GET /people/settings" do
    test "renders settings page", %{conn: conn} do
      conn = get(conn, ~p"/people/settings")
      response = html_response(conn, 200)
      assert response =~ "Settings"
    end

    test "redirects if person is not logged in" do
      conn = build_conn()
      conn = get(conn, ~p"/people/settings")
      assert redirected_to(conn) == ~p"/people/signin"
    end

    test "shows the email and password forms in sudo mode", %{conn: conn} do
      html = conn |> get(~p"/people/settings") |> html_response(200)

      assert html =~ ~s(id="update_email")
      assert html =~ ~s(id="update_password")
      refute html =~ "Re-confirm to change"
    end
  end

  describe "outside sudo mode" do
    @describetag token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)

    test "still shows the page with the profile forms", %{conn: conn} do
      html = conn |> get(~p"/people/settings") |> html_response(200)

      assert html =~ ~s(id="update_display_name")
      assert html =~ ~s(id="update_avatar")
    end

    test "replaces the email and password forms with a re-confirm link", %{conn: conn} do
      html = conn |> get(~p"/people/settings") |> html_response(200)

      refute html =~ ~s(id="update_email")
      refute html =~ ~s(id="update_password")
      assert html =~ "Re-confirm to change"
      assert html =~ ~s(href="/people/signin?return_to=%2Fpeople%2Fsettings")
    end

    test "accepts a display name change", %{conn: conn, person: person} do
      conn =
        put(conn, ~p"/people/settings", %{
          "action" => "update_display_name",
          "person" => %{"display_name" => "Fresh Name"}
        })

      assert redirected_to(conn) == ~p"/people/settings"
      assert People.get_person!(person.id).display_name == "Fresh Name"
    end

    test "still requires re-authentication to change the email", %{conn: conn} do
      conn =
        put(conn, ~p"/people/settings", %{
          "action" => "update_email",
          "person" => %{"email" => unique_person_email()}
        })

      assert redirected_to(conn) == ~p"/people/signin"
    end

    test "still requires re-authentication to change the password", %{conn: conn, person: person} do
      conn =
        put(conn, ~p"/people/settings", %{
          "action" => "update_password",
          "person" => %{
            "password" => "NewValidPass123!",
            "password_confirmation" => "NewValidPass123!"
          }
        })

      assert redirected_to(conn) == ~p"/people/signin"
      assert People.get_person_by_email_and_password(person.email, "NewValidPass123!") == nil
    end

    test "still requires re-authentication to confirm an email change", %{conn: conn} do
      conn = get(conn, ~p"/people/settings/confirm/some-token")
      assert redirected_to(conn) == ~p"/people/signin"
    end
  end

  describe "PUT /people/settings (change display name form)" do
    test "updates the person display name", %{conn: conn, person: person} do
      conn =
        put(conn, ~p"/people/settings", %{
          "action" => "update_display_name",
          "person" => %{"display_name" => "Alice"}
        })

      assert redirected_to(conn) == ~p"/people/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Display name updated successfully"

      assert People.get_person!(person.id).display_name == "Alice"
    end

    test "allows clearing the display name", %{conn: conn, person: person} do
      conn =
        put(conn, ~p"/people/settings", %{
          "action" => "update_display_name",
          "person" => %{"display_name" => ""}
        })

      assert redirected_to(conn) == ~p"/people/settings"
      assert People.get_person!(person.id).display_name == nil
    end

    test "does not update display name when too long", %{conn: conn} do
      conn =
        put(conn, ~p"/people/settings", %{
          "action" => "update_display_name",
          "person" => %{"display_name" => String.duplicate("a", 21)}
        })

      response = html_response(conn, 200)
      assert response =~ "Settings"
      assert response =~ "should be at most 20 character(s)"
    end
  end

  describe "PUT /people/settings (change password form)" do
    test "disconnects live sockets for the person's other sessions", %{conn: conn, person: person} do
      other_token = People.generate_person_session_token(person)
      other_topic = "people_sessions:#{Base.url_encode64(other_token)}"
      RevixWeb.Endpoint.subscribe(other_topic)

      put(conn, ~p"/people/settings", %{
        "action" => "update_password",
        "person" => %{
          "password" => "NewValidPass123!",
          "password_confirmation" => "NewValidPass123!"
        }
      })

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^other_topic}
    end

    test "updates the person password and resets tokens", %{conn: conn, person: person} do
      new_password_conn =
        put(conn, ~p"/people/settings", %{
          "action" => "update_password",
          "person" => %{
            "password" => "NewValidPass123!",
            "password_confirmation" => "NewValidPass123!"
          }
        })

      assert redirected_to(new_password_conn) == ~p"/people/settings"

      assert get_session(new_password_conn, :person_token) != get_session(conn, :person_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert People.get_person_by_email_and_password(person.email, "NewValidPass123!")
    end

    test "does not update password on invalid data", %{conn: conn} do
      old_password_conn =
        put(conn, ~p"/people/settings", %{
          "action" => "update_password",
          "person" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      response = html_response(old_password_conn, 200)
      assert response =~ "Settings"
      assert response =~ "should be at least 12 character(s)"
      assert response =~ "does not match password"

      assert get_session(old_password_conn, :person_token) == get_session(conn, :person_token)
    end
  end

  describe "PUT /people/settings (change avatar form)" do
    @tag :capture_log
    test "shows a rejected upload's error on the avatar form, not the password form", %{
      conn: conn
    } do
      path =
        Path.join(System.tmp_dir!(), "not-an-image-#{System.unique_integer([:positive])}.png")

      File.write!(path, "plain text, not a PNG")
      on_exit(fn -> File.rm(path) end)

      upload = %Plug.Upload{path: path, filename: "avatar.png", content_type: "image/png"}

      conn =
        put(conn, ~p"/people/settings", %{
          "action" => "update_avatar",
          "person" => %{"avatar" => upload}
        })

      doc = conn |> html_response(200) |> LazyHTML.from_document()
      avatar_form = doc |> LazyHTML.query("#update_avatar") |> LazyHTML.text()
      password_form = doc |> LazyHTML.query("#update_password") |> LazyHTML.text()

      assert avatar_form =~ "invalid file type"
      refute password_form =~ "invalid file type"
    end
  end

  describe "PUT /people/settings (change email form)" do
    @tag :capture_log
    test "updates the person email", %{conn: conn, person: person} do
      conn =
        put(conn, ~p"/people/settings", %{
          "action" => "update_email",
          "person" => %{"email" => unique_person_email()}
        })

      assert redirected_to(conn) == ~p"/people/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "A link to confirm your email"

      assert People.get_person_by_email(person.email)
    end

    test "does not update email on invalid data", %{conn: conn} do
      conn =
        put(conn, ~p"/people/settings", %{
          "action" => "update_email",
          "person" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ "Settings"
      assert response =~ "must have the @ sign and no spaces"
    end
  end

  describe "GET /people/settings/confirm/:token" do
    setup %{person: person} do
      email = unique_person_email()

      token =
        extract_person_token(fn url ->
          People.deliver_person_update_email_instructions(
            %{person | email: email},
            person.email,
            url
          )
        end)

      %{token: token, email: email}
    end

    test "updates the person email once", %{
      conn: conn,
      person: person,
      token: token,
      email: email
    } do
      conn = get(conn, ~p"/people/settings/confirm/#{token}")
      assert redirected_to(conn) == ~p"/people/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Email changed successfully"

      refute People.get_person_by_email(person.email)
      assert People.get_person_by_email(email)

      conn = get(conn, ~p"/people/settings/confirm/#{token}")

      assert redirected_to(conn) == ~p"/people/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired"
    end

    test "does not update email with invalid token", %{conn: conn, person: person} do
      conn = get(conn, ~p"/people/settings/confirm/oops")
      assert redirected_to(conn) == ~p"/people/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired"

      assert People.get_person_by_email(person.email)
    end

    test "redirects if person is not logged in", %{token: token} do
      conn = build_conn()
      conn = get(conn, ~p"/people/settings/confirm/#{token}")
      assert redirected_to(conn) == ~p"/people/signin"
    end
  end
end
