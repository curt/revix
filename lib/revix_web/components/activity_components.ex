defmodule RevixWeb.ActivityComponents do
  use Phoenix.Component

  import Phoenix.HTML, only: [raw: 1]
  import RevixWeb.CoreComponents, only: [icon: 1, icon_link: 1]
  import RevixWeb.View.Helpers, only: [format_local_datetime: 3]

  alias Revix.Snippet

  @snippet_max 120

  @doc """
  Renders the activity feed as a daisyUI vertical timeline.

  Each activity is a tagged tuple: `{:checkin, checkin}`, `{:post, post}`,
  `{:draft, entry}`, `{:like, like}`, or `{:comment, comment}` — one row per
  event, sorted chronologically (see `Revix.ActivityFeed.group_activities/1`).

  When `has_more` is `true`, a sentinel element is rendered after the list with
  `phx-hook="InfiniteScroll"`; scrolling it into view pushes a `load_more` event
  to the parent LiveView. Omit `has_more` (defaults to `false`) for feeds that
  don't support pagination, e.g. the unauthenticated static-template feed.
  """
  attr :activities, :list, required: true
  attr :has_more, :boolean, default: false

  def activity_feed(assigns) do
    ~H"""
    <div class="my-4">
      <ul class="timeline timeline-vertical w-full [--timeline-col-start:auto] [--timeline-col-end:minmax(0,100%)]">
        <%= for {activity, index} <- Enum.with_index(@activities) do %>
          <li class="w-full">
            <hr :if={index > 0} />
            <div class="timeline-start text-xs opacity-50 whitespace-nowrap px-2">
              <.activity_timestamp_fields activity={activity} />
            </div>
            <div class="timeline-middle">
              <.activity_avatar author={activity_author(activity)} width={8} />
            </div>
            <div class="timeline-end text-xs p-2 w-full">
              <%= case activity do %>
                <% {:checkin, checkin} -> %>
                  <.checkin_activity checkin={checkin} />
                <% {:post, post} -> %>
                  <.post_activity post={post} />
                <% {:draft, %{type: :checkin} = checkin} -> %>
                  <.draft_checkin_activity checkin={checkin} />
                <% {:draft, post} -> %>
                  <.draft_activity post={post} />
                <% {:like, like} -> %>
                  <.like_activity like={like} />
                <% {:comment, comment} -> %>
                  <.comment_activity comment={comment} />
              <% end %>
            </div>
            <hr :if={index < length(@activities) - 1} />
          </li>
        <% end %>
      </ul>
      <div :if={@has_more} id="activity-feed-sentinel" phx-hook="InfiniteScroll"></div>
    </div>
    """
  end

  # Returns the acting author for the timeline-middle avatar. Used ahead of
  # the per-type case in `activity_feed/1` since the avatar slot is common to
  # every row regardless of activity type.
  defp activity_author({:checkin, checkin}), do: checkin.author
  defp activity_author({:post, post}), do: post.author
  defp activity_author({:draft, entry}), do: entry.author
  defp activity_author({:like, like}), do: like.author
  defp activity_author({:comment, comment}), do: comment.author

  attr :activity, :any, required: true

  defp activity_timestamp_fields(%{activity: {:checkin, checkin}} = assigns) do
    assigns = assign(assigns, :checkin, checkin)

    ~H"""
    <.activity_timestamp
      :if={has_place_name?(@checkin)}
      local={@checkin.starts_at_local}
      tz={@checkin.starts_tz}
      utc={@checkin.starts_at_utc}
    />
    """
  end

  defp activity_timestamp_fields(%{activity: {:post, post}} = assigns) do
    assigns = assign(assigns, :post, post)

    ~H"""
    <.activity_timestamp
      local={@post.published_at_local}
      tz={@post.published_tz}
      utc={@post.published_at_utc}
    />
    """
  end

  defp activity_timestamp_fields(%{activity: {:draft, entry}} = assigns) do
    assigns = assign(assigns, :entry, entry)

    ~H"""
    <span class="badge badge-warning badge-sm">Draft</span>
    Updated {Calendar.strftime(@entry.updated_at, "%Y-%m-%d")}
    """
  end

  defp activity_timestamp_fields(%{activity: {:like, like}} = assigns) do
    assigns = assign(assigns, :like, like)

    ~H"""
    <.activity_timestamp
      local={@like.published_at_local}
      tz={@like.published_tz}
      utc={@like.published_at_utc}
    />
    """
  end

  defp activity_timestamp_fields(%{activity: {:comment, comment}} = assigns) do
    assigns = assign(assigns, :comment, comment)

    ~H"""
    <.activity_timestamp
      local={@comment.published_at_local}
      tz={@comment.published_tz}
      utc={@comment.published_at_utc}
    />
    """
  end

  @doc """
  Renders a single checkin activity item's content (for the timeline box).
  """
  attr :checkin, :map, required: true

  def checkin_activity(assigns) do
    ~H"""
    checked into
    <%= if place_name = place_name(@checkin) do %>
      <a href={@checkin.url} class="font-semibold hover:underline inline-block text-sm">
        {place_name}
      </a>
    <% else %>
      <span class="font-semibold">{@checkin.name || "somewhere"}</span>
    <% end %>
    <%= if @checkin.companions != [] do %>
      <div class="inline-block">
        <span class="text-xs italic">with</span>
        <span class="inline-flex -space-x-2 align-middle">
          <%= for ep <- Enum.take(@checkin.companions, 5), ep.person do %>
            <.activity_avatar author={ep.person} width={5} />
          <% end %>
          <%= if length(@checkin.companions) > 5 do %>
            <span class="text-xs ml-1">+{length(@checkin.companions) - 5}</span>
          <% end %>
        </span>
      </div>
    <% end %>
    <.entry_snippet entry={@checkin} />
    """
  end

  @doc """
  Renders a single post activity item's content (for the timeline box).
  """
  attr :post, :map, required: true

  def post_activity(assigns) do
    ~H"""
    posted
    <a href={@post.url} class="font-semibold hover:underline inline-block text-sm">
      {@post.name || "a post"}
    </a>
    <.entry_snippet entry={@post} />
    """
  end

  attr :post, :map, required: true

  def draft_activity(assigns) do
    ~H"""
    drafted
    <a href={@post.url} class="font-semibold hover:underline inline-block text-sm">
      {@post.name || "a post"}
    </a>
    """
  end

  attr :checkin, :map, required: true

  def draft_checkin_activity(assigns) do
    ~H"""
    drafted a checkin to
    <a
      href={"/checkins/#{@checkin.id}/edit"}
      class="font-semibold hover:underline inline-block text-sm"
    >
      {get_in(@checkin, [Access.key(:place), Access.key(:name)]) ||
        @checkin.name || "somewhere"}
    </a>
    """
  end

  @doc """
  Renders a single like activity item's content (for the timeline box).
  """
  attr :like, :map, required: true

  def like_activity(assigns) do
    ~H"""
    <.icon name="hero-heart-solid" class="w-4 h-4 inline text-error" />
    <%= if @like.object && @like.object.type == :note do %>
      liked
      <a href={@like.object.url} class="font-semibold hover:underline inline-block text-sm">
        a comment
      </a>
    <% else %>
      liked
      <%= if place_name = place_name(@like.object) do %>
        <a href={@like.object.url} class="font-semibold hover:underline inline-block text-sm">
          {place_name}
        </a>
      <% else %>
        <span class="font-semibold">a checkin</span>
      <% end %>
    <% end %>
    """
  end

  @doc """
  Renders a single comment activity item's content (for the timeline box).
  """
  attr :comment, :map, required: true

  def comment_activity(assigns) do
    ~H"""
    <%= if root = comment_root_entry(@comment) do %>
      commented on
      <%= if href = comment_target_href(root, @comment.id) do %>
        <a href={href} class="font-semibold hover:underline inline-block text-sm">
          {comment_target_label(root)}
        </a>
      <% else %>
        <span class="font-semibold">{comment_target_label(root)}</span>
      <% end %>
    <% else %>
      replied to
      <.activity_avatar author={@comment.in_reply_to && @comment.in_reply_to.author} width={7} />
    <% end %>
    <.entry_snippet entry={@comment} />
    """
  end

  @doc """
  Renders a person's avatar `<img>`.

  `Revix.Uploaders.Avatar`'s only version, `:thumb`, is always a 64x64 crop
  regardless of source image, so `width`/`height` are hardcoded here rather
  than measured — see GH issue 107.
  """
  attr :person, :map, required: true
  attr :alt, :string, default: nil

  def avatar_image(assigns) do
    ~H"""
    <img
      src={Revix.Uploaders.Avatar.url({@person.avatar, @person}, :thumb)}
      alt={@alt || avatar_alt(@person)}
      width="64"
      height="64"
    />
    """
  end

  defp avatar_alt(person), do: person.display_name || person.username || ""

  @doc """
  Renders an author avatar linked to their profile.

  Renders nothing when `author` is nil.
  """
  attr :author, :map, default: nil
  attr :width, :integer, default: 8

  def activity_avatar(assigns) do
    ~H"""
    <%= if @author do %>
      <a href={@author.url} class="inline-block shrink-0">
        <div class="avatar" title={@author.display_name || @author.username}>
          <div class={"w-#{@width} rounded-full"}>
            <.avatar_image person={@author} />
          </div>
        </div>
      </a>
    <% end %>
    """
  end

  attr :entry, :map, required: true

  defp entry_snippet(assigns) do
    snippet = entry_snippet_text(assigns.entry)
    assigns = assign(assigns, :snippet, snippet)

    ~H"""
    <span :if={@snippet != ""} class="block text-xs opacity-60">{raw(@snippet)}</span>
    """
  end

  defp entry_snippet_text(%{content: content}) when is_binary(content) do
    content
    |> Snippet.snippify(@snippet_max)
    |> render_typography()
  end

  defp entry_snippet_text(_entry), do: ""

  # The snippet is truncated plain text extracted from markdown before Earmark's
  # HTML render, so it still carries raw markdown punctuation (e.g. "---",
  # straight quotes) that `content_html` would already have converted to
  # typographic dashes/quotes. Round-trip it through Earmark the same way
  # `Entry.maybe_convert_content_to_html/1` does, then strip the wrapping tag.
  defp render_typography(text) do
    case Earmark.as_html(text, compact_output: true) do
      {:ok, html, _} -> html |> String.trim_leading("<p>") |> String.trim_trailing("</p>")
      {:error, _, _} -> text
    end
  end

  attr :local, :any, required: true
  attr :tz, :string, required: true
  attr :utc, :any, required: true

  defp activity_timestamp(assigns) do
    ~H"""
    <span class="text-xs italic text-right flex flex-col">
      <span>{Calendar.strftime(@local, "%Y-%m-%d")}</span>
      <span>{format_local_datetime(@local, @tz, @utc)}</span>
    </span>
    """
  end

  defp comment_root_entry(%{in_reply_to: %{type: :note} = parent}), do: comment_root_entry(parent)
  defp comment_root_entry(%{in_reply_to: %{type: _type} = entry}), do: entry
  defp comment_root_entry(_), do: nil

  defp comment_target_href(%{url: url}, comment_id)
       when is_binary(url) and is_binary(comment_id),
       do: "#{url}#comment-#{comment_id}"

  defp comment_target_href(_, _), do: nil

  defp comment_target_label(%{type: :checkin, place: %{name: name}}) when is_binary(name),
    do: name

  defp comment_target_label(%{type: :checkin}), do: "a checkin"

  defp comment_target_label(%{type: :post, name: name}) when is_binary(name) and name != "",
    do: name

  defp comment_target_label(%{type: :post}), do: "a post"
  defp comment_target_label(_), do: "an entry"

  defp place_name(%{place: %{name: name}}) when is_binary(name) and name != "", do: name
  defp place_name(_), do: nil

  defp has_place_name?(entry), do: not is_nil(place_name(entry))

  @doc """
  Renders the Likes and Comments sections for a show-entity page.

  For unauthenticated users the two sections sit inline as wrapping flex
  items; authenticated users get the full stacked layout each LiveView
  renders internally.
  """
  attr :conn, :map, required: true
  attr :current_scope, :any, required: true
  attr :entry_uri, :string, required: true
  attr :entry_author_uri, :string, required: true
  attr :person_token, :any, required: true

  def entry_interactions(assigns) do
    ~H"""
    <div class={if @current_scope, do: "my-4", else: "flex flex-wrap items-start gap-2 my-4"}>
      {live_render(@conn, RevixWeb.EntryLikeLive,
        id: "like-section",
        session: %{
          "entry_uri" => @entry_uri,
          "entry_author_uri" => @entry_author_uri,
          "person_token" => @person_token
        }
      )}
      {live_render(@conn, RevixWeb.CommentSectionLive,
        id: "comment-section",
        session: %{"checkin_uri" => @entry_uri, "person_token" => @person_token}
      )}
    </div>
    """
  end

  @doc """
  Renders the owner/author action bar (Edit, Re-transform photos) shown
  above the byline on a show-entity page.

  Renders nothing unless `current_scope` is present and is either the
  entry's author or an owner viewing an entry with images.
  """
  attr :current_scope, :any, required: true
  attr :entry_author_uri, :string, required: true
  attr :has_images, :boolean, required: true
  attr :edit_href, :string, required: true
  attr :retransform_href, :string, required: true
  attr :entry_label, :string, required: true

  def entry_owner_actions(assigns) do
    ~H"""
    <%= if @current_scope &&
             (@current_scope.person.uri == @entry_author_uri ||
                (@current_scope.role == :owner && @has_images)) do %>
      <div class="my-4 flex flex-wrap gap-2">
        <%= if @current_scope.person.uri == @entry_author_uri do %>
          <.icon_link href={@edit_href} icon="hero-pencil-square">
            Edit
          </.icon_link>
        <% end %>
        <%= if @current_scope.role == :owner && @has_images do %>
          <.link
            href={@retransform_href}
            method="post"
            data-confirm={"Re-transform all photos in this #{@entry_label}? This regenerates large, medium, and thumb versions from the originals."}
            class="btn btn-soft p-2 no-underline"
          >
            Re-transform photos <.icon name="hero-arrow-path" class="w-4 h-4" />
          </.link>
        <% end %>
      </div>
    <% end %>
    """
  end
end
