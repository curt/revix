defmodule RevixWeb.WebfingerControllerTest do
  use RevixWeb.ConnCase, async: true

  import Ecto.Query
  import Revix.PeopleFixtures

  defp person_with_username do
    person = person_fixture()
    username = "user#{System.unique_integer([:positive])}"

    Revix.Repo.update_all(
      from(p in Revix.People.Person, where: p.id == ^person.id),
      set: [username: username]
    )

    %{person | username: username}
  end

  describe "GET /.well-known/webfinger" do
    test "returns JRD for a known local person", %{conn: conn} do
      person = person_with_username()
      resource = "acct:#{person.username}@www.example.com"

      conn = get(conn, "/.well-known/webfinger?resource=#{URI.encode(resource)}")
      body = json_response(conn, 200)

      assert body["subject"] == resource
      assert is_list(body["aliases"])
      assert is_list(body["links"])
      assert Enum.any?(body["links"], &(&1["rel"] == "self"))
    end

    test "returns 404 when person is not found", %{conn: conn} do
      conn = get(conn, "/.well-known/webfinger?resource=acct:nobody@www.example.com")
      assert conn.status == 404
    end

    test "returns 400 when resource param is missing", %{conn: conn} do
      conn = get(conn, "/.well-known/webfinger")
      assert conn.status == 400
    end
  end
end
