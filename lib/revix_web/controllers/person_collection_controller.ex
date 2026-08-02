defmodule RevixWeb.PersonCollectionController do
  use RevixWeb, :controller

  alias Revix.Entries
  alias Revix.Follows
  alias Revix.People
  alias RevixWeb.CanonicalRoutes

  @outbox_limit 10

  action_fallback RevixWeb.FallbackController

  def followers(conn, %{"id" => id}) do
    with {:ok, person} <- People.get_person(id) do
      items = person.uri |> Follows.get_followers_for_person() |> Enum.map(& &1.follower_uri)

      activity(conn, %{
        "type" => "OrderedCollection",
        "id" => request_url(conn),
        "totalItems" => length(items),
        "orderedItems" => items
      })
    end
  end

  def following(conn, %{"id" => id}) do
    with {:ok, person} <- People.get_person(id) do
      items = person.uri |> Follows.get_following_for_person() |> Enum.map(& &1.following_uri)

      activity(conn, %{
        "type" => "OrderedCollection",
        "id" => request_url(conn),
        "totalItems" => length(items),
        "orderedItems" => items
      })
    end
  end

  def liked(conn, %{"id" => id}), do: render_collection(conn, id)

  def outbox(conn, %{"id" => id}) do
    with {:ok, person} <- People.get_person(id) do
      checkins = Entries.get_recent_checkins_for_person(person, limit: @outbox_limit)
      posts = Entries.get_recent_posts_for_person(person, limit: @outbox_limit)

      items =
        (checkins ++ posts)
        |> Enum.sort_by(& &1.published_at_utc, {:desc, DateTime})
        |> Enum.take(@outbox_limit)
        |> Enum.map(fn
          %{type: :checkin} = entry -> wrap_create(to_checkin_activity(entry), entry)
          %{type: :post} = entry -> wrap_create(to_post_activity(entry), entry)
        end)

      activity(conn, %{
        "type" => "OrderedCollection",
        "id" => request_url(conn),
        "totalItems" => length(items),
        "orderedItems" => items
      })
    end
  end

  defp render_collection(conn, id) do
    with {:ok, _person} <- People.get_person(id) do
      activity(conn, %{
        "type" => "OrderedCollection",
        "id" => request_url(conn),
        "totalItems" => 0,
        "orderedItems" => []
      })
    end
  end

  defp wrap_create(object, entry) do
    %{
      "type" => "Create",
      "id" => entry.uri <> "#create",
      "actor" => entry.author_uri,
      "published" => DateTime.to_iso8601(entry.published_at_utc),
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => [CanonicalRoutes.person_followers_url(entry.author.id)],
      "object" => object
    }
  end
end
