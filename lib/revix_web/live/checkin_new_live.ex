defmodule RevixWeb.CheckinNewLive do
  use RevixWeb, :live_view

  import RevixWeb.Live.EntryHelpers

  alias Revix.Entries
  alias Revix.Places
  alias RevixWeb.CanonicalRoutes

  on_mount {RevixWeb.Live.PersonAuth, :require_authenticated_person}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    socket =
      socket
      |> assign(:checkin_form, Entries.change_checkin(scope.role) |> to_form(as: :checkin))
      |> assign(:place_changeset, Places.change_place())
      |> assign(:place_results, [])
      |> assign(:place_searched, false)
      |> assign(:place_loading, false)
      |> assign(:place_task_ref, nil)
      |> assign(:place_list_open, true)
      |> assign(:selected_place, nil)
      |> assign(:place_mode, :none)
      |> assign(:companions, [])
      |> assign(:companion_query, "")
      |> assign(:companion_results, [])
      |> assign(:timezones, Tzdata.zone_list() |> Enum.sort())
      |> assign(:can_create_place, scope.role in [:owner, :contributor])
      |> assign(:can_edit_place_coords, scope.role == :owner)
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
  end

  @impl true
  def handle_event("locate", %{"lat" => lat, "lon" => lon, "accuracy" => accuracy}, socket) do
    lat = to_float(lat)
    lon = to_float(lon)
    accuracy = to_float(accuracy)

    db_results = Places.search_nearby_db(lat, lon, accuracy)

    task =
      Task.async(fn ->
        {:osm_results, Places.search_nearby_osm(lat, lon, accuracy), db_results}
      end)

    existing = socket.assigns.place_changeset.changes

    place_changeset =
      if existing[:latitude] || existing[:longitude] do
        socket.assigns.place_changeset
      else
        attrs = %{"latitude" => lat, "longitude" => lon}
        attrs = if name = existing[:name], do: Map.put(attrs, "name", name), else: attrs
        Places.change_place(attrs)
      end

    {:noreply,
     socket
     |> assign(:place_results, db_results)
     |> assign(:place_searched, true)
     |> assign(:place_loading, true)
     |> assign(:place_task_ref, task.ref)
     |> assign(:place_list_open, true)
     |> assign(:place_changeset, place_changeset)}
  end

  def handle_event("set_defaults", %{"local_datetime" => dt, "timezone" => tz}, socket) do
    role = socket.assigns.current_scope.role

    form =
      Entries.change_checkin(role, %{"starts_at_local" => dt, "starts_tz" => tz})
      |> to_form(as: :checkin)

    {:noreply, assign(socket, :checkin_form, form)}
  end

  def handle_event("select_place", %{"index" => index_str}, socket) do
    with {:ok, index} <- parse_index(index_str),
         selected when not is_nil(selected) <- Enum.at(socket.assigns.place_results, index) do
      {:noreply,
       assign(socket, selected_place: selected, place_mode: :selected, place_list_open: false)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_place_list", _params, socket) do
    {:noreply, assign(socket, :place_list_open, not socket.assigns.place_list_open)}
  end

  def handle_event("select_manual", _params, socket) do
    if socket.assigns.can_create_place do
      {:noreply, assign(socket, selected_place: nil, place_mode: :manual, place_list_open: false)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate", params, socket) do
    role = socket.assigns.current_scope.role

    checkin_form =
      Entries.change_checkin(role, params["checkin"] || %{})
      |> Map.put(:action, :validate)
      |> to_form(as: :checkin)

    place_changeset =
      case params["place_manual"] do
        nil ->
          socket.assigns.place_changeset

        place_params ->
          action = if socket.assigns.place_mode == :manual, do: :validate, else: nil
          Places.change_place(place_params) |> Map.put(:action, action)
      end

    {:noreply,
     socket
     |> assign(:checkin_form, checkin_form)
     |> assign(:place_changeset, place_changeset)}
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
        %{"checkin" => checkin_params, "action" => "publish"} = params,
        socket
      ) do
    {:noreply,
     socket
     |> assign(:show_publish_modal, true)
     |> assign(:pending_publish_params, %{
       checkin: checkin_params,
       place: params["place_manual"] || %{}
     })}
  end

  def handle_event("submit", %{"checkin" => checkin_params} = params, socket) do
    do_create_checkin(socket, checkin_params, params["place_manual"] || %{}, :draft)
  end

  def handle_event("confirm_publish", _params, socket) do
    %{checkin: checkin_params, place: place_params} = socket.assigns.pending_publish_params
    do_create_checkin(socket, checkin_params, place_params, :publish)
  end

  def handle_event("cancel_publish", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_publish_modal, false)
     |> assign(:pending_publish_params, nil)}
  end

  defp do_create_checkin(socket, checkin_params, place_params, mode) do
    scope = socket.assigns.current_scope
    companion_uris = Enum.map(socket.assigns.companions, & &1.uri)

    case resolve_place(
           scope,
           socket.assigns.place_mode,
           socket.assigns.selected_place,
           place_params
         ) do
      {:ok, place} ->
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

            dest =
              if mode == :publish,
                do: CanonicalRoutes.checkin_path(checkin),
                else: ~p"/checkins/#{checkin.id}/edit"

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

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> assign(:show_publish_modal, false)
         |> put_flash(:error, "You do not have permission to create places.")
         |> assign(:place_mode, :none)
         |> assign(:selected_place, nil)}

      {:error, :no_place_selected} ->
        {:noreply,
         socket
         |> assign(:show_publish_modal, false)
         |> put_flash(:error, "Please select a place before submitting.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:show_publish_modal, false)
         |> assign(place_changeset: Map.put(changeset, :action, :insert))}
    end
  end

  @impl true
  def handle_info({ref, {:osm_results, osm_results, db_results}}, socket)
      when is_reference(ref) do
    if socket.assigns.place_task_ref == ref do
      Process.demonitor(ref, [:flush])
      merged = Places.merge_place_results(db_results, osm_results)

      socket =
        socket
        |> assign(:place_results, merged)
        |> assign(:place_loading, false)
        |> assign(:place_task_ref, nil)

      socket =
        if socket.assigns.place_mode == :selected do
          selected = socket.assigns.selected_place

          still_valid =
            case selected.source do
              :db ->
                Enum.any?(db_results, &(&1.id == selected.id))

              :osm ->
                Enum.any?(osm_results, fn r ->
                  r.osm_type == selected.osm_type && r.osm_id == selected.osm_id
                end)
            end

          if still_valid do
            socket
          else
            assign(socket, place_mode: :none, selected_place: nil, place_list_open: true)
          end
        else
          socket
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket) do
    if socket.assigns.place_task_ref == ref do
      {:noreply,
       socket
       |> assign(:place_loading, false)
       |> assign(:place_task_ref, nil)}
    else
      {:noreply, socket}
    end
  end

  attr :changeset, Ecto.Changeset, required: true
  attr :can_edit_coords, :boolean, required: true

  defp manual_place_fields(assigns) do
    ~H"""
    <div class="mt-2">
      <.input
        name="place_manual[name]"
        type="text"
        label="Place Name"
        value={@changeset.changes[:name] || ""}
        errors={
          if @changeset.action do
            @changeset.errors |> Keyword.get_values(:name) |> Enum.map(&elem(&1, 0))
          else
            []
          end
        }
      />
      <div class="sm:flex sm:gap-4">
        <div class="sm:w-1/2">
          <.input
            name="place_manual[latitude]"
            type="number"
            label="Latitude"
            value={@changeset.changes[:latitude] || ""}
            step="any"
            readonly={not @can_edit_coords}
            errors={
              if @changeset.action do
                @changeset.errors |> Keyword.get_values(:latitude) |> Enum.map(&elem(&1, 0))
              else
                []
              end
            }
          />
        </div>
        <div class="sm:w-1/2">
          <.input
            name="place_manual[longitude]"
            type="number"
            label="Longitude"
            value={@changeset.changes[:longitude] || ""}
            step="any"
            readonly={not @can_edit_coords}
            errors={
              if @changeset.action do
                @changeset.errors |> Keyword.get_values(:longitude) |> Enum.map(&elem(&1, 0))
              else
                []
              end
            }
          />
        </div>
      </div>
    </div>
    """
  end

  # Resolve or create a place based on the current mode and selection.
  defp resolve_place(_scope, :selected, %{source: :db, id: id}, _manual_params) do
    Places.get_local_place(id)
  end

  defp resolve_place(_scope, :selected, %{source: :osm} = result, _manual_params) do
    osm_type = result.osm_type
    osm_id = result.osm_id

    case Places.get_local_place_by_osm(osm_type, osm_id) do
      %Revix.Places.Place{} = place ->
        {:ok, place}

      nil ->
        Places.create_local_place(
          %{
            "name" => result.name,
            "latitude" => result.lat,
            "longitude" => result.lon,
            "osm_type" => to_string(osm_type),
            "osm_id" => to_string(osm_id)
          },
          &CanonicalRoutes.place_uri/1,
          &CanonicalRoutes.place_url/2
        )
    end
  end

  defp resolve_place(scope, :manual, _selected, manual_params) do
    if scope.role in [:owner, :contributor] do
      Places.create_local_place(
        manual_params,
        &CanonicalRoutes.place_uri/1,
        &CanonicalRoutes.place_url/2
      )
    else
      {:error, :unauthorized}
    end
  end

  defp resolve_place(scope, :none, _selected, manual_params)
       when map_size(manual_params) > 0 do
    resolve_place(scope, :manual, nil, manual_params)
  end

  defp resolve_place(_scope, :none, _selected, _manual_params) do
    {:error, :no_place_selected}
  end

  defp resolve_place(_scope, _mode, nil, _manual_params) do
    {:error, :no_place_selected}
  end

  defp to_float(val) when is_float(val), do: val
  defp to_float(val) when is_integer(val), do: val * 1.0

  defp to_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, ""} -> f
      _ -> 0.0
    end
  end

  defp parse_index(value) do
    case Integer.parse(value) do
      {index, ""} when index >= 0 -> {:ok, index}
      _ -> :error
    end
  end
end
