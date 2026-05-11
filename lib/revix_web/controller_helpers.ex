defmodule RevixWeb.Controller.Helpers do
  alias Revix.People.Person
  alias RevixWeb.CanonicalRoutes

  @spec activity(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def activity(conn, data) do
    conn
    |> Plug.Conn.put_resp_content_type("application/activity+json")
    |> Phoenix.Controller.json(contextify(data))
  end

  @spec to_person_activity(%Person{}) :: map()
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

  @spec to_place_activity(%Revix.Places.Place{}) :: map()
  def to_place_activity(%Revix.Places.Place{} = place) do
    %{
      "type" => "Place",
      "id" => place.uri,
      "name" => place.name,
      "url" => place.url
    }
    |> maybe_add_coordinates(place)
    |> maybe_add_content(place)
  end

  def to_post_activity(%Revix.Entries.Entry{} = post) do
    note_base(post, "#post")
    |> maybe_add_name(post)
    |> maybe_add_post_locations(post)
  end

  def to_checkin_activity(%Revix.Entries.Entry{} = checkin) do
    note_base(checkin, "#checkin")
    |> Map.put("startTime", format_datetime(checkin.starts_at_utc))
    |> maybe_add_place(checkin)
  end

  defp note_base(entry, tag) do
    %{
      "type" => "Note",
      "id" => entry.uri,
      "url" => entry.url,
      "attributedTo" => entry.author_uri,
      "published" => format_datetime(entry.published_at_utc),
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => [CanonicalRoutes.person_followers_url(entry.author.id)],
      "tag" => [%{"type" => "Hashtag", "name" => tag}]
    }
    |> maybe_add_checkin_content(entry)
    |> maybe_add_attachments(entry)
    |> maybe_add_context(entry)
  end

  defp maybe_add_name(map, %{name: nil}), do: map
  defp maybe_add_name(map, %{name: name}), do: Map.put(map, "name", name)

  defp maybe_add_post_locations(map, %{entry_places: []}), do: map

  defp maybe_add_post_locations(map, %{entry_places: entry_places}) do
    locations =
      Enum.map(entry_places, fn ep ->
        %{"id" => ep.place_uri, "type" => "Place"}
        |> Map.put("name", ep.place && ep.place.name)
        |> maybe_add_coordinates(ep.place || %{})
      end)

    Map.put(map, "location", locations)
  end

  defp maybe_add_post_locations(map, _), do: map

  defp maybe_add_coordinates(map, %{coordinates: %Geo.Point{coordinates: {lon, lat}}}) do
    Map.merge(map, %{"longitude" => lon, "latitude" => lat})
  end

  defp maybe_add_coordinates(map, _), do: map

  defp maybe_add_content(map, %{content: nil}), do: map
  defp maybe_add_content(map, %{content: content}), do: Map.put(map, "summary", content)

  defp maybe_add_checkin_content(map, %{content: nil}), do: map

  defp maybe_add_checkin_content(map, %{content: content, content_html: html}) do
    map
    |> Map.put("content", html || content)
    |> Map.put("mediaType", "text/html")
  end

  defp maybe_add_place(map, %{place_uri: nil}), do: map
  defp maybe_add_place(map, %{place_uri: uri, place: nil}), do: Map.put(map, "location", uri)

  defp maybe_add_place(map, %{place_uri: uri, place: place}) do
    location =
      %{"id" => uri, "type" => "Place"}
      |> Map.put("name", place.name)
      |> maybe_add_coordinates(place)

    map
    |> Map.put("location", location)
  end

  defp maybe_add_context(map, %{context: nil}), do: map
  defp maybe_add_context(map, %{context: ctx}), do: Map.put(map, "context", ctx)

  defp maybe_add_attachments(map, %{entry_images: []}), do: map

  defp maybe_add_attachments(map, %{entry_images: entry_images}) do
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

  defp maybe_add_attachment_caption(map, %{caption: caption, caption_html: html}) do
    map
    |> Map.put("name", caption)
    |> Map.put("summary", html || caption)
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

  @spec contextify(map()) :: map()
  def contextify(map) do
    map |> Map.merge(%{"@context" => "https://www.w3.org/ns/activitystreams"})
  end

  @spec geo(Plug.Conn.t(), [Geo.geometry()]) :: Plug.Conn.t()
  def geo(conn, data) do
    conn
    |> Plug.Conn.put_resp_content_type("application/geo+json")
    |> Phoenix.Controller.json(
      Geo.JSON.Encoder.encode!(%Geo.GeometryCollection{geometries: data}, feature: true)
    )
  end
end
