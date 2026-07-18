defmodule RevixWeb.CheckinController do
  use RevixWeb, :controller

  alias Revix.Entries
  alias Revix.EntryPeople
  alias Revix.Likes
  alias Revix.Media
  alias Revix.Places
  alias RevixWeb.CanonicalRoutes
  alias RevixWeb.StructuredData

  action_fallback RevixWeb.FallbackController

  def index(conn, _) do
    checkins = Entries.get_local_checkins()
    index_by_format(conn, checkins, get_format(conn))
  end

  defp index_by_format(conn, checkins, "geo"), do: geo(conn, index_geo_features(checkins))

  defp index_by_format(conn, checkins, _) do
    unique = index_unique_checkins(checkins)
    uris = Enum.map(unique, & &1.uri)
    like_counts = Likes.count_active_likes_by_object_uris(uris)

    render(conn,
      checkins: unique,
      like_counts: like_counts,
      page_title: "Checkins · Revix",
      meta_description: "Recent check-ins on Revix."
    )
  end

  defp index_geo_features(checkins) do
    index_unique_checkins(checkins)
    |> Enum.map(fn c ->
      Map.merge(c.place.coordinates, %{
        properties: %{name: c.place.name, url: c.place.url}
      })
    end)
  end

  defp index_unique_checkins(checkins) do
    checkins
    |> Enum.filter(& &1.place)
    |> Enum.uniq_by(& &1.place.id)
  end

  def show(conn, %{"id" => id} = params) do
    with {:ok, checkin} <- Entries.get_local_checkin(id) do
      nearby = Places.get_local_places_near(checkin.place)
      checkins = Entries.get_local_checkins_for_place(checkin.place)
      other_checkins = Enum.reject(checkins, &(&1.id == checkin.id))

      show_by_format(
        conn,
        checkin,
        checkin.place,
        other_checkins,
        nearby,
        params["slug"],
        get_format(conn)
      )
    end
  end

  defp show_by_format(conn, checkin, _place, _checkins, _nearby, _, "activity"),
    do: activity(conn, to_checkin_activity(checkin))

  defp show_by_format(conn, _checkin, place, _checkins, nearby, _, "geo"),
    do: geo(conn, show_geo_features(place, nearby))

  defp show_by_format(conn, checkin, place, checkins, nearby, _, _) do
    canonical = checkin_path(checkin)

    if canonical != conn.request_path do
      redirect(conn, to: canonical)
    else
      companions = EntryPeople.get_companions_for_entry(checkin.uri)

      conn
      |> assign(:json_ld, StructuredData.checkin_json_ld(checkin))
      |> assign(:head_links, [
        %{rel: "canonical", href: CanonicalRoutes.checkin_url(checkin)},
        %{
          rel: "alternate",
          type: "application/activity+json",
          href: CanonicalRoutes.checkin_uri(checkin)
        }
      ])
      |> assign(:head_meta, StructuredData.checkin_og(checkin))
      |> assign(:meta_description, StructuredData.checkin_description(checkin))
      |> render(
        checkin: checkin,
        place: place,
        checkins: checkins,
        nearby: nearby,
        companions: companions,
        person_token: get_session(conn, :person_token),
        page_title: "#{StructuredData.checkin_name(place)} · Revix"
      )
    end
  end

  def retransform_images(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope

    if scope && scope.role == :owner do
      case Entries.get_local_checkin(id) do
        {:ok, checkin} ->
          Media.retransform_images_for_entry(checkin.id)

          conn
          |> put_flash(:info, "Photos re-transformed.")
          |> redirect(to: ~p"/checkins/#{checkin.id}")

        {:error, _} ->
          conn
          |> put_flash(:error, "Checkin not found.")
          |> redirect(to: ~p"/checkins")
      end
    else
      conn
      |> put_flash(:error, "Not authorized.")
      |> redirect(to: ~p"/")
    end
  end

  defp show_geo_features(place, nearby) do
    [
      Map.merge(place.coordinates, %{
        properties: %{name: place.name, url: place.url, focus: true}
      })
      | Enum.map(nearby, fn n ->
          Map.merge(n.place.coordinates, %{properties: %{name: n.place.name, url: n.place.url}})
        end)
    ]
  end
end
