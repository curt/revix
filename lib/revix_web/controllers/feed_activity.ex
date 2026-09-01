defmodule RevixWeb.FeedActivity do
  @moduledoc """
  Format-agnostic helpers shared by the Atom (`RevixWeb.FeedATOM`) and RSS
  (`RevixWeb.FeedRSS`) feed views.

  Every function pattern-matches the `{tag, item}` activity tuple emitted by
  `Revix.ActivityFeed` and returns plain strings/DateTimes — no feed-format
  markup. The public feeds run through `Revix.ActivityFeed.build_feed_activities(nil, _)`
  / `build_person_activities(_, nil, _)`, which only ever produce `:checkin`,
  `:post`, and `:like` tuples, so there are no `:comment`/`:draft` clauses here.
  """

  def feed_entry_title({:checkin, checkin}) do
    author = get_in(checkin, [Access.key(:author), Access.key(:display_name)]) || "Someone"

    place =
      get_in(checkin, [Access.key(:place), Access.key(:name)]) || checkin.name || "somewhere"

    "#{author} checked into #{place}"
  end

  def feed_entry_title({:post, post}) do
    author = get_in(post, [Access.key(:author), Access.key(:display_name)]) || "Someone"
    title = post.name || "a post"
    "#{author} posted: #{title}"
  end

  def feed_entry_title({:like, like}) do
    author = get_in(like, [Access.key(:author), Access.key(:display_name)]) || "Someone"

    place =
      get_in(like, [Access.key(:object), Access.key(:place), Access.key(:name)]) || "a checkin"

    "#{author} liked #{place}"
  end

  def feed_entry_link({:checkin, entry}), do: entry.url
  def feed_entry_link({:post, entry}), do: entry.url
  def feed_entry_link({:like, like}), do: like.object && like.object.url

  def feed_entry_author_name({_, item}) do
    (item.author && (item.author.display_name || item.author.username)) || "Someone"
  end

  def feed_entry_author_uri({_, item}), do: item.author && item.author.url

  def feed_entry_content({:checkin, checkin}), do: Revix.Entries.checkin_display_content(checkin)
  def feed_entry_content({:post, post}), do: post.content_html || post.content
  def feed_entry_content({:like, _}), do: nil

  def feed_entry_enclosures({:checkin, entry}), do: entry_image_enclosures(entry.entry_images)
  def feed_entry_enclosures({:post, entry}), do: entry_image_enclosures(entry.entry_images)
  def feed_entry_enclosures({:like, _}), do: []

  defp entry_image_enclosures(entry_images) do
    Enum.map(entry_images, fn ei ->
      %{url: Revix.Uploaders.Image.public_url(ei.image, :large), type: "image/jpeg"}
    end)
  end

  @doc """
  The effective "updated" timestamp for an entry: the later of its
  `modified_at_utc` and `published_at_utc`, falling back gracefully when either
  is nil.
  """
  def effective_updated(%{modified_at_utc: nil, published_at_utc: published}), do: published

  def effective_updated(%{modified_at_utc: modified, published_at_utc: published}) do
    if is_nil(published) or DateTime.compare(modified, published) == :gt do
      modified
    else
      published
    end
  end

  def effective_updated(%{published_at_utc: published}), do: published

  @doc """
  Escapes text for interpolation into an XML text node (feed title, author
  name, channel metadata). Both feed templates are plain `.eex` (no automatic
  escaping), so callers must run user-derived strings through this.
  """
  def html_escaped(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
