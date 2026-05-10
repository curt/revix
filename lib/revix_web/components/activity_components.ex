defmodule RevixWeb.ActivityComponents do
  use Phoenix.Component

  import RevixWeb.CoreComponents, only: [icon: 1]
  import RevixWeb.View.Helpers, only: [format_local_datetime: 3]

  @doc """
  Renders a list of activity feed items.

  Each activity is a tagged tuple: `{:checkin, checkin}`, `{:like, like}`,
  or `{:comment, comment}`.
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
            <% {:like, like} -> %>
              <.like_activity like={like} />
            <% {:comment, comment} -> %>
              <.comment_activity comment={comment} />
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
        <.activity_author author={@checkin.author} /> checked into
        <%= if @checkin.place do %>
          <a href={@checkin.url} class="font-semibold hover:underline inline-block">
            {@checkin.place.name}
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
        <%= if @checkin.place do %>
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
        <.activity_author author={@post.author} /> posted
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

  @doc """
  Renders a single like activity item.
  """
  attr :like, :map, required: true

  def like_activity(assigns) do
    ~H"""
    <li class="flex items-start gap-2">
      <.activity_avatar author={@like.author} />
      <span>
        <.activity_author author={@like.author} />
        <.icon name="hero-heart-solid" class="w-4 h-4 inline text-error" />
        <%= if @like.object && @like.object.type == :note do %>
          liked
          <a href={@like.object.url} class="font-semibold hover:underline inline-block">
            a comment
          </a>
        <% else %>
          liked
          <%= if @like.object && @like.object.place do %>
            <a href={@like.object.url} class="font-semibold hover:underline inline-block">
              {@like.object.place.name}
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
  Renders a single comment activity item.
  """
  attr :comment, :map, required: true

  def comment_activity(assigns) do
    ~H"""
    <li class="flex items-start gap-2">
      <.activity_avatar author={@comment.author} />
      <span>
        <%= if @comment.in_reply_to && @comment.in_reply_to.type == :checkin do %>
          <.activity_author author={@comment.author} /> commented on
          <%= if @comment.in_reply_to.place do %>
            <a
              href={"#{@comment.in_reply_to.url}#comment-#{@comment.id}"}
              class="font-semibold hover:underline inline-block"
            >
              {@comment.in_reply_to.place.name}
            </a>
          <% else %>
            <span class="font-semibold">a checkin</span>
          <% end %>
        <% else %>
          <.activity_author author={@comment.author} /> replied to
          <a href={@comment.url} class="font-semibold hover:underline inline-block">
            a comment
          </a>
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
            <img src={Revix.Uploaders.Avatar.url({@author.avatar, @author}, :thumb)} />
          </div>
        </div>
      </a>
    <% end %>
    """
  end

  attr :local, :any, required: true
  attr :tz, :string, required: true
  attr :utc, :any, required: true
  attr :href, :string, default: nil

  defp activity_timestamp(assigns) do
    ~H"""
    <%= if @href do %>
      <a href={@href} class="text-sm italic hover:underline inline-block">
        {Calendar.strftime(@local, "%Y-%m-%d")} {format_local_datetime(@local, @tz, @utc)}
      </a>
    <% else %>
      <span class="text-sm italic">
        {Calendar.strftime(@local, "%Y-%m-%d")} {format_local_datetime(@local, @tz, @utc)}
      </span>
    <% end %>
    """
  end

  @doc """
  Renders an author's display name as a link, or "Someone" if no author.
  """
  attr :author, :map, default: nil

  def activity_author(assigns) do
    ~H"""
    <%= if @author do %>
      <a href={@author.url} class="font-semibold hover:underline inline-block">
        {@author.display_name || "Someone"}
      </a>
    <% else %>
      <span class="font-semibold">Someone</span>
    <% end %>
    """
  end
end
