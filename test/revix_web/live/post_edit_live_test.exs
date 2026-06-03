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

    test "confirm_remove_image enqueues an Update activity", %{conn: conn, post: post} do
      image = image_fixture()
      Revix.Media.attach_image_to_entry(post.id, image.id, 0)

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")
      render_click(view, "request_remove_image", %{"image-id" => image.id})
      render_click(view, "confirm_remove_image", %{})

      assert_enqueued(
        worker: Revix.Workers.DeliverEntryWorker,
        args: %{"entry_id" => post.id, "activity_type" => "Update"}
      )
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

  # ── Caption, alt, reorder, validate ─────────────────────────────────────────

  describe "caption and alt text updates" do
    setup :register_and_log_in_person

    setup %{person: person} do
      post = post_fixture(%{author_uri: person.uri})
      image = image_fixture()
      Revix.Media.attach_image_to_entry(post.id, image.id, 0)
      {:ok, post: post, image: image}
    end

    test "update_caption stores caption for existing image", %{
      conn: conn,
      post: post,
      image: image
    } do
      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")

      render_change(view, "update_caption", %{
        "_target" => ["photo_caption", image.id],
        "photo_caption" => %{image.id => "Post caption"}
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert get_in(assigns, [:image_captions, image.id, :caption]) == "Post caption"
    end

    test "update_alt stores alt text for existing image", %{
      conn: conn,
      post: post,
      image: image
    } do
      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")

      render_change(view, "update_alt", %{
        "_target" => ["photo_alt", image.id],
        "photo_alt" => %{image.id => "Post alt"}
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert get_in(assigns, [:image_captions, image.id, :alt]) == "Post alt"
    end

    test "reorder_images updates upload_order and existing_image_order", %{
      conn: conn,
      post: post,
      image: image
    } do
      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")

      render_click(view, "reorder_images", %{
        "order" => [%{"ref" => "ref1", "image_id" => image.id}]
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.upload_order == ["ref1"]
      assert assigns.existing_image_order == [image.id]
    end
  end

  describe "form validation" do
    setup :register_and_log_in_person

    setup %{person: person} do
      post = post_fixture(%{author_uri: person.uri})
      {:ok, post: post}
    end

    test "validate event updates the form changeset", %{conn: conn, post: post} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")
      html = render_change(view, "validate", %{"post" => %{"content" => "Draft text"}})
      assert html =~ "Draft text"
    end

    test "search_places with empty query returns no results", %{conn: conn, post: post} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")
      _html = render_change(view, "search_places", %{place_query: "  "})
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.place_results == []
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

  # ── Draft post editing ───────────────────────────────────────────────────────

  # ── Timezone auto-fill for draft posts ──────────────────────────────────────

  describe "set_timezone event on draft post" do
    setup :register_and_log_in_person

    setup %{person: person} do
      draft = draft_post_fixture(%{author_uri: person.uri})
      {:ok, draft: draft}
    end

    test "populates timezone field when draft has no stored timezone", %{
      conn: conn,
      draft: draft
    } do
      assert is_nil(draft.published_tz)
      {:ok, view, _html} = live(conn, ~p"/posts/#{draft.id}/edit")

      html = render_click(view, "set_timezone", %{"timezone" => "America/Denver"})
      assert html =~ "America/Denver"

      assigns = :sys.get_state(view.pid).socket.assigns
      assert Phoenix.HTML.Form.input_value(assigns.form, :published_tz) == "America/Denver"
    end

    test "sets timezone when none is stored (every new draft has nil published_tz)", %{
      conn: conn,
      draft: draft
    } do
      assert is_nil(draft.published_tz)
      {:ok, view, _html} = live(conn, ~p"/posts/#{draft.id}/edit")

      render_click(view, "set_timezone", %{"timezone" => "Pacific/Auckland"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert Phoenix.HTML.Form.input_value(assigns.form, :published_tz) == "Pacific/Auckland"
    end
  end

  describe "set_timezone event on published post" do
    setup :register_and_log_in_person

    setup %{person: person} do
      post = post_fixture(%{author_uri: person.uri, published_tz: "America/New_York"})
      {:ok, post: post}
    end

    test "is a no-op — does not change the form", %{conn: conn, post: post} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")

      render_click(view, "set_timezone", %{"timezone" => "America/Denver"})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert Phoenix.HTML.Form.input_value(assigns.form, :published_tz) == "America/New_York"
    end
  end

  describe "edit draft post — save as draft" do
    setup :register_and_log_in_person

    setup %{person: person} do
      draft = draft_post_fixture(%{author_uri: person.uri})
      {:ok, draft: draft}
    end

    test "renders edit form for draft", %{conn: conn, draft: draft} do
      {:ok, _view, html} = live(conn, ~p"/posts/#{draft.id}/edit")
      assert html =~ "Edit Post"
    end

    test "shows Publish button for draft (not Save Changes)", %{conn: conn, draft: draft} do
      {:ok, _view, html} = live(conn, ~p"/posts/#{draft.id}/edit")
      assert html =~ "Publish"
      refute html =~ "Save Changes"
    end

    test "shows timezone field for non-owner on draft", %{conn: conn, draft: draft} do
      {:ok, _view, html} = live(conn, ~p"/posts/#{draft.id}/edit")
      assert html =~ ~s(name="post[published_tz]")
    end

    test "save as draft updates content without setting published_at", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{draft.id}/edit")

      {:error, {:redirect, %{to: path}}} =
        render_submit(view, "submit", %{
          "post" => %{"content" => "Updated draft"},
          "action" => "draft"
        })

      assert path =~ ~r|^/posts/[^/]+$|
      {:ok, updated} = Entries.get_local_post(draft.id)
      assert updated.content == "Updated draft"
      assert is_nil(updated.published_at_utc)
    end

    test "save as draft with timezone in params does not crash (owner)", %{
      conn: conn,
      person: person,
      draft: draft
    } do
      People.set_person_role(person, :owner)
      {:ok, view, _html} = live(conn, ~p"/posts/#{draft.id}/edit")

      {:error, {:redirect, %{to: path}}} =
        render_submit(view, "submit", %{
          "post" => %{"content" => "Updated", "published_tz" => "America/Phoenix"},
          "action" => "draft"
        })

      assert path =~ ~r|^/posts/[^/]+$|
      {:ok, updated} = Entries.get_local_post(draft.id)
      assert updated.content == "Updated"
      assert is_nil(updated.published_at_utc)
    end
  end

  describe "edit draft post — publish flow" do
    setup :register_and_log_in_person

    setup %{person: person} do
      draft = draft_post_fixture(%{author_uri: person.uri})
      {:ok, draft: draft}
    end

    test "clicking Publish shows confirmation modal", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{draft.id}/edit")

      html =
        render_submit(view, "submit", %{
          "post" => %{"content" => "Hello!", "published_tz" => "UTC"},
          "action" => "publish"
        })

      assert html =~ "Publish this post?"
    end

    test "cancel_publish hides modal without publishing", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{draft.id}/edit")

      render_submit(view, "submit", %{
        "post" => %{"content" => "Hello!", "published_tz" => "UTC"},
        "action" => "publish"
      })

      html = render_click(view, "cancel_publish", %{})
      refute html =~ "Publish this post?"

      {:ok, unchanged} = Entries.get_local_post(draft.id)
      assert is_nil(unchanged.published_at_utc)
    end

    test "confirm_publish sets all three published_at fields", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{draft.id}/edit")

      render_submit(view, "submit", %{
        "post" => %{"content" => "Ready to publish", "published_tz" => "America/Chicago"},
        "action" => "publish"
      })

      {:error, {:redirect, %{to: path}}} = render_click(view, "confirm_publish", %{})

      assert path =~ ~r|/posts/[^/]+/\d{4}/\d{2}/\d{2}/|

      {:ok, published} = Entries.get_local_post(draft.id)
      assert %DateTime{} = published.published_at_utc
      assert %NaiveDateTime{} = published.published_at_local
      assert published.published_tz == "America/Chicago"
      assert published.content == "Ready to publish"
    end

    test "confirm_publish enqueues delivery with Create type", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{draft.id}/edit")

      render_submit(view, "submit", %{
        "post" => %{"content" => "Hello!", "published_tz" => "UTC"},
        "action" => "publish"
      })

      render_click(view, "confirm_publish", %{})

      assert_enqueued(
        worker: Revix.Workers.DeliverEntryWorker,
        args: %{"activity_type" => "Create"}
      )
    end

    test "confirm_publish with missing timezone shows form error", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{draft.id}/edit")

      render_submit(view, "submit", %{
        "post" => %{"content" => "Hello!"},
        "action" => "publish"
      })

      html = render_click(view, "confirm_publish", %{})
      refute html =~ "Publish this post?"
      assert html =~ "Edit Post"

      {:ok, unchanged} = Entries.get_local_post(draft.id)
      assert is_nil(unchanged.published_at_utc)
    end
  end

  describe "published post — no Publish button" do
    setup :register_and_log_in_person

    setup %{person: person} do
      post = post_fixture(%{author_uri: person.uri})
      {:ok, post: post}
    end

    test "shows Save Changes button and no Publish button", %{conn: conn, post: post} do
      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}/edit")
      assert html =~ "Save Changes"
      refute html =~ "Publish…"
    end

    test "non-owner does not see timezone field on published post", %{conn: conn, post: post} do
      {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}/edit")
      refute html =~ ~s(name="post[published_tz]")
    end
  end

  describe "companion error branch — remove non-existent companion" do
    setup :register_and_log_in_person

    setup %{person: person} do
      post = post_fixture(%{author_uri: person.uri})
      {:ok, post: post}
    end

    test "remove_companion for a URI that was never added is a no-op", %{conn: conn, post: post} do
      other = person_fixture()
      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")

      render_click(view, "remove_companion", %{"uri" => other.uri})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.companions == []
    end
  end

  describe "place error branch — remove non-linked place" do
    setup :register_and_log_in_person

    setup %{person: person} do
      post = post_fixture(%{author_uri: person.uri})
      {:ok, post: post}
    end

    test "remove_place for a place that was never linked is a no-op", %{conn: conn, post: post} do
      place = place_fixture()
      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")

      render_click(view, "remove_place", %{"uri" => place.uri})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_places == []
    end
  end

  describe "image side effects on save" do
    setup :register_and_log_in_person

    setup %{person: person} do
      post = post_fixture(%{author_uri: person.uri})
      image = image_fixture(%{author_uri: person.uri})
      Revix.Media.attach_image_to_entry(post.id, image.id, 0)
      {:ok, post: post, image: image}
    end

    test "saving with updated caption persists it to the image", %{
      conn: conn,
      post: post,
      image: image
    } do
      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")

      render_change(view, "update_caption", %{
        "_target" => ["photo_caption", image.id],
        "photo_caption" => %{image.id => "Saved caption"}
      })

      {:error, {:redirect, _}} =
        view
        |> form("#edit-post-form")
        |> render_submit()

      {:ok, updated_image} = Revix.Media.get_image(image.id)
      assert updated_image.caption == "Saved caption"
    end

    test "saving with reordered images updates positions", %{
      conn: conn,
      post: post,
      image: image,
      person: person
    } do
      image2 = image_fixture(%{author_uri: person.uri})
      Revix.Media.attach_image_to_entry(post.id, image2.id, 1)

      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")

      render_click(view, "reorder_images", %{
        "order" => [
          %{"ref" => "ref1", "image_id" => image2.id},
          %{"ref" => "ref2", "image_id" => image.id}
        ]
      })

      {:error, {:redirect, _}} =
        view
        |> form("#edit-post-form")
        |> render_submit()

      entry_images = Revix.Media.get_images_for_entry(post.id)
      image_ids = Enum.map(entry_images, & &1.id)
      assert image_ids == [image2.id, image.id]
    end
  end

  describe "published post — invalid timezone submit" do
    setup :register_and_log_in_person

    setup %{person: person} do
      People.set_person_role(person, :owner)
      post = post_fixture(%{author_uri: person.uri})
      {:ok, post: post}
    end

    test "owner submit with invalid timezone shows form error", %{conn: conn, post: post} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")

      html =
        render_submit(view, "submit", %{
          "post" => %{"published_tz" => "Not/ATimezone"}
        })

      assert html =~ "not a valid timezone"
    end

    test "post is unchanged after invalid timezone submit", %{conn: conn, post: post} do
      original_tz = post.published_tz
      {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}/edit")

      render_submit(view, "submit", %{
        "post" => %{"published_tz" => "Not/ATimezone"}
      })

      {:ok, unchanged} = Entries.get_local_post(post.id)
      assert unchanged.published_tz == original_tz
    end
  end

  # ── Delete post flow ──────────────────────────────────────────────────────────

  describe "delete post — draft only" do
    setup :register_and_log_in_person

    setup %{person: person} do
      draft =
        post_fixture(%{
          author_uri: person.uri,
          published_at_utc: nil,
          published_at_local: nil,
          published_tz: nil
        })

      {:ok, draft: draft}
    end

    test "shows Delete button for draft post", %{conn: conn, draft: draft} do
      {:ok, _view, html} = live(conn, ~p"/posts/#{draft.id}/edit")
      assert html =~ "Delete post"
    end

    test "does not show Delete button for published post", %{conn: conn, person: person} do
      published = post_fixture(%{author_uri: person.uri})
      {:ok, _view, html} = live(conn, ~p"/posts/#{published.id}/edit")
      refute html =~ "Delete post"
    end

    test "request_delete shows confirmation modal", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{draft.id}/edit")
      render_click(view, "request_delete", %{})
      html = render(view)
      assert html =~ "Delete this post?"
    end

    test "cancel_delete hides modal", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{draft.id}/edit")
      render_click(view, "request_delete", %{})
      render_click(view, "cancel_delete", %{})
      html = render(view)
      refute html =~ "Delete this post?"
    end

    test "confirm_delete hard-deletes draft post and redirects", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/posts/#{draft.id}/edit")
      render_click(view, "request_delete", %{})

      {:error, {:redirect, %{to: _path}}} = render_click(view, "confirm_delete", %{})

      assert {:error, :not_found} = Entries.get_local_post(draft.id)
    end

    test "published post: request_delete is ignored", %{conn: conn, person: person} do
      published = post_fixture(%{author_uri: person.uri})
      {:ok, view, _html} = live(conn, ~p"/posts/#{published.id}/edit")
      render_click(view, "request_delete", %{})
      html = render(view)
      refute html =~ "Delete this post?"
    end
  end
end
