defmodule RevixWeb.CanonicalRoutes do
  use RevixWeb, :verified_routes

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

  # Places
  def place_path(%{id: id, slug: slug}), do: place_path(id, slug)

  def place_path(%{id: id}), do: place_path(id)

  def place_path(id), do: ~p"/places/#{id}"

  def place_path(id, slug) when is_binary(slug) and slug != "" do
    ~p"/places/#{id}/#{slug}"
  end

  def place_path(id, _slug), do: place_path(id)

  def place_url(place) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, place_path(place))
  end

  def place_url(id, slug) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, place_path(id, slug))
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

  # Likes
  def like_path(id), do: "/likes/#{id}"

  def like_uri(id),
    do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, like_path(id))

  # Notes
  def note_path(id), do: ~p"/notes/#{id}"

  def note_uri(id),
    do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, note_path(id))

  def note_url(id),
    do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, note_path(id))

  # Checkins
  def checkin_path(%{id: id, place: %{slug: slug}}), do: checkin_path(id, slug)

  def checkin_path(%{id: id}), do: checkin_path(id)

  def checkin_path(id), do: ~p"/checkins/#{id}"

  def checkin_path(id, slug) when is_binary(slug) and slug != "" do
    ~p"/checkins/#{id}/#{slug}"
  end

  def checkin_path(id, _slug), do: checkin_path(id)

  def checkin_url(checkin) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, checkin_path(checkin))
  end

  def checkin_url(id, slug) do
    Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, checkin_path(id, slug))
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
end
