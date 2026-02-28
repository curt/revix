defmodule RevixWeb.PersonSearchController do
  use RevixWeb, :controller

  alias Revix.People

  def search(conn, %{"q" => query}) when byte_size(query) > 0 do
    scope = conn.assigns.current_scope
    people = People.search_people(query, scope.person.uri)

    results =
      Enum.map(people, fn person ->
        %{
          uri: person.uri,
          display_name: person.display_name,
          username: person.username,
          avatar_url: Revix.Uploaders.Avatar.url({person.avatar, person}, :thumb)
        }
      end)

    json(conn, results)
  end

  def search(conn, _params) do
    json(conn, [])
  end
end
