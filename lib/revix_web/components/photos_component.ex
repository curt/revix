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

  def photos_section(assigns) do
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
        <%= for entry <- @uploads.entries do %>
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
        <%= for entry_image <- @existing_images do %>
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
                width="300"
                height="300"
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
      <dialog
        :if={not is_nil(@pending_remove_image_id)}
        id={"#{@container_id}-remove-dialog"}
        class="modal"
        open
      >
        <div class="modal-box">
          <h3 class="font-bold text-lg">Remove photo?</h3>
          <p class="py-4">This will permanently delete the photo from this checkin.</p>
          <div class="modal-action">
            <button type="button" class="btn" phx-click="cancel_remove_image">Cancel</button>
            <button type="button" class="btn btn-error" phx-click="confirm_remove_image">
              Remove
            </button>
          </div>
        </div>
        <div class="modal-backdrop" phx-click="cancel_remove_image"></div>
      </dialog>
    </div>
    """
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 20MB)"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 10)"
  defp upload_error_to_string(:not_accepted), do: "File type not accepted"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
end
