defmodule RevixWeb.PostNewLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Revix.PeopleFixtures
  import Revix.PlacesFixtures

  alias Revix.EntryPeople
  alias Revix.EntryPlaces
  alias Revix.People

  # ── Authentication ───────────────────────────────────────────────────────────

  describe "unauthenticated access" do
    test "redirects to sign in when not authenticated", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/posts/new")
      assert path =~ "/people/signin"
    end
  end

  # ── Authorization ────────────────────────────────────────────────────────────

  describe "non-owner access" do
    setup :register_and_log_in_person

    test "redirects non-owner with flash error", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/posts/new")
      assert path == "/posts"
    end
  end

  # ── Mount ────────────────────────────────────────────────────────────────────

  describe "owner mount" do
    setup :register_and_log_in_person

    setup %{person: person} do
      People.set_person_role(person, :owner)
      :ok
    end

    test "renders new post form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/posts/new")
      assert html =~ "New Post"
      assert html =~ "Title"
      assert html =~ "Content"
      assert html =~ "Time Zone"
    end

    test "includes timezone select", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/posts/new")
      assert html =~ "America/New_York"
      assert html =~ "Europe/London"
    end

    test "shows companions and photos sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/posts/new")
      assert html =~ "Companions"
      assert html =~ "Photos"
    end
  end

  # ── set_defaults event ───────────────────────────────────────────────────────

  describe "set_defaults event" do
    setup :register_and_log_in_person

    setup %{person: person} do
      People.set_person_role(person, :owner)
      :ok
    end

    test "prefills timezone in form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/posts/new")
      render_hook(view, "set_timezone", %{timezone: "America/Chicago"})
      html = render(view)
      assert html =~ "America/Chicago"
    end
  end

  # ── Companion management ─────────────────────────────────────────────────────

  describe "companion management" do
    setup :register_and_log_in_person

    setup %{person: person} do
      People.set_person_role(person, :owner)
      :ok
    end

    test "search_companions returns matching people", %{conn: conn} do
      other = person_fixture()
      {:ok, other} = Revix.People.update_person_display_name(other, %{display_name: "AlicePost"})

      {:ok, view, _html} = live(conn, ~p"/posts/new")
      html = render_change(view, "search_companions", %{companion_query: "AlicePost"})

      assert html =~ other.display_name
    end

    test "add_companion adds person to pending list", %{conn: conn} do
      other = person_fixture()
      {:ok, other} = Revix.People.update_person_display_name(other, %{display_name: "BobPost"})

      {:ok, view, _html} = live(conn, ~p"/posts/new")
      render_change(view, "search_companions", %{companion_query: "BobPost"})
      render_click(view, "add_companion", %{"uri" => other.uri})
      html = render(view)

      assert html =~ other.display_name
    end

    test "add_companion is idempotent — no duplicates", %{conn: conn} do
      other = person_fixture()

      {:ok, view, _html} = live(conn, ~p"/posts/new")
      render_click(view, "add_companion", %{"uri" => other.uri})
      render_click(view, "add_companion", %{"uri" => other.uri})

      html = render(view)
      count = html |> String.split("remove_companion") |> length()
      assert count == 2
    end

    test "remove_companion removes person from pending list", %{conn: conn} do
      other = person_fixture(%{display_name: "DavePost"})

      {:ok, view, _html} = live(conn, ~p"/posts/new")
      render_change(view, "search_companions", %{companion_query: "DavePost"})
      render_click(view, "add_companion", %{"uri" => other.uri})
      render_click(view, "remove_companion", %{"uri" => other.uri})

      refute render(view) =~ "remove_companion"
    end

    test "cannot add self as companion", %{conn: conn, person: person} do
      {:ok, view, _html} = live(conn, ~p"/posts/new")
      render_click(view, "add_companion", %{"uri" => person.uri})
      refute render(view) =~ "remove_companion"
    end
  end

  # ── Post creation ────────────────────────────────────────────────────────────

  describe "submit event — post creation" do
    setup :register_and_log_in_person

    setup %{person: person} do
      People.set_person_role(person, :owner)
      :ok
    end

    test "creates post and redirects to show", %{conn: conn, person: person} do
      {:ok, view, _html} = live(conn, ~p"/posts/new")

      {:error, {:redirect, %{to: path}}} =
        view
        |> form("#post-form", post: %{published_tz: "America/New_York", content: "Hello!"})
        |> render_submit()

      assert path =~ "/posts/#{person.id}" or String.starts_with?(path, "/posts/")
      posts = Revix.Entries.get_recent_posts()
      assert length(posts) == 1
      assert hd(posts).content == "Hello!"
    end

    test "creates post with name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/posts/new")

      {:error, {:redirect, _}} =
        view
        |> form("#post-form", post: %{published_tz: "UTC", name: "My Title"})
        |> render_submit()

      assert hd(Revix.Entries.get_recent_posts()).name == "My Title"
    end

    test "companions are persisted atomically with post", %{conn: conn} do
      other = person_fixture()

      {:ok, view, _html} = live(conn, ~p"/posts/new")
      render_change(view, "search_companions", %{companion_query: ""})
      render_click(view, "add_companion", %{"uri" => other.uri})

      {:error, {:redirect, _}} =
        view
        |> form("#post-form", post: %{published_tz: "UTC"})
        |> render_submit()

      post = hd(Revix.Entries.get_recent_posts())
      assert EntryPeople.companion_of?(other.uri, post.uri)
    end

    test "re-renders form with errors when timezone is missing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/posts/new")

      html = render_submit(view, "submit", %{"post" => %{"content" => "No timezone"}})
      assert html =~ "New Post"
    end
  end

  # ── File upload ──────────────────────────────────────────────────────────────

  describe "file upload" do
    setup :register_and_log_in_person

    setup %{person: person} do
      People.set_person_role(person, :owner)
      :ok
    end

    test "cancel_upload removes pending entry", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/posts/new")

      upload =
        file_input(view, "#post-form", :images, [
          %{
            last_modified: 1_594_171_879_000,
            name: "test.jpg",
            content: :binary.copy(<<0>>, 100),
            size: 100,
            type: "image/jpeg"
          }
        ])

      render_upload(upload, "test.jpg")
      assert render(view) =~ "test.jpg"

      [%{"ref" => ref}] = upload.entries
      render_click(view, "cancel_upload", %{"ref" => ref})
      refute render(view) =~ "test.jpg"
    end

    test "update_caption stores caption for a pending upload", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/posts/new")

      upload =
        file_input(view, "#post-form", :images, [
          %{
            last_modified: 1_594_171_879_000,
            name: "photo.jpg",
            content: :binary.copy(<<0>>, 100),
            size: 100,
            type: "image/jpeg"
          }
        ])

      render_upload(upload, "photo.jpg")
      [%{"ref" => ref}] = upload.entries

      render_hook(view, "update_caption", %{
        "_target" => ["photo_caption", ref],
        "photo_caption" => %{ref => "A post photo"}
      })

      assert render(view) =~ "A post photo"
    end

    test "reorder_images stores the new ref order", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/posts/new")

      upload_a =
        file_input(view, "#post-form", :images, [
          %{
            last_modified: 1_594_171_879_000,
            name: "a.jpg",
            content: :binary.copy(<<0>>, 100),
            size: 100,
            type: "image/jpeg"
          }
        ])

      render_upload(upload_a, "a.jpg")

      upload_b =
        file_input(view, "#post-form", :images, [
          %{
            last_modified: 1_594_171_879_000,
            name: "b.jpg",
            content: :binary.copy(<<0>>, 100),
            size: 100,
            type: "image/jpeg"
          }
        ])

      render_upload(upload_b, "b.jpg")

      [%{"ref" => ref_a}] = upload_a.entries
      [%{"ref" => ref_b}] = upload_b.entries

      render_hook(view, "reorder_images", %{
        "order" => [%{"ref" => ref_b}, %{"ref" => ref_a}]
      })

      assert :sys.get_state(view.pid).socket.assigns.upload_order == [ref_b, ref_a]
    end
  end

  # ── Place management ─────────────────────────────────────────────────────────

  describe "place management" do
    setup :register_and_log_in_person

    setup %{person: person} do
      People.set_person_role(person, :owner)
      :ok
    end

    test "search_places returns matching places", %{conn: conn} do
      place = place_fixture(%{name: "The Grand Cafe"})

      {:ok, view, _html} = live(conn, ~p"/posts/new")
      html = render_change(view, "search_places", %{place_query: "Grand"})

      assert html =~ place.name
    end

    test "search_places returns empty when query is blank", %{conn: conn} do
      place_fixture(%{name: "Any Cafe"})

      {:ok, view, _html} = live(conn, ~p"/posts/new")
      html = render_change(view, "search_places", %{place_query: "   "})

      refute html =~ "add_place"
    end

    test "add_place shows place chip", %{conn: conn} do
      place = place_fixture(%{name: "Corner Spot"})

      {:ok, view, _html} = live(conn, ~p"/posts/new")
      render_change(view, "search_places", %{place_query: "Corner"})
      render_click(view, "add_place", %{"uri" => place.uri})

      assert render(view) =~ place.name
    end

    test "add_place is idempotent — no duplicates", %{conn: conn} do
      place = place_fixture(%{name: "Idempotent Spot"})

      {:ok, view, _html} = live(conn, ~p"/posts/new")
      render_change(view, "search_places", %{place_query: "Idempotent"})
      render_click(view, "add_place", %{"uri" => place.uri})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.selected_places) == 1

      # Search again so place is back in results, then try adding same place
      render_change(view, "search_places", %{place_query: "Idempotent"})
      render_click(view, "add_place", %{"uri" => place.uri})
      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.selected_places) == 1
    end

    test "remove_place removes chip", %{conn: conn} do
      place = place_fixture(%{name: "Removable Spot"})

      {:ok, view, _html} = live(conn, ~p"/posts/new")
      render_change(view, "search_places", %{place_query: "Removable"})
      render_click(view, "add_place", %{"uri" => place.uri})
      assert render(view) =~ place.name

      render_click(view, "remove_place", %{"uri" => place.uri})
      refute render(view) =~ place.name
    end

    test "places are persisted atomically with post", %{conn: conn} do
      place = place_fixture(%{name: "Atomic Place"})

      {:ok, view, _html} = live(conn, ~p"/posts/new")
      render_change(view, "search_places", %{place_query: "Atomic"})
      render_click(view, "add_place", %{"uri" => place.uri})

      {:error, {:redirect, _}} =
        view
        |> form("#post-form", post: %{published_tz: "UTC"})
        |> render_submit()

      post = hd(Revix.Entries.get_recent_posts())
      assert EntryPlaces.place_of?(place.uri, post.uri)
    end
  end
end
