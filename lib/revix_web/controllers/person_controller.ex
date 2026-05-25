defmodule RevixWeb.PersonController do
  use RevixWeb, :controller

  alias Revix.ActivityFeed
  alias Revix.People
  alias Revix.Places

  action_fallback RevixWeb.FallbackController

  def show(conn, %{"id" => id}) do
    with {:ok, person} <- People.get_local_person(id) do
      show_by_format(conn, person, nil, get_format(conn))
    end
  end

  def show(conn, %{"username" => username}) do
    with {:ok, person} <- People.get_local_person_by_username(username) do
      show_by_format(conn, person, username, get_format(conn))
    end
  end

  defp show_by_format(conn, person, username, "activity") when not is_nil(username),
    do: redirect(conn, to: ~p"/people/#{person.id}")

  defp show_by_format(conn, person, _username, "activity"),
    do: activity(conn, to_person_activity(person))

  defp show_by_format(conn, person, _username, "geo") do
    places = Places.get_places_for_person(person)
    geo(conn, geo_features(places))
  end

  defp show_by_format(conn, %{username: username}, nil, _format) when not is_nil(username),
    do: redirect(conn, to: ~p"/@#{username}")

  defp show_by_format(conn, person, _username, _format) do
    if conn.assigns.current_scope && conn.assigns.current_scope.person do
      Phoenix.LiveView.Controller.live_render(conn, RevixWeb.PersonFeedLive,
        session: %{"person_id" => person.id}
      )
    else
      limit = Application.get_env(:revix, :home)[:activity_limit] || 50
      activities = ActivityFeed.build_person_activities(person, nil, limit)
      render(conn, :show, person: person, activities: activities)
    end
  end

  defp geo_features(places) do
    Enum.map(places, fn p ->
      Map.merge(p.coordinates, %{properties: %{name: p.name, url: p.url}})
    end)
  end
end
