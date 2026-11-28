defmodule RevixWeb.CommentSectionLive do
  use RevixWeb, :live_view

  import RevixWeb.Live.EntryHelpers

  alias Revix.Entries
  alias Revix.Likes
  alias Revix.People.Scope
  alias RevixWeb.CanonicalRoutes

  @impl true
  def mount(_params, session, socket) do
    session["checkin_uri"]
    |> Entries.get_entry_by_uri()
    |> mount_for_entry(session, socket)
  end

  # The entry can be deleted between the page render and the socket connecting;
  # render nothing rather than crash.
  defp mount_for_entry({:error, :not_found}, _session, socket) do
    {:ok, assign(socket, :checkin, nil)}
  end

  defp mount_for_entry({:ok, checkin}, session, socket) do
    scope = RevixWeb.Live.PersonAuth.scope_from_session(session)

    if connected?(socket) do
      Entries.subscribe_to_context(checkin.context)
    end

    comment_tree = Entries.Comments.get_comment_tree(checkin)

    can_upload = Scope.contributor?(scope)

    socket =
      socket
      |> assign(:checkin, checkin)
      |> assign(:sign_in_path, sign_in_path(session["return_to"]))
      |> assign(:current_scope, scope)
      |> assign(:comment_max_length, Entries.Comments.comment_max_length(scope))
      |> assign(:comment_tree, comment_tree)
      |> assign_like_state(comment_tree)
      |> assign(:timezone, nil)
      |> assign(:reply_to_id, nil)
      |> assign(comment_error: nil, reply_error: nil, edit_error: nil)
      |> assign(:reply_content, "")
      |> assign(:editing_id, nil)
      |> assign(:new_comment_content, "")
      |> assign(:can_upload_images, !!can_upload)

    socket =
      if can_upload do
        socket
        |> allow_upload(:images,
          accept: ~w(.jpg .jpeg .gif .png .webp),
          max_entries: 4,
          max_file_size: 20_000_000,
          auto_upload: true
        )
        |> assign(:upload_captions, %{})
        |> assign(:upload_order, [])
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("set_timezone", %{"timezone" => tz}, socket) do
    {:noreply, assign(socket, :timezone, tz)}
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, :new_comment_content, Map.get(params, "content", ""))}
  end

  @impl true
  def handle_event("validate_reply", params, socket) do
    {:noreply, assign(socket, :reply_content, Map.get(params, "content", ""))}
  end

  @impl true
  def handle_event("cancel_comment", _params, socket) do
    {:noreply,
     socket
     |> assign(:new_comment_content, "")
     |> maybe_reset_comment_uploads()}
  end

  # The form and buttons for these are only rendered for a signed-in viewer,
  # but a client can send the events anyway.
  @impl true
  def handle_event(event, _params, %{assigns: %{current_scope: nil}} = socket)
      when event in ~w(submit_comment submit_reply like_comment unlike_comment) do
    {:noreply, put_flash(socket, :error, "You must sign in to do that.")}
  end

  @impl true
  def handle_event("submit_comment", %{"content" => content}, socket) do
    scope = socket.assigns.current_scope
    checkin = socket.assigns.checkin
    tz = socket.assigns.timezone || "Etc/UTC"
    has_media? = socket.assigns.can_upload_images and socket.assigns.uploads.images.entries != []

    case Entries.Comments.create_comment(
           scope,
           checkin,
           %{"content" => content, "published_tz" => tz},
           &CanonicalRoutes.note_uri/1,
           &CanonicalRoutes.note_url/1,
           allow_empty_content: has_media?
         ) do
      {:ok, comment} ->
        socket =
          if socket.assigns.can_upload_images do
            consume_uploads(socket, comment.id, scope.person.uri)

            socket
            |> assign(:upload_order, [])
            |> assign(:upload_captions, %{})
          else
            socket
          end

        {:noreply, assign(socket, new_comment_content: "", comment_error: nil)}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :comment_error, save_error("Couldn't post your comment.", changeset))}
    end
  end

  @impl true
  def handle_event("submit_reply", %{"comment_id" => parent_id, "content" => content}, socket) do
    scope = socket.assigns.current_scope
    tz = socket.assigns.timezone || "Etc/UTC"

    with {:ok, parent} <- Entries.Comments.get_comment(parent_id),
         :ok <- in_thread(parent, socket.assigns.checkin) do
      case Entries.Comments.create_reply(
             scope,
             parent,
             %{"content" => content, "published_tz" => tz},
             &CanonicalRoutes.note_uri/1,
             &CanonicalRoutes.note_url/1
           ) do
        {:ok, _reply} ->
          {:noreply, assign(socket, reply_to_id: nil, reply_content: "", reply_error: nil)}

        {:error, changeset} ->
          {:noreply,
           assign(socket, :reply_error, save_error("Couldn't post your reply.", changeset))}
      end
    else
      _ ->
        {:noreply,
         assign(socket, :reply_error, "That comment is no longer available to reply to.")}
    end
  end

  @impl true
  def handle_event("like_comment", %{"comment_uri" => comment_uri}, socket) do
    scope = socket.assigns.current_scope
    tz = socket.assigns.timezone || "Etc/UTC"
    context_uri = socket.assigns.checkin.context

    case Likes.like_entry(scope, comment_uri, tz, context_uri) do
      {:ok, _} ->
        {:noreply, socket}

      {:error, :self_like} ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not like comment.")}
    end
  end

  @impl true
  def handle_event("unlike_comment", %{"comment_uri" => comment_uri}, socket) do
    scope = socket.assigns.current_scope
    context_uri = socket.assigns.checkin.context

    case Likes.unlike_entry(scope, comment_uri, context_uri) do
      {:ok, _} -> {:noreply, socket}
      {:error, _} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reply_to", %{"comment_id" => id}, socket) do
    {:noreply, assign(socket, reply_to_id: id, reply_content: "", reply_error: nil)}
  end

  @impl true
  def handle_event("cancel_reply", _params, socket) do
    {:noreply, assign(socket, reply_to_id: nil, reply_content: "", reply_error: nil)}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, handle_cancel_upload(socket, ref)}
  end

  @impl true
  def handle_event("edit_comment", %{"comment_id" => id}, socket) do
    {:noreply, assign(socket, editing_id: id, edit_error: nil)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_id: nil, edit_error: nil)}
  end

  @impl true
  def handle_event("update_comment", %{"comment_id" => id, "content" => content}, socket) do
    with {:ok, comment} <- Entries.Comments.get_comment(id),
         :ok <- authorize_edit(comment, socket.assigns.current_scope),
         :ok <- not_tombstoned(comment) do
      case Entries.Comments.update_comment(comment, %{"content" => content}) do
        {:ok, _updated} ->
          {:noreply, assign(socket, editing_id: nil, edit_error: nil)}

        {:error, changeset} ->
          {:noreply,
           assign(socket, :edit_error, save_error("Couldn't save your edit.", changeset))}
      end
    else
      {:error, :unauthorized} ->
        {:noreply, assign(socket, :edit_error, "You can only edit your own comments.")}

      {:error, :tombstoned} ->
        {:noreply, assign(socket, :edit_error, "This comment has been deleted.")}

      _ ->
        {:noreply, assign(socket, :edit_error, "That comment is no longer available.")}
    end
  end

  @impl true
  def handle_event("delete_comment", %{"comment_id" => id}, socket) do
    with {:ok, comment} <- Entries.Comments.get_comment(id),
         :ok <- authorize_edit(comment, socket.assigns.current_scope) do
      Entries.tombstone_entry(comment)
      {:noreply, socket}
    else
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Comment not found.")}
    end
  end

  @impl true
  def handle_info({:comment_created, _comment}, socket) do
    {:noreply, reload_comments(socket)}
  end

  @impl true
  def handle_info({:comment_updated, _comment}, socket) do
    {:noreply, reload_comments(socket)}
  end

  @impl true
  def handle_info({:comment_tombstoned, _comment_id}, socket) do
    {:noreply, reload_comments(socket)}
  end

  @impl true
  def handle_info({:comment_deleted, _comment_id}, socket) do
    {:noreply, reload_comments(socket)}
  end

  @impl true
  def handle_info({:entry_liked, _object_uri, _liker_uri}, socket) do
    {:noreply, reload_like_counts(socket)}
  end

  @impl true
  def handle_info({:entry_unliked, _object_uri, _liker_uri}, socket) do
    {:noreply, reload_like_counts(socket)}
  end

  defp reload_comments(socket) do
    comment_tree = Entries.Comments.get_comment_tree(socket.assigns.checkin)

    socket
    |> assign(:comment_tree, comment_tree)
    |> assign_like_state(comment_tree)
  end

  defp reload_like_counts(socket) do
    assign_like_state(socket, Entries.Comments.get_comment_tree(socket.assigns.checkin))
  end

  defp assign_like_state(socket, comment_tree) do
    like_state = load_like_state(socket.assigns.current_scope, comment_tree)

    socket
    |> assign(:liked_uris, like_state.liked_uris)
    |> assign(:like_counts, like_state.like_counts)
    |> assign(:liker_map, like_state.liker_map)
  end

  defp load_like_state(nil, _comment_tree) do
    %{liked_uris: MapSet.new(), like_counts: %{}, liker_map: %{}}
  end

  defp load_like_state(scope, comment_tree) do
    all_uris = all_comment_uris(comment_tree)
    like_counts = Likes.count_active_likes_by_object_uris(all_uris)
    liker_map = Likes.get_active_likes_by_object_uris(all_uris)

    liked_uris =
      all_uris
      |> Enum.filter(&Likes.liked_by?(scope.person.uri, &1))
      |> MapSet.new()

    %{liked_uris: liked_uris, like_counts: like_counts, liker_map: liker_map}
  end

  defp all_comment_uris(comment_tree) do
    Enum.map(comment_tree, & &1.uri)
  end

  defp authorize_edit(comment, scope) do
    if scope && comment.author_uri == scope.person.uri, do: :ok, else: {:error, :unauthorized}
  end

  # This LiveView is rendered inside a controller page, whose flash it can't
  # reach, so form errors are shown inline and say what went wrong.
  defp save_error(lead, %Ecto.Changeset{} = changeset) do
    details =
      changeset
      |> Ecto.Changeset.traverse_errors(&RevixWeb.CoreComponents.translate_error/1)
      |> Enum.flat_map(fn {field, messages} ->
        Enum.map(messages, &"#{Phoenix.Naming.humanize(field)} #{&1}.")
      end)

    Enum.join([lead | details], " ")
  end

  defp sign_in_path(nil), do: ~p"/people/signin"
  defp sign_in_path(return_to), do: ~p"/people/signin?#{[return_to: return_to]}"

  defp in_thread(%{context: context}, %{context: context}), do: :ok
  defp in_thread(_comment, _checkin), do: {:error, :not_found}

  defp not_tombstoned(%{tombstoned_at: nil}), do: :ok
  defp not_tombstoned(%{}), do: {:error, :tombstoned}

  defp unique_comment_authors(comment_tree) do
    comment_tree
    |> Enum.map(& &1.author)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  attr :author, :map, default: nil
  attr :author_uri, :string, default: nil
  attr :width, :integer, default: 8

  defp comment_avatar(%{author: nil} = assigns) do
    ~H"""
    <div class="avatar avatar-placeholder" title={remote_author_label(@author_uri)}>
      <div class={"w-#{@width} rounded-full bg-neutral text-neutral-content flex items-center justify-center"}>
        <.icon name="hero-user" class="w-1/2 h-1/2" />
      </div>
    </div>
    """
  end

  defp comment_avatar(assigns) do
    ~H"""
    <.activity_avatar author={@author} width={@width} />
    """
  end

  attr :comment, :map, required: true
  attr :current_scope, :map, default: nil
  attr :liked_uris, :any, required: true
  attr :like_counts, :map, required: true
  attr :liker_map, :map, required: true
  attr :editing_id, :string, default: nil
  attr :edit_error, :string, default: nil
  attr :comment_max_length, :integer, default: nil

  defp comment_row(%{comment: %{tombstoned_at: ts}} = assigns) when not is_nil(ts) do
    ~H"""
    <div class="chat-header mb-1">
      <time class="text-xs opacity-50">
        {Calendar.strftime(@comment.published_at_local, "%Y-%m-%d")} {format_local_datetime(
          @comment.published_at_local,
          @comment.published_tz,
          @comment.published_at_utc
        )}
      </time>
    </div>
    <div class="chat-bubble italic opacity-50">[deleted]</div>
    """
  end

  defp comment_row(assigns) do
    ~H"""
    <div class="chat-header mb-1 flex items-center gap-1">
      <time class="text-xs opacity-50">
        {Calendar.strftime(@comment.published_at_local, "%Y-%m-%d")} {format_local_datetime(
          @comment.published_at_local,
          @comment.published_tz,
          @comment.published_at_utc
        )}
      </time>
      <%= if @comment.in_reply_to && @comment.in_reply_to.type == :note do %>
        <a
          href={"#comment-#{@comment.in_reply_to.id}"}
          class="flex items-center gap-1 text-xs opacity-50"
        >
          in reply to
          <.comment_avatar
            author={@comment.in_reply_to.author}
            author_uri={@comment.in_reply_to.author_uri}
            width={5}
          />
        </a>
      <% end %>
    </div>

    <%= if @editing_id == @comment.id do %>
      <form phx-submit="update_comment" class="mt-1">
        <input type="hidden" name="comment_id" value={@comment.id} />
        <textarea
          name="content"
          aria-label="Edit comment"
          class="textarea textarea-bordered w-full text-sm"
          rows="3"
          phx-mounted={Phoenix.LiveView.JS.focus()}
          phx-keydown="cancel_edit"
          phx-key="Escape"
          {if @comment_max_length, do: [maxlength: @comment_max_length], else: []}
        >{@comment.content}</textarea>
        <p :if={@edit_error} role="alert" class="text-error text-sm mt-1">{@edit_error}</p>
        <div class="flex gap-1 mt-1">
          <button type="submit" class="btn btn-primary btn-sm">Save</button>
          <button type="button" class="btn btn-soft btn-sm" phx-click="cancel_edit">Cancel</button>
        </div>
      </form>
    <% else %>
      <div class={[
        "chat-bubble",
        if(@current_scope && @current_scope.person.uri == @comment.author_uri,
          do: "chat-bubble-accent"
        )
      ]}>
        <div class="font-serif text-sm">
          {raw(@comment.content_html)}
        </div>
        <%= if @comment.entry_images != [] do %>
          <div class="flex flex-wrap gap-2 mt-2">
            <%= for entry_image <- @comment.entry_images do %>
              <figure class="m-0">
                <a href={
                  Revix.Uploaders.Image.url({entry_image.image.file, entry_image.image}, :large)
                }>
                  <img
                    src={
                      Revix.Uploaders.Image.url(
                        {entry_image.image.file, entry_image.image},
                        :medium
                      )
                    }
                    alt={entry_image.image.alt || ""}
                    class="rounded w-48 max-h-48 object-cover"
                    loading="lazy"
                    {dimension_attrs(entry_image.image, :medium)}
                    {srcset_attrs(entry_image.image, "192px")}
                  />
                </a>
                <%= if entry_image.image.caption_html do %>
                  <figcaption class="text-xs text-base-content/70 font-serif">
                    {raw(entry_image.image.caption_html)}
                  </figcaption>
                <% end %>
              </figure>
            <% end %>
          </div>
        <% end %>
      </div>
      <div class="chat-footer opacity-80 flex items-center mt-1">
        <%= if @current_scope do %>
          <button
            class="btn btn-soft btn-sm"
            phx-click={
              if MapSet.member?(@liked_uris, @comment.uri), do: "unlike_comment", else: "like_comment"
            }
            phx-value-comment_uri={@comment.uri}
            disabled={@current_scope.person.uri == @comment.author_uri}
          >
            {if MapSet.member?(@liked_uris, @comment.uri), do: "Unlike", else: "Like"}
            <.icon
              name={
                if MapSet.member?(@liked_uris, @comment.uri),
                  do: "hero-heart-solid",
                  else: "hero-heart"
              }
              class={[
                "w-4 h-4",
                if(MapSet.member?(@liked_uris, @comment.uri),
                  do: "text-error",
                  else: "text-current"
                )
              ]}
            />
          </button>
          <%= for like <- Enum.take(Map.get(@liker_map, @comment.uri, []), 3), like.author do %>
            <.activity_avatar author={like.author} width={5} />
          <% end %>
          <button
            class="btn btn-soft btn-sm"
            phx-click="reply_to"
            phx-value-comment_id={@comment.id}
          >
            Reply
          </button>
        <% end %>
        <%= if @current_scope && @current_scope.person.uri == @comment.author_uri do %>
          <button
            class="btn btn-soft btn-sm"
            phx-click="edit_comment"
            phx-value-comment_id={@comment.id}
            aria-label="Edit comment"
          >
            <.icon name="hero-pencil-square" class="w-4 h-4" />
          </button>
          <button
            class="btn btn-soft btn-sm text-error"
            phx-click="delete_comment"
            phx-value-comment_id={@comment.id}
            aria-label="Delete comment"
            data-confirm="Delete this comment?"
          >
            <.icon name="hero-trash" class="w-4 h-4" />
          </button>
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :comment_id, :string, required: true
  attr :comment_max_length, :integer, default: nil
  attr :reply_content, :string, default: ""
  attr :reply_error, :string, default: nil

  defp reply_form(assigns) do
    ~H"""
    <form
      id={"reply-form-#{@comment_id}"}
      class="mt-2"
      phx-change="validate_reply"
      phx-submit="submit_reply"
    >
      <input type="hidden" name="comment_id" value={@comment_id} />
      <textarea
        name="content"
        aria-label="Reply"
        class="textarea textarea-bordered w-full text-sm"
        placeholder="Write a reply..."
        rows="2"
        phx-mounted={Phoenix.LiveView.JS.focus()}
        {if @comment_max_length, do: [maxlength: @comment_max_length], else: []}
      >{@reply_content}</textarea>
      <p :if={@reply_error} role="alert" class="text-error text-sm mt-1">{@reply_error}</p>
      <div class="flex gap-1 mt-1">
        <button
          type="submit"
          class="btn btn-primary btn-sm"
          disabled={not content_submittable?(@reply_content)}
        >
          Reply
        </button>
        <button type="button" class="btn btn-soft btn-sm" phx-click="cancel_reply">Cancel</button>
      </div>
    </form>
    """
  end

  defp remote_author_label(nil), do: "Unknown"

  defp remote_author_label(uri) do
    parsed = URI.parse(uri)
    username = parsed.path |> Path.basename()
    if parsed.host, do: "@#{username}@#{parsed.host}", else: uri
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 20MB)"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 4)"
  defp upload_error_to_string(:not_accepted), do: "File type not accepted"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"

  # True when the textarea holds non-blank text. Drives the Reply button and is
  # the text half of `comment_submittable?/3`.
  defp content_submittable?(content), do: String.trim(content || "") != ""

  # The Comment button is enabled once the textarea has non-blank text or at least
  # one image is staged (an image-only comment is allowed).
  defp comment_submittable?(content, true, uploads) do
    content_submittable?(content) or uploads.images.entries != []
  end

  defp comment_submittable?(content, _can_upload_images, _uploads) do
    content_submittable?(content)
  end

  # Clears any images staged on the top-level comment form. No-op when the
  # current person cannot upload (the upload was never allow_upload'd).
  defp maybe_reset_comment_uploads(%{assigns: %{can_upload_images: true}} = socket) do
    Enum.reduce(socket.assigns.uploads.images.entries, socket, fn entry, acc ->
      handle_cancel_upload(acc, entry.ref)
    end)
  end

  defp maybe_reset_comment_uploads(socket), do: socket
end
