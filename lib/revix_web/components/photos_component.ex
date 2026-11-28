defmodule RevixWeb.PhotosComponent do
  use RevixWeb, :html

  @doc """
  Renders the unified Photos section: file picker, sortable upload cards (pending +
  existing), and a delete confirmation modal for existing images.

  Required assigns:
    - `uploads`         — the `@uploads.images` LiveView upload struct
    - `upload_captions` — `%{ref => %{caption: string, alt: string}}`
    - `container_id`    — unique string id for the drag container

  Optional assigns (default to empty/nil for the new-checkin form):
    - `existing_images`         — list of `EntryImage` structs with preloaded `.image`
    - `image_captions`          — `%{image_id => %{caption: string, alt: string}}`
    - `pending_remove_image_id` — image id awaiting delete confirmation, or nil
  """
  attr :uploads, :map, required: true
  attr :upload_captions, :map, required: true
  attr :container_id, :string, required: true
  attr :existing_images, :list, default: []
  attr :image_captions, :map, default: %{}
  attr :pending_remove_image_id, :string, default: nil

  attr :upload_order, :list,
    default: [],
    doc: "upload refs in the order the person chose (from reorder_images)"

  attr :existing_image_order, :list,
    default: [],
    doc: "saved image ids in the order the person chose (edit pages)"

  def photos_section(assigns) do
    # Draw cards in the chosen order, so a LiveView re-render (after a caption
    # edit, say) can't put back the old order the page no longer means.
    assigns =
      assigns
      |> assign(
        :ordered_entries,
        in_order(assigns.uploads.entries, assigns.upload_order, & &1.ref)
      )
      |> assign(
        :ordered_images,
        in_order(assigns.existing_images, assigns.existing_image_order, & &1.image.id)
      )

    ~H"""
    <div>
      <h2 class="text-lg font-semibold mb-3">Photos</h2>

      <.live_file_input upload={@uploads} class="file-input file-input-bordered w-full" />

      <div
        :if={@uploads.entries != [] or @existing_images != []}
        id={@container_id}
        phx-hook="ImageSort"
        class="mt-3 space-y-2"
      >
        <%!-- Pending upload cards (appear at top) --%>
        <%= for entry <- @ordered_entries do %>
          <div
            id={"upload-entry-#{entry.ref}"}
            data-ref={entry.ref}
            class="flex items-start gap-3 p-2 border border-base-300 rounded bg-base-100"
          >
            <%!-- Drag handle --%>
            <div
              class="pt-2 shrink-0 text-base-content/40 cursor-grab select-none"
              aria-hidden="true"
            >
              <.icon name="hero-bars-3" class="w-5 h-5" />
            </div>

            <.move_buttons />

            <%!-- Thumbnail via built-in Phoenix LiveView component --%>
            <div class="shrink-0">
              <.live_img_preview entry={entry} class="w-20 h-20 rounded object-cover" />
            </div>

            <%!-- Filename, progress bar, caption, alt --%>
            <div class="grow space-y-1 min-w-0">
              <p class="text-sm font-medium truncate">{entry.client_name}</p>
              <progress value={entry.progress} max="100" class="progress progress-primary w-full" />
              <textarea
                name={"photo_caption[#{entry.ref}]"}
                class="textarea textarea-bordered textarea-sm w-full"
                placeholder="Optional caption…"
                phx-change="update_caption"
                phx-debounce="300"
                rows="2"
              >{get_in(@upload_captions, [entry.ref, :caption]) || ""}</textarea>
              <textarea
                name={"photo_alt[#{entry.ref}]"}
                class="textarea textarea-bordered textarea-sm w-full"
                placeholder="Alt text…"
                phx-change="update_alt"
                phx-debounce="300"
                rows="2"
              >{get_in(@upload_captions, [entry.ref, :alt]) || ""}</textarea>
            </div>

            <%!-- Cancel button --%>
            <button
              type="button"
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
              class="btn btn-ghost btn-sm btn-square text-error shrink-0"
              aria-label="Cancel upload"
            >
              &times;
            </button>
          </div>
          <%= for err <- upload_errors(@uploads, entry) do %>
            <p class="text-error text-sm">{entry.client_name}: {upload_error_to_string(err)}</p>
          <% end %>
        <% end %>

        <%!-- Existing saved image cards --%>
        <%= for entry_image <- @ordered_images do %>
          <% image_id = entry_image.image.id %>
          <div
            id={"image-#{image_id}"}
            data-image-id={image_id}
            class="flex items-start gap-3 p-2 border border-base-300 rounded bg-base-100"
          >
            <%!-- Drag handle --%>
            <div
              class="pt-2 shrink-0 text-base-content/40 cursor-grab select-none"
              aria-hidden="true"
            >
              <.icon name="hero-bars-3" class="w-5 h-5" />
            </div>

            <.move_buttons />

            <%!-- Served thumbnail --%>
            <div class="shrink-0">
              <img
                src={
                  Revix.Uploaders.Image.url(
                    {entry_image.image.file, entry_image.image},
                    :thumb
                  )
                }
                alt={entry_image.image.alt || ""}
                class="w-20 h-20 rounded object-cover"
                width={Revix.Uploaders.Image.thumb_size()}
                height={Revix.Uploaders.Image.thumb_size()}
              />
            </div>

            <%!-- Caption + alt inputs --%>
            <div class="grow space-y-1 min-w-0">
              <textarea
                name={"photo_caption[#{image_id}]"}
                class="textarea textarea-bordered textarea-sm w-full"
                placeholder="Optional caption…"
                phx-change="update_caption"
                phx-debounce="300"
                rows="2"
              >{Map.get(@image_captions, image_id, %{}) |> Map.get(:caption, "")}</textarea>
              <textarea
                name={"photo_alt[#{image_id}]"}
                class="textarea textarea-bordered textarea-sm w-full"
                placeholder="Alt text…"
                phx-change="update_alt"
                phx-debounce="300"
                rows="2"
              >{Map.get(@image_captions, image_id, %{}) |> Map.get(:alt, "")}</textarea>
            </div>

            <%!-- Delete button --%>
            <button
              type="button"
              phx-click="request_remove_image"
              phx-value-image-id={image_id}
              class="btn btn-ghost btn-sm btn-square text-error shrink-0"
              aria-label="Remove photo"
            >
              <.icon name="hero-trash" class="w-4 h-4" />
            </button>
          </div>
        <% end %>
      </div>

      <%= for err <- upload_errors(@uploads) do %>
        <p class="text-error text-sm mt-1">{upload_error_to_string(err)}</p>
      <% end %>

      <%!-- Delete confirmation modal — rendered when a deletion is pending --%>
      <.confirm_dialog
        id={"#{@container_id}-remove-dialog"}
        show={not is_nil(@pending_remove_image_id)}
        title="Remove photo?"
        on_cancel="cancel_remove_image"
        on_confirm="confirm_remove_image"
        confirm_label="Remove"
        confirm_class="btn-error"
      >
        <p class="py-4">This will permanently delete the photo from this checkin.</p>
      </.confirm_dialog>
    </div>
    """
  end

  # Items listed in `order` come first, in that order; the rest keep their
  # original order after them.
  defp in_order(items, order, key_fun) do
    rank = order |> Enum.with_index() |> Map.new()
    last = map_size(rank)

    items
    |> Enum.with_index()
    |> Enum.sort_by(fn {item, index} -> {Map.get(rank, key_fun.(item), last), index} end)
    |> Enum.map(&elem(&1, 0))
  end

  # Keyboard and screen-reader alternative to dragging. The ImageSort hook
  # handles the clicks and pushes the same reorder_images event as a drag.
  defp move_buttons(assigns) do
    ~H"""
    <div class="flex flex-col shrink-0">
      <button
        type="button"
        data-photo-move="earlier"
        class="btn btn-ghost btn-xs btn-square"
        title="Move earlier"
      >
        <.icon name="hero-chevron-up" class="w-4 h-4" />
        <span class="sr-only">Move earlier</span>
      </button>
      <button
        type="button"
        data-photo-move="later"
        class="btn btn-ghost btn-xs btn-square"
        title="Move later"
      >
        <.icon name="hero-chevron-down" class="w-4 h-4" />
        <span class="sr-only">Move later</span>
      </button>
    </div>
    """
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 20MB)"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 10)"
  defp upload_error_to_string(:not_accepted), do: "File type not accepted"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
end
