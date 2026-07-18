defmodule RevixWeb.PostController do
  use RevixWeb, :controller

  alias Revix.Entries
  alias Revix.Likes
  alias Revix.Media
  alias RevixWeb.CanonicalRoutes
  alias RevixWeb.StructuredData

  action_fallback RevixWeb.FallbackController

  def index(conn, _params) do
    posts = Entries.get_recent_posts()
    drafts = get_author_drafts(conn.assigns.current_scope)
    index_by_format(conn, posts, drafts, get_format(conn))
  end

  defp get_author_drafts(%{person: person}) when not is_nil(person) do
    Entries.get_draft_posts_for_person(person)
  end

  defp get_author_drafts(_), do: []

  defp index_by_format(conn, posts, _drafts, "geo"), do: geo(conn, index_geo_features(posts))

  defp index_by_format(conn, posts, drafts, _format) do
    uris = Enum.map(posts, & &1.uri)
    like_counts = Likes.count_active_likes_by_object_uris(uris)

    conn
    |> assign(:head_links, [%{rel: "canonical", href: CanonicalRoutes.posts_index_url()}])
    |> assign(:head_meta, StructuredData.posts_index_og())
    |> render(
      posts: posts,
      draft_posts: drafts,
      like_counts: like_counts,
      page_title: "Posts · Revix",
      meta_description: "Posts from the Revix community."
    )
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

  defp show_by_format(conn, %{published_at_utc: nil} = post, _params, _format) do
    scope = conn.assigns.current_scope

    if scope && scope.person && scope.person.uri == post.author_uri do
      render(conn,
        post: post,
        like_counts: %{},
        person_token: get_session(conn, :person_token),
        page_title: post_page_title(post)
      )
    else
      {:error, :not_found}
    end
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
      |> assign(:meta_description, StructuredData.post_description(post))
      |> render(
        post: post,
        like_counts: like_counts,
        person_token: get_session(conn, :person_token),
        page_title: post_page_title(post)
      )
    end
  end

  def retransform_images(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope

    if scope && scope.role == :owner do
      case Entries.get_local_post(id) do
        {:ok, post} ->
          Media.retransform_images_for_entry(post.id)

          conn
          |> put_flash(:info, "Photos re-transformed.")
          |> redirect(to: ~p"/posts/#{post.id}")

        {:error, _} ->
          conn
          |> put_flash(:error, "Post not found.")
          |> redirect(to: ~p"/posts")
      end
    else
      conn
      |> put_flash(:error, "Not authorized.")
      |> redirect(to: ~p"/")
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

  defp post_page_title(%{name: name}) when is_binary(name) and name != "", do: "#{name} · Revix"
  defp post_page_title(_post), do: "Post · Revix"
end
