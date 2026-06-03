defmodule RevixWeb.CheckinEditLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures
  import Revix.PeopleFixtures
  import Revix.MediaFixtures

  alias Revix.EntryPeople
  alias Revix.Entries

  # ── Authentication & Authorization ──────────────────────────────────────────

  describe "unauthenticated access" do
    test "redirects to sign in when not authenticated", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      assert path =~ "/people/signin"
    end
  end

  describe "authorization" do
    setup :register_and_log_in_person

    test "redirects non-author with flash error", %{conn: conn} do
      place = place_fixture()
      other_person = person_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri, author_uri: other_person.uri})

      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      assert path =~ "/checkins"
    end

    test "returns not-found redirect for nonexistent checkin", %{conn: conn} do
      # Use a valid-format Base58 ID that doesn't exist in the DB
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/checkins/11111111111/edit")
      assert path =~ "/checkins"
    end
  end

  # ── Mount ───────────────────────────────────────────────────────────────────

  describe "authenticated mount as author" do
    setup :register_and_log_in_person

    setup %{person: person} do
      place = place_fixture(%{slug: "test-cafe"})

      checkin =
        checkin_fixture(%{
          place_uri: place.uri,
          author_uri: person.uri,
          content: "Original content"
        })

      {:ok, place: place, checkin: checkin}
    end

    test "renders edit form with place name and content", %{
      conn: conn,
      checkin: checkin,
      place: place
    } do
      {:ok, _view, html} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      assert html =~ "Edit Checkin"
      assert html =~ place.name
      assert html =~ "Original content"
    end

    test "edit page does not show place creation UI", %{conn: conn, checkin: checkin} do
      {:ok, _view, html} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      refute html =~ "locate-btn"
      refute html =~ "Place Name"
    end
  end

  # ── Content update ───────────────────────────────────────────────────────────

  describe "update checkin content" do
    setup :register_and_log_in_person

    setup %{person: person} do
      place = place_fixture(%{slug: "test-cafe"})
      checkin = checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})
      {:ok, checkin: checkin}
    end

    test "updates content and redirects to show", %{conn: conn, checkin: checkin} do
      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")

      {:error, {:redirect, %{to: _path}}} =
        view
        |> form("#edit-checkin-form", checkin: %{content: "Updated content"})
        |> render_submit()

      {:ok, updated} = Entries.get_local_checkin(checkin.id)
      assert updated.content == "Updated content"
    end
  end

  # ── Companion management (immediate) ─────────────────────────────────────────

  describe "companion management on edit page" do
    setup :register_and_log_in_person

    setup %{person: person} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})
      {:ok, checkin: checkin}
    end

    test "search_companions returns matching suggestions", %{conn: conn, checkin: checkin} do
      other = person_fixture()
      {:ok, other} = Revix.People.update_person_display_name(other, %{display_name: "FrankEdit"})

      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      html = render_change(view, "search_companions", %{companion_query: "FrankEdit"})

      assert html =~ other.display_name
    end

    test "add_companion immediately creates EntryPerson record", %{
      conn: conn,
      checkin: checkin,
      person: person
    } do
      other = person_fixture()

      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      render_click(view, "add_companion", %{"uri" => other.uri})

      assert EntryPeople.companion_of?(other.uri, checkin.uri)
      _ = person
    end

    test "add_companion shows chip in UI", %{conn: conn, checkin: checkin} do
      other = person_fixture()
      {:ok, other} = Revix.People.update_person_display_name(other, %{display_name: "HenryChip"})

      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      render_click(view, "add_companion", %{"uri" => other.uri})

      html = render(view)
      assert html =~ other.display_name
    end

    test "remove_companion immediately deletes EntryPerson record", %{
      conn: conn,
      checkin: checkin,
      person: person,
      scope: scope
    } do
      other = person_fixture()
      EntryPeople.add_companion(scope, checkin.uri, other.uri)

      assert EntryPeople.companion_of?(other.uri, checkin.uri)

      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      render_click(view, "remove_companion", %{"uri" => other.uri})

      refute EntryPeople.companion_of?(other.uri, checkin.uri)
      _ = person
    end

    test "remove_companion removes chip from UI", %{
      conn: conn,
      checkin: checkin,
      scope: scope
    } do
      other = person_fixture()
      {:ok, other} = Revix.People.update_person_display_name(other, %{display_name: "JackChip"})
      EntryPeople.add_companion(scope, checkin.uri, other.uri)

      {:ok, view, html} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      assert html =~ other.display_name

      render_click(view, "remove_companion", %{"uri" => other.uri})
      html = render(view)
      refute html =~ other.display_name
    end

    test "companions loaded from DB are shown on mount", %{
      conn: conn,
      checkin: checkin,
      scope: scope
    } do
      other = person_fixture()
      {:ok, other} = Revix.People.update_person_display_name(other, %{display_name: "KateMount"})
      EntryPeople.add_companion(scope, checkin.uri, other.uri)

      {:ok, _view, html} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      assert html =~ other.display_name
    end
  end

  # ── Image removal ────────────────────────────────────────────────────────────

  describe "image removal" do
    setup :register_and_log_in_person

    setup %{person: person} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})
      {:ok, checkin: checkin}
    end

    test "request_remove_image opens the confirmation modal", %{
      conn: conn,
      checkin: checkin
    } do
      image = image_fixture()
      Revix.Media.attach_image_to_entry(checkin.id, image.id, 0)

      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")

      render_click(view, "request_remove_image", %{"image-id" => image.id})
      html = render(view)
      # Modal should be rendered (dialog element present)
      assert html =~ ~s(<dialog)
      assert html =~ "Remove photo?"
    end

    test "cancel_remove_image closes the modal without deleting", %{
      conn: conn,
      checkin: checkin
    } do
      image = image_fixture()
      Revix.Media.attach_image_to_entry(checkin.id, image.id, 0)

      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      render_click(view, "request_remove_image", %{"image-id" => image.id})
      render_click(view, "cancel_remove_image", %{})

      html = render(view)
      # Modal should be gone (dialog element not rendered)
      refute html =~ ~s(<dialog)
      # Image should still be attached
      assert Revix.Media.get_images_for_entry(checkin.id) != []
    end

    test "confirm_remove_image deletes the image and removes it from UI", %{
      conn: conn,
      checkin: checkin
    } do
      image = image_fixture()
      Revix.Media.attach_image_to_entry(checkin.id, image.id, 0)

      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      render_click(view, "request_remove_image", %{"image-id" => image.id})
      render_click(view, "confirm_remove_image", %{})

      html = render(view)
      # Modal should be gone (dialog element not rendered after confirm)
      refute html =~ ~s(<dialog)
      # Image card should be gone from DOM
      refute html =~ ~s(data-image-id="#{image.id}")
      # Image should no longer be attached
      assert Revix.Media.get_images_for_entry(checkin.id) == []
    end

    test "confirm_remove_image enqueues an Update activity", %{conn: conn, checkin: checkin} do
      image = image_fixture()
      Revix.Media.attach_image_to_entry(checkin.id, image.id, 0)

      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      render_click(view, "request_remove_image", %{"image-id" => image.id})
      render_click(view, "confirm_remove_image", %{})

      assert_enqueued(
        worker: Revix.Workers.DeliverEntryWorker,
        args: %{"entry_id" => checkin.id, "activity_type" => "Update"}
      )
    end
  end

  # ── File upload on edit ──────────────────────────────────────────────────────

  describe "file upload on edit page" do
    setup :register_and_log_in_person

    setup %{person: person} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})
      {:ok, checkin: checkin}
    end

    test "cancel_upload removes pending upload entry", %{conn: conn, checkin: checkin} do
      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")

      upload =
        file_input(view, "#edit-checkin-form", :images, [
          %{
            last_modified: 1_594_171_879_000,
            name: "new_photo.jpg",
            content: :binary.copy(<<0>>, 100),
            size: 100,
            type: "image/jpeg"
          }
        ])

      render_upload(upload, "new_photo.jpg")
      html = render(view)
      assert html =~ "new_photo.jpg"

      # Extract the ref from the upload struct and cancel
      [%{"ref" => ref}] = upload.entries
      render_click(view, "cancel_upload", %{"ref" => ref})
      html = render(view)
      refute html =~ "new_photo.jpg"
    end
  end

  # ── Caption, alt, reorder, validate ─────────────────────────────────────────

  describe "caption and alt text updates" do
    setup :register_and_log_in_person

    setup %{person: person} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})
      image = image_fixture()
      Revix.Media.attach_image_to_entry(checkin.id, image.id, 0)
      {:ok, checkin: checkin, image: image}
    end

    test "update_caption stores caption for existing image", %{
      conn: conn,
      checkin: checkin,
      image: image
    } do
      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")

      render_change(view, "update_caption", %{
        "_target" => ["photo_caption", image.id],
        "photo_caption" => %{image.id => "My caption"}
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert get_in(assigns, [:image_captions, image.id, :caption]) == "My caption"
    end

    test "update_alt stores alt text for existing image", %{
      conn: conn,
      checkin: checkin,
      image: image
    } do
      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")

      render_change(view, "update_alt", %{
        "_target" => ["photo_alt", image.id],
        "photo_alt" => %{image.id => "Alt text"}
      })

      assigns = :sys.get_state(view.pid).socket.assigns
      assert get_in(assigns, [:image_captions, image.id, :alt]) == "Alt text"
    end

    test "reorder_images updates upload_order and existing_image_order", %{
      conn: conn,
      checkin: checkin,
      image: image
    } do
      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")

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
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})
      {:ok, checkin: checkin}
    end

    test "validate event updates the form changeset", %{conn: conn, checkin: checkin} do
      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      html = render_change(view, "validate", %{"checkin" => %{"content" => "In progress"}})
      assert html =~ "In progress"
    end
  end

  # ── Datetime editing (owner only) ─────────────────────────────────────────────

  describe "datetime editing on edit page" do
    setup :register_and_log_in_person

    setup %{person: person} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})
      {:ok, place: place, checkin: checkin}
    end

    test "non-owner does not see datetime fields on edit page", %{conn: conn, checkin: checkin} do
      {:ok, _view, html} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      refute html =~ ~s(name="checkin[starts_at_local]")
      refute html =~ ~s(name="checkin[starts_tz]")
    end

    test "owner sees datetime fields on edit page", %{
      conn: conn,
      person: person,
      checkin: checkin
    } do
      Revix.People.set_person_role(person, :owner)
      {:ok, _view, html} = live(conn, ~p"/checkins/#{checkin.id}/edit")
      assert html =~ ~s(name="checkin[starts_at_local]")
      assert html =~ ~s(name="checkin[starts_tz]")
    end

    test "owner can update the checkin datetime", %{conn: conn, person: person, checkin: checkin} do
      Revix.People.set_person_role(person, :owner)
      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")

      new_local =
        NaiveDateTime.utc_now(:second)
        |> NaiveDateTime.add(-2, :hour)
        |> NaiveDateTime.to_iso8601()
        |> String.slice(0, 16)

      {:error, {:redirect, %{to: _path}}} =
        view
        |> form("#edit-checkin-form",
          checkin: %{starts_at_local: new_local, starts_tz: "Etc/UTC"}
        )
        |> render_submit()

      {:ok, updated} = Revix.Entries.get_local_checkin(checkin.id)
      assert updated.starts_tz == "Etc/UTC"
    end

    test "non-owner submit ignores datetime params even if injected", %{
      conn: conn,
      checkin: checkin
    } do
      original_utc = checkin.starts_at_utc

      {:ok, view, _html} = live(conn, ~p"/checkins/#{checkin.id}/edit")

      future =
        NaiveDateTime.utc_now(:second)
        |> NaiveDateTime.add(3600, :second)
        |> NaiveDateTime.to_iso8601()
        |> String.slice(0, 16)

      # Inject datetime params directly — the update changeset ignores them for non-owners
      {:error, {:redirect, _}} =
        render_submit(view, "submit", %{
          "checkin" => %{
            "content" => "Updated",
            "starts_at_local" => future,
            "starts_tz" => "Etc/UTC"
          }
        })

      {:ok, updated} = Revix.Entries.get_local_checkin(checkin.id)
      assert updated.starts_at_utc == original_utc
    end
  end

  # ── Draft checkin publish flow ────────────────────────────────────────────────

  describe "draft checkin — publish flow" do
    setup :register_and_log_in_person

    setup %{person: person} do
      place = place_fixture()

      draft =
        checkin_fixture(%{
          place_uri: place.uri,
          author_uri: person.uri,
          published_at_utc: nil,
          published_at_local: nil,
          published_tz: nil
        })

      {:ok, place: place, draft: draft}
    end

    test "shows Save as Draft and Publish buttons for draft checkin", %{conn: conn, draft: draft} do
      {:ok, _view, html} = live(conn, ~p"/checkins/#{draft.id}/edit")
      assert html =~ "Save as Draft"
      assert html =~ "Publish"
      refute html =~ "Save Changes"
    end

    test "Publish button shows confirmation modal", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/checkins/#{draft.id}/edit")

      view
      |> form("#edit-checkin-form", checkin: %{content: "Ready to publish"})
      |> render_submit(%{action: "publish"})

      html = render(view)
      assert html =~ "Publish this checkin?"
    end

    test "confirm_publish sets published_at and redirects", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/checkins/#{draft.id}/edit")

      view
      |> form("#edit-checkin-form", checkin: %{content: "Published!"})
      |> render_submit(%{action: "publish"})

      {:error, {:redirect, %{to: _path}}} = render_click(view, "confirm_publish", %{})

      {:ok, updated} = Entries.get_local_checkin(draft.id)
      assert updated.published_at_utc != nil
    end

    test "cancel_publish hides modal", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/checkins/#{draft.id}/edit")

      view
      |> form("#edit-checkin-form", checkin: %{content: "Maybe later"})
      |> render_submit(%{action: "publish"})

      render_click(view, "cancel_publish", %{})
      html = render(view)
      refute html =~ "Publish this checkin?"
    end
  end

  # ── Delete checkin flow ──────────────────────────────────────────────────────

  describe "delete checkin — draft only" do
    setup :register_and_log_in_person

    setup %{person: person} do
      place = place_fixture()

      draft =
        checkin_fixture(%{
          place_uri: place.uri,
          author_uri: person.uri,
          published_at_utc: nil,
          published_at_local: nil,
          published_tz: nil
        })

      published = checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})

      {:ok, place: place, draft: draft, published: published}
    end

    test "shows Delete button for draft checkin", %{conn: conn, draft: draft} do
      {:ok, _view, html} = live(conn, ~p"/checkins/#{draft.id}/edit")
      assert html =~ "Delete checkin"
    end

    test "does not show Delete button for published checkin", %{conn: conn, published: published} do
      {:ok, _view, html} = live(conn, ~p"/checkins/#{published.id}/edit")
      refute html =~ "Delete checkin"
    end

    test "request_delete shows confirmation modal", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/checkins/#{draft.id}/edit")
      render_click(view, "request_delete", %{})
      html = render(view)
      assert html =~ "Delete this checkin?"
    end

    test "cancel_delete hides modal", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/checkins/#{draft.id}/edit")
      render_click(view, "request_delete", %{})
      render_click(view, "cancel_delete", %{})
      html = render(view)
      refute html =~ "Delete this checkin?"
    end

    test "confirm_delete hard-deletes draft checkin and redirects", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/checkins/#{draft.id}/edit")
      render_click(view, "request_delete", %{})

      {:error, {:redirect, %{to: _path}}} = render_click(view, "confirm_delete", %{})

      assert {:error, :not_found} = Entries.get_local_checkin(draft.id)
    end

    test "published checkin: request_delete is ignored", %{conn: conn, published: published} do
      {:ok, view, _html} = live(conn, ~p"/checkins/#{published.id}/edit")
      render_click(view, "request_delete", %{})
      html = render(view)
      refute html =~ "Delete this checkin?"
    end
  end
end
