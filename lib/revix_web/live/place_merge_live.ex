defmodule RevixWeb.PlaceMergeLive do
  use RevixWeb, :live_view

  alias Revix.Places
  alias RevixWeb.CanonicalRoutes

  on_mount {RevixWeb.Live.PersonAuth, :require_authenticated_person}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.role != :owner do
      {:ok,
       socket
       |> put_flash(:error, "You are not authorized to merge places.")
       |> redirect(to: ~p"/places/#{id}")}
    else
      case Places.get_local_place(id) do
        {:ok, place} ->
          nearby = Places.get_local_places_near(place, limit: 10)

          {:ok,
           socket
           |> assign(:place, place)
           |> assign(:nearby, nearby)
           |> assign(:selected_ids, MapSet.new())
           |> assign(:confirm, false)}

        {:error, :not_found} ->
          {:ok,
           socket
           |> put_flash(:error, "Place not found.")
           |> redirect(to: ~p"/places")}
      end
    end
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected = socket.assigns.selected_ids

    updated =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, :selected_ids, updated)}
  end

  def handle_event("confirm", _params, socket) do
    if MapSet.size(socket.assigns.selected_ids) == 0 do
      {:noreply, socket}
    else
      {:noreply, assign(socket, :confirm, true)}
    end
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, assign(socket, :confirm, false)}
  end

  def handle_event("merge", _params, socket) do
    target = socket.assigns.place
    source_ids = MapSet.to_list(socket.assigns.selected_ids)

    case Places.merge_into(target, source_ids) do
      {:ok, _counts} ->
        {:noreply,
         socket
         |> put_flash(:info, "Places merged successfully.")
         |> redirect(to: CanonicalRoutes.place_path(target))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:confirm, false)
         |> put_flash(:error, "Merge failed. The selected places may no longer exist.")}
    end
  end
end
