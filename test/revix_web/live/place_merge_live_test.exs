defmodule RevixWeb.PlaceMergeLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures

  alias Revix.EntryPlaces
  alias Revix.Places

  # ── Authentication & Authorization ──────────────────────────────────────────

  describe "unauthenticated access" do
    test "redirects to sign-in when not authenticated", %{conn: conn} do
      place = place_fixture()
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/places/#{place.id}/merge")
      assert path =~ "/people/signin"
    end
  end

  describe "authorization" do
    setup :register_and_log_in_person

    test "redirects non-owner with flash error", %{conn: conn} do
      place = place_fixture()

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/places/#{place.id}/merge")

      assert path == "/places/#{place.id}"
      assert flash["error"] =~ "not authorized"
    end

    test "redirects to /places for nonexistent place", %{conn: conn, person: person} do
      Revix.People.set_person_role(person, :owner)
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/places/11111111111/merge")
      assert path == "/places"
    end
  end

  # ── Mount ────────────────────────────────────────────────────────────────────

  describe "authenticated mount as owner" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)

      target =
        place_fixture(%{
          name: "Target Cafe",
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      {:ok, target: target}
    end

    test "renders target place name in heading", %{conn: conn, target: target} do
      {:ok, _view, html} = live(conn, ~p"/places/#{target.id}/merge")
      assert html =~ "Target Cafe"
    end

    test "shows no nearby places message when no candidates within range", %{
      conn: conn,
      target: target
    } do
      {:ok, _view, html} = live(conn, ~p"/places/#{target.id}/merge")
      assert html =~ "No other local places found nearby"
    end

    test "renders nearby candidate places", %{conn: conn, target: target} do
      nearby =
        place_fixture(%{
          name: "Nearby Spot",
          coordinates: %Geo.Point{coordinates: {-105.0001, 40.0001}, srid: 4326}
        })

      {:ok, _view, html} = live(conn, ~p"/places/#{target.id}/merge")
      assert html =~ nearby.name
    end

    test "does not list the target itself as a checkbox candidate", %{conn: conn, target: target} do
      place_fixture(%{
        name: "Nearby Spot",
        coordinates: %Geo.Point{coordinates: {-105.0001, 40.0001}, srid: 4326}
      })

      {:ok, _view, html} = live(conn, ~p"/places/#{target.id}/merge")
      # The target's ID must not appear as a phx-value-id on a checkbox.
      refute html =~ "phx-value-id=\"#{target.id}\""
    end

    test "Merge selected button is disabled initially", %{conn: conn, target: target} do
      place_fixture(%{
        name: "Nearby Spot",
        coordinates: %Geo.Point{coordinates: {-105.0001, 40.0001}, srid: 4326}
      })

      {:ok, _view, html} = live(conn, ~p"/places/#{target.id}/merge")
      assert html =~ "disabled"
    end
  end

  # ── toggle_select ────────────────────────────────────────────────────────────

  describe "toggle_select" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)

      target =
        place_fixture(%{
          name: "Target",
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      nearby =
        place_fixture(%{
          name: "Nearby",
          coordinates: %Geo.Point{coordinates: {-105.0001, 40.0001}, srid: 4326}
        })

      {:ok, target: target, nearby: nearby}
    end

    test "checking a place enables the Merge button", %{
      conn: conn,
      target: target,
      nearby: nearby
    } do
      {:ok, view, _html} = live(conn, ~p"/places/#{target.id}/merge")

      html = render_click(view, "toggle_select", %{"id" => nearby.id})
      refute html =~ ~r/disabled[^>]*>\s*<[^>]*hero-arrows-pointing-in/
    end

    test "unchecking a place disables the Merge button again", %{
      conn: conn,
      target: target,
      nearby: nearby
    } do
      {:ok, view, _html} = live(conn, ~p"/places/#{target.id}/merge")

      render_click(view, "toggle_select", %{"id" => nearby.id})
      html = render_click(view, "toggle_select", %{"id" => nearby.id})
      assert html =~ "disabled"
    end
  end

  # ── confirm / cancel_confirm ──────────────────────────────────────────────────

  describe "confirm and cancel_confirm" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)

      target =
        place_fixture(%{
          name: "Target",
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      nearby =
        place_fixture(%{
          name: "Nearby",
          coordinates: %Geo.Point{coordinates: {-105.0001, 40.0001}, srid: 4326}
        })

      {:ok, target: target, nearby: nearby}
    end

    test "confirm shows confirmation panel with selected place name", %{
      conn: conn,
      target: target,
      nearby: nearby
    } do
      {:ok, view, _html} = live(conn, ~p"/places/#{target.id}/merge")

      render_click(view, "toggle_select", %{"id" => nearby.id})
      html = render_click(view, "confirm", %{})

      assert html =~ "Confirm merge"
      assert html =~ nearby.name
    end

    test "confirm does nothing when nothing is selected", %{conn: conn, target: target} do
      {:ok, view, _html} = live(conn, ~p"/places/#{target.id}/merge")

      html = render_click(view, "confirm", %{})
      refute html =~ "Confirm merge"
    end

    test "cancel_confirm hides the confirmation panel", %{
      conn: conn,
      target: target,
      nearby: nearby
    } do
      {:ok, view, _html} = live(conn, ~p"/places/#{target.id}/merge")

      render_click(view, "toggle_select", %{"id" => nearby.id})
      render_click(view, "confirm", %{})
      html = render_click(view, "cancel_confirm", %{})

      refute html =~ "This cannot be undone."
    end
  end

  # ── merge ─────────────────────────────────────────────────────────────────────

  describe "merge" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)

      target =
        place_fixture(%{
          name: "Target",
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      nearby =
        place_fixture(%{
          name: "Nearby",
          coordinates: %Geo.Point{coordinates: {-105.0001, 40.0001}, srid: 4326}
        })

      {:ok, target: target, nearby: nearby}
    end

    test "merges places and redirects to target show page", %{
      conn: conn,
      target: target,
      nearby: nearby
    } do
      {:ok, view, _html} = live(conn, ~p"/places/#{target.id}/merge")

      render_click(view, "toggle_select", %{"id" => nearby.id})
      render_click(view, "confirm", %{})

      {:ok, conn} =
        view
        |> render_click("merge", %{})
        |> follow_redirect(conn)

      assert conn.resp_body =~ "Places merged successfully"
      assert conn.request_path =~ "/places/#{target.id}"
    end

    test "deletes source place after merge", %{conn: conn, target: target, nearby: nearby} do
      {:ok, view, _html} = live(conn, ~p"/places/#{target.id}/merge")

      render_click(view, "toggle_select", %{"id" => nearby.id})
      render_click(view, "confirm", %{})
      render_click(view, "merge", %{})

      assert {:error, :not_found} = Places.get_local_place(nearby.id)
    end

    test "reassigns checkins to target after merge", %{
      conn: conn,
      target: target,
      nearby: nearby
    } do
      checkin = checkin_fixture(%{place_uri: nearby.uri})

      {:ok, view, _html} = live(conn, ~p"/places/#{target.id}/merge")

      render_click(view, "toggle_select", %{"id" => nearby.id})
      render_click(view, "confirm", %{})
      render_click(view, "merge", %{})

      updated = Revix.Repo.get(Revix.Entries.Entry, checkin.id)
      assert updated.place_uri == target.uri
    end

    test "reassigns entry_places to target after merge", %{
      conn: conn,
      target: target,
      nearby: nearby
    } do
      post = post_fixture()
      {:ok, _} = EntryPlaces.add_place(post.uri, nearby.uri)

      {:ok, view, _html} = live(conn, ~p"/places/#{target.id}/merge")

      render_click(view, "toggle_select", %{"id" => nearby.id})
      render_click(view, "confirm", %{})
      render_click(view, "merge", %{})

      assert EntryPlaces.place_of?(target.uri, post.uri)
      refute EntryPlaces.place_of?(nearby.uri, post.uri)
    end

    test "shows error flash when merge fails (source already deleted)", %{
      conn: conn,
      target: target,
      nearby: nearby
    } do
      {:ok, view, _html} = live(conn, ~p"/places/#{target.id}/merge")

      render_click(view, "toggle_select", %{"id" => nearby.id})
      render_click(view, "confirm", %{})

      # Delete the source place underneath the LiveView
      Revix.Repo.delete!(nearby)

      html = render_click(view, "merge", %{})
      assert html =~ "Merge failed"
    end
  end
end
