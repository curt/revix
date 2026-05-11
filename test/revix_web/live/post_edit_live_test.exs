defmodule RevixWeb.PostEditLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Revix.EntriesFixtures
  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.MediaFixtures

  alias Revix.EntryPeople
  alias Revix.EntryPlaces
  alias Revix.Entries
  alias Revix.People

  # ── Authentication & Authorization ──────────────────────────────────────────

  describe "unauthenticated access" do
    test "redirects to sign in when not authenticated", %{conn: conn} do
      person = person_fixture()
      post = post_fixture(%{author_uri: person.uri})

      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/posts/#{post.id}/edit")
      assert path =~ "/people/signin"
    end
  end

  describe "authorization" do
    setup :register_and_log_in_person

    test "redirects non-author with flash error", %{conn: conn} do
      other_person = person_fixture()
      post = post_fixture(%{author_uri: other_person.uri})

      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/posts/#{post.id}/edit")
      assert path =~ "/posts/#{post.id}"
    end

    test "returns not-found redirect for nonexistent post", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/posts/11111111111/edit")
      assert path == "/posts"
    end
  end

  # ── Mount ────────────────────────────────────────────────────────────────────

  describe "authenticated mount as author" do
    setup :register_and_log_in_person

    setup %{person: person} do
      post = post_fixture(%{author_uri: person.uri, content: "Original content"})
      {:ok, post: post}
    end

    test "renders edit form with content", %{conn: conn, post: post} do
      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}/edit")
      assert html =~ "Edit Post"
      assert html =~ "Original content"
    end

    test "owner sees timezone select", %{conn: conn, person: person, post: post} do
      People.set_person_role(person, :owner)
      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}/edit")
      assert html =~ "America/New_York"
      assert html =~ "Europe/London"
    end

    test "shows companions and photos sections", %{conn: conn, post: post} do
      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}/edit")
      assert html =~ "Companions"
      assert html =~ "Photos"
    end
  end

  # ── Content update ───────────────────────────────────────────────────────────

  describe "update post content" do
    setup :register_and_log_in_person

    setup %{person: person} do
      post = post_fixture(%{author_uri: person.uri})
      {:ok, post: post}
    end

    test "updates content and redirects to show", %{conn: conn, post: post} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")

      {:error, {:redirect, %{to: _path}}} =
        view
        |> form("#edit-post-form", post: %{content: "Updated content"})
        |> render_submit()

      {:ok, updated} = Entries.get_local_post(post.id)
      assert updated.content == "Updated content"
    end

    test "updates title", %{conn: conn, post: post} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")

      {:error, {:redirect, %{to: _path}}} =
        view
        |> form("#edit-post-form", post: %{name: "New Title"})
        |> render_submit()

      {:ok, updated} = Entries.get_local_post(post.id)
      assert updated.name == "New Title"
    end
  end

  # ── Companion management ─────────────────────────────────────────────────────

  describe "companion management on edit page" do
    setup :register_and_log_in_person

    setup %{person: person} do
      post = post_fixture(%{author_uri: person.uri})
      {:ok, post: post}
    end

    test "search_companions returns matching suggestions", %{conn: conn, post: post} do
      other = person_fixture()
      {:ok, other} = Revix.People.update_person_display_name(other, %{display_name: "AliceEdit"})

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")
      html = render_change(view, "search_companions", %{companion_query: "AliceEdit"})

      assert html =~ other.display_name
    end

    test "add_companion immediately creates EntryPerson record", %{conn: conn, post: post} do
      other = person_fixture()

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")
      render_click(view, "add_companion", %{"uri" => other.uri})

      assert EntryPeople.companion_of?(other.uri, post.uri)
    end

    test "add_companion shows chip in UI", %{conn: conn, post: post} do
      other = person_fixture()

      {:ok, other} =
        Revix.People.update_person_display_name(other, %{display_name: "BobEditPost"})

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")
      render_click(view, "add_companion", %{"uri" => other.uri})

      assert render(view) =~ other.display_name
    end

    test "remove_companion immediately deletes EntryPerson record", %{
      conn: conn,
      post: post,
      scope: scope
    } do
      other = person_fixture()
      EntryPeople.add_companion(scope, post.uri, other.uri)
      assert EntryPeople.companion_of?(other.uri, post.uri)

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")
      render_click(view, "remove_companion", %{"uri" => other.uri})

      refute EntryPeople.companion_of?(other.uri, post.uri)
    end

    test "remove_companion removes chip from UI", %{conn: conn, post: post, scope: scope} do
      other = person_fixture()
      {:ok, other} = Revix.People.update_person_display_name(other, %{display_name: "CarolChip"})
      EntryPeople.add_companion(scope, post.uri, other.uri)

      {:ok, view, html} = live(conn, ~p"/posts/#{post.id}/edit")
      assert html =~ other.display_name

      render_click(view, "remove_companion", %{"uri" => other.uri})
      refute render(view) =~ other.display_name
    end

    test "companions loaded from DB are shown on mount", %{conn: conn, post: post, scope: scope} do
      other = person_fixture()
      {:ok, other} = Revix.People.update_person_display_name(other, %{display_name: "DaveMount"})
      EntryPeople.add_companion(scope, post.uri, other.uri)

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}/edit")
      assert html =~ other.display_name
    end
  end

  # ── Image removal ────────────────────────────────────────────────────────────

  describe "image removal" do
    setup :register_and_log_in_person

    setup %{person: person} do
      post = post_fixture(%{author_uri: person.uri})
      {:ok, post: post}
    end

    test "request_remove_image opens the confirmation modal", %{conn: conn, post: post} do
      image = image_fixture()
      Revix.Media.attach_image_to_entry(post.id, image.id, 0)

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")
      render_click(view, "request_remove_image", %{"image-id" => image.id})

      html = render(view)
      assert html =~ ~s(<dialog)
      assert html =~ "Remove photo?"
    end

    test "cancel_remove_image closes the modal without deleting", %{conn: conn, post: post} do
      image = image_fixture()
      Revix.Media.attach_image_to_entry(post.id, image.id, 0)

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")
      render_click(view, "request_remove_image", %{"image-id" => image.id})
      render_click(view, "cancel_remove_image", %{})

      html = render(view)
      refute html =~ ~s(<dialog)
      assert Revix.Media.get_images_for_entry(post.id) != []
    end

    test "confirm_remove_image deletes the image and removes it from UI", %{
      conn: conn,
      post: post
    } do
      image = image_fixture()
      Revix.Media.attach_image_to_entry(post.id, image.id, 0)

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")
      render_click(view, "request_remove_image", %{"image-id" => image.id})
      render_click(view, "confirm_remove_image", %{})

      html = render(view)
      refute html =~ ~s(<dialog)
      refute html =~ ~s(data-image-id="#{image.id}")
      assert Revix.Media.get_images_for_entry(post.id) == []
    end
  end

  # ── File upload on edit ──────────────────────────────────────────────────────

  describe "file upload on edit page" do
    setup :register_and_log_in_person

    setup %{person: person} do
      post = post_fixture(%{author_uri: person.uri})
      {:ok, post: post}
    end

    test "cancel_upload removes pending upload entry", %{conn: conn, post: post} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")

      upload =
        file_input(view, "#edit-post-form", :images, [
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

  # ── Timezone editing (owner only) ─────────────────────────────────────────────

  describe "timezone editing on edit page" do
    setup :register_and_log_in_person

    setup %{person: person} do
      post = post_fixture(%{author_uri: person.uri})
      {:ok, post: post}
    end

    test "non-owner does not see timezone field on edit page", %{conn: conn, post: post} do
      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}/edit")
      refute html =~ ~s(name="post[published_tz]")
    end

    test "owner sees timezone field on edit page", %{conn: conn, person: person, post: post} do
      People.set_person_role(person, :owner)
      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}/edit")
      assert html =~ ~s(name="post[published_tz]")
    end

    test "owner can update the post timezone", %{conn: conn, person: person, post: post} do
      People.set_person_role(person, :owner)
      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")

      {:error, {:redirect, %{to: _path}}} =
        view
        |> form("#edit-post-form", post: %{published_tz: "Etc/UTC"})
        |> render_submit()

      {:ok, updated} = Entries.get_local_post(post.id)
      assert updated.published_tz == "Etc/UTC"
    end

    test "non-owner submit ignores timezone param even if injected", %{
      conn: conn,
      post: post
    } do
      original_tz = post.published_tz

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")

      {:error, {:redirect, _}} =
        render_submit(view, "submit", %{
          "post" => %{
            "content" => "Updated",
            "published_tz" => "Pacific/Auckland"
          }
        })

      {:ok, updated} = Entries.get_local_post(post.id)
      assert updated.published_tz == original_tz
    end
  end

  # ── Place management ─────────────────────────────────────────────────────────

  describe "place management on edit page" do
    setup :register_and_log_in_person

    setup %{person: person} do
      post = post_fixture(%{author_uri: person.uri})
      {:ok, post: post}
    end

    test "search_places returns matching places", %{conn: conn, post: post} do
      place = place_fixture(%{name: "Hidden Gem"})

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")
      html = render_change(view, "search_places", %{place_query: "Hidden"})

      assert html =~ place.name
    end

    test "add_place immediately creates EntryPlace record", %{conn: conn, post: post} do
      place = place_fixture()

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")
      render_change(view, "search_places", %{place_query: ""})
      render_click(view, "add_place", %{"uri" => place.uri})

      assert EntryPlaces.place_of?(place.uri, post.uri)
    end

    test "add_place shows chip in UI", %{conn: conn, post: post} do
      place = place_fixture(%{name: "Visible Spot"})

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")
      render_change(view, "search_places", %{place_query: "Visible"})
      render_click(view, "add_place", %{"uri" => place.uri})

      assert render(view) =~ "Visible Spot"
    end

    test "add_place is idempotent — no duplicates in UI", %{conn: conn, post: post} do
      place = place_fixture()

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")
      render_change(view, "search_places", %{place_query: ""})
      render_click(view, "add_place", %{"uri" => place.uri})
      render_click(view, "add_place", %{"uri" => place.uri})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert length(assigns.selected_places) == 1
    end

    test "remove_place immediately deletes EntryPlace record", %{conn: conn, post: post} do
      place = place_fixture()
      EntryPlaces.add_place(post.uri, place.uri)
      assert EntryPlaces.place_of?(place.uri, post.uri)

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")
      render_click(view, "remove_place", %{"uri" => place.uri})

      refute EntryPlaces.place_of?(place.uri, post.uri)
    end

    test "remove_place removes chip from UI", %{conn: conn, post: post} do
      place = place_fixture(%{name: "Gone Cafe"})
      EntryPlaces.add_place(post.uri, place.uri)

      {:ok, view, html} = live(conn, ~p"/posts/#{post.id}/edit")
      assert html =~ "Gone Cafe"

      render_click(view, "remove_place", %{"uri" => place.uri})
      refute render(view) =~ "Gone Cafe"
    end

    test "places loaded from DB are shown on mount", %{conn: conn, post: post} do
      place = place_fixture(%{name: "Preloaded Cafe"})
      EntryPlaces.add_place(post.uri, place.uri)

      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}/edit")
      assert html =~ "Preloaded Cafe"
    end
  end
end
