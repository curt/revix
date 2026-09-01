defmodule RevixWeb.NotificationSettingsLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Revix.People

  describe "unauthenticated access" do
    test "redirects to sign-in", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/settings/notifications")
      assert path =~ "/people/signin"
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_person

    test "renders the settings form", %{conn: conn, person: person} do
      {:ok, view, html} = live(conn, ~p"/settings/notifications")
      assert html =~ "Email Notifications"
      assert has_element?(view, "#notification-settings-form")
      assert has_element?(view, ~s(option[value="daily"]))
      assert has_element?(view, ~s(option[value="monthly"]))

      # default cadence is :daily and the select reflects it
      assert view
             |> element("#notification-settings-form select")
             |> render() =~ ~s(<option selected="" value="daily">)

      assert People.get_person_by_email(person.email).notification_schedule == :daily
    end

    test "saves a new cadence", %{conn: conn, person: person} do
      {:ok, view, _html} = live(conn, ~p"/settings/notifications")

      html =
        view
        |> form("#notification-settings-form", notification: %{notification_schedule: "weekly"})
        |> render_submit()

      assert html =~ "Notification frequency updated."
      assert People.get_person_by_email(person.email).notification_schedule == :weekly
    end

    test "selecting Off persists :none", %{conn: conn, person: person} do
      {:ok, view, _html} = live(conn, ~p"/settings/notifications")

      view
      |> form("#notification-settings-form", notification: %{notification_schedule: "none"})
      |> render_submit()

      assert People.get_person_by_email(person.email).notification_schedule == :none
    end

    test "re-renders the form without changing state on an invalid value", %{
      conn: conn,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/settings/notifications")

      # "user" is an existing atom (a Role value) but not a valid cadence; sent
      # via render_hook to bypass the client-side select validation.
      html = render_hook(view, "save", %{"notification" => %{"notification_schedule" => "user"}})

      refute html =~ "Notification frequency updated."
      assert People.get_person_by_email(person.email).notification_schedule == :daily
    end
  end
end
