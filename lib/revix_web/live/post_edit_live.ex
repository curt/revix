defmodule RevixWeb.PostEditLive do
  use RevixWeb, :live_view

  import RevixWeb.Live.EntryHelpers

  alias Revix.Entries
  alias Revix.EntryPeople
  alias Revix.EntryPlaces
  alias Revix.Media
  alias Revix.Places
  alias RevixWeb.CanonicalRoutes

  on_mount {RevixWeb.Live.PersonAuth, :require_authenticated_person}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    case Entries.get_local_post(id) do
      {:ok, post} ->
        cond do
          post.author_uri != scope.person.uri ->
            {:ok,
             socket
             |> put_flash(:error, "You are not authorized to edit this post.")
             |> redirect(to: CanonicalRoutes.post_path(post))}

          not is_nil(post.tombstoned_at) ->
            {:ok,
             socket
             |> put_flash(:error, "This post has been deleted.")
             |> redirect(to: ~p"/posts")}

          true ->
            companions =
              EntryPeople.get_companions_for_entry(post.uri)
              |> Enum.filter(& &1.person)
              |> Enum.map(&normalize_person(&1.person))

            image_captions = build_image_captions(post.entry_images)

            socket =
              socket
              |> assign(:post, post)
              |> assign(:timezones, Tzdata.zone_list() |> Enum.sort())
              |> assign(
                :form,
                Entries.change_post_for_update(post, scope.role) |> to_form(as: :post)
              )
              |> assign(:companions, companions)
              |> assign(:companion_query, "")
              |> assign(:companion_results, [])
              |> assign(:selected_places, Enum.map(post.entry_places, & &1.place))
              |> assign(:place_query, "")
              |> assign(:place_results, [])
              |> assign(:image_captions, image_captions)
              |> assign(
                :can_edit_datetime,
                scope.role == :owner or is_nil(post.published_at_utc)
              )
              |> assign(:post_published, not is_nil(post.published_at_utc))
              |> assign(:show_publish_modal, false)
              |> assign(:pending_publish_params, nil)
              |> assign(:pending_delete, false)
              |> assign(:upload_captions, %{})
              |> assign(:upload_order, [])
              |> assign(:existing_image_order, [])
              |> assign(:pending_remove_image_id, nil)
              |> allow_upload(:images,
                accept: ~w(.jpg .jpeg .gif .png .webp),
                max_entries: 10,
                max_file_size: 20_000_000
              )

            {:ok, socket}
        end

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Post not found.")
         |> redirect(to: ~p"/posts")}
    end
  end

  @impl true
  def handle_event("search_companions", %{"companion_query" => query}, socket) do
    results = search_companions(query, socket.assigns.current_scope.person.uri)
    {:noreply, assign(socket, companion_results: results, companion_query: query)}
  end

  def handle_event("add_companion", %{"uri" => uri}, socket) do
    scope = socket.assigns.current_scope
    post = socket.assigns.post

    case EntryPeople.add_companion(scope, post.uri, uri) do
      {:ok, _} ->
        companions =
          EntryPeople.get_companions_for_entry(post.uri)
          |> Enum.filter(& &1.person)
          |> Enum.map(&normalize_person(&1.person))

        {:noreply,
         assign(socket,
           companions: companions,
           companion_results: [],
           companion_query: ""
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_companion", %{"uri" => uri}, socket) do
    scope = socket.assigns.current_scope
    post = socket.assigns.post

    case EntryPeople.remove_companion(scope, post.uri, uri) do
      {:ok, _} ->
        companions =
          EntryPeople.get_companions_for_entry(post.uri)
          |> Enum.filter(& &1.person)
          |> Enum.map(&normalize_person(&1.person))

        {:noreply, assign(socket, :companions, companions)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("search_places", %{"place_query" => query}, socket) do
    results = if String.trim(query) == "", do: [], else: Places.search_local_places(query)
    {:noreply, assign(socket, place_results: results, place_query: query)}
  end

  def handle_event("add_place", %{"uri" => uri}, socket) do
    post = socket.assigns.post
    selected = socket.assigns.selected_places
    already = Enum.any?(selected, &(&1.uri == uri))

    if already do
      {:noreply, assign(socket, place_results: [], place_query: "")}
    else
      case EntryPlaces.add_place(post.uri, uri) do
        {:ok, _} ->
          places =
            EntryPlaces.get_places_for_entry(post.uri)
            |> Enum.map(& &1.place)
            |> Enum.filter(& &1)

          {:noreply, assign(socket, selected_places: places, place_results: [], place_query: "")}

        {:error, _} ->
          {:noreply, socket}
      end
    end
  end

  def handle_event("remove_place", %{"uri" => uri}, socket) do
    post = socket.assigns.post

    case EntryPlaces.remove_place(post.uri, uri) do
      {:ok, _} ->
        selected = Enum.reject(socket.assigns.selected_places, &(&1.uri == uri))
        {:noreply, assign(socket, :selected_places, selected)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("request_remove_image", %{"image-id" => image_id}, socket) do
    {:noreply, assign(socket, :pending_remove_image_id, image_id)}
  end

  def handle_event("cancel_remove_image", _params, socket) do
    {:noreply, assign(socket, :pending_remove_image_id, nil)}
  end

  def handle_event("confirm_remove_image", _params, socket) do
    image_id = socket.assigns.pending_remove_image_id
    post = socket.assigns.post
    scope = socket.assigns.current_scope

    if image_id do
      Media.remove_image_from_entry(post.id, image_id)
      Entries.update_local_post(post, %{}, scope.role, &CanonicalRoutes.post_url/1)
    end

    captions = Map.delete(socket.assigns.image_captions, image_id)
    order = List.delete(socket.assigns.existing_image_order, image_id)
    {:ok, updated_post} = Entries.get_local_post(post.id)

    {:noreply,
     socket
     |> assign(:post, updated_post)
     |> assign(:pending_remove_image_id, nil)
     |> assign(:image_captions, captions)
     |> assign(:existing_image_order, order)}
  end

  def handle_event(
        "update_caption",
        %{"_target" => [_, key], "photo_caption" => captions_map},
        socket
      ) do
    {:noreply, update_photo_field(socket, key, :caption, Map.get(captions_map, key, ""))}
  end

  def handle_event("update_alt", %{"_target" => [_, key], "photo_alt" => alts_map}, socket) do
    {:noreply, update_photo_field(socket, key, :alt, Map.get(alts_map, key, ""))}
  end

  def handle_event("reorder_images", %{"order" => order}, socket) when is_list(order) do
    refs = for %{"ref" => r} <- order, do: r
    ids = for %{"image_id" => i} <- order, do: i
    {:noreply, socket |> assign(:upload_order, refs) |> assign(:existing_image_order, ids)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, handle_cancel_upload(socket, ref)}
  end

  def handle_event("set_timezone", %{"timezone" => tz}, socket) do
    {:noreply, apply_default_timezone(socket, tz)}
  end

  def handle_event("validate", %{"post" => post_params}, socket) do
    form = build_validate_form(socket, post_params)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("submit", %{"post" => post_params, "action" => "publish"}, socket) do
    {:noreply,
     socket
     |> assign(:show_publish_modal, true)
     |> assign(:pending_publish_params, post_params)}
  end

  def handle_event("submit", %{"post" => post_params}, socket) do
    do_save_post(socket, post_params)
  end

  def handle_event("cancel_publish", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_publish_modal, false)
     |> assign(:pending_publish_params, nil)}
  end

  def handle_event("confirm_publish", _params, socket) do
    scope = socket.assigns.current_scope
    post = socket.assigns.post
    post_params = socket.assigns.pending_publish_params
    next_position = run_image_side_effects(socket)

    case Entries.publish_local_post(post, post_params, scope.role, &CanonicalRoutes.post_url/1,
           enqueue_delivery: false
         ) do
      {:ok, updated} ->
        consume_uploads(socket, updated.id, scope.person.uri, next_position)
        Entries.enqueue_delivery(updated, "Create")

        {:noreply,
         socket
         |> put_flash(:info, "Post published.")
         |> redirect(to: CanonicalRoutes.post_path(updated))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:show_publish_modal, false)
         |> assign(:form, changeset |> Map.put(:action, :update) |> to_form(as: :post))}
    end
  end

  def handle_event("request_delete", _params, socket) do
    {:noreply, assign(socket, :pending_delete, true)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :pending_delete, false)}
  end

  def handle_event("confirm_delete", _params, %{assigns: %{post_published: true}} = socket) do
    post = socket.assigns.post
    person = socket.assigns.current_scope.person

    case Entries.tombstone_entry(post) do
      {:ok, _tombstoned} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post deleted.")
         |> redirect(to: CanonicalRoutes.person_path(person))}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:pending_delete, false)
         |> put_flash(:error, "Could not delete post.")}
    end
  end

  def handle_event("confirm_delete", _params, socket) do
    post = socket.assigns.post
    person = socket.assigns.current_scope.person

    case Entries.delete_entry(post) do
      {:ok, _deleted} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post deleted.")
         |> redirect(to: CanonicalRoutes.person_path(person))}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:pending_delete, false)
         |> put_flash(:error, "Could not delete post.")}
    end
  end

  defp apply_default_timezone(%{assigns: %{post_published: true}} = socket, _tz), do: socket

  defp apply_default_timezone(socket, tz) do
    form =
      Entries.change_post_for_draft_update(socket.assigns.post, %{"published_tz" => tz})
      |> to_form(as: :post)

    assign(socket, :form, form)
  end

  defp build_validate_form(%{assigns: %{post_published: true}} = socket, post_params) do
    role = socket.assigns.current_scope.role

    socket.assigns.post
    |> Entries.change_post_for_update(post_params, role)
    |> Map.put(:action, :validate)
    |> to_form(as: :post)
  end

  defp build_validate_form(%{assigns: %{post_published: false}} = socket, post_params) do
    socket.assigns.post
    |> Entries.change_post_for_draft_update(post_params)
    |> Map.put(:action, :validate)
    |> to_form(as: :post)
  end

  defp run_image_side_effects(socket) do
    post = socket.assigns.post

    socket.assigns.existing_image_order
    |> Enum.with_index()
    |> Enum.each(fn {image_id, pos} ->
      Media.update_entry_image_position(post.id, image_id, pos)
    end)

    Enum.each(socket.assigns.image_captions, fn {image_id, attrs} ->
      case Media.get_image(image_id) do
        {:ok, image} ->
          Media.update_image(image, %{
            caption: attrs[:caption] || attrs["caption"],
            alt: attrs[:alt] || attrs["alt"]
          })

        _ ->
          :ok
      end
    end)

    length(post.entry_images)
  end

  defp do_save_post(%{assigns: %{post_published: false}} = socket, post_params) do
    scope = socket.assigns.current_scope
    post = socket.assigns.post
    next_position = run_image_side_effects(socket)

    case Entries.update_draft_post(post, post_params) do
      {:ok, updated} ->
        consume_uploads(socket, updated.id, scope.person.uri, next_position)

        {:noreply,
         socket
         |> put_flash(:info, "Draft saved.")
         |> redirect(to: CanonicalRoutes.post_path(updated))}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :form, changeset |> Map.put(:action, :update) |> to_form(as: :post))}
    end
  end

  defp do_save_post(socket, post_params) do
    scope = socket.assigns.current_scope
    post = socket.assigns.post
    next_position = run_image_side_effects(socket)

    case Entries.update_local_post(post, post_params, scope.role, &CanonicalRoutes.post_url/1,
           enqueue_delivery: false
         ) do
      {:ok, updated} ->
        consume_uploads(socket, updated.id, scope.person.uri, next_position)
        Entries.enqueue_delivery(updated, "Update")

        {:noreply,
         socket
         |> put_flash(:info, "Post saved.")
         |> redirect(to: CanonicalRoutes.post_path(updated))}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :form, changeset |> Map.put(:action, :update) |> to_form(as: :post))}
    end
  end

  defp update_photo_field(socket, key, field, value) do
    if Map.has_key?(socket.assigns.image_captions, key) do
      captions =
        Map.update(
          socket.assigns.image_captions,
          key,
          %{caption: "", alt: ""},
          &Map.put(&1, field, value)
        )

      assign(socket, :image_captions, captions)
    else
      captions =
        Map.update(
          socket.assigns.upload_captions,
          key,
          %{caption: "", alt: ""},
          &Map.put(&1, field, value)
        )

      assign(socket, :upload_captions, captions)
    end
  end

  defp build_image_captions(entry_images) do
    Map.new(entry_images, fn ei ->
      {ei.image.id, %{caption: ei.image.caption || "", alt: ei.image.alt || ""}}
    end)
  end
end
