defmodule RevixWeb.CheckinEditLive do
  use RevixWeb, :live_view

  import RevixWeb.Live.CheckinHelpers

  alias Revix.Entries
  alias Revix.EntryPeople
  alias Revix.Media
  alias RevixWeb.CanonicalRoutes

  on_mount {RevixWeb.Live.PersonAuth, :require_authenticated_person}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    case Entries.get_local_checkin(id) do
      {:ok, checkin} ->
        if checkin.author_uri != scope.person.uri do
          {:ok,
           socket
           |> put_flash(:error, "You are not authorized to edit this checkin.")
           |> redirect(to: CanonicalRoutes.checkin_path(checkin))}
        else
          companions =
            EntryPeople.get_companions_for_entry(checkin.uri)
            |> Enum.filter(& &1.person)
            |> Enum.map(&normalize_person(&1.person))

          image_captions = build_image_captions(checkin.entry_images)

          socket =
            socket
            |> assign(:checkin, checkin)
            |> assign(:can_edit_datetime, scope.role == :owner)
            |> assign(:timezones, Tzdata.zone_list() |> Enum.sort())
            |> assign(
              :form,
              Entries.change_checkin_for_update(checkin, scope.role) |> to_form(as: :checkin)
            )
            |> assign(:companions, companions)
            |> assign(:companion_query, "")
            |> assign(:companion_results, [])
            |> assign(:image_captions, image_captions)
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
         |> put_flash(:error, "Checkin not found.")
         |> redirect(to: ~p"/checkins")}
    end
  end

  @impl true
  def handle_event("search_companions", %{"companion_query" => query}, socket) do
    results = search_companions(query, socket.assigns.current_scope.person.uri)
    {:noreply, assign(socket, companion_results: results, companion_query: query)}
  end

  def handle_event("add_companion", %{"uri" => uri}, socket) do
    scope = socket.assigns.current_scope
    checkin = socket.assigns.checkin

    case EntryPeople.add_companion(scope, checkin.uri, uri) do
      {:ok, _} ->
        companions =
          EntryPeople.get_companions_for_entry(checkin.uri)
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
    checkin = socket.assigns.checkin

    case EntryPeople.remove_companion(scope, checkin.uri, uri) do
      {:ok, _} ->
        companions =
          EntryPeople.get_companions_for_entry(checkin.uri)
          |> Enum.filter(& &1.person)
          |> Enum.map(&normalize_person(&1.person))

        {:noreply, assign(socket, :companions, companions)}

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
    checkin = socket.assigns.checkin

    if image_id, do: Media.remove_image_from_entry(checkin.id, image_id)

    captions = Map.delete(socket.assigns.image_captions, image_id)
    order = List.delete(socket.assigns.existing_image_order, image_id)
    {:ok, updated_checkin} = Entries.get_local_checkin(checkin.id)

    {:noreply,
     socket
     |> assign(:checkin, updated_checkin)
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

  def handle_event("validate", %{"checkin" => checkin_params}, socket) do
    role = socket.assigns.current_scope.role

    form =
      socket.assigns.checkin
      |> Entries.change_checkin_for_update(checkin_params, role)
      |> Map.put(:action, :validate)
      |> to_form(as: :checkin)

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("submit", %{"checkin" => checkin_params}, socket) do
    scope = socket.assigns.current_scope
    checkin = socket.assigns.checkin

    socket.assigns.existing_image_order
    |> Enum.with_index()
    |> Enum.each(fn {image_id, pos} ->
      Media.update_entry_image_position(checkin.id, image_id, pos)
    end)

    # Update captions and alt text for existing images
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

    next_position = length(checkin.entry_images)

    case Entries.update_local_checkin(checkin, checkin_params, scope.role) do
      {:ok, updated} ->
        consume_uploads(socket, updated.id, scope.person.uri, next_position)

        {:noreply,
         socket
         |> put_flash(:info, "Checkin updated.")
         |> redirect(to: CanonicalRoutes.checkin_path(updated))}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :form, changeset |> Map.put(:action, :update) |> to_form(as: :checkin))}
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
