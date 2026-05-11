defmodule RevixWeb.PersonCollectionControllerTest do
  use RevixWeb.ConnCase, async: true

  import Revix.PeopleFixtures
  import Revix.EntriesFixtures
  import Revix.PlacesFixtures

  setup do
    %{person: person_fixture()}
  end

  for action <- ~w[followers following liked] do
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

  describe "GET /people/:id/outbox" do
    test "returns empty outbox for person with no entries", %{conn: conn, person: person} do
      conn = get(conn, "/people/#{person.id}/outbox?_format=activity")
      response = json_response(conn, 200)

      assert response["type"] == "OrderedCollection"
      assert response["totalItems"] == 0
      assert response["orderedItems"] == []
      assert response["@context"] == "https://www.w3.org/ns/activitystreams"
      assert response["id"] =~ "/people/#{person.id}/outbox"
    end

    test "includes recent checkins and posts wrapped in Create activities", %{
      conn: conn,
      person: person
    } do
      place = place_fixture()
      checkin = checkin_fixture(%{author_uri: person.uri, place_uri: place.uri})
      post = post_fixture(%{author_uri: person.uri})

      conn = get(conn, "/people/#{person.id}/outbox?_format=activity")
      response = json_response(conn, 200)

      assert response["totalItems"] == 2
      activity_types = Enum.map(response["orderedItems"], & &1["type"])
      assert Enum.all?(activity_types, &(&1 == "Create"))

      object_ids = Enum.map(response["orderedItems"], & &1["object"]["id"])
      assert checkin.uri in object_ids
      assert post.uri in object_ids

      actors = Enum.map(response["orderedItems"], & &1["actor"])
      assert Enum.all?(actors, &(&1 == person.uri))

      to_fields = Enum.map(response["orderedItems"], & &1["to"])
      assert Enum.all?(to_fields, &(&1 == ["https://www.w3.org/ns/activitystreams#Public"]))

      object_to = Enum.map(response["orderedItems"], & &1["object"]["to"])
      assert Enum.all?(object_to, &(&1 == ["https://www.w3.org/ns/activitystreams#Public"]))

      object_cc = Enum.map(response["orderedItems"], & &1["object"]["cc"])
      assert Enum.all?(object_cc, &(&1 == [person.uri <> "/followers"]))
    end

    test "does not include other people's entries", %{conn: conn, person: person} do
      other = person_fixture()
      place = place_fixture()
      checkin_fixture(%{author_uri: other.uri, place_uri: place.uri})

      conn = get(conn, "/people/#{person.id}/outbox?_format=activity")
      response = json_response(conn, 200)

      assert response["totalItems"] == 0
    end

    test "returns 404 for unknown person", %{conn: conn} do
      nonexistent_id = Revix.Ecto.Base58Id.autogenerate()

      assert_error_sent 404, fn ->
        get(conn, "/people/#{nonexistent_id}/outbox?_format=activity")
      end
    end
  end
end
