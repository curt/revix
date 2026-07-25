defmodule RevixWeb.ActivityComponents do
  use Phoenix.Component

  import RevixWeb.CoreComponents, only: [icon: 1, icon_link: 1]
  import RevixWeb.View.Helpers, only: [format_local_datetime: 3]

  @doc """
  Renders a list of activity feed items.

  Each activity is a tagged tuple: `{:checkin, checkin}`, `{:like, like}`,
  `{:like_group, group}`, `{:comment, comment}`, or `{:comment_group, group}`.
  """
  attr :activities, :list, required: true

  def activity_feed(assigns) do
    ~H"""
    <div class="my-4">
      <ul class="space-y-3">
        <%= for activity <- @activities do %>
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
            <% {:like_group, group} -> %>
              <.like_group_activity group={group} />
            <% {:comment, comment} -> %>
              <.comment_activity comment={comment} />
            <% {:comment_group, group} -> %>
              <.comment_group_activity group={group} />
          <% end %>
        <% end %>
      </ul>
    </div>
    """
  end

  @doc """
  Renders a single checkin activity item.
  """
  attr :checkin, :map, required: true

  def checkin_activity(assigns) do
    ~H"""
    <li class="flex items-start gap-2">
      <.activity_avatar author={@checkin.author} />
      <span>
        checked into
        <%= if place_name = place_name(@checkin) do %>
          <a href={@checkin.url} class="font-semibold hover:underline inline-block">
            {place_name}
          </a>
        <% else %>
          <span class="font-semibold">{@checkin.name || "somewhere"}</span>
        <% end %>
        <%= if @checkin.companions != [] do %>
          <div class="inline-block">
            <span class="text-sm italic">with</span>
            <span class="mx-1 inline-flex -space-x-2 align-middle">
              <%= for ep <- Enum.take(@checkin.companions, 5), ep.person do %>
                <.activity_avatar author={ep.person} width={6} />
              <% end %>
              <%= if length(@checkin.companions) > 5 do %>
                <span class="text-sm ml-1">+{length(@checkin.companions) - 5}</span>
              <% end %>
            </span>
          </div>
        <% end %>
        <%= if has_place_name?(@checkin) do %>
          <.activity_timestamp
            local={@checkin.starts_at_local}
            tz={@checkin.starts_tz}
            utc={@checkin.starts_at_utc}
          />
        <% end %>
      </span>
    </li>
    """
  end

  @doc """
  Renders a single post activity item.
  """
  attr :post, :map, required: true

  def post_activity(assigns) do
    ~H"""
    <li class="flex items-start gap-2">
      <.activity_avatar author={@post.author} />
      <span>
        posted
        <a href={@post.url} class="font-semibold hover:underline inline-block">
          {@post.name || "a post"}
        </a>
        <.activity_timestamp
          local={@post.published_at_local}
          tz={@post.published_tz}
          utc={@post.published_at_utc}
        />
      </span>
    </li>
    """
  end

  attr :post, :map, required: true

  def draft_activity(assigns) do
    ~H"""
    <li class="flex items-start gap-2">
      <.activity_avatar author={@post.author} />
      <span>
        drafted
        <a href={@post.url} class="font-semibold hover:underline inline-block">
          {@post.name || "a post"}
        </a>
        <span class="badge badge-warning badge-sm ml-1">Draft</span>
        <span class="text-sm italic">
          Updated {Calendar.strftime(@post.updated_at, "%Y-%m-%d")}
        </span>
      </span>
    </li>
    """
  end

  attr :checkin, :map, required: true

  def draft_checkin_activity(assigns) do
    ~H"""
    <li class="flex items-start gap-2">
      <.activity_avatar author={@checkin.author} />
      <span>
        drafted a checkin to
        <a href={"/checkins/#{@checkin.id}/edit"} class="font-semibold hover:underline inline-block">
          {get_in(@checkin, [Access.key(:place), Access.key(:name)]) ||
            @checkin.name || "somewhere"}
        </a>
        <span class="badge badge-warning badge-sm ml-1">Draft</span>
        <span class="text-sm italic">
          Updated {Calendar.strftime(@checkin.updated_at, "%Y-%m-%d")}
        </span>
      </span>
    </li>
    """
  end

  @doc """
  Renders a single like activity item.
  """
  attr :like, :map, required: true

  def like_activity(assigns) do
    ~H"""
    <li class="flex items-start gap-2">
      <.activity_avatar author={@like.author} />
      <span>
        <.icon name="hero-heart-solid" class="w-4 h-4 inline text-error" />
        <%= if @like.object && @like.object.type == :note do %>
          liked
          <a href={@like.object.url} class="font-semibold hover:underline inline-block">
            a comment
          </a>
        <% else %>
          liked
          <%= if place_name = place_name(@like.object) do %>
            <a href={@like.object.url} class="font-semibold hover:underline inline-block">
              {place_name}
            </a>
          <% else %>
            <span class="font-semibold">a checkin</span>
          <% end %>
        <% end %>
        <.activity_timestamp
          local={@like.published_at_local}
          tz={@like.published_tz}
          utc={@like.published_at_utc}
        />
      </span>
    </li>
    """
  end

  @doc """
  Renders a grouped like activity: multiple people liked the same object.
  """
  attr :group, :map, required: true

  def like_group_activity(assigns) do
    ~H"""
    <li class="flex items-start gap-2">
      <.avatar_group authors={@group.authors} />
      <span>
        <.icon name="hero-heart-solid" class="w-4 h-4 inline text-error" />
        <%= if @group.root_entry do %>
          liked a comment on
          <%= if place_name = place_name(@group.root_entry) do %>
            <a href={@group.root_entry.url} class="font-semibold hover:underline inline-block">
              {place_name}
            </a>
          <% else %>
            <a href={@group.root_entry.url} class="font-semibold hover:underline inline-block">
              {@group.root_entry.name || "a post"}
            </a>
          <% end %>
        <% else %>
          liked
          <%= if place_name = place_name(@group.object) do %>
            <a href={@group.object.url} class="font-semibold hover:underline inline-block">
              {place_name}
            </a>
          <% else %>
            <span class="font-semibold">a checkin</span>
          <% end %>
        <% end %>
        <.activity_timestamp
          local={@group.latest_published_at_local}
          tz={@group.latest_published_tz}
          utc={@group.latest_at}
        />
      </span>
    </li>
    """
  end

  @doc """
  Renders a group of overlapping author avatars with an overflow indicator.
  """
  attr :authors, :list, required: true
  attr :max, :integer, default: 3

  def avatar_group(assigns) do
    ~H"""
    <span class="inline-flex -space-x-2 shrink-0">
      <%= for author <- Enum.take(@authors, @max) do %>
        <.activity_avatar author={author} />
      <% end %>
      <%= if length(@authors) > @max do %>
        <span class="w-8 h-8 rounded-full bg-base-300 flex items-center justify-center text-xs font-semibold shrink-0">
          +{length(@authors) - @max}
        </span>
      <% end %>
    </span>
    """
  end

  @doc """
  Renders a single comment activity item.
  """
  attr :comment, :map, required: true

  def comment_activity(assigns) do
    ~H"""
    <li class="flex items-start gap-2">
      <.activity_avatar author={@comment.author} />
      <span>
        <%= if root = comment_root_entry(@comment) do %>
          commented on
          <%= if href = comment_target_href(root, @comment.id) do %>
            <a
              href={href}
              class="font-semibold hover:underline inline-block"
            >
              {comment_target_label(root)}
            </a>
          <% else %>
            <span class="font-semibold">{comment_target_label(root)}</span>
          <% end %>
        <% else %>
          replied to
          <.activity_avatar
            author={@comment.in_reply_to && @comment.in_reply_to.author}
            width={7}
          />
        <% end %>
        <.activity_timestamp
          local={@comment.published_at_local}
          tz={@comment.published_tz}
          utc={@comment.published_at_utc}
        />
      </span>
    </li>
    """
  end

  @doc """
  Renders a grouped comment activity: multiple people commented on the same object.
  """
  attr :group, :map, required: true

  def comment_group_activity(assigns) do
    ~H"""
    <li class="flex items-start gap-2">
      <.avatar_group authors={@group.authors} />
      <span>
        commented on
        <%= if href = comment_target_href(@group.root, @group.latest_comment_id) do %>
          <a
            href={href}
            class="font-semibold hover:underline inline-block"
          >
            {comment_target_label(@group.root)}
          </a>
        <% else %>
          <span class="font-semibold">{comment_target_label(@group.root)}</span>
        <% end %>
        <.activity_timestamp
          local={@group.latest_published_at_local}
          tz={@group.latest_published_tz}
          utc={@group.latest_at}
        />
      </span>
    </li>
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

  attr :local, :any, required: true
  attr :tz, :string, required: true
  attr :utc, :any, required: true

  defp activity_timestamp(assigns) do
    ~H"""
    <span class="text-sm italic">
      {Calendar.strftime(@local, "%Y-%m-%d")} {format_local_datetime(@local, @tz, @utc)}
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
