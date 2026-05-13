defmodule RevixWeb.CheckinNewLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Revix.PlacesFixtures
  import Revix.PeopleFixtures

  alias Revix.EntryPeople
  alias Revix.People

  # ── Authentication ──────────────────────────────────────────────────────────

  describe "unauthenticated access" do
    test "redirects to sign in when not authenticated", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/checkins/new")
      assert path =~ "/people/signin"
    end
  end

  # ── Mount ───────────────────────────────────────────────────────────────────

  describe "authenticated mount" do
    setup :register_and_log_in_person

    test "renders new checkin form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/checkins/new")
      assert html =~ "New Checkin"
      assert html =~ "locate-btn"
      assert html =~ "Time Zone"
    end

    test "includes timezone select", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/checkins/new")
      assert html =~ "America/New_York"
      assert html =~ "Europe/London"
    end

    test "does not show manual place entry for non-owner", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/checkins/new")
      # Owner-only manual place entry should not appear before geolocation runs
      refute html =~ "Enter manually..."
    end

    test "shows place section and companion section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/checkins/new")
      assert html =~ "Companions"
      assert html =~ "Photos"
    end
  end

  # ── Owner vs Non-owner ──────────────────────────────────────────────────────

  describe "owner capabilities" do
    setup :register_and_log_in_person

    setup %{person: person} do
      People.set_person_role(person, :owner)
      Req.Test.stub(:overpass, fn conn -> Req.Test.json(conn, %{"elements" => []}) end)
      :ok
    end

    test "owner sees manual place entry option after locate", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      place = place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})

      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})
      html = render(view)

      assert html =~ place.name
      assert html =~ "Enter manually..."
    end
  end

  # ── Place Search (locate event) ──────────────────────────────────────────────

  describe "locate event" do
    setup :register_and_log_in_person

    setup do
      Req.Test.stub(:overpass, fn conn -> Req.Test.json(conn, %{"elements" => []}) end)
      :ok
    end

    test "renders place results after locate with nearby places", %{conn: conn} do
      place =
        place_fixture(%{
          name: "Test Cafe",
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})
      html = render(view)

      assert html =~ place.name
    end

    test "renders no place results when no places are nearby", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)

      # Far-away coordinates; no places in DB near there
      render_hook(view, "locate", %{lat: 0.0, lon: 0.0, accuracy: 5.0})
      html = wait_for_place_search(view)

      # No place list shown
      refute html =~ "Nearby Places"
    end

    test "select_place event marks a place as selected", %{conn: conn} do
      place_fixture(%{
        name: "Clicked Place",
        coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
      })

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})

      # Select the first result (index 0)
      render_click(view, "select_place", %{"index" => "0"})
      html = render(view)

      assert html =~ "Clicked Place"
      assert html =~ "Selected:"
    end
  end

  # ── Locate with mocked Overpass ───────────────────────────────────────────────

  describe "locate with mocked Overpass" do
    setup :register_and_log_in_person

    test "OSM returns places — shows them after task completes", %{conn: conn} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "node",
              "id" => 42,
              "lat" => 40.001,
              "lon" => -105.001,
              "tags" => %{"name" => "Test OSM Cafe", "amenity" => "cafe"}
            }
          ]
        })
      end)

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 100.0})
      html = wait_for_place_search(view)

      assert html =~ "Test OSM Cafe"
      refute html =~ "loading-spinner"
    end

    test "OSM returns empty — shows no-results message after loading", %{conn: conn} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{"elements" => []})
      end)

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 0.0, lon: 0.0, accuracy: 5.0})
      html = wait_for_place_search(view)

      assert html =~ "No places found nearby"
      refute html =~ "loading-spinner"
    end

    test "OSM returns HTTP error — DB results still shown, spinner gone", %{conn: conn} do
      place =
        place_fixture(%{
          name: "DB Only Place",
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      Req.Test.stub(:overpass, fn conn ->
        Plug.Conn.send_resp(conn, 429, "Too Many Requests")
      end)

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})
      html = wait_for_place_search(view)

      assert html =~ place.name
      refute html =~ "loading-spinner"
    end

    test "OSM transport error — LiveView survives, spinner gone", %{conn: conn} do
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 0.0, lon: 0.0, accuracy: 5.0})
      html = wait_for_place_search(view)

      refute html =~ "loading-spinner"
    end

    test "spinner is shown immediately after locate before OSM completes", %{conn: conn} do
      # Stub is required but we capture intermediate state right after render_hook
      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{"elements" => []})
      end)

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      # render_hook returns HTML of the current render (before task handle_info)
      html = render_hook(view, "locate", %{lat: 0.0, lon: 0.0, accuracy: 5.0})

      assert html =~ "loading-spinner"
      refute html =~ "No places found nearby"
    end
  end

  # ── set_defaults event ───────────────────────────────────────────────────────

  describe "set_defaults event" do
    setup :register_and_log_in_person

    test "prefills starts_at_local and starts_tz in form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")

      render_hook(view, "set_defaults", %{
        local_datetime: "2026-02-26T14:00",
        timezone: "America/Chicago"
      })

      html = render(view)
      assert html =~ "2026-02-26T14:00"
    end
  end

  # ── Companion management ─────────────────────────────────────────────────────

  describe "companion management" do
    setup :register_and_log_in_person

    test "search_companions returns matching people", %{conn: conn} do
      other = person_fixture()

      {:ok, other} =
        Revix.People.update_person_display_name(other, %{display_name: "AliceSearch"})

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      html = render_change(view, "search_companions", %{companion_query: "AliceSearch"})

      assert html =~ other.display_name
    end

    test "search_companions returns empty for blank query", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      html = render_change(view, "search_companions", %{companion_query: ""})

      # No suggestions list
      refute html =~ "add_companion"
    end

    test "add_companion adds person chip to pending list", %{conn: conn} do
      other = person_fixture()

      {:ok, other} =
        Revix.People.update_person_display_name(other, %{display_name: "BobCompanion"})

      {:ok, view, _html} = live(conn, ~p"/checkins/new")

      # Search to load into companion_results
      render_change(view, "search_companions", %{companion_query: "BobCompanion"})

      render_click(view, "add_companion", %{"uri" => other.uri})
      html = render(view)

      assert html =~ other.display_name
    end

    test "add_companion is idempotent — no duplicates", %{conn: conn} do
      other = person_fixture()

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      render_change(view, "search_companions", %{companion_query: "Carol"})
      render_click(view, "add_companion", %{"uri" => other.uri})
      render_click(view, "add_companion", %{"uri" => other.uri})

      html = render(view)
      # Only one chip for Carol
      count = html |> String.split("remove_companion") |> length()
      # 1 occurrence + 1 split = 2 parts means exactly 1 remove button
      assert count == 2
    end

    test "remove_companion removes person from pending list", %{conn: conn} do
      other = person_fixture(%{display_name: "Dave"})

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      render_change(view, "search_companions", %{companion_query: "Dave"})
      render_click(view, "add_companion", %{"uri" => other.uri})
      render_click(view, "remove_companion", %{"uri" => other.uri})

      html = render(view)
      refute html =~ "remove_companion"
    end

    test "cannot add self as companion", %{conn: conn, person: person} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      render_click(view, "add_companion", %{"uri" => person.uri})

      html = render(view)
      # No companion chips should appear
      refute html =~ "remove_companion"
    end
  end

  # ── Checkin creation ─────────────────────────────────────────────────────────

  describe "submit event — checkin creation" do
    setup :register_and_log_in_person

    setup do
      Req.Test.stub(:overpass, fn conn -> Req.Test.json(conn, %{"elements" => []}) end)
      :ok
    end

    test "creates checkin with an existing DB place", %{conn: conn, person: person} do
      People.set_person_role(person, :owner)
      place = place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})
      render_click(view, "select_place", %{"index" => "0"})

      {:error, {:redirect, %{to: _path}}} =
        view
        |> form("#checkin-form",
          checkin: %{
            starts_at_local: "2026-02-26T10:00",
            starts_tz: "America/New_York",
            content: "Great visit!"
          }
        )
        |> render_submit()

      # Verify checkin was created in DB
      checkins = Revix.Entries.get_local_checkins_for_place(place)
      assert length(checkins) == 1
      assert hd(checkins).place_uri == place.uri
    end

    test "creates checkin with new manual place for owner", %{conn: conn, person: person} do
      People.set_person_role(person, :owner)

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      render_click(view, "select_manual", %{})

      {:error, {:redirect, %{to: _path}}} =
        view
        |> form("#checkin-form",
          checkin: %{
            starts_at_local: "2026-02-26T10:00",
            starts_tz: "America/New_York"
          },
          place_manual: %{
            name: "My Cafe",
            latitude: "40.0",
            longitude: "-105.0"
          }
        )
        |> render_submit()

      places = Revix.Places.get_local_places()
      place = Enum.find(places, &(&1.name == "My Cafe"))
      assert place != nil

      checkins = Revix.Entries.get_local_checkins_for_place(place)
      assert length(checkins) == 1
    end

    test "non-owner cannot switch to manual place mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")

      # select_manual is ignored for non-owners; place_mode stays :none
      render_click(view, "select_manual", %{})

      # Submitting without a place selected shows "no place" error
      html =
        view
        |> form("#checkin-form",
          checkin: %{starts_at_local: "2026-02-26T10:00", starts_tz: "America/New_York"}
        )
        |> render_submit()

      assert html =~ "New Checkin"
    end

    test "companions are persisted atomically with checkin", %{conn: conn, person: person} do
      People.set_person_role(person, :owner)
      place = place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})
      other = person_fixture(%{display_name: "Eve"})

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})
      render_click(view, "select_place", %{"index" => "0"})

      render_change(view, "search_companions", %{companion_query: "Eve"})
      render_click(view, "add_companion", %{"uri" => other.uri})

      {:error, {:redirect, %{to: _path}}} =
        view
        |> form("#checkin-form",
          checkin: %{
            starts_at_local: "2026-02-26T10:00",
            starts_tz: "America/New_York"
          }
        )
        |> render_submit()

      checkins = Revix.Entries.get_local_checkins_for_place(place)
      assert length(checkins) == 1
      checkin = hd(checkins)
      assert EntryPeople.companion_of?(other.uri, checkin.uri)
    end

    test "re-renders form with errors when no place is selected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")

      html =
        view
        |> form("#checkin-form",
          checkin: %{starts_at_local: "2026-02-26T10:00", starts_tz: "America/New_York"}
        )
        |> render_submit()

      assert html =~ "New Checkin"
    end

    test "re-renders form with errors when checkin data is invalid", %{conn: conn} do
      place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})
      render_click(view, "select_place", %{"index" => "0"})

      # Submit without required starts_at_local (use UTC as valid tz to pass select validation)
      html =
        view
        |> form("#checkin-form", checkin: %{starts_at_local: "", starts_tz: "UTC"})
        |> render_submit()

      assert html =~ "New Checkin"
    end
  end

  # ── Upload UI ────────────────────────────────────────────────────────────────

  describe "file upload" do
    setup :register_and_log_in_person

    test "cancel_upload removes pending entry", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")

      upload =
        file_input(view, "#checkin-form", :images, [
          %{
            last_modified: 1_594_171_879_000,
            name: "test.jpg",
            content: :binary.copy(<<0>>, 100),
            size: 100,
            type: "image/jpeg"
          }
        ])

      render_upload(upload, "test.jpg")
      html = render(view)
      assert html =~ "test.jpg"

      # Extract the ref from the upload struct and cancel
      [%{"ref" => ref}] = upload.entries
      render_click(view, "cancel_upload", %{"ref" => ref})
      html = render(view)
      refute html =~ "test.jpg"
    end
  end

  # ── Image upload enhancements ─────────────────────────────────────────────────

  describe "image upload enhancements" do
    setup :register_and_log_in_person

    defp add_upload_entry(view, name) do
      upload =
        file_input(view, "#checkin-form", :images, [
          %{
            last_modified: 1_594_171_879_000,
            name: name,
            content: :binary.copy(<<0>>, 100),
            size: 100,
            type: "image/jpeg"
          }
        ])

      render_upload(upload, name)
      upload
    end

    test "update_caption stores caption for a pending upload entry", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      upload = add_upload_entry(view, "photo.jpg")
      [%{"ref" => ref}] = upload.entries

      render_hook(view, "update_caption", %{
        "_target" => ["photo_caption", ref],
        "photo_caption" => %{ref => "A great photo"}
      })

      html = render(view)
      assert html =~ "A great photo"
    end

    test "update_caption persists across re-renders", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      upload = add_upload_entry(view, "photo.jpg")
      [%{"ref" => ref}] = upload.entries

      render_hook(view, "update_caption", %{
        "_target" => ["photo_caption", ref],
        "photo_caption" => %{ref => "My caption"}
      })

      # Trigger a re-render (validate event) and check caption is still in the input
      render_change(view, "validate", %{"checkin" => %{"content" => "test"}})
      html = render(view)
      assert html =~ "My caption"
    end

    test "reorder_images stores the new ref order in assigns", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")

      upload_a = add_upload_entry(view, "a.jpg")
      upload_b = add_upload_entry(view, "b.jpg")

      [%{"ref" => ref_a}] = upload_a.entries
      [%{"ref" => ref_b}] = upload_b.entries

      # Reorder: b before a (order items are now objects, matching the JS hook format)
      render_hook(view, "reorder_images", %{"order" => [%{"ref" => ref_b}, %{"ref" => ref_a}]})

      assert :sys.get_state(view.pid).socket.assigns.upload_order == [ref_b, ref_a]
    end

    test "cancel_upload removes caption and order entry for that ref", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")

      keep_upload = add_upload_entry(view, "keep.jpg")
      drop_upload = add_upload_entry(view, "drop.jpg")

      [%{"ref" => keep_ref}] = keep_upload.entries
      [%{"ref" => drop_ref}] = drop_upload.entries

      # Set a caption for both and establish an order
      render_hook(view, "update_caption", %{
        "_target" => ["photo_caption", keep_ref],
        "photo_caption" => %{keep_ref => "Keep this"}
      })

      render_hook(view, "update_caption", %{
        "_target" => ["photo_caption", drop_ref],
        "photo_caption" => %{drop_ref => "Drop this"}
      })

      render_hook(view, "reorder_images", %{
        "order" => [%{"ref" => keep_ref}, %{"ref" => drop_ref}]
      })

      # Cancel the second entry
      render_click(view, "cancel_upload", %{"ref" => drop_ref})

      html = render(view)
      assert html =~ "keep.jpg"
      refute html =~ "drop.jpg"

      assigns = :sys.get_state(view.pid).socket.assigns
      assert Map.has_key?(assigns.upload_captions, keep_ref)
      refute Map.has_key?(assigns.upload_captions, drop_ref)
      refute drop_ref in assigns.upload_order
    end

    test "update_alt stores alt text for a pending upload entry", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      upload = add_upload_entry(view, "alt_photo.jpg")
      [%{"ref" => ref}] = upload.entries

      render_hook(view, "update_alt", %{
        "_target" => ["photo_alt", ref],
        "photo_alt" => %{ref => "A sunset photo"}
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert get_in(assigns, [:upload_captions, ref, :alt]) == "A sunset photo"
    end

    test "thumbnail container and caption input are rendered for each entry", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      _upload = add_upload_entry(view, "photo.jpg")

      html = render(view)
      # Upload entries container with hook
      assert html =~ ~s(id="upload-entries-new")
      assert html =~ ~s(phx-hook="ImageSort")
      # Caption input is rendered
      assert html =~ ~s(phx-change="update_caption")
      assert html =~ "Optional caption"
      # Drag handle icon
      assert html =~ "hero-bars-3"
    end
  end

  # ── Datetime window rule ─────────────────────────────────────────────────────

  describe "datetime window rule — new checkin" do
    setup :register_and_log_in_person

    setup do
      Req.Test.stub(:overpass, fn conn -> Req.Test.json(conn, %{"elements" => []}) end)
      :ok
    end

    defp recent_local_datetime do
      NaiveDateTime.utc_now(:second)
      |> NaiveDateTime.add(-30, :minute)
      |> NaiveDateTime.to_iso8601()
      |> String.slice(0, 16)
    end

    test "non-owner: rejects future datetime with validation error", %{conn: conn} do
      place = place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})
      render_click(view, "select_place", %{"index" => "0"})

      future =
        NaiveDateTime.utc_now(:second)
        |> NaiveDateTime.add(3600, :second)
        |> NaiveDateTime.to_iso8601()
        |> String.slice(0, 16)

      html =
        view
        |> form("#checkin-form", checkin: %{starts_at_local: future, starts_tz: "Etc/UTC"})
        |> render_submit()

      assert html =~ "must be in the past"
      refute Revix.Entries.get_local_checkins_for_place(place) != []
    end

    test "non-owner: rejects datetime older than lookback window", %{conn: conn} do
      _place = place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})
      render_click(view, "select_place", %{"index" => "0"})

      lookback = Application.get_env(:revix, :entry)[:checkin_lookback_hours] || 24

      too_old =
        NaiveDateTime.utc_now(:second)
        |> NaiveDateTime.add(-(lookback + 1), :hour)
        |> NaiveDateTime.to_iso8601()
        |> String.slice(0, 16)

      html =
        view
        |> form("#checkin-form", checkin: %{starts_at_local: too_old, starts_tz: "Etc/UTC"})
        |> render_submit()

      assert html =~ "must be within the last #{lookback} hours"
    end

    test "non-owner: accepts datetime within the lookback window", %{conn: conn} do
      place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})
      render_click(view, "select_place", %{"index" => "0"})

      {:error, {:redirect, %{to: _path}}} =
        view
        |> form("#checkin-form",
          checkin: %{starts_at_local: recent_local_datetime(), starts_tz: "Etc/UTC"}
        )
        |> render_submit()
    end

    test "owner: accepts future datetime", %{conn: conn, person: person} do
      People.set_person_role(person, :owner)
      place_fixture(%{coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}})

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})
      render_click(view, "select_place", %{"index" => "0"})

      future =
        NaiveDateTime.utc_now(:second)
        |> NaiveDateTime.add(3600, :second)
        |> NaiveDateTime.to_iso8601()
        |> String.slice(0, 16)

      {:error, {:redirect, %{to: _path}}} =
        view
        |> form("#checkin-form", checkin: %{starts_at_local: future, starts_tz: "Etc/UTC"})
        |> render_submit()
    end

    test "non-owner: datetime and timezone fields are visible on new checkin form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/checkins/new")
      assert html =~ "Date and Time"
      assert html =~ "Time Zone"
    end
  end

  # ── Issue 1: owner manual entry without locate ────────────────────────────────

  describe "owner manual entry without locate" do
    setup :register_and_log_in_person

    setup %{person: person} do
      People.set_person_role(person, :owner)
      :ok
    end

    test "owner can create checkin with manual place without clicking Locate me", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")

      {:error, {:redirect, %{to: _path}}} =
        view
        |> form("#checkin-form",
          checkin: %{starts_at_local: "2026-05-06T10:00", starts_tz: "America/Denver"},
          place_manual: %{name: "Hidden Gem", latitude: "40.1", longitude: "-105.1"}
        )
        |> render_submit()

      places = Revix.Places.get_local_places()
      assert Enum.any?(places, &(&1.name == "Hidden Gem"))
    end

    test "non-owner cannot create a place via manual params fallback", %{conn: _conn} do
      %{conn: conn} = register_and_log_in_person(%{conn: Phoenix.ConnTest.build_conn()})
      {:ok, view, _html} = live(conn, ~p"/checkins/new")

      # Non-owners don't see the place_manual fields so we submit the event directly
      html =
        render_submit(view, "submit", %{
          "checkin" => %{"starts_at_local" => "2026-05-06T10:00", "starts_tz" => "UTC"},
          "place_manual" => %{
            "name" => "Sneaky Place",
            "latitude" => "40.0",
            "longitude" => "-105.0"
          }
        })

      assert html =~ "New Checkin"
      places = Revix.Places.get_local_places()
      refute Enum.any?(places, &(&1.name == "Sneaky Place"))
    end
  end

  # ── Issue 2: lat/lon pre-population from geolocation ─────────────────────────

  describe "lat/lon pre-population from geolocation" do
    setup :register_and_log_in_person

    setup %{person: person} do
      People.set_person_role(person, :owner)
      Req.Test.stub(:overpass, fn conn -> Req.Test.json(conn, %{"elements" => []}) end)
      :ok
    end

    test "locate pre-populates lat/lon into place_changeset when fields are empty", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)

      render_hook(view, "locate", %{lat: 40.5, lon: -105.5, accuracy: 10.0})

      changeset = :sys.get_state(view.pid).socket.assigns.place_changeset
      assert changeset.changes[:latitude] == 40.5
      assert changeset.changes[:longitude] == -105.5
    end

    test "locate does not overwrite existing lat/lon values", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)

      render_change(view, "validate", %{
        "checkin" => %{},
        "place_manual" => %{"latitude" => "51.0", "longitude" => ""}
      })

      render_hook(view, "locate", %{lat: 40.5, lon: -105.5, accuracy: 10.0})

      changeset = :sys.get_state(view.pid).socket.assigns.place_changeset
      assert changeset.changes[:latitude] == 51.0
    end
  end

  # ── Issue 3: place_changeset survives re-render ───────────────────────────────

  describe "place changeset persisted across re-renders" do
    setup :register_and_log_in_person

    setup %{person: person} do
      People.set_person_role(person, :owner)

      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{
          "elements" => [
            %{
              "type" => "node",
              "id" => 99,
              "lat" => 40.001,
              "lon" => -105.001,
              "tags" => %{"name" => "OSM Result", "amenity" => "cafe"}
            }
          ]
        })
      end)

      :ok
    end

    test "manual lat/lon values survive OSM results arriving", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)

      # First fire locate to trigger the async OSM task
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 5.0})

      # Simulate user typing manual coordinates before OSM finishes
      render_change(view, "validate", %{
        "checkin" => %{},
        "place_manual" => %{"name" => "My Spot", "latitude" => "40.0", "longitude" => "-105.0"}
      })

      # Wait for OSM task to complete (triggers handle_info re-render)
      _html = wait_for_place_search(view)

      changeset = :sys.get_state(view.pid).socket.assigns.place_changeset
      assert changeset.changes[:latitude] == 40.0
    end
  end

  # ── Issue 4: selection preserved when OSM results arrive late ─────────────────

  describe "place selection preserved on late OSM results" do
    setup :register_and_log_in_person

    test "selection survives when selected place still present in merged results", %{conn: conn} do
      place =
        place_fixture(%{
          name: "Steady Place",
          coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
        })

      Req.Test.stub(:overpass, fn conn ->
        Req.Test.json(conn, %{"elements" => []})
      end)

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)

      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})
      render_click(view, "select_place", %{"index" => "0"})

      _html = wait_for_place_search(view)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.place_mode == :selected
      assert assigns.selected_place.name == place.name
    end

    test "selection is cleared when selected place no longer appears in merged results", %{
      conn: conn
    } do
      # Place is far away — won't appear in a tight-radius search around 0,0
      place_fixture(%{
        name: "Far Away Place",
        coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
      })

      # First locate near Colorado to pick up the place; user selects it
      Req.Test.stub(:overpass, fn conn -> Req.Test.json(conn, %{"elements" => []}) end)

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)

      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})
      render_click(view, "select_place", %{"index" => "0"})

      # Now simulate a second locate at a different location with no nearby places;
      # the OSM task arrives with an empty merge — selected place is gone
      render_hook(view, "locate", %{lat: 0.0, lon: 0.0, accuracy: 5.0})
      _html = wait_for_place_search(view)

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.place_mode == :none
      assert assigns.selected_place == nil
    end
  end

  # ── Issue 5: result limit ─────────────────────────────────────────────────────

  describe "nearby result limit" do
    test "merge_place_results honours nearby_result_limit config" do
      limit = Application.get_env(:revix, :places)[:nearby_result_limit] || 20

      osm_results =
        for i <- 1..30 do
          %{
            source: :osm,
            name: "Place #{i}",
            lat: 40.0,
            lon: -105.0,
            distance: i * 10.0,
            osm_type: :node,
            osm_id: i
          }
        end

      merged = Revix.Places.merge_place_results([], osm_results)
      assert length(merged) == limit
    end
  end

  # ── Issue 6: collapse / expand place list ────────────────────────────────────

  describe "place list collapse and expand" do
    setup :register_and_log_in_person

    setup do
      Req.Test.stub(:overpass, fn conn -> Req.Test.json(conn, %{"elements" => []}) end)
      :ok
    end

    test "selecting a place collapses the list", %{conn: conn} do
      place_fixture(%{
        name: "Collapsible Cafe",
        coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
      })

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})

      render_click(view, "select_place", %{"index" => "0"})
      html = render(view)

      assert :sys.get_state(view.pid).socket.assigns.place_list_open == false
      assert html =~ "Collapsible Cafe"
      refute html =~ "phx-value-index"
    end

    test "toggle_place_list re-expands the list", %{conn: conn} do
      place_fixture(%{
        name: "Expandable Spot",
        coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
      })

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})
      render_click(view, "select_place", %{"index" => "0"})

      render_click(view, "toggle_place_list", %{})
      html = render(view)

      assert :sys.get_state(view.pid).socket.assigns.place_list_open == true
      assert html =~ "phx-value-index"
    end

    test "toggle_place_list collapses an open list", %{conn: conn} do
      place_fixture(%{
        name: "Togglable Tavern",
        coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
      })

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})

      render_click(view, "toggle_place_list", %{})

      assert :sys.get_state(view.pid).socket.assigns.place_list_open == false
    end

    test "re-locating after collapse re-opens the list", %{conn: conn} do
      place_fixture(%{
        name: "Re-locate Roastery",
        coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
      })

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})

      assert :sys.get_state(view.pid).socket.assigns.place_list_open == true

      render_click(view, "toggle_place_list", %{})
      assert :sys.get_state(view.pid).socket.assigns.place_list_open == false

      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})
      assert :sys.get_state(view.pid).socket.assigns.place_list_open == true
    end

    test "selecting 'Enter manually' collapses the list", %{conn: conn, person: person} do
      Revix.People.set_person_role(person, :owner)

      place_fixture(%{
        name: "Manual Entry Cafe",
        coordinates: %Geo.Point{coordinates: {-105.0, 40.0}, srid: 4326}
      })

      {:ok, view, _html} = live(conn, ~p"/checkins/new")
      Req.Test.allow(:overpass, self(), view.pid)
      render_hook(view, "locate", %{lat: 40.0, lon: -105.0, accuracy: 10.0})

      assert :sys.get_state(view.pid).socket.assigns.place_list_open == true

      render_click(view, "select_manual", %{})

      assert :sys.get_state(view.pid).socket.assigns.place_list_open == false
      assert :sys.get_state(view.pid).socket.assigns.place_mode == :manual
    end
  end
end
