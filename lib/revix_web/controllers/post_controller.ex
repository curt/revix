defmodule RevixWeb.PostController do
  use RevixWeb, :controller

  alias Revix.Entries
  alias Revix.Likes
  alias RevixWeb.CanonicalRoutes
  alias RevixWeb.StructuredData

  action_fallback RevixWeb.FallbackController

  def index(conn, _params) do
    posts = Entries.get_recent_posts()
    index_by_format(conn, posts, get_format(conn))
  end

  defp index_by_format(conn, posts, "geo"), do: geo(conn, index_geo_features(posts))

  defp index_by_format(conn, posts, _) do
    uris = Enum.map(posts, & &1.uri)
    like_counts = Likes.count_active_likes_by_object_uris(uris)
    render(conn, posts: posts, like_counts: like_counts)
  end

  defp index_geo_features(posts) do
    posts
    |> Enum.flat_map(& &1.entry_places)
    |> Enum.filter(&(&1.place && &1.place.coordinates))
    |> Enum.uniq_by(& &1.place_uri)
    |> Enum.map(fn ep ->
      Map.merge(ep.place.coordinates, %{properties: %{name: ep.place.name, url: ep.place.url}})
    end)
  end

  def show(conn, %{"id" => id} = params) do
    with {:ok, post} <- Entries.get_local_post(id) do
      show_by_format(conn, post, params, get_format(conn))
    end
  end

  defp show_by_format(conn, post, _params, "geo") do
    geo(conn, show_geo_features(post))
  end

  defp show_by_format(conn, post, _params, "activity") do
    activity(conn, to_post_activity(post))
  end

  defp show_by_format(conn, post, params, _format) do
    canonical_date = canonical_date(post)
    canonical_slug = canonical_slug(post)

    if params["year"] != canonical_date.year ||
         params["month"] != canonical_date.month ||
         params["day"] != canonical_date.day ||
         params["slug"] != canonical_slug do
      redirect(conn, to: CanonicalRoutes.post_path(post))
    else
      like_counts = Likes.count_active_likes_by_object_uris([post.uri])

      conn
      |> assign(:json_ld, StructuredData.post_json_ld(post))
      |> assign(:head_links, [
        %{rel: "canonical", href: CanonicalRoutes.post_url(post)},
        %{
          rel: "alternate",
          type: "application/activity+json",
          href: CanonicalRoutes.post_uri(post)
        }
      ])
      |> assign(:head_meta, StructuredData.post_og(post))
      |> render(
        post: post,
        like_counts: like_counts,
        person_token: get_session(conn, :person_token)
      )
    end
  end

  defp show_geo_features(post) do
    post.entry_places
    |> Enum.filter(& &1.place.coordinates)
    |> Enum.map(fn ep ->
      Map.merge(ep.place.coordinates, %{
        properties: %{name: ep.place.name, url: ep.place.url, focus: true}
      })
    end)
  end

  defp canonical_date(%{published_at_local: nil}), do: %{year: nil, month: nil, day: nil}

  defp canonical_date(%{published_at_local: local}) do
    %{
      year: Calendar.strftime(local, "%Y"),
      month: Calendar.strftime(local, "%m"),
      day: Calendar.strftime(local, "%d")
    }
  end

  defp canonical_slug(%{name: nil, id: id}), do: id
  defp canonical_slug(%{name: "", id: id}), do: id

  defp canonical_slug(%{name: name, id: id}) do
    case Slug.slugify(name) do
      "" -> id
      slug -> slug
    end
  end
end
