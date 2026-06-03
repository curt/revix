defmodule RevixWeb.CheckinFromPlaceLive do
  use RevixWeb, :live_view

  import RevixWeb.Live.EntryHelpers

  alias Revix.Entries
  alias Revix.Places
  alias RevixWeb.CanonicalRoutes

  on_mount {RevixWeb.Live.PersonAuth, :require_authenticated_person}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.role != :owner do
      {:ok,
       socket
       |> put_flash(:error, "You are not authorized to check in from a place page.")
       |> redirect(to: ~p"/checkins/new")}
    else
      case Places.get_local_place(id) do
        {:ok, place} ->
          socket =
            socket
            |> assign(:place, place)
            |> assign(:checkin_form, Entries.change_checkin(scope.role) |> to_form(as: :checkin))
            |> assign(:companions, [])
            |> assign(:companion_query, "")
            |> assign(:companion_results, [])
            |> assign(:timezones, Tzdata.zone_list() |> Enum.sort())
            |> assign(:can_edit_datetime, scope.role == :owner)
            |> assign(:upload_captions, %{})
            |> assign(:upload_order, [])
            |> assign(:show_publish_modal, false)
            |> assign(:pending_publish_params, nil)
            |> allow_upload(:images,
              accept: ~w(.jpg .jpeg .gif .png .webp),
              max_entries: 10,
              max_file_size: 20_000_000
            )

          {:ok, socket}

        {:error, :not_found} ->
          {:ok,
           socket
           |> put_flash(:error, "Place not found.")
           |> redirect(to: ~p"/places")}
      end
    end
  end

  @impl true
  def handle_event("set_defaults", %{"local_datetime" => dt, "timezone" => tz}, socket) do
    role = socket.assigns.current_scope.role

    form =
      Entries.change_checkin(role, %{"starts_at_local" => dt, "starts_tz" => tz})
      |> to_form(as: :checkin)

    {:noreply, assign(socket, :checkin_form, form)}
  end

  def handle_event("validate", params, socket) do
    role = socket.assigns.current_scope.role

    checkin_form =
      Entries.change_checkin(role, params["checkin"] || %{})
      |> Map.put(:action, :validate)
      |> to_form(as: :checkin)

    {:noreply, assign(socket, :checkin_form, checkin_form)}
  end

  def handle_event("search_companions", %{"companion_query" => query}, socket) do
    results = search_companions(query, socket.assigns.current_scope.person.uri)
    {:noreply, assign(socket, companion_results: results, companion_query: query)}
  end

  def handle_event("add_companion", %{"uri" => uri}, socket) do
    scope = socket.assigns.current_scope

    if uri == scope.person.uri do
      {:noreply, assign(socket, companion_results: [], companion_query: "")}
    else
      companions = socket.assigns.companions
      already = Enum.any?(companions, &(&1.uri == uri))

      if already do
        {:noreply, assign(socket, companion_results: [], companion_query: "")}
      else
        new_companion =
          Enum.find(socket.assigns.companion_results, &(&1.uri == uri)) ||
            %{uri: uri, display_name: nil, username: nil, avatar_url: nil}

        {:noreply,
         assign(socket,
           companions: companions ++ [new_companion],
           companion_results: [],
           companion_query: ""
         )}
      end
    end
  end

  def handle_event("remove_companion", %{"uri" => uri}, socket) do
    companions = Enum.reject(socket.assigns.companions, &(&1.uri == uri))
    {:noreply, assign(socket, :companions, companions)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, handle_cancel_upload(socket, ref)}
  end

  def handle_event(
        "update_caption",
        %{"_target" => [_, ref], "photo_caption" => captions_map},
        socket
      ) do
    value = Map.get(captions_map, ref, "")

    captions =
      Map.update(
        socket.assigns.upload_captions,
        ref,
        %{caption: value, alt: ""},
        &Map.put(&1, :caption, value)
      )

    {:noreply, assign(socket, :upload_captions, captions)}
  end

  def handle_event("update_alt", %{"_target" => [_, ref], "photo_alt" => alts_map}, socket) do
    value = Map.get(alts_map, ref, "")

    captions =
      Map.update(
        socket.assigns.upload_captions,
        ref,
        %{caption: "", alt: value},
        &Map.put(&1, :alt, value)
      )

    {:noreply, assign(socket, :upload_captions, captions)}
  end

  def handle_event("reorder_images", %{"order" => order}, socket) when is_list(order) do
    refs = for %{"ref" => r} <- order, do: r
    {:noreply, assign(socket, :upload_order, refs)}
  end

  def handle_event(
        "submit",
        %{"checkin" => checkin_params, "action" => "publish"},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:show_publish_modal, true)
     |> assign(:pending_publish_params, checkin_params)}
  end

  def handle_event("submit", %{"checkin" => checkin_params}, socket) do
    do_create_checkin(socket, checkin_params, :draft)
  end

  def handle_event("confirm_publish", _params, socket) do
    do_create_checkin(socket, socket.assigns.pending_publish_params, :publish)
  end

  def handle_event("cancel_publish", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_publish_modal, false)
     |> assign(:pending_publish_params, nil)}
  end

  defp do_create_checkin(socket, checkin_params, mode) do
    scope = socket.assigns.current_scope
    place = socket.assigns.place
    companion_uris = Enum.map(socket.assigns.companions, & &1.uri)

    case Entries.create_local_checkin_with_companions(
           scope,
           place,
           checkin_params,
           &CanonicalRoutes.checkin_uri/1,
           &CanonicalRoutes.checkin_url/2,
           companion_uris,
           enqueue_delivery: false,
           mode: mode
         ) do
      {:ok, checkin} ->
        consume_uploads(socket, checkin.id, scope.person.uri)
        if mode == :publish, do: Entries.enqueue_delivery(checkin, "Create")

        flash = if mode == :publish, do: "Checkin published.", else: "Draft saved."
        dest = if mode == :publish, do: CanonicalRoutes.checkin_path(checkin), else: ~p"/checkins/#{checkin.id}/edit"

        {:noreply,
         socket
         |> put_flash(:info, flash)
         |> redirect(to: dest)}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:show_publish_modal, false)
         |> assign(
           checkin_form: Map.put(changeset, :action, :insert) |> to_form(as: :checkin)
         )}
    end
  end
end
