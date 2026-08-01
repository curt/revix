defmodule RevixWeb.StructuredData do
  alias Revix.Places.Place
  alias Revix.Snippet
  alias RevixWeb.CanonicalRoutes

  @og_title_max 60
  @og_description_max 160

  def place_og(%Place{} = place) do
    [{"og:type", "place"}, {"og:url", CanonicalRoutes.place_url(place)}]
    |> maybe_append_og_title(place.name)
    |> maybe_append_og_description(place.content)
  end

  def checkin_og(%Revix.Entries.Entry{} = checkin) do
    [
      {"og:type", "article"},
      {"og:url", CanonicalRoutes.checkin_url(checkin)}
    ]
    |> maybe_append_og_title(checkin_name(checkin.place))
    |> maybe_append_og_description(checkin.content)
    |> maybe_append("og:image", first_image_url(checkin.entry_images))
  end

  def post_og(%Revix.Entries.Entry{} = post) do
    [{"og:type", "article"}, {"og:url", CanonicalRoutes.post_url(post)}]
    |> maybe_append_og_title(post.name)
    |> maybe_append_og_description(post.summary)
    |> maybe_append("og:image", first_image_url(post.entry_images))
  end

  def home_og(title, description) do
    [{"og:type", "website"}, {"og:url", CanonicalRoutes.home_url()}]
    |> maybe_append_og_title(title)
    |> maybe_append_og_description(description)
  end

  def places_index_og do
    [{"og:type", "website"}, {"og:url", CanonicalRoutes.places_index_url()}]
    |> maybe_append_og_title("Places")
    |> maybe_append_og_description("Browse places on Revix.")
  end

  def checkins_index_og do
    [{"og:type", "website"}, {"og:url", CanonicalRoutes.checkins_index_url()}]
    |> maybe_append_og_title("Checkins")
    |> maybe_append_og_description("Recent check-ins on Revix.")
  end

  def posts_index_og do
    [{"og:type", "website"}, {"og:url", CanonicalRoutes.posts_index_url()}]
    |> maybe_append_og_title("Posts")
    |> maybe_append_og_description("Posts from the Revix community.")
  end

  def credits_og do
    [{"og:type", "website"}, {"og:url", CanonicalRoutes.credits_url()}]
    |> maybe_append_og_title("Credits")
    |> maybe_append_og_description("Version and system diagnostics for Revix.")
  end

  def person_og(%Revix.People.Person{} = person) do
    name = person.display_name || person.username

    [{"og:type", "profile"}, {"og:url", CanonicalRoutes.person_url(person)}]
    |> maybe_append_og_title(name)
    |> maybe_append("og:image", CanonicalRoutes.avatar_url(person))
  end

  def twitter_card(og_tags) do
    title = og_value(og_tags, "og:title")
    description = og_value(og_tags, "og:description")
    image = og_value(og_tags, "og:image")
    card_type = if image, do: "summary_large_image", else: "summary"

    [{"twitter:card", card_type}]
    |> maybe_append("twitter:title", title)
    |> maybe_append("twitter:description", description)
    |> maybe_append("twitter:image", image)
  end

  def person_json_ld(%Revix.People.Person{} = person) do
    name = person.display_name || person.username

    %{
      "@context" => "https://schema.org",
      "@type" => "ProfilePage",
      "mainEntity" =>
        %{"@type" => "Person", "name" => name, "url" => CanonicalRoutes.person_url(person)}
        |> maybe_put("image", CanonicalRoutes.avatar_url(person))
    }
  end

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

  def home_json_ld(title, description) do
    %{
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "name" => title,
      "url" => CanonicalRoutes.home_url()
    }
    |> maybe_put("description", description)
  end

  def post_json_ld(%Revix.Entries.Entry{published_at_utc: nil}), do: nil

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

  def checkin_name(%Place{name: name}), do: "Checkin at #{name}"
  def checkin_name(nil), do: "Checkin"

  def place_description(%Place{} = place),
    do: blank_to_nil(truncate_og_value(place.content, @og_description_max))

  def checkin_description(%Revix.Entries.Entry{} = checkin),
    do: blank_to_nil(truncate_og_value(checkin.content, @og_description_max))

  def post_description(%Revix.Entries.Entry{} = post),
    do: blank_to_nil(truncate_og_value(post.summary, @og_description_max))

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

  defp first_image_url([]), do: nil
  defp first_image_url([ei | _]), do: Revix.Uploaders.Image.public_url(ei.image, :large)

  defp maybe_append(list, _key, nil), do: list
  defp maybe_append(list, _key, ""), do: list
  defp maybe_append(list, key, value), do: list ++ [{key, value}]

  defp og_value(og_tags, key) do
    case List.keyfind(og_tags, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp maybe_append_og_title(list, value),
    do: maybe_append_og_value(list, "og:title", value, @og_title_max)

  defp maybe_append_og_description(list, value),
    do: maybe_append_og_value(list, "og:description", value, @og_description_max)

  defp maybe_append_og_value(list, key, value, max) do
    maybe_append(list, key, truncate_og_value(value, max))
  end

  defp truncate_og_value(value, max) do
    truncated = Snippet.snippify(value, max)
    fit_og_value(truncated, value, max)
  end

  defp fit_og_value(truncated, value, max)
       when is_binary(truncated) and is_integer(max) and max > 4 do
    if String.length(truncated) <= max do
      truncated
    else
      Snippet.snippify(value, max - 4)
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
