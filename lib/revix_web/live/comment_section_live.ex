defmodule RevixWeb.CommentSectionLive do
  use RevixWeb, :live_view

  alias Revix.Entries
  alias Revix.Likes
  alias Revix.People
  alias Revix.People.Scope
  alias RevixWeb.CanonicalRoutes

  @impl true
  def mount(_params, session, socket) do
    checkin_uri = session["checkin_uri"]
    scope = mount_current_scope(session)
    {:ok, checkin} = Entries.get_entry_by_uri(checkin_uri)

    if connected?(socket) do
      Entries.subscribe_to_context(checkin.context)
    end

    comment_tree = Entries.get_comment_tree(checkin)
    like_state = load_like_state(scope, comment_tree)

    socket =
      socket
      |> assign(:checkin, checkin)
      |> assign(:current_scope, scope)
      |> assign(:comment_max_length, Entries.comment_max_length(scope))
      |> assign(:comment_tree, comment_tree)
      |> assign(:liked_uris, like_state.liked_uris)
      |> assign(:like_counts, like_state.like_counts)
      |> assign(:liker_map, like_state.liker_map)
      |> assign(:timezone, nil)
      |> assign(:reply_to_id, nil)
      |> assign(:editing_id, nil)
      |> assign(:new_comment_content, "")

    {:ok, socket}
  end

  @impl true
  def handle_event("set_timezone", %{"timezone" => tz}, socket) do
    {:noreply, assign(socket, :timezone, tz)}
  end

  @impl true
  def handle_event("submit_comment", %{"content" => content}, socket) do
    scope = socket.assigns.current_scope
    checkin = socket.assigns.checkin
    tz = socket.assigns.timezone || "Etc/UTC"

    case Entries.create_comment(
           scope,
           checkin,
           %{"content" => content, "published_tz" => tz},
           &CanonicalRoutes.note_uri/1,
           &CanonicalRoutes.note_url/1
         ) do
      {:ok, _comment} ->
        {:noreply, assign(socket, :new_comment_content, "")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save comment.")}
    end
  end

  @impl true
  def handle_event("submit_reply", %{"comment_id" => parent_id, "content" => content}, socket) do
    scope = socket.assigns.current_scope
    tz = socket.assigns.timezone || "Etc/UTC"

    with {:ok, parent} <- Entries.get_comment(parent_id) do
      case Entries.create_reply(
             scope,
             parent,
             %{"content" => content, "published_tz" => tz},
             &CanonicalRoutes.note_uri/1,
             &CanonicalRoutes.note_url/1
           ) do
        {:ok, _reply} ->
          {:noreply, assign(socket, :reply_to_id, nil)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not save reply.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Comment not found.")}
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
    {:noreply, assign(socket, :reply_to_id, id)}
  end

  @impl true
  def handle_event("cancel_reply", _params, socket) do
    {:noreply, assign(socket, :reply_to_id, nil)}
  end

  @impl true
  def handle_event("edit_comment", %{"comment_id" => id}, socket) do
    {:noreply, assign(socket, :editing_id, id)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_id, nil)}
  end

  @impl true
  def handle_event("update_comment", %{"comment_id" => id, "content" => content}, socket) do
    with {:ok, comment} <- Entries.get_comment(id),
         :ok <- authorize_edit(comment, socket.assigns.current_scope) do
      case Entries.update_comment(comment, %{"content" => content}) do
        {:ok, _updated} ->
          {:noreply, assign(socket, :editing_id, nil)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not update comment.")}
      end
    else
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Comment not found.")}
    end
  end

  @impl true
  def handle_event("delete_comment", %{"comment_id" => id}, socket) do
    with {:ok, comment} <- Entries.get_comment(id),
         :ok <- authorize_edit(comment, socket.assigns.current_scope) do
      Entries.delete_comment(comment)
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
    checkin = socket.assigns.checkin
    comment_tree = Entries.get_comment_tree(checkin)
    like_state = load_like_state(socket.assigns.current_scope, comment_tree)

    socket
    |> assign(:comment_tree, comment_tree)
    |> assign(:liked_uris, like_state.liked_uris)
    |> assign(:like_counts, like_state.like_counts)
    |> assign(:liker_map, like_state.liker_map)
  end

  defp reload_like_counts(socket) do
    checkin = socket.assigns.checkin
    comment_tree = Entries.get_comment_tree(checkin)
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
      if scope && scope.person do
        all_uris
        |> Enum.filter(&Likes.liked_by?(scope.person.uri, &1))
        |> MapSet.new()
      else
        MapSet.new()
      end

    %{liked_uris: liked_uris, like_counts: like_counts, liker_map: liker_map}
  end

  defp all_comment_uris(comment_tree) do
    Enum.flat_map(comment_tree, fn {comment, replies} ->
      [comment.uri | Enum.map(replies, & &1.uri)]
    end)
  end

  defp mount_current_scope(session) do
    case session["person_token"] && People.get_person_by_session_token(session["person_token"]) do
      {person, _token_inserted_at} -> Scope.for_person(person)
      _ -> nil
    end
  end

  defp authorize_edit(comment, scope) do
    if scope && comment.author_uri == scope.person.uri, do: :ok, else: {:error, :unauthorized}
  end

  defp unique_comment_authors(comment_tree) do
    comment_tree
    |> Enum.flat_map(fn {comment, replies} ->
      [comment | replies]
    end)
    |> Enum.map(& &1.author)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  attr :comment, :map, required: true
  attr :current_scope, :map, default: nil
  attr :liked_uris, :any, required: true
  attr :like_counts, :map, required: true
  attr :liker_map, :map, required: true
  attr :editing_id, :string, default: nil
  attr :comment_max_length, :integer, default: nil

  defp comment_row(assigns) do
    ~H"""
    <div class="flex items-center gap-2 mb-1">
      <.activity_avatar author={@comment.author} width={6} />
      <span class="text-sm font-medium">
        <%= if @comment.author do %>
          {@comment.author.display_name || @comment.author.username}
        <% else %>
          {remote_author_label(@comment.author_uri)}
        <% end %>
      </span>
      <span class="text-xs text-base-content/60">
        {Calendar.strftime(@comment.published_at_local, "%Y-%m-%d")} {format_local_datetime(
          @comment.published_at_local,
          @comment.published_tz,
          @comment.published_at_utc
        )}
      </span>
      <%= if @current_scope && @current_scope.person.uri == @comment.author_uri do %>
        <div class="ml-auto flex gap-1">
          <button
            class="btn btn-ghost btn-xs"
            phx-click="edit_comment"
            phx-value-comment_id={@comment.id}
            aria-label="Edit comment"
          >
            <.icon name="hero-pencil-square" class="w-4 h-4" />
          </button>
          <button
            class="btn btn-ghost btn-xs text-error"
            phx-click="delete_comment"
            phx-value-comment_id={@comment.id}
            aria-label="Delete comment"
            data-confirm="Delete this comment?"
          >
            <.icon name="hero-trash" class="w-4 h-4" />
          </button>
        </div>
      <% end %>
    </div>

    <%= if @editing_id == @comment.id do %>
      <form phx-submit="update_comment" class="mt-1">
        <input type="hidden" name="comment_id" value={@comment.id} />
        <textarea
          name="content"
          class="textarea textarea-bordered w-full text-sm"
          rows="3"
          {if @comment_max_length, do: [maxlength: @comment_max_length], else: []}
        >{@comment.content}</textarea>
        <div class="flex gap-2 mt-1">
          <button type="submit" class="btn btn-primary btn-xs">Save</button>
          <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_edit">Cancel</button>
        </div>
      </form>
    <% else %>
      <div class="my-2 font-serif text">
        {raw(@comment.content_html)}
      </div>
      <%= if @current_scope do %>
        <div class="flex items-center gap-2 mt-1">
          <button
            class="btn btn-soft btn-xs"
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
              class="w-4 h-4 text-error"
            />
          </button>
          <%= for like <- Enum.take(Map.get(@liker_map, @comment.uri, []), 3), like.author do %>
            <.activity_avatar author={like.author} width={5} />
          <% end %>
          <button
            class="btn btn-ghost btn-xs text-xs"
            phx-click="reply_to"
            phx-value-comment_id={@comment.id}
          >
            Reply
          </button>
        </div>
      <% end %>
    <% end %>
    """
  end

  attr :comment_id, :string, required: true
  attr :comment_max_length, :integer, default: nil

  defp reply_form(assigns) do
    ~H"""
    <form class="mt-2" phx-submit="submit_reply">
      <input type="hidden" name="comment_id" value={@comment_id} />
      <textarea
        name="content"
        class="textarea textarea-bordered w-full text-sm"
        placeholder="Write a reply..."
        rows="2"
        {if @comment_max_length, do: [maxlength: @comment_max_length], else: []}
      ></textarea>
      <div class="flex gap-2 mt-1">
        <button type="submit" class="btn btn-primary btn-xs">Reply</button>
        <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_reply">Cancel</button>
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
end
