defmodule RevixWeb.LikeController do
  use RevixWeb, :controller

  alias Revix.Likes

  def create(conn, %{"object_uri" => object_uri, "published_tz" => timezone}) do
    scope = conn.assigns.current_scope
    uri_fn = &RevixWeb.CanonicalRoutes.like_uri/1

    case Likes.like_entry(scope, object_uri, timezone, uri_fn) do
      {:ok, _like} ->
        json(conn, like_response(object_uri, true))

      {:error, :self_like} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You cannot like your own entry"})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Could not create like"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Missing required parameters"})
  end

  def delete(conn, %{"object_uri" => object_uri}) do
    scope = conn.assigns.current_scope

    case Likes.unlike_entry(scope, object_uri) do
      {:ok, _like} ->
        json(conn, like_response(object_uri, false))

      {:error, :not_found} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active like found"})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Could not remove like"})
    end
  end

  def delete(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Missing required parameters"})
  end

  # Builds the JSON response with count and liker avatar info for client-side refresh.
  defp like_response(object_uri, liked) do
    likes = Likes.get_active_likes_for_entry(object_uri)
    count = length(likes)

    likers =
      likes
      |> Enum.take(5)
      |> Enum.filter(& &1.author)
      |> Enum.map(fn like ->
        %{
          avatar_url: Revix.Uploaders.Avatar.url({like.author.avatar, like.author}, :thumb),
          display_name: like.author.display_name || like.author.username || like.author.id
        }
      end)

    %{liked: liked, count: count, likers: likers, total: count}
  end
end
