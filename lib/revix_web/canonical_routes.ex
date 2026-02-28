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
end
