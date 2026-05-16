defmodule RevixWeb.StructuredData do
  alias Revix.Places.Place
  alias RevixWeb.CanonicalRoutes

  def place_json_ld(%Place{} = place) do
    %{
      "@context" => "https://schema.org",
      "@type" => "TouristAttraction",
      "name" => place.name,
      "url" => CanonicalRoutes.place_url(place)
    }
    |> maybe_put("geo", geo_coordinates(place.coordinates))
    |> maybe_put("sameAs", osm_url(place))
  end

  def checkin_json_ld(%Revix.Entries.Entry{} = checkin) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Event",
      "name" => checkin_name(checkin.place),
      "startDate" => DateTime.to_iso8601(checkin.starts_at_utc),
      "url" => CanonicalRoutes.checkin_url(checkin)
    }
    |> maybe_put("location", place_location(checkin.place))
    |> maybe_put("organizer", author_person(checkin.author))
  end

  def post_json_ld(%Revix.Entries.Entry{} = post) do
    %{
      "@context" => "https://schema.org",
      "@type" => "BlogPosting",
      "datePublished" => DateTime.to_iso8601(post.published_at_utc),
      "url" => CanonicalRoutes.post_url(post)
    }
    |> maybe_put("headline", post.name)
    |> maybe_put("author", author_person(post.author))
    |> maybe_put("description", post.summary)
    |> maybe_put("contentLocation", post_locations(post.entry_places))
  end

  defp geo_coordinates(%Geo.Point{coordinates: {lon, lat}}) do
    %{"@type" => "GeoCoordinates", "latitude" => lat, "longitude" => lon}
  end

  defp geo_coordinates(_), do: nil

  defp place_location(%Place{} = place) do
    %{"@type" => "Place", "name" => place.name}
    |> maybe_put("geo", geo_coordinates(place.coordinates))
    |> maybe_put("sameAs", osm_url(place))
  end

  defp place_location(nil), do: nil

  defp post_locations([]), do: nil

  defp post_locations(entry_places) do
    Enum.map(entry_places, fn ep -> place_location(ep.place) end)
  end

  defp checkin_name(%Place{name: name}), do: "Checkin at #{name}"
  defp checkin_name(nil), do: "Checkin"

  defp author_person(%{display_name: name, url: url}) when is_binary(name) and name != "" do
    %{"@type" => "Person", "name" => name}
    |> maybe_put("url", url)
  end

  defp author_person(%{username: username, url: url})
       when is_binary(username) and username != "" do
    %{"@type" => "Person", "name" => username}
    |> maybe_put("url", url)
  end

  defp author_person(_), do: nil

  defp osm_url(%Place{osm_type: osm_type, osm_id: osm_id})
       when not is_nil(osm_type) and not is_nil(osm_id) do
    "https://www.openstreetmap.org/#{osm_type}/#{osm_id}"
  end

  defp osm_url(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
