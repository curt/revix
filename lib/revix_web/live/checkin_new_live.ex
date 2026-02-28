defmodule RevixWeb.CheckinNewLive do
  use RevixWeb, :live_view

  import RevixWeb.Live.CheckinHelpers

  alias Revix.Entries
  alias Revix.Places
  alias RevixWeb.CanonicalRoutes

  on_mount {RevixWeb.Live.PersonAuth, :require_authenticated_person}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    socket =
      socket
      |> assign(:checkin_form, Entries.change_checkin() |> to_form(as: :checkin))
      |> assign(:place_changeset, Places.change_place())
      |> assign(:place_results, [])
      |> assign(:place_searched, false)
      |> assign(:place_loading, false)
      |> assign(:selected_place, nil)
      |> assign(:place_mode, :none)
      |> assign(:companions, [])
      |> assign(:companion_query, "")
      |> assign(:companion_results, [])
      |> assign(:timezones, Tzdata.zone_list() |> Enum.sort())
      |> assign(:can_create_place, scope.role == :owner)
      |> assign(:upload_captions, %{})
      |> assign(:upload_order, [])
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

    Task.async(fn -> {:osm_results, Places.search_nearby_osm(lat, lon, accuracy), db_results} end)

    {:noreply,
     socket
     |> assign(:place_results, db_results)
     |> assign(:place_searched, true)
     |> assign(:place_loading, true)}
  end

  def handle_event("set_defaults", %{"local_datetime" => dt, "timezone" => tz}, socket) do
    form =
      Entries.change_checkin(%{"starts_at_local" => dt, "starts_tz" => tz})
      |> to_form(as: :checkin)

    {:noreply, assign(socket, :checkin_form, form)}
  end

  def handle_event("select_place", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    selected = Enum.at(socket.assigns.place_results, index)
    {:noreply, assign(socket, selected_place: selected, place_mode: :selected)}
  end

  def handle_event("select_manual", _params, socket) do
    if socket.assigns.can_create_place do
      {:noreply, assign(socket, selected_place: nil, place_mode: :manual)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate", %{"checkin" => checkin_params} = params, socket) do
    place_params = params["place_manual"] || %{}

    checkin_form =
      Entries.change_checkin(checkin_params)
      |> Map.put(:action, :validate)
      |> to_form(as: :checkin)

    place_changeset =
      if socket.assigns.place_mode == :manual do
        Places.change_place(place_params) |> Map.put(:action, :validate)
      else
        socket.assigns.place_changeset
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
    captions = Map.delete(socket.assigns.upload_captions, ref)
    order = List.delete(socket.assigns.upload_order, ref)

    {:noreply,
     socket
     |> cancel_upload(:images, ref)
     |> assign(:upload_captions, captions)
     |> assign(:upload_order, order)}
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

  def handle_event("submit", %{"checkin" => checkin_params} = params, socket) do
    scope = socket.assigns.current_scope
    place_params = params["place_manual"] || %{}
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
               companion_uris
             ) do
          {:ok, checkin} ->
            consume_uploads(socket, checkin.id, scope.person.uri)

            {:noreply,
             socket
             |> put_flash(:info, "Checkin created.")
             |> redirect(to: CanonicalRoutes.checkin_path(checkin))}

          {:error, changeset} ->
            {:noreply,
             assign(socket,
               checkin_form: Map.put(changeset, :action, :insert) |> to_form(as: :checkin)
             )}
        end

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "You do not have permission to create places.")
         |> assign(:place_mode, :none)
         |> assign(:selected_place, nil)}

      {:error, :no_place_selected} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please select a place before submitting.")}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           place_changeset: Map.put(changeset, :action, :insert)
         )}
    end
  end

  @impl true
  def handle_info({ref, {:osm_results, osm_results, db_results}}, socket)
      when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    merged = Places.merge_place_results(db_results, osm_results)
    {:noreply, socket |> assign(:place_results, merged) |> assign(:place_loading, false)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, assign(socket, :place_loading, false)}
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
    if scope.role == :owner do
      Places.create_local_place(
        manual_params,
        &CanonicalRoutes.place_uri/1,
        &CanonicalRoutes.place_url/2
      )
    else
      {:error, :unauthorized}
    end
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
    {f, ""} = Float.parse(val)
    f
  end
end
