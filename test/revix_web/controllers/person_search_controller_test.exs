defmodule RevixWeb.PersonSearchControllerTest do
  use RevixWeb.ConnCase, async: true

  import Revix.PeopleFixtures

  describe "GET /api/people/search (unauthenticated)" do
    test "redirects to sign in", %{conn: conn} do
      conn = get(conn, "/api/people/search", %{q: "alice"})
      assert redirected_to(conn) =~ "/people/signin"
    end
  end

  describe "GET /api/people/search (authenticated)" do
    setup :register_and_log_in_person

    test "returns people matching display_name query", %{conn: conn} do
      target = person_fixture()
      Revix.People.update_person_display_name(target, %{display_name: "Alice Smith"})

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/api/people/search", %{q: "Alice"})

      results = json_response(conn, 200)
      assert is_list(results)
      uris = Enum.map(results, & &1["uri"])
      assert target.uri in uris
    end

    test "excludes the current user from results", %{conn: conn, person: current_person} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/api/people/search", %{q: current_person.email})

      results = json_response(conn, 200)
      uris = Enum.map(results, & &1["uri"])
      refute current_person.uri in uris
    end

    test "returns empty list when query is empty", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/api/people/search", %{q: ""})

      assert json_response(conn, 200) == []
    end

    test "returns empty list when no params given", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/api/people/search")

      assert json_response(conn, 200) == []
    end

    test "returns results with expected fields", %{conn: conn} do
      target = person_fixture()
      Revix.People.update_person_display_name(target, %{display_name: "Bob Jones"})

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/api/people/search", %{q: "Bob"})

      results = json_response(conn, 200)
      [result | _] = Enum.filter(results, &(&1["uri"] == target.uri))
      assert Map.has_key?(result, "uri")
      assert Map.has_key?(result, "display_name")
      assert Map.has_key?(result, "username")
      assert Map.has_key?(result, "avatar_url")
    end
  end
end
