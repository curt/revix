defmodule RevixWeb.CanonicalRoutes do
  use RevixWeb, :verified_routes

  # Site pages
  def home_url, do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, ~p"/")

  def places_index_url, do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, ~p"/places")

  def checkins_index_url,
    do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, ~p"/checkins")

  def posts_index_url, do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, ~p"/posts")

  def credits_url, do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, ~p"/credits")

  # People
  def person_path(%{id: id, username: username}), do: person_path(id, username)

  def person_path(id), do: ~p"/people/#{id}"

  def person_path(_id, username) when is_binary(username) and username != "" do
    ~p"/@#{username}"
  end

  def person_path(id, _username), do: person_path(id)

  def person_url(place) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, person_path(place))
  end

  def person_url(id, username) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, person_path(id, username))
  end

  def person_uri(%{id: id}) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, person_path(id))
  end

  def person_uri(id) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, person_path(id))
  end

  def person_inbox_url(id),
    do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, ~p"/people/#{id}/inbox")

  def person_followers_url(id),
    do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, ~p"/people/#{id}/followers")

  def person_following_url(id),
    do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, ~p"/people/#{id}/following")

  def person_outbox_url(id),
    do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, ~p"/people/#{id}/outbox")

  def person_liked_url(id),
    do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, ~p"/people/#{id}/liked")

  # Places
  def place_path(%{id: id} = place) when is_map_key(place, :slug) do
    country = Map.get(place, :country)
    city = Map.get(place, :city)
    secondary = Map.get(place, :secondary)
    slug = Map.get(place, :slug)
    place_path(id, country, secondary, city, slug)
  end

  def place_path(%{id: id}), do: place_path(id)

  def place_path(id), do: ~p"/places/#{id}"

  def place_path(id, slug), do: place_path(id, nil, nil, nil, slug)

  def place_path(id, country, secondary, city, slug)
      when is_binary(country) and is_binary(secondary) and is_binary(city) and is_binary(slug) and
             slug != "" do
    ~p"/places/#{id}/#{country}/#{secondary}/#{city}/#{slug}"
  end

  def place_path(id, country, _secondary, city, slug)
      when is_binary(country) and is_binary(city) and is_binary(slug) and slug != "" do
    ~p"/places/#{id}/#{country}/#{city}/#{slug}"
  end

  def place_path(id, country, _secondary, _city, slug)
      when is_binary(country) and is_binary(slug) and slug != "" do
    ~p"/places/#{id}/#{country}/#{slug}"
  end

  def place_path(id, _country, _secondary, _city, slug)
      when is_binary(slug) and slug != "" do
    ~p"/places/#{id}/#{slug}"
  end

  def place_path(id, _country, _secondary, _city, _slug), do: place_path(id)

  def place_url(place) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, place_path(place))
  end

  def place_url(id, slug) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, place_path(id, nil, nil, nil, slug))
  end

  def place_uri(%{id: id}) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, place_path(id))
  end

  def place_uri(id) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, place_path(id))
  end

  # Avatars
  def avatar_url(person) do
    case Revix.Uploaders.Avatar.url({person.avatar, person}, :thumb) do
      "//" <> _ = url -> url
      "/" <> _ = path -> Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, path)
      url -> url
    end
  end

  # Entry collections
  def entry_likes_url(id),
    do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, ~p"/entries/#{id}/likes")

  def entry_replies_url(id),
    do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, ~p"/entries/#{id}/replies")

  # Notes
  def note_path(id), do: ~p"/notes/#{id}"

  def note_uri(id),
    do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, note_path(id))

  def note_url(id),
    do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, note_path(id))

  # Checkins
  def checkin_path(%{id: id, place: place}) when is_map(place) do
    country = Map.get(place, :country)
    city = Map.get(place, :city)
    secondary = Map.get(place, :secondary)
    slug = Map.get(place, :slug)
    checkin_path(id, country, secondary, city, slug)
  end

  def checkin_path(%{id: id}), do: checkin_path(id)

  def checkin_path(id), do: ~p"/checkins/#{id}"

  def checkin_path(id, slug), do: checkin_path(id, nil, nil, nil, slug)

  def checkin_path(id, country, secondary, city, slug)
      when is_binary(country) and is_binary(secondary) and is_binary(city) and is_binary(slug) and
             slug != "" do
    ~p"/checkins/#{id}/#{country}/#{secondary}/#{city}/#{slug}"
  end

  def checkin_path(id, country, _secondary, city, slug)
      when is_binary(country) and is_binary(city) and is_binary(slug) and slug != "" do
    ~p"/checkins/#{id}/#{country}/#{city}/#{slug}"
  end

  def checkin_path(id, country, _secondary, _city, slug)
      when is_binary(country) and is_binary(slug) and slug != "" do
    ~p"/checkins/#{id}/#{country}/#{slug}"
  end

  def checkin_path(id, _country, _secondary, _city, slug)
      when is_binary(slug) and slug != "" do
    ~p"/checkins/#{id}/#{slug}"
  end

  def checkin_path(id, _country, _secondary, _city, _slug), do: checkin_path(id)

  def checkin_url(checkin) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, checkin_path(checkin))
  end

  def checkin_url(id, slug) do
    Phoenix.VerifiedRoutes.unverified_url(
      RevixWeb.Endpoint,
      checkin_path(id, nil, nil, nil, slug)
    )
  end

  def checkin_uri(%{id: id}) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, checkin_path(id))
  end

  def checkin_uri(id) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, checkin_path(id))
  end

  # Posts
  def post_path(%{id: id, published_at_local: local, name: name}) when not is_nil(local) do
    year = Calendar.strftime(local, "%Y")
    month = Calendar.strftime(local, "%m")
    day = Calendar.strftime(local, "%d")
    slug = Slug.slugify(name || "") |> then(fn s -> if s in [nil, ""], do: id, else: s end)
    ~p"/posts/#{id}/#{year}/#{month}/#{day}/#{slug}"
  end

  def post_path(%{id: id}), do: post_path(id)

  def post_path(id), do: ~p"/posts/#{id}"

  def post_url(post_or_id) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, post_path(post_or_id))
  end

  def post_uri(%{id: id}) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, post_path(id))
  end

  def post_uri(id) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, post_path(id))
  end

  def notification_settings_url,
    do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, ~p"/settings/notifications")
end
