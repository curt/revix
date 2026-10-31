defmodule RevixWeb.CheckinSettingsLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Revix.People

  describe "unauthenticated access" do
    test "redirects to sign-in", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/settings/checkin")
      assert path =~ "/people/signin"
    end
  end

  describe "authenticated" do
    setup :register_and_log_in_person

    test "renders the settings form with auto-locate off by default", %{
      conn: conn,
      person: person
    } do
      {:ok, view, html} = live(conn, ~p"/settings/checkin")
      assert html =~ "Checkin"
      assert has_element?(view, "#checkin-settings-form")

      assert has_element?(
               view,
               ~s(input[type="checkbox"][name="checkin[auto_locate_on_checkin]"])
             )

      # default is off and the checkbox reflects it
      checkbox = element(view, ~s(#checkin-settings-form input[type="checkbox"]))
      refute render(checkbox) =~ "checked"

      assert People.get_person_by_email(person.email).auto_locate_on_checkin == false
    end

    test "saves auto-locate enabled", %{conn: conn, person: person} do
      {:ok, view, _html} = live(conn, ~p"/settings/checkin")

      html =
        view
        |> form("#checkin-settings-form", checkin: %{auto_locate_on_checkin: "true"})
        |> render_submit()

      assert html =~ "Checkin settings updated."
      assert People.get_person_by_email(person.email).auto_locate_on_checkin == true

      # the checkbox reflects the saved value
      checkbox = element(view, ~s(#checkin-settings-form input[type="checkbox"]))
      assert render(checkbox) =~ "checked"
    end

    test "saving with the checkbox unchecked turns auto-locate off", %{
      conn: conn,
      person: person
    } do
      {:ok, person} = People.update_checkin_preferences(person, %{auto_locate_on_checkin: true})
      {:ok, view, _html} = live(conn, ~p"/settings/checkin")

      view
      |> form("#checkin-settings-form", checkin: %{auto_locate_on_checkin: "false"})
      |> render_submit()

      assert People.get_person_by_email(person.email).auto_locate_on_checkin == false
    end
  end
end
