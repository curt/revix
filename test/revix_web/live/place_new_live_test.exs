defmodule RevixWeb.PlaceNewLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Revix.PeopleFixtures

  alias Revix.Places

  # ── Authentication ────────────────────────────────────────────────────────────

  describe "unauthenticated access" do
    test "redirects to sign-in when not authenticated", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/places/new")
      assert path =~ "/people/signin"
    end
  end

  # ── Authorization ─────────────────────────────────────────────────────────────

  describe "non-owner access" do
    setup :register_and_log_in_person

    test "redirects non-owner with flash error", %{conn: conn} do
      {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, ~p"/places/new")
      assert path == "/places"
      assert flash["error"] =~ "not authorized"
    end
  end

  # ── Mount ─────────────────────────────────────────────────────────────────────

  describe "owner mount" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      :ok
    end

    test "renders new place form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/places/new")
      assert html =~ "New Place"
      assert html =~ "Name"
      assert html =~ "Latitude"
      assert html =~ "Longitude"
    end

    test "renders locate button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/places/new")
      assert html =~ "locate-btn"
      assert html =~ "Locate me"
    end

    test "renders OSM type and OSM ID inputs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/places/new")
      assert html =~ "OSM Type"
      assert html =~ "OSM ID"
    end

    test "does not show sync button when OSM fields are empty", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/places/new")
      refute html =~ "Sync from OSM"
    end

    test "shows search nearby button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/places/new")
      assert html =~ "Search nearby"
    end
  end

  # ── Validate ──────────────────────────────────────────────────────────────────

  describe "validate" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      :ok
    end

    test "shows inline error for blank name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places/new")

      html =
        view
        |> form("#place-new-form", place: %{name: "", latitude: "40.0", longitude: "-105.0"})
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end

    test "shows inline error for out-of-range latitude", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places/new")

      html =
        view
        |> form("#place-new-form", place: %{name: "Test", latitude: "91.0", longitude: "-105.0"})
        |> render_change()

      assert html =~ "must be less than or equal to"
    end

    test "shows inline error for out-of-range longitude", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places/new")

      html =
        view
        |> form("#place-new-form", place: %{name: "Test", latitude: "40.0", longitude: "181.0"})
        |> render_change()

      assert html =~ "must be less than or equal to"
    end

    test "osm_type and osm_id inputs persist through validate", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places/new")

      html =
        view
        |> form("#place-new-form",
          place: %{
            name: "X",
            latitude: "40.0",
            longitude: "-105.0",
            osm_type: "node",
            osm_id: "9999"
          }
        )
        |> render_change()

      assert html =~ "9999"
    end

    test "sync button appears when both osm_type and osm_id are filled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places/new")

      html =
        view
        |> form("#place-new-form",
          place: %{
            name: "X",
            latitude: "40.0",
            longitude: "-105.0",
            osm_type: "node",
            osm_id: "9999"
          }
        )
        |> render_change()

      assert html =~ "Sync from OSM"
    end
  end

  # ── Locate event ──────────────────────────────────────────────────────────────

  describe "locate event" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      :ok
    end

    test "pre-fills lat/lon in form when fields are empty", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places/new")

      html = render_hook(view, "locate", %{lat: 51.5, lon: -0.1, accuracy: 20.0})

      assert html =~ "51.5"
      assert html =~ "-0.1"
    end

    test "does not overwrite lat/lon when already set", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places/new")

      view
      |> form("#place-new-form", place: %{name: "X", latitude: "40.0", longitude: "-105.0"})
      |> render_change()

      html = render_hook(view, "locate", %{lat: 51.5, lon: -0.1, accuracy: 20.0})

      assert html =~ "40.0"
      assert html =~ "-105.0"
      refute html =~ "51.5"
    end
  end

  # ── Save ──────────────────────────────────────────────────────────────────────

  describe "save" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      :ok
    end

    test "creates place and redirects to place show page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places/new")

      {:ok, conn} =
        view
        |> form("#place-new-form",
          place: %{name: "New Cafe", latitude: "40.0", longitude: "-105.0"}
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert conn.resp_body =~ "New Cafe"
      assert conn.request_path =~ "/places/"
    end

    test "shows validation errors and stays on page when name is blank", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places/new")

      html =
        view
        |> form("#place-new-form", place: %{name: "", latitude: "40.0", longitude: "-105.0"})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert html =~ "New Place"
    end

    test "persists osm_type and osm_id on create", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places/new")

      {:ok, _conn} =
        view
        |> form("#place-new-form",
          place: %{
            name: "OSM Cafe",
            latitude: "40.0",
            longitude: "-105.0",
            osm_type: "node",
            osm_id: "77777"
          }
        )
        |> render_submit()
        |> follow_redirect(conn)

      places = Places.get_local_places()
      assert length(places) == 1
      [place] = places
      assert place.name == "OSM Cafe"
      assert place.osm_type == :node
      assert place.osm_id == 77_777
    end
  end

  # ── Sync from OSM ─────────────────────────────────────────────────────────────

  describe "sync_osm" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      :ok
    end

    test "populates name and coordinates from OSM on success", %{conn: conn} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "node",
              "id" => 12345,
              "lat" => 51.5,
              "lon" => -0.1,
              "tags" => %{"name" => "Synced Place"}
            }
          ]
        })
      end)

      {:ok, view, _html} = live(conn, ~p"/places/new")
      Req.Test.allow(:overpass, self(), view.pid)

      view
      |> form("#place-new-form",
        place: %{name: "", latitude: "", longitude: "", osm_type: "node", osm_id: "12345"}
      )
      |> render_change()

      render_click(view, "sync_osm")
      html = wait_for_osm_sync(view)

      assert html =~ "Synced Place"
      assert html =~ "51.5"
      assert html =~ "-0.1"
    end

    test "shows inline error when OSM element not found", %{conn: conn} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{"elements" => []})
      end)

      {:ok, view, _html} = live(conn, ~p"/places/new")
      Req.Test.allow(:overpass, self(), view.pid)

      view
      |> form("#place-new-form",
        place: %{name: "", latitude: "", longitude: "", osm_type: "node", osm_id: "99999"}
      )
      |> render_change()

      render_click(view, "sync_osm")
      html = wait_for_osm_sync(view)

      assert html =~ "OSM element not found"
    end

    test "shows inline error on HTTP failure", %{conn: conn} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      {:ok, view, _html} = live(conn, ~p"/places/new")
      Req.Test.allow(:overpass, self(), view.pid)

      view
      |> form("#place-new-form",
        place: %{name: "", latitude: "", longitude: "", osm_type: "node", osm_id: "1"}
      )
      |> render_change()

      render_click(view, "sync_osm")
      html = wait_for_osm_sync(view)

      assert html =~ "Failed to fetch from OSM"
    end

    test "does nothing when osm_type and osm_id are blank", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places/new")

      html_before = render(view)
      render_click(view, "sync_osm")
      html_after = render(view)

      assert html_before == html_after
    end
  end

  # ── Task DOWN handler ─────────────────────────────────────────────────────────

  describe "task DOWN handler" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      :ok
    end

    test "clears osm_sync_loading and shows error on unexpected task crash", %{conn: conn} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      {:ok, view, _html} = live(conn, ~p"/places/new")
      Req.Test.allow(:overpass, self(), view.pid)

      view
      |> form("#place-new-form",
        place: %{name: "", latitude: "", longitude: "", osm_type: "node", osm_id: "1"}
      )
      |> render_change()

      render_click(view, "sync_osm")
      html = wait_for_osm_sync(view)

      refute html =~ "loading-spinner loading-xs"
    end
  end

  # ── Search nearby ─────────────────────────────────────────────────────────────

  describe "search_nearby" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      :ok
    end

    defp wait_for_osm_results(view, text) do
      Enum.reduce_while(1..30, Phoenix.LiveViewTest.render(view), fn _, _ ->
        h = Phoenix.LiveViewTest.render(view)

        if h =~ text,
          do: {:halt, h},
          else:
            (
              Process.sleep(20)
              {:cont, h}
            )
      end)
    end

    defp wait_for_osm_search_done(view) do
      Enum.reduce_while(1..30, Phoenix.LiveViewTest.render(view), fn _, _ ->
        h = Phoenix.LiveViewTest.render(view)

        if h =~ "Searching for nearby places",
          do:
            (
              Process.sleep(20)
              {:cont, h}
            ),
          else: {:halt, h}
      end)
    end

    test "search nearby button is visible on mount", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/places/new")
      assert html =~ "Search nearby"
    end

    test "shows nearby OSM results after search completes", %{conn: conn} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "node",
              "id" => 9000,
              "lat" => 40.001,
              "lon" => -105.001,
              "tags" => %{"name" => "Nearby Cafe", "amenity" => "cafe"}
            }
          ]
        })
      end)

      {:ok, view, _html} = live(conn, ~p"/places/new")
      Req.Test.allow(:overpass, self(), view.pid)

      view
      |> form("#place-new-form", place: %{name: "", latitude: "40.0", longitude: "-105.0"})
      |> render_change()

      render_click(view, "search_nearby")
      html = wait_for_osm_results(view, "Nearby Cafe")

      assert html =~ "Nearby Cafe"
      assert html =~ "OSM"
    end

    test "shows 'No places found nearby' when OSM returns empty", %{conn: conn} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{"elements" => []})
      end)

      {:ok, view, _html} = live(conn, ~p"/places/new")
      Req.Test.allow(:overpass, self(), view.pid)

      view
      |> form("#place-new-form", place: %{name: "", latitude: "40.0", longitude: "-105.0"})
      |> render_change()

      render_click(view, "search_nearby")
      html = wait_for_osm_search_done(view)

      assert html =~ "No places found nearby"
    end

    test "selecting an OSM result pre-fills osm_type and osm_id", %{conn: conn} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "way",
              "id" => 77777,
              "center" => %{"lat" => 40.001, "lon" => -105.001},
              "tags" => %{"name" => "Big Building", "tourism" => "museum"}
            }
          ]
        })
      end)

      {:ok, view, _html} = live(conn, ~p"/places/new")
      Req.Test.allow(:overpass, self(), view.pid)

      view
      |> form("#place-new-form", place: %{name: "", latitude: "40.0", longitude: "-105.0"})
      |> render_change()

      render_click(view, "search_nearby")
      wait_for_osm_results(view, "Big Building")

      html = render_click(view, "select_osm_result", %{"index" => "0"})

      assert html =~ "77777"
    end

    test "toggle_osm_list collapses and expands the result list", %{conn: conn} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "node",
              "id" => 1,
              "lat" => 40.0,
              "lon" => -105.0,
              "tags" => %{"name" => "Togglable Place"}
            }
          ]
        })
      end)

      {:ok, view, _html} = live(conn, ~p"/places/new")
      Req.Test.allow(:overpass, self(), view.pid)

      view
      |> form("#place-new-form", place: %{name: "", latitude: "40.0", longitude: "-105.0"})
      |> render_change()

      render_click(view, "search_nearby")
      wait_for_osm_results(view, "Togglable Place")

      html = render_click(view, "toggle_osm_list")
      refute html =~ "Togglable Place"

      html = render_click(view, "toggle_osm_list")
      assert html =~ "Togglable Place"
    end

    test "search nearby does nothing when lat/lon are blank", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/places/new")

      html_before = render(view)
      render_click(view, "search_nearby")
      html_after = render(view)

      assert html_before == html_after
    end
  end

  # ── Nav menu item ─────────────────────────────────────────────────────────────

  describe "nav menu item" do
    test "shows New Place link for owner", %{conn: conn} do
      person = person_fixture()
      Revix.People.set_person_role(person, :owner)
      conn = log_in_person(conn, person)

      {:ok, _view, html} = live(conn, ~p"/places/new")
      assert html =~ "New Place"
      assert html =~ ~s(/places/new)
    end

    test "does not show New Place link for non-owner", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)

      conn = get(conn, ~p"/places")
      refute conn.resp_body =~ ~s(href="/places/new")
    end
  end
end
