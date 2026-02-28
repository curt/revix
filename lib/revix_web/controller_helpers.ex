defmodule RevixWeb.Controller.Helpers do
  alias Revix.People.Person

  @spec activity(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def activity(conn, data) do
    conn
    |> Plug.Conn.put_resp_content_type("application/activity+json")
    |> Phoenix.Controller.json(contextify(data))
  end

  @spec to_person_activity(%Person{}) :: map()
  def to_person_activity(%Person{} = person) do
    %{
      "followers" => "#{person.uri}/followers",
      "following" => "#{person.uri}/following",
      "id" => person.uri,
      "name" => person.display_name || "Someone",
      "preferredUsername" => person.username || person.id,
      "inbox" => "#{person.uri}/inbox",
      "liked" => "#{person.uri}/liked",
      "outbox" => "#{person.uri}/outbox",
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

  @spec to_checkin_activity(%Revix.Entries.Entry{}) :: map()
  def to_checkin_activity(%Revix.Entries.Entry{} = checkin) do
    %{
      "type" => "Note",
      "id" => checkin.uri,
      "url" => checkin.url,
      "attributedTo" => checkin.author_uri,
      "published" => format_datetime(checkin.published_at_utc),
      "startTime" => format_datetime(checkin.starts_at_utc),
      "tag" => [%{"type" => "Hashtag", "name" => "#checkin"}]
    }
    |> maybe_add_checkin_content(checkin)
    |> maybe_add_place(checkin)
    |> maybe_add_context(checkin)
  end

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
