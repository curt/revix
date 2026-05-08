defmodule RevixWeb.CheckinFromPlaceLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Revix.PlacesFixtures
  import Revix.PeopleFixtures

  alias Revix.Entries

  # ── Authentication & Authorization ──────────────────────────────────────────

  describe "unauthenticated access" do
    test "redirects to sign in when not authenticated", %{conn: conn} do
      place = place_fixture()
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/places/#{place.id}/checkins/new")
      assert path =~ "/people/signin"
    end
  end

  describe "authorization" do
    setup :register_and_log_in_person

    test "redirects non-owner to /checkins/new with flash error", %{conn: conn} do
      place = place_fixture()

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/places/#{place.id}/checkins/new")

      assert path == "/checkins/new"
      assert flash["error"] =~ "not authorized"
    end

    test "redirects to /places for nonexistent place", %{conn: conn, person: person} do
      Revix.People.set_person_role(person, :owner)
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/places/11111111111/checkins/new")
      assert path == "/places"
    end
  end

  # ── Mount ────────────────────────────────────────────────────────────────────

  describe "authenticated mount as owner" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      place = place_fixture(%{slug: "test-cafe"})
      {:ok, place: place}
    end

    test "renders place name in header", %{conn: conn, place: place} do
      {:ok, _view, html} = live(conn, ~p"/places/#{place.id}/checkins/new")
      assert html =~ place.name
    end

    test "does not render place search UI", %{conn: conn, place: place} do
      {:ok, _view, html} = live(conn, ~p"/places/#{place.id}/checkins/new")
      refute html =~ "locate-btn"
      refute html =~ "Locate me"
      refute html =~ "Nearby Places"
      refute html =~ "Place Name"
    end

    test "renders checkin details form", %{conn: conn, place: place} do
      {:ok, _view, html} = live(conn, ~p"/places/#{place.id}/checkins/new")
      assert html =~ "Date and Time"
      assert html =~ "Time Zone"
      assert html =~ "Content"
    end

    test "renders companions and photos sections", %{conn: conn, place: place} do
      {:ok, _view, html} = live(conn, ~p"/places/#{place.id}/checkins/new")
      assert html =~ "Companions"
      assert html =~ "Photos"
    end
  end

  # ── Checkin creation ─────────────────────────────────────────────────────────

  describe "create checkin from place" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      place = place_fixture()
      {:ok, place: place}
    end

    test "owner can create a checkin and is redirected to show", %{
      conn: conn,
      place: place,
      person: person
    } do
      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/checkins/new")

      future = NaiveDateTime.add(NaiveDateTime.utc_now(:second), 3600, :second)

      local =
        future
        |> NaiveDateTime.to_iso8601()
        |> String.slice(0, 16)

      {:error, {:redirect, %{to: path}}} =
        view
        |> form("#checkin-form", checkin: %{starts_at_local: local, starts_tz: "Etc/UTC"})
        |> render_submit()

      assert path =~ "/checkins/"

      checkins = Entries.get_local_checkins_for_place(place)
      assert length(checkins) == 1
      assert hd(checkins).author_uri == person.uri
      assert hd(checkins).place_uri == place.uri
    end

    test "validation errors are shown without creating a checkin", %{conn: conn, place: place} do
      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/checkins/new")

      html =
        view
        |> form("#checkin-form", checkin: %{starts_at_local: "", starts_tz: "Etc/UTC"})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert Entries.get_local_checkins_for_place(place) == []
    end

    test "owner: future datetime is accepted", %{conn: conn, place: place} do
      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/checkins/new")

      future =
        NaiveDateTime.add(NaiveDateTime.utc_now(:second), 3600, :second)
        |> NaiveDateTime.to_iso8601()
        |> String.slice(0, 16)

      {:error, {:redirect, _}} =
        view
        |> form("#checkin-form", checkin: %{starts_at_local: future, starts_tz: "Etc/UTC"})
        |> render_submit()

      assert length(Entries.get_local_checkins_for_place(place)) == 1
    end

    test "owner: ancient datetime is accepted", %{conn: conn, place: place} do
      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/checkins/new")

      {:error, {:redirect, _}} =
        view
        |> form("#checkin-form",
          checkin: %{starts_at_local: "2020-01-01T12:00", starts_tz: "Etc/UTC"}
        )
        |> render_submit()

      assert length(Entries.get_local_checkins_for_place(place)) == 1
    end
  end

  # ── Companion management ─────────────────────────────────────────────────────

  describe "companion management" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      place = place_fixture()
      {:ok, place: place}
    end

    test "search_companions returns matching suggestions", %{conn: conn, place: place} do
      other = person_fixture()
      {:ok, other} = Revix.People.update_person_display_name(other, %{display_name: "UrsulaFrom"})

      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/checkins/new")
      html = render_change(view, "search_companions", %{companion_query: "UrsulaFrom"})
      assert html =~ other.display_name
    end

    test "add_companion shows chip in UI", %{conn: conn, place: place} do
      other = person_fixture()
      {:ok, other} = Revix.People.update_person_display_name(other, %{display_name: "VeraFrom"})

      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/checkins/new")
      render_change(view, "search_companions", %{companion_query: "VeraFrom"})
      render_click(view, "add_companion", %{"uri" => other.uri})
      assert render(view) =~ other.display_name
    end

    test "remove_companion removes chip from UI", %{conn: conn, place: place} do
      other = person_fixture()
      {:ok, other} = Revix.People.update_person_display_name(other, %{display_name: "WendyFrom"})

      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/checkins/new")
      render_change(view, "search_companions", %{companion_query: "WendyFrom"})
      render_click(view, "add_companion", %{"uri" => other.uri})
      assert render(view) =~ other.display_name

      render_click(view, "remove_companion", %{"uri" => other.uri})
      refute render(view) =~ other.display_name
    end

    test "companions are persisted when checkin is created", %{
      conn: conn,
      place: place,
      person: person
    } do
      other = person_fixture()

      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/checkins/new")
      render_click(view, "add_companion", %{"uri" => other.uri})

      future =
        NaiveDateTime.add(NaiveDateTime.utc_now(:second), 3600, :second)
        |> NaiveDateTime.to_iso8601()
        |> String.slice(0, 16)

      {:error, {:redirect, _}} =
        view
        |> form("#checkin-form", checkin: %{starts_at_local: future, starts_tz: "Etc/UTC"})
        |> render_submit()

      [checkin] = Entries.get_local_checkins_for_place(place)
      assert Revix.EntryPeople.companion_of?(other.uri, checkin.uri)
      _ = person
    end
  end

  # ── File upload ──────────────────────────────────────────────────────────────

  describe "file upload" do
    setup :register_and_log_in_person

    setup %{person: person} do
      Revix.People.set_person_role(person, :owner)
      place = place_fixture()
      {:ok, place: place}
    end

    test "cancel_upload removes pending upload entry", %{conn: conn, place: place} do
      {:ok, view, _html} = live(conn, ~p"/places/#{place.id}/checkins/new")

      upload =
        file_input(view, "#checkin-form", :images, [
          %{
            last_modified: 1_594_171_879_000,
            name: "new_photo.jpg",
            content: :binary.copy(<<0>>, 100),
            size: 100,
            type: "image/jpeg"
          }
        ])

      render_upload(upload, "new_photo.jpg")
      assert render(view) =~ "new_photo.jpg"

      [%{"ref" => ref}] = upload.entries
      render_click(view, "cancel_upload", %{"ref" => ref})
      refute render(view) =~ "new_photo.jpg"
    end
  end
end
