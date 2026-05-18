defmodule RevixWeb.PersonController do
  use RevixWeb, :controller

  alias Revix.People
  alias Revix.Entries
  alias Revix.Likes
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

  defp show_by_format(conn, person, _username, _format),
    do:
      render(conn,
        person: person,
        activities: person_activities(person, conn.assigns.current_scope)
      )

  defp geo_features(places) do
    Enum.map(places, fn p ->
      Map.merge(p.coordinates, %{properties: %{name: p.name, url: p.url}})
    end)
  end

  defp person_activities(person, scope) do
    limit = Application.get_env(:revix, :home)[:activity_limit] || 50
    checkins = Entries.get_recent_checkins_for_person(person, limit: limit)
    likes = Likes.get_recent_likes_for_person(person, limit: limit)
    comments = Entries.get_recent_comments_for_person(person, limit: limit)
    drafts = get_person_drafts(person, scope)

    (Enum.map(checkins, &{:checkin, &1}) ++
       Enum.map(likes, &{:like, &1}) ++
       Enum.map(comments, &{:comment, &1}) ++
       Enum.map(drafts, &{:draft, &1}))
    |> Enum.sort_by(
      fn {_, item} ->
        Map.from_struct(item)[:starts_at_utc] || item.published_at_utc || item.updated_at
      end,
      {:desc, DateTime}
    )
    |> Enum.take(limit)
  end

  defp get_person_drafts(person, %{person: %{uri: uri}}) when uri == person.uri do
    Entries.get_draft_posts_for_person(person)
  end

  defp get_person_drafts(_person, _scope), do: []
end
