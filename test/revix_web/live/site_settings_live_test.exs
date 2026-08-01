defmodule RevixWeb.SiteSettingsLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Revix.Sites

  describe "unauthenticated access" do
    test "redirects to sign-in when not authenticated", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/settings/site")
      assert path =~ "/people/signin"
    end
  end

  describe "authorization" do
    setup :register_and_log_in_person

    test "redirects non-owner with flash error", %{conn: conn} do
      {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, ~p"/settings/site")

      assert path == "/"
      assert flash["error"] =~ "not authorized"
    end
  end

  describe "authenticated mount as owner" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      :ok
    end

    test "renders default title and description when no site row exists", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/site")
      assert html =~ "Revix"
    end

    test "renders existing site title and description", %{conn: conn} do
      Sites.update_site(RevixWeb.CanonicalRoutes.home_url(), %{
        title: "My Custom Site",
        description: "A custom description"
      })

      {:ok, _view, html} = live(conn, ~p"/settings/site")
      assert html =~ "My Custom Site"
      assert html =~ "A custom description"
    end

    test "saves updated title and description", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/site")

      view
      |> form("#site-settings-form", site: %{title: "Updated Title", description: "Updated body"})
      |> render_submit()

      site = Sites.get_site(RevixWeb.CanonicalRoutes.home_url())
      assert site.title == "Updated Title"
      assert site.description == "Updated body"
    end

    test "renders a markdown preview on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/site")

      html =
        view
        |> form("#site-settings-form", site: %{title: "T", description: "**bold text**"})
        |> render_change()

      assert html =~ "<strong>bold text</strong>"
    end

    test "validate produces a valid changeset for a valid change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/site")

      view
      |> form("#site-settings-form", site: %{title: "Valid Title", description: "Valid body"})
      |> render_change()

      # Regression test: the validate handler previously rebuilt the changeset
      # from a bare `%Site{}` instead of `socket.assigns.site`, dropping the
      # (required) :endpoint field and making the changeset permanently
      # invalid regardless of user input. No error was visible in the
      # rendered HTML (the form has no :endpoint field), so this must inspect
      # the LiveView's internal form assign directly.
      form_source = :sys.get_state(view.pid).socket.assigns.form.source
      assert form_source.valid?
    end

    test "shows changeset errors when title exceeds max length", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/site")

      html =
        view
        |> form("#site-settings-form", site: %{title: String.duplicate("a", 256)})
        |> render_submit()

      assert html =~ "should be at most"
    end
  end
end
