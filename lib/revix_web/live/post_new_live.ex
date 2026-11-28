defmodule RevixWeb.PostNewLive do
  use RevixWeb, :live_view

  alias RevixWeb.Live.EntryForm

  import RevixWeb.Live.EntryHelpers

  alias Revix.Entries
  alias Revix.Places
  alias RevixWeb.CanonicalRoutes

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    socket =
      socket
      |> assign(:post_form, Entries.change_post(scope.role) |> to_form(as: :post))
      |> assign(:companions, [])
      |> assign(:companion_query, "")
      |> assign(:companion_results, [])
      |> assign(:selected_places, [])
      |> assign(:place_query, "")
      |> assign(:place_results, [])
      |> assign(:timezones, Tzdata.zone_list() |> Enum.sort())
      |> assign(:upload_captions, %{})
      |> assign(:upload_order, [])
      |> assign(:show_publish_modal, false)
      |> EntryForm.attach_companions(:draft)
      |> EntryForm.attach_photos(:new)
      |> EntryForm.attach_dialogs()
      |> assign(:pending_publish_params, nil)
      |> allow_upload(:images,
        accept: ~w(.jpg .jpeg .gif .png .webp),
        max_entries: 10,
        max_file_size: 20_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("set_timezone", %{"timezone" => tz}, socket) do
    role = socket.assigns.current_scope.role

    form =
      Entries.change_post(role, %{"published_tz" => tz})
      |> to_form(as: :post)

    {:noreply, assign(socket, :post_form, form)}
  end

  def handle_event("validate", params, socket) do
    role = socket.assigns.current_scope.role

    post_form =
      Entries.change_post(role, params["post"] || %{})
      |> Map.put(:action, :validate)
      |> to_form(as: :post)

    {:noreply, assign(socket, :post_form, post_form)}
  end

  def handle_event("search_places", %{"place_query" => query}, socket) do
    results = if String.trim(query) == "", do: [], else: Places.search_local_places(query)
    {:noreply, assign(socket, place_results: results, place_query: query)}
  end

  def handle_event("add_place", %{"uri" => uri}, socket) do
    selected = socket.assigns.selected_places
    already = Enum.any?(selected, &(&1.uri == uri))
    place = Enum.find(socket.assigns.place_results, &(&1.uri == uri))

    if already || is_nil(place) do
      {:noreply, assign(socket, place_results: [], place_query: "")}
    else
      {:noreply,
       assign(socket,
         selected_places: selected ++ [place],
         place_results: [],
         place_query: ""
       )}
    end
  end

  def handle_event("remove_place", %{"uri" => uri}, socket) do
    selected = Enum.reject(socket.assigns.selected_places, &(&1.uri == uri))
    {:noreply, assign(socket, :selected_places, selected)}
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

  def handle_event("submit", %{"post" => post_params, "action" => "publish"}, socket) do
    {:noreply,
     socket
     |> assign(:show_publish_modal, true)
     |> assign(:pending_publish_params, post_params)}
  end

  def handle_event("submit", %{"post" => post_params}, socket) do
    do_create_post(socket, post_params, :draft)
  end

  def handle_event("confirm_publish", _params, socket) do
    do_create_post(socket, socket.assigns.pending_publish_params, :publish)
  end

  defp do_create_post(socket, post_params, mode) do
    scope = socket.assigns.current_scope
    companion_uris = Enum.map(socket.assigns.companions, & &1.uri)
    place_uris = Enum.map(socket.assigns.selected_places, & &1.uri)

    case Entries.create_local_post_with_companions(
           scope,
           post_params,
           &CanonicalRoutes.post_uri/1,
           &CanonicalRoutes.post_url/1,
           companion_uris,
           place_uris,
           mode: mode,
           enqueue_delivery: mode != :publish
         ) do
      {:ok, post} ->
        consume_uploads(socket, post.id, scope.person.uri)
        if mode == :publish, do: Entries.enqueue_delivery(post, "Create")

        flash = if mode == :publish, do: "Post published.", else: "Draft saved."

        {:noreply,
         socket
         |> put_flash(:info, flash)
         |> redirect(to: CanonicalRoutes.post_path(post))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:show_publish_modal, false)
         |> assign(post_form: Map.put(changeset, :action, :insert) |> to_form(as: :post))}
    end
  end
end
