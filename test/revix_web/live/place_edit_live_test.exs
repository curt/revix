defmodule RevixWeb.PlaceEditLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Revix.PlacesFixtures

  alias Revix.Places

  # ── Authentication & Authorization ──────────────────────────────────────────

  describe "unauthenticated access" do
    test "redirects to sign-in when not authenticated", %{conn: conn} do
      place = place_fixture()
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/places/#{place.id}/edit")
      assert path =~ "/people/signin"
    end
  end

  describe "authorization" do
    setup :register_and_log_in_person

    test "redirects non-owner with flash error", %{conn: conn} do
      place = place_fixture()

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/places/#{place.id}/edit")

      assert path == "/places/#{place.id}"
      assert flash["error"] =~ "not authorized"
    end

    test "redirects to /places for nonexistent place", %{conn: conn, person: person} do
      Revix.People.set_person_role(person, :owner)
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/places/11111111111/edit")
      assert path == "/places"
    end
  end

  # ── Mount ────────────────────────────────────────────────────────────────────

  describe "authenticated mount as owner" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)

      place =
        place_fixture(%{
          name: "Test Cafe",
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      {:ok, place: place}
    end

    test "renders form pre-populated with place name", %{conn: conn, place: place} do
      {:ok, _view, html} = live(conn, ~p"/places/#{place.id}/edit")
      assert html =~ "Test Cafe"
    end

    test "renders form pre-populated with latitude and longitude", %{conn: conn, place: place} do
      {:ok, _view, html} = live(conn, ~p"/places/#{place.id}/edit")
      assert html =~ "40.0"
      assert html =~ "-105.0"
    end

    test "renders osm_type select and osm_id input", %{conn: conn, place: place} do
      {:ok, _view, html} = live(conn, ~p"/places/#{place.id}/edit")
      assert html =~ "OSM Type"
      assert html =~ "OSM ID"
    end

    test "does not show sync/unlink buttons when no OSM link", %{conn: conn, place: place} do
      {:ok, _view, html} = live(conn, ~p"/places/#{place.id}/edit")
      refute html =~ "Sync from OSM"
      refute html =~ "Unlink"
    end

    test "shows sync and unlink buttons when place has OSM link", %{conn: conn} do
      place = place_fixture(%{osm_type: :node, osm_id: 12345})

      {:ok, _view, html} = live(conn, ~p"/places/#{place.id}/edit")
      assert html =~ "Sync from OSM"
      assert html =~ "Unlink"
    end

    test "hides search nearby, OSM type, and OSM ID inputs when place has OSM link",
         %{conn: conn} do
      place = place_fixture(%{osm_type: :node, osm_id: 12345})

      {:ok, _view, html} = live(conn, ~p"/places/#{place.id}/edit")
      refute html =~ "Search nearby"
      refute html =~ "OSM Type"
      refute html =~ "OSM ID"
    end

    test "renders OSM type pre-populated when place has OSM link", %{conn: conn} do
      place = place_fixture(%{osm_type: :way, osm_id: 99999})

      {:ok, _view, html} = live(conn, ~p"/places/#{place.id}/edit")
      assert html =~ "99999"
    end
  end

  # ── Validate ─────────────────────────────────────────────────────────────────

  describe "validate" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      place = place_fixture()
      {:ok, place: place}
    end

    test "shows inline error for blank name", %{conn: conn, place: place} do
      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")

      html =
        view
        |> form("#place-edit-form", place: %{name: ""})
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end

    test "shows inline error for out-of-range latitude", %{conn: conn, place: place} do
      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")

      html =
        view
        |> form("#place-edit-form", place: %{name: "Test", latitude: "91.0", longitude: "-105.0"})
        |> render_change()

      assert html =~ "must be less than or equal to"
    end
  end

  # ── Save ─────────────────────────────────────────────────────────────────────

  describe "save" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      place = place_fixture(%{name: "Original Name"})
      {:ok, place: place}
    end

    test "updates name and redirects to place show", %{conn: conn, place: place} do
      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")

      {:ok, conn} =
        view
        |> form("#place-edit-form",
          place: %{name: "Updated Name", latitude: "40.0", longitude: "-105.0"}
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert conn.resp_body =~ "Updated Name"
      assert conn.request_path =~ "/places/#{place.id}"
    end

    test "returns validation errors without redirecting", %{conn: conn, place: place} do
      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")

      html =
        view
        |> form("#place-edit-form", place: %{name: "", latitude: "40.0", longitude: "-105.0"})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "can link a place to OSM by providing type and ID", %{conn: conn, place: place} do
      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")

      {:ok, _conn} =
        view
        |> form("#place-edit-form",
          place: %{
            name: "OSM Place",
            latitude: "40.0",
            longitude: "-105.0",
            osm_type: "node",
            osm_id: "55555"
          }
        )
        |> render_submit()
        |> follow_redirect(conn)

      {:ok, updated} = Places.get_local_place(place.id)
      assert updated.osm_type == :node
      assert updated.osm_id == 55_555
    end
  end

  # ── Unlink OSM ───────────────────────────────────────────────────────────────

  describe "unlink_osm" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      place = place_fixture(%{osm_type: :node, osm_id: 12345})
      {:ok, place: place}
    end

    test "clears osm_type and osm_id from the database", %{conn: conn, place: place} do
      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")

      render_click(view, "unlink_osm")

      {:ok, updated} = Places.get_local_place(place.id)
      assert updated.osm_type == nil
      assert updated.osm_id == nil
    end

    test "hides sync and unlink buttons after unlinking", %{conn: conn, place: place} do
      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")

      html = render_click(view, "unlink_osm")

      refute html =~ "Sync from OSM"
      refute html =~ "Unlink"
    end

    test "shows search nearby, OSM type, and OSM ID inputs after unlinking",
         %{conn: conn, place: place} do
      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")

      html = render_click(view, "unlink_osm")

      assert html =~ "Search nearby"
      assert html =~ "OSM Type"
      assert html =~ "OSM ID"
    end
  end

  # ── Search nearby ─────────────────────────────────────────────────────────────

  describe "search_nearby" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      place = place_fixture()
      {:ok, place: place}
    end

    test "shows nearby OSM results after search completes", %{conn: conn, place: place} do
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

      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")
      Req.Test.allow(:overpass, self(), view.pid)

      render_click(view, "search_nearby")
      html = wait_for_text(view, "Nearby Cafe")

      assert html =~ "Nearby Cafe"
      assert html =~ "OSM"
    end

    test "shows 'No places found nearby' when OSM returns empty", %{conn: conn, place: place} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{"elements" => []})
      end)

      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")
      Req.Test.allow(:overpass, self(), view.pid)

      render_click(view, "search_nearby")
      html = wait_until_text_absent(view, "Searching for nearby places")

      assert html =~ "No places found nearby"
    end

    test "selecting an OSM result pre-fills osm_type and osm_id", %{conn: conn, place: place} do
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

      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")
      Req.Test.allow(:overpass, self(), view.pid)

      render_click(view, "search_nearby")
      wait_for_text(view, "Big Building")

      html = render_click(view, "select_osm_result", %{"index" => "0"})

      assert html =~ "77777"
    end

    test "invalid OSM selection index does not crash", %{conn: conn, place: place} do
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

      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")
      Req.Test.allow(:overpass, self(), view.pid)

      render_click(view, "search_nearby")
      wait_for_text(view, "Big Building")

      html = render_click(view, "select_osm_result", %{"index" => "invalid"})

      assert html =~ "Edit Place"
      assert html =~ "Big Building"
    end

    test "toggle_osm_list collapses and expands the result list", %{conn: conn, place: place} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "node",
              "id" => 1,
              "lat" => 40.0,
              "lon" => -105.0,
              "tags" => %{"name" => "Some Place", "amenity" => "cafe"}
            }
          ]
        })
      end)

      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")
      Req.Test.allow(:overpass, self(), view.pid)

      render_click(view, "search_nearby")
      wait_for_text(view, "Some Place")

      html_collapsed = render_click(view, "toggle_osm_list")
      refute html_collapsed =~ "Some Place"

      html_expanded = render_click(view, "toggle_osm_list")
      assert html_expanded =~ "Some Place"
    end
  end

  # ── Sync from OSM ─────────────────────────────────────────────────────────────

  describe "sync_osm" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      place = place_fixture(%{osm_type: :node, osm_id: 12345})
      {:ok, place: place}
    end

    test "populates name and coordinates from OSM on success", %{conn: conn, place: place} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "node",
              "id" => 12345,
              "lat" => 51.5,
              "lon" => -0.1,
              "tags" => %{"name" => "Synced Name"}
            }
          ]
        })
      end)

      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")
      Req.Test.allow(:overpass, self(), view.pid)

      render_click(view, "sync_osm")
      html = wait_for_osm_sync(view)

      assert html =~ "Synced Name"
      assert html =~ "51.5"
      assert html =~ "-0.1"
    end

    test "shows inline error when OSM element not found", %{conn: conn, place: place} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{"elements" => []})
      end)

      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")
      Req.Test.allow(:overpass, self(), view.pid)

      render_click(view, "sync_osm")
      html = wait_for_osm_sync(view)

      assert html =~ "OSM element not found"
    end

    test "shows inline error on HTTP error", %{conn: conn, place: place} do
      Req.Test.stub(:overpass, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Plug.Conn.send_resp(500, "Server Error")
      end)

      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")
      Req.Test.allow(:overpass, self(), view.pid)

      render_click(view, "sync_osm")
      html = wait_for_osm_sync(view)

      assert html =~ "Failed to fetch from OSM"
    end

    test "clears spinner after sync completes", %{conn: conn, place: place} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "node",
              "id" => 12345,
              "lat" => 51.5,
              "lon" => -0.1,
              "tags" => %{"name" => "Done"}
            }
          ]
        })
      end)

      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")
      Req.Test.allow(:overpass, self(), view.pid)

      render_click(view, "sync_osm")
      html = wait_for_osm_sync(view)

      refute html =~ "loading-spinner loading-xs"
    end

    test "sync is available after selecting an OSM result without a prior saved link",
         %{conn: conn} do
      place = place_fixture()

      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "node",
              "id" => 55555,
              "lat" => 40.5,
              "lon" => -105.5,
              "tags" => %{"name" => "New Link"}
            }
          ]
        })
      end)

      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")
      Req.Test.allow(:overpass, self(), view.pid)

      render_click(view, "search_nearby")
      wait_for_text(view, "New Link")

      render_click(view, "select_osm_result", %{"index" => "0"})

      render_click(view, "sync_osm")
      html = wait_for_osm_sync(view)

      assert html =~ "New Link"
      assert html =~ "40.5"
      assert html =~ "-105.5"
    end

    test "ignores stale refs for sync task result and DOWN messages", %{conn: conn, place: place} do
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

      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/edit")
      Req.Test.allow(:overpass, self(), view.pid)

      stale_ref = make_ref()
      send(view.pid, {stale_ref, {:osm_sync, {:error, :not_found}}})
      send(view.pid, {:DOWN, stale_ref, :process, self(), :normal})

      render_click(view, "sync_osm")
      html_done = wait_for_osm_sync(view)
      assert html_done =~ "Nearby Cafe"
    end
  end

  # ── OSM badge on show page ────────────────────────────────────────────────────

  describe "OSM badge on place show page" do
    test "shows OSM badge when place has osm link", %{conn: conn} do
      place = place_fixture(%{osm_type: :node, osm_id: 12345})

      conn = get(conn, ~p"/places/#{place.id}")
      assert conn.resp_body =~ "openstreetmap.org/node/12345"
    end

    test "does not show OSM badge when place has no osm link", %{conn: conn} do
      place = place_fixture()

      conn = get(conn, ~p"/places/#{place.id}")
      refute conn.resp_body =~ "openstreetmap.org"
    end
  end
end
