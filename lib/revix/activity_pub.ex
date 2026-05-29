defmodule Revix.ActivityPub do
  # This module references RevixWeb.CanonicalRoutes and RevixWeb.Endpoint, creating a
  # cross-layer cycle. The fix is a config-driven Revix.URIs module that builds absolute
  # URLs from a :revix base_url config key instead of calling RevixWeb.Endpoint directly,
  # eliminating the compile-time dependency. Deferred for now.
  alias Revix.People.Person
  alias Revix.Snippet
  alias RevixWeb.CanonicalRoutes

  @as_context "https://www.w3.org/ns/activitystreams"
  @schema_context %{"schema" => "https://schema.org/", "sameAs" => "schema:sameAs"}
  @attachment_name_max 160
  @attachment_summary_max 1024

  def contextify(map) do
    Map.put(map, "@context", [@as_context, @schema_context])
  end

  def to_person_activity(%Person{} = person) do
    %{
      "followers" => CanonicalRoutes.person_followers_url(person.id),
      "following" => CanonicalRoutes.person_following_url(person.id),
      "id" => person.uri,
      "name" => person.display_name || "Someone",
      "preferredUsername" => person.username || person.id,
      "inbox" => CanonicalRoutes.person_inbox_url(person.id),
      "liked" => CanonicalRoutes.person_liked_url(person.id),
      "outbox" => CanonicalRoutes.person_outbox_url(person.id),
      "type" => "Person",
      "url" => person.url
    }
    |> maybe_add_public_key(person)
    |> maybe_add_icon(person)
  end

  def to_place_activity(%Revix.Places.Place{} = place) do
    place_to_map(place.uri, place)
    |> maybe_add_content(place)
  end

  def to_post_activity(%Revix.Entries.Entry{} = post) do
    note_base(post)
    |> maybe_add_name(post)
    |> maybe_add_post_locations(post)
  end

  def to_checkin_activity(%Revix.Entries.Entry{} = checkin) do
    note_base(checkin)
    |> Map.put("startTime", format_datetime(checkin.starts_at_utc))
    |> maybe_add_tag("#checkin")
    |> maybe_add_place(checkin)
  end

  def to_note_activity(%Revix.Entries.Entry{} = note) do
    note_base(note)
    |> maybe_add_in_reply_to(note)
  end

  defp note_base(entry) do
    %{
      "type" => "Note",
      "id" => entry.uri,
      "url" => entry.url,
      "attributedTo" => entry.author_uri,
      "published" => format_datetime(entry.published_at_utc),
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => [CanonicalRoutes.person_followers_url(entry.author.id)],
      "likes" => CanonicalRoutes.entry_likes_url(entry.id),
      "replies" => CanonicalRoutes.entry_replies_url(entry.id)
    }
    |> maybe_add_checkin_content(entry)
    |> maybe_add_attachments(entry)
    |> maybe_add_context(entry)
    |> maybe_add_updated(entry)
  end

  defp maybe_add_tag(map, tag), do: Map.put(map, "tag", [%{"type" => "Hashtag", "name" => tag}])

  defp maybe_add_name(map, %{name: nil}), do: map
  defp maybe_add_name(map, %{name: name}), do: Map.put(map, "name", name)

  defp maybe_add_post_locations(map, %{entry_places: []}), do: map

  defp maybe_add_post_locations(map, %{entry_places: entry_places}) when is_list(entry_places) do
    locations = Enum.map(entry_places, fn ep -> place_to_map(ep.place_uri, ep.place) end)
    Map.put(map, "location", locations)
  end

  defp maybe_add_post_locations(map, _), do: map

  defp maybe_add_coordinates(map, %{coordinates: %Geo.Point{coordinates: {lon, lat}}}) do
    Map.merge(map, %{"longitude" => lon, "latitude" => lat})
  end

  defp maybe_add_coordinates(map, _), do: map

  defp maybe_add_content(map, %{content: nil}), do: map
  defp maybe_add_content(map, %{content: content}), do: Map.put(map, "summary", content)

  defp maybe_add_checkin_content(map, checkin) do
    map
    |> Map.put("content", Revix.Entries.checkin_display_content(checkin))
    |> Map.put("mediaType", "text/html")
  end

  defp maybe_add_place(map, %{place_uri: nil}), do: map
  defp maybe_add_place(map, %{place_uri: uri, place: nil}), do: Map.put(map, "location", uri)

  defp maybe_add_place(map, %{place_uri: uri, place: place}) do
    Map.put(map, "location", place_to_map(uri, place))
  end

  defp place_to_map(uri, nil) do
    %{"id" => uri, "type" => "Place"}
  end

  defp place_to_map(uri, place) do
    %{"id" => uri, "type" => "Place"}
    |> Map.put("name", place.name)
    |> Map.put("url", place.url)
    |> maybe_add_coordinates(place)
    |> maybe_add_osm_same_as(place)
  end

  defp maybe_add_osm_same_as(map, %{osm_type: osm_type, osm_id: osm_id})
       when not is_nil(osm_type) and not is_nil(osm_id) do
    Map.put(map, "sameAs", "https://www.openstreetmap.org/#{osm_type}/#{osm_id}")
  end

  defp maybe_add_osm_same_as(map, _), do: map

  defp maybe_add_context(map, %{context: nil}), do: map
  defp maybe_add_context(map, %{context: ctx}), do: Map.put(map, "context", ctx)

  defp maybe_add_in_reply_to(map, %{in_reply_to_uri: nil}), do: map
  defp maybe_add_in_reply_to(map, %{in_reply_to_uri: uri}), do: Map.put(map, "inReplyTo", uri)

  defp maybe_add_updated(map, %{modified_at_utc: nil}), do: map

  defp maybe_add_updated(map, %{modified_at_utc: modified, published_at_utc: published}) do
    if is_nil(published) or DateTime.compare(modified, published) == :gt do
      Map.put(map, "updated", format_datetime(modified))
    else
      map
    end
  end

  defp maybe_add_attachments(map, %{entry_images: []}), do: map

  defp maybe_add_attachments(map, %{entry_images: entry_images}) when is_list(entry_images) do
    attachments =
      Enum.map(entry_images, fn ei ->
        url =
          case Revix.Uploaders.Image.url({ei.image.file, ei.image}, :large) do
            "//" <> _ = u -> u
            "/" <> _ = path -> Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, path)
            u -> u
          end

        %{"type" => "Document", "mediaType" => ei.image.content_type, "url" => url}
        |> maybe_add_attachment_caption(ei.image)
      end)

    Map.put(map, "attachment", attachments)
  end

  defp maybe_add_attachments(map, _), do: map

  defp maybe_add_attachment_caption(map, %{caption: nil}), do: map

  defp maybe_add_attachment_caption(map, %{caption: caption}) do
    map
    |> Map.put("name", attachment_name(caption))
    |> Map.put("summary", attachment_summary(caption))
  end

  defp attachment_name(caption) do
    truncated = Snippet.snippify(caption, @attachment_name_max)
    fit_snippet_to_limit(truncated, caption, @attachment_name_max)
  end

  defp attachment_summary(caption) do
    truncated = Snippet.snippify(caption, @attachment_summary_max)
    fit_snippet_to_limit(truncated, caption, @attachment_summary_max)
  end

  defp fit_snippet_to_limit(truncated, caption, max) do
    if String.length(truncated) <= max do
      truncated
    else
      Snippet.snippify(caption, max - 4)
    end
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp maybe_add_icon(map, person) do
    Map.put(map, "icon", %{
      "type" => "Image",
      "mediaType" => "image/png",
      "url" => RevixWeb.CanonicalRoutes.avatar_url(person)
    })
  end

  defp maybe_add_public_key(map, %Person{public_key: nil}), do: map

  defp maybe_add_public_key(map, %Person{} = person) do
    Map.merge(map, %{
      "publicKey" => %{
        "id" => "#{person.uri}#key",
        "owner" => person.uri,
        "publicKeyPem" => person.public_key
      }
    })
  end
end
