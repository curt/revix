defmodule RevixWeb.PostNewLive do
  use RevixWeb, :live_view

  import RevixWeb.Live.EntryHelpers

  alias Revix.Entries
  alias Revix.Places
  alias RevixWeb.CanonicalRoutes

  on_mount {RevixWeb.Live.PersonAuth, :require_authenticated_person}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.role != :owner do
      {:ok, socket |> put_flash(:error, "Not authorized.") |> redirect(to: ~p"/posts")}
    else
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
        |> assign(:pending_publish_params, nil)
        |> allow_upload(:images,
          accept: ~w(.jpg .jpeg .gif .png .webp),
          max_entries: 10,
          max_file_size: 20_000_000
        )

      {:ok, socket}
    end
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

  def handle_event("submit", %{"post" => post_params, "action" => "publish"}, socket) do
    {:noreply,
     socket
     |> assign(:show_publish_modal, true)
     |> assign(:pending_publish_params, post_params)}
  end

  def handle_event("submit", %{"post" => post_params}, socket) do
    do_create_post(socket, post_params, :draft)
  end

  def handle_event("cancel_publish", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_publish_modal, false)
     |> assign(:pending_publish_params, nil)}
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
           mode: mode
         ) do
      {:ok, post} ->
        consume_uploads(socket, post.id, scope.person.uri)

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
