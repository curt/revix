defmodule RevixWeb.FeedATOM do
  use RevixWeb, :html

  embed_templates "feed_atom/*"

  def format_atom_datetime(nil), do: ""
  def format_atom_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  def feed_entry_id({:checkin, entry}), do: entry.uri
  def feed_entry_id({:post, entry}), do: entry.uri
  def feed_entry_id({:like, like}), do: "#{like.object_uri}#like-#{like.id}"
  def feed_entry_id({:comment, entry}), do: entry.uri

  def feed_entry_updated({:checkin, entry}), do: format_atom_datetime(effective_updated(entry))
  def feed_entry_updated({:post, entry}), do: format_atom_datetime(effective_updated(entry))
  def feed_entry_updated({:comment, entry}), do: format_atom_datetime(effective_updated(entry))
  def feed_entry_updated({:like, like}), do: format_atom_datetime(like.published_at_utc)

  def effective_updated(%{modified_at_utc: nil, published_at_utc: published}), do: published

  def effective_updated(%{modified_at_utc: modified, published_at_utc: published}) do
    if is_nil(published) or DateTime.compare(modified, published) == :gt do
      modified
    else
      published
    end
  end

  def effective_updated(%{published_at_utc: published}), do: published

  def feed_entry_enclosures({:checkin, entry}), do: entry_image_enclosures(entry.entry_images)
  def feed_entry_enclosures({:post, entry}), do: entry_image_enclosures(entry.entry_images)
  def feed_entry_enclosures({:comment, _}), do: []
  def feed_entry_enclosures({:like, _}), do: []

  defp entry_image_enclosures(entry_images) do
    Enum.map(entry_images, fn ei ->
      %{url: Revix.Uploaders.Image.public_url(ei.image, :large), type: "image/jpeg"}
    end)
  end

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

  def feed_entry_title({:comment, comment}) do
    author = get_in(comment, [Access.key(:author), Access.key(:display_name)]) || "Someone"

    place =
      get_in(comment, [Access.key(:in_reply_to), Access.key(:place), Access.key(:name)]) ||
        "a checkin"

    "#{author} commented on #{place}"
  end

  def feed_entry_link({:checkin, entry}), do: entry.url
  def feed_entry_link({:post, entry}), do: entry.url
  def feed_entry_link({:like, like}), do: like.object && like.object.url
  def feed_entry_link({:comment, entry}), do: entry.url

  def feed_entry_author_name({_, item}) do
    (item.author && (item.author.display_name || item.author.username)) || "Someone"
  end

  def feed_entry_author_uri({_, item}), do: item.author && item.author.url

  def feed_entry_content({:checkin, checkin}), do: Revix.Entries.checkin_display_content(checkin)
  def feed_entry_content({:post, post}), do: post.content_html || post.content
  def feed_entry_content({:like, _}), do: nil
  def feed_entry_content({:comment, comment}), do: comment.content_html || comment.content
end
