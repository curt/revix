defmodule RevixWeb.PersonCollectionControllerTest do
  use RevixWeb.ConnCase, async: true

  import Revix.PeopleFixtures

  setup do
    %{person: person_fixture()}
  end

  for action <- ~w[followers following outbox liked] do
    describe "GET /people/:id/#{action}" do
      test "returns empty OrderedCollection for existing person", %{conn: conn, person: person} do
        conn = get(conn, "/people/#{person.id}/#{unquote(action)}?_format=activity")
        response = json_response(conn, 200)

        assert response["type"] == "OrderedCollection"
        assert response["totalItems"] == 0
        assert response["orderedItems"] == []
        assert response["@context"] == "https://www.w3.org/ns/activitystreams"
        assert response["id"] =~ "/people/#{person.id}/#{unquote(action)}"
      end

      test "returns 404 for unknown person", %{conn: conn} do
        nonexistent_id = Revix.Ecto.Base58Id.autogenerate()

        assert_error_sent 404, fn ->
          get(conn, "/people/#{nonexistent_id}/#{unquote(action)}?_format=activity")
        end
      end
    end
  end
end
