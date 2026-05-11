defmodule RevixWeb.PersonCollectionController do
  use RevixWeb, :controller

  alias Revix.People

  def followers(conn, %{"id" => id}), do: render_collection(conn, id)
  def following(conn, %{"id" => id}), do: render_collection(conn, id)
  def outbox(conn, %{"id" => id}), do: render_collection(conn, id)
  def liked(conn, %{"id" => id}), do: render_collection(conn, id)

  defp render_collection(conn, id) do
    People.get_person!(id)

    activity(conn, %{
      "type" => "OrderedCollection",
      "id" => request_url(conn),
      "totalItems" => 0,
      "orderedItems" => []
    })
  end
end
