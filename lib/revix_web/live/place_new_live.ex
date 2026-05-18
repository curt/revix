defmodule RevixWeb.PlaceNewLive do
  use RevixWeb, :live_view

  alias Revix.Overpass
  alias Revix.Places
  alias Revix.Places.Place
  alias RevixWeb.CanonicalRoutes

  on_mount {RevixWeb.Live.PersonAuth, :require_authenticated_person}

  @search_radius 500

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.role != :owner do
      {:ok,
       socket
       |> put_flash(:error, "You are not authorized to create places.")
       |> redirect(to: ~p"/places")}
    else
      form = Places.change_place() |> to_form(as: :place)

      {:ok,
       socket
       |> assign(:form, form)
       |> assign(:osm_form_type, nil)
       |> assign(:osm_form_id, nil)
       |> assign(:osm_results, [])
       |> assign(:osm_searched, false)
       |> assign(:osm_loading, false)
       |> assign(:osm_list_open, true)
       |> assign(:osm_sync_loading, false)
       |> assign(:osm_sync_error, nil)}
    end
  end

  @impl true
  def handle_event("validate", %{"place" => params}, socket) do
    form =
      %Place{}
      |> Place.create_changeset(params)
      |> Place.update_situation_changeset(params)
      |> Map.put(:action, :validate)
      |> to_form(as: :place)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:osm_form_type, params["osm_type"])
     |> assign(:osm_form_id, params["osm_id"])}
  end

  def handle_event("locate", %{"lat" => lat, "lon" => lon, "accuracy" => _accuracy}, socket) do
    current_params = form_params(socket.assigns.form)

    form =
      if current_params["latitude"] not in ["", nil] or
           current_params["longitude"] not in ["", nil] do
        socket.assigns.form
      else
        %Place{}
        |> Place.create_changeset(%{current_params | "latitude" => lat, "longitude" => lon})
        |> Place.update_situation_changeset(current_params)
        |> to_form(as: :place)
      end

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"place" => params}, socket) do
    case Places.create_local_place(
           params,
           &CanonicalRoutes.place_uri/1,
           &CanonicalRoutes.place_url/2
         ) do
      {:ok, new_place} ->
        {:noreply,
         socket
         |> put_flash(:info, "Place created.")
         |> redirect(to: CanonicalRoutes.place_path(new_place))}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :form, changeset |> Map.put(:action, :insert) |> to_form(as: :place))}
    end
  end

  def handle_event("search_nearby", _params, socket) do
    current_params = form_params(socket.assigns.form)
    lat = parse_float(current_params["latitude"])
    lon = parse_float(current_params["longitude"])

    if lat && lon do
      Task.async(fn -> {:osm_results, Places.search_nearby_osm(lat, lon, @search_radius)} end)

      {:noreply,
       socket
       |> assign(:osm_results, [])
       |> assign(:osm_searched, true)
       |> assign(:osm_loading, true)
       |> assign(:osm_list_open, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_osm_result", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    result = Enum.at(socket.assigns.osm_results, index)
    current_params = form_params(socket.assigns.form)

    form =
      Place.create_changeset(%Place{}, %{
        current_params
        | "osm_type" => to_string(result.osm_type),
          "osm_id" => to_string(result.osm_id)
      })
      |> to_form(as: :place)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:osm_form_type, to_string(result.osm_type))
     |> assign(:osm_form_id, to_string(result.osm_id))
     |> assign(:osm_list_open, false)}
  end

  def handle_event("toggle_osm_list", _params, socket) do
    {:noreply, assign(socket, :osm_list_open, not socket.assigns.osm_list_open)}
  end

  def handle_event("sync_osm", _params, socket) do
    osm_type_str = socket.assigns.osm_form_type
    osm_id_str = socket.assigns.osm_form_id

    with true <- osm_type_str not in [nil, ""],
         true <- osm_id_str not in [nil, ""],
         osm_type <- String.to_existing_atom(osm_type_str),
         {osm_id, ""} <- Integer.parse(osm_id_str) do
      Task.async(fn -> {:osm_sync, Overpass.fetch_element(osm_type, osm_id)} end)

      {:noreply,
       socket
       |> assign(:osm_sync_loading, true)
       |> assign(:osm_sync_error, nil)}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({ref, {:osm_results, osm_results}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, socket |> assign(:osm_results, osm_results) |> assign(:osm_loading, false)}
  end

  def handle_info({ref, {:osm_sync, result}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, %{name: name, lat: lat, lon: lon}} ->
        current_params = form_params(socket.assigns.form)

        form =
          Place.create_changeset(%Place{}, %{
            current_params
            | "name" => name,
              "latitude" => lat,
              "longitude" => lon
          })
          |> to_form(as: :place)

        {:noreply,
         socket
         |> assign(:form, form)
         |> assign(:osm_sync_loading, false)
         |> assign(:osm_sync_error, nil)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:osm_sync_loading, false)
         |> assign(:osm_sync_error, "OSM element not found. Check the type and ID.")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:osm_sync_loading, false)
         |> assign(:osm_sync_error, "Failed to fetch from OSM. Try again later.")}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:osm_loading, false)
     |> assign(:osm_sync_loading, false)
     |> assign(:osm_sync_error, "OSM request failed unexpectedly.")}
  end

  defp parse_float(""), do: nil
  defp parse_float(nil), do: nil

  defp parse_float(val) do
    case Float.parse(to_string(val)) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp form_params(form) do
    %{
      "name" => Phoenix.HTML.Form.input_value(form, :name) |> to_string(),
      "latitude" => Phoenix.HTML.Form.input_value(form, :latitude) |> to_string(),
      "longitude" => Phoenix.HTML.Form.input_value(form, :longitude) |> to_string(),
      "osm_type" => Phoenix.HTML.Form.input_value(form, :osm_type) |> to_string(),
      "osm_id" => Phoenix.HTML.Form.input_value(form, :osm_id) |> to_string(),
      "country" => Phoenix.HTML.Form.input_value(form, :country) |> to_string(),
      "city" => Phoenix.HTML.Form.input_value(form, :city) |> to_string(),
      "secondary" => Phoenix.HTML.Form.input_value(form, :secondary) |> to_string()
    }
  end
end
