defmodule RevixWeb.Live.EntryForm do
  @moduledoc """
  Event handlers shared by the checkin and post form LiveViews.

  Each `attach_*` function attaches a `:handle_event` hook in `mount`. The hook
  handles its own events and passes every other event on to the LiveView.

  - `attach_companions/2` — `search_companions`, `add_companion`, `remove_companion`.
    `:draft` keeps companions in memory until the entry is saved;
    `{:saved, assign_key}` saves each change at once to the entry in that assign.
  - `attach_photos/2` — `cancel_upload`, `update_alt`, `reorder_images`, and on edit
    pages `request_remove_image` and `cancel_remove_image`. `:new` tracks uploads only;
    `{:edit, on_change}` also tracks existing images and calls `on_change` after each
    change, so the page can update its unsaved-changes state.
  - `attach_dialogs/1` — `cancel_publish`, `request_delete`, `cancel_delete`.
  """
  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]
  import RevixWeb.Live.EntryHelpers

  alias Revix.EntryPeople

  @blank_companion %{display_name: nil, username: nil, avatar_url: nil}

  # ── Companions ─────────────────────────────────────────────────────────────

  def attach_companions(socket, mode) do
    attach_hook(socket, :entry_form_companions, :handle_event, fn event, params, socket ->
      companion_event(event, params, socket, mode)
    end)
  end

  defp companion_event("search_companions", %{"companion_query" => query}, socket, _mode) do
    results = search_companions(query, socket.assigns.current_scope.person.uri)
    {:halt, assign(socket, companion_results: results, companion_query: query)}
  end

  defp companion_event("add_companion", %{"uri" => uri}, socket, mode),
    do: {:halt, add_companion(socket, uri, mode)}

  defp companion_event("remove_companion", %{"uri" => uri}, socket, mode),
    do: {:halt, remove_companion(socket, uri, mode)}

  defp companion_event(_event, _params, socket, _mode), do: {:cont, socket}

  # You can't be your own companion.
  defp add_companion(%{assigns: %{current_scope: %{person: %{uri: uri}}}} = socket, uri, :draft),
    do: clear_companion_search(socket)

  defp add_companion(socket, uri, :draft) do
    socket.assigns.companions
    |> Enum.any?(&(&1.uri == uri))
    |> add_draft_companion(socket, uri)
  end

  defp add_companion(socket, uri, {:saved, key}) do
    entry = Map.fetch!(socket.assigns, key)

    socket.assigns.current_scope
    |> EntryPeople.add_companion(entry.uri, uri)
    |> after_saved_add(socket, entry)
  end

  defp add_draft_companion(true, socket, _uri), do: clear_companion_search(socket)

  defp add_draft_companion(false, socket, uri) do
    companion =
      Enum.find(socket.assigns.companion_results, &(&1.uri == uri)) ||
        Map.put(@blank_companion, :uri, uri)

    socket
    |> assign(:companions, socket.assigns.companions ++ [companion])
    |> clear_companion_search()
  end

  defp after_saved_add({:ok, _}, socket, entry) do
    socket
    |> assign(:companions, saved_companions(entry))
    |> clear_companion_search()
  end

  defp after_saved_add({:error, _}, socket, _entry), do: socket

  defp remove_companion(socket, uri, :draft),
    do: assign(socket, :companions, Enum.reject(socket.assigns.companions, &(&1.uri == uri)))

  defp remove_companion(socket, uri, {:saved, key}) do
    entry = Map.fetch!(socket.assigns, key)

    socket.assigns.current_scope
    |> EntryPeople.remove_companion(entry.uri, uri)
    |> after_saved_remove(socket, entry)
  end

  defp after_saved_remove({:ok, _}, socket, entry),
    do: assign(socket, :companions, saved_companions(entry))

  defp after_saved_remove({:error, _}, socket, _entry), do: socket

  defp saved_companions(entry) do
    entry.uri
    |> EntryPeople.get_companions_for_entry()
    |> Enum.filter(& &1.person)
    |> Enum.map(&normalize_person(&1.person))
  end

  defp clear_companion_search(socket),
    do: assign(socket, companion_results: [], companion_query: "")

  # ── Photos ─────────────────────────────────────────────────────────────────

  def attach_photos(socket, mode) do
    attach_hook(socket, :entry_form_photos, :handle_event, fn event, params, socket ->
      photo_event(event, params, socket, mode)
    end)
  end

  defp photo_event("cancel_upload", %{"ref" => ref}, socket, mode),
    do: {:halt, socket |> handle_cancel_upload(ref) |> photos_changed(mode)}

  defp photo_event("update_alt", %{"_target" => [_, key], "photo_alt" => alts}, socket, mode) do
    value = Map.get(alts, key, "")
    {:halt, socket |> update_alt(key, value, mode) |> photos_changed(mode)}
  end

  defp photo_event("reorder_images", %{"order" => order}, socket, mode) when is_list(order),
    do: {:halt, socket |> reorder(order, mode) |> photos_changed(mode)}

  defp photo_event("request_remove_image", %{"image-id" => image_id}, socket, {:edit, _}),
    do: {:halt, assign(socket, :pending_remove_image_id, image_id)}

  defp photo_event("cancel_remove_image", _params, socket, {:edit, _}),
    do: {:halt, assign(socket, :pending_remove_image_id, nil)}

  defp photo_event(_event, _params, socket, _mode), do: {:cont, socket}

  defp update_alt(socket, ref, value, :new) do
    captions =
      Map.update(
        socket.assigns.upload_captions,
        ref,
        %{caption: "", alt: value},
        &Map.put(&1, :alt, value)
      )

    assign(socket, :upload_captions, captions)
  end

  defp update_alt(socket, key, value, {:edit, _}),
    do: update_photo_field(socket, key, :alt, value)

  defp reorder(socket, order, :new),
    do: assign(socket, :upload_order, for(%{"ref" => r} <- order, do: r))

  defp reorder(socket, order, {:edit, _}) do
    socket
    |> assign(:upload_order, for(%{"ref" => r} <- order, do: r))
    |> assign(:existing_image_order, for(%{"image_id" => i} <- order, do: i))
  end

  defp photos_changed(socket, :new), do: socket
  defp photos_changed(socket, {:edit, on_change}), do: on_change.(socket)

  @doc """
  On edit pages, sets a photo's caption or alt text: an existing image's when
  `key` is its id, otherwise a pending upload's.
  """
  def update_photo_field(socket, key, field, value) do
    socket.assigns.image_captions
    |> Map.has_key?(key)
    |> put_photo_field(socket, key, field, value)
  end

  defp put_photo_field(true, socket, key, field, value),
    do:
      assign(socket, :image_captions, put_field(socket.assigns.image_captions, key, field, value))

  defp put_photo_field(false, socket, key, field, value),
    do:
      assign(
        socket,
        :upload_captions,
        put_field(socket.assigns.upload_captions, key, field, value)
      )

  defp put_field(captions, key, field, value),
    do:
      Map.update(
        captions,
        key,
        Map.put(%{caption: "", alt: ""}, field, value),
        &Map.put(&1, field, value)
      )

  # ── Dialogs ────────────────────────────────────────────────────────────────

  def attach_dialogs(socket) do
    attach_hook(socket, :entry_form_dialogs, :handle_event, &dialog_event/3)
  end

  defp dialog_event("cancel_publish", _params, socket),
    do: {:halt, assign(socket, show_publish_modal: false, pending_publish_params: nil)}

  defp dialog_event("request_delete", _params, socket),
    do: {:halt, assign(socket, :pending_delete, true)}

  defp dialog_event("cancel_delete", _params, socket),
    do: {:halt, assign(socket, :pending_delete, false)}

  defp dialog_event(_event, _params, socket), do: {:cont, socket}
end
