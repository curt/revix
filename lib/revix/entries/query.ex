defmodule Revix.Entries.Query do
  @moduledoc false
  # Query building blocks shared by Revix.Entries and its submodules.
  import Ecto.Query
  alias Revix.Entries.Entry
  alias Revix.Media.EntryImage

  def maybe_limit(query, limit) when is_integer(limit), do: limit(query, ^limit)

  def maybe_limit(query, _limit), do: query

  def maybe_before_recency(query, %DateTime{} = before),
    do: where(query, [e], e.starts_at_utc < ^before)

  def maybe_before_recency(query, _before), do: query

  def maybe_before_published(query, %DateTime{} = before),
    do: where(query, [e], e.published_at_utc < ^before)

  def maybe_before_published(query, _before), do: query

  def local_checkins(query) do
    where(query, [e], e.origin == :local and e.type == :checkin)
  end

  def local_comments(query) do
    where(query, [e], e.type == :note and e.origin == :local and is_nil(e.tombstoned_at))
  end

  def local_posts(query) do
    where(query, [e], e.origin == :local and e.type == :post)
  end

  def published_posts(query) do
    where(query, [e], not is_nil(e.published_at_utc) and is_nil(e.tombstoned_at))
  end

  def published_checkins(query) do
    where(query, [e], not is_nil(e.published_at_utc) and is_nil(e.tombstoned_at))
  end

  def draft_posts(query), do: where(query, [e], is_nil(e.published_at_utc))

  def order_by_recency(query) do
    order_by(query, [e], desc: e.starts_at_utc)
  end

  def order_by_published(query) do
    order_by(query, [e], desc: e.published_at_utc)
  end

  def with_checkin_preloads(query) do
    preloads = [
      :author,
      :place,
      companions: [:person],
      entry_images: ordered_entry_images_query()
    ]

    preload(query, ^preloads)
  end

  def with_comment_preloads(query) do
    preload(query, [:author, in_reply_to: [:author, :place, in_reply_to: [:author, :place]]])
  end

  def with_post_preloads(query) do
    preloads = [
      :author,
      companions: [:person],
      entry_places: [:place],
      entry_images: ordered_entry_images_query()
    ]

    preload(query, ^preloads)
  end

  def ordered_entry_images_query do
    from(ei in EntryImage, order_by: [asc: ei.position], preload: [image: :dimensions])
  end

  def entry_ok_or_not_found(%Entry{} = entry), do: {:ok, entry}

  def entry_ok_or_not_found(nil), do: {:error, :not_found}
end
