defmodule RevixWeb.EntryPeopleControllerTest do
  use RevixWeb.ConnCase, async: true

  import Revix.PeopleFixtures
  import Revix.EntriesFixtures
  import Revix.PlacesFixtures

  alias Revix.EntryPeople

  setup do
    author = person_fixture()
    place = place_fixture()
    checkin = checkin_fixture(%{place_uri: place.uri, author_uri: author.uri})
    companion = person_fixture()
    %{author: author, checkin: checkin, companion: companion}
  end

  describe "POST /api/entry_people (unauthenticated)" do
    test "redirects to sign in", %{conn: conn, checkin: checkin, companion: companion} do
      conn =
        post(conn, "/api/entry_people", %{
          entry_uri: checkin.uri,
          person_uri: companion.uri
        })

      assert redirected_to(conn) =~ "/people/signin"
    end
  end

  describe "DELETE /api/entry_people (unauthenticated)" do
    test "redirects to sign in", %{conn: conn, checkin: checkin, companion: companion} do
      conn =
        delete(conn, "/api/entry_people", %{entry_uri: checkin.uri, person_uri: companion.uri})

      assert redirected_to(conn) =~ "/people/signin"
    end
  end

  describe "POST /api/entry_people (authenticated as author)" do
    setup %{author: author} = context do
      %{conn: log_in_person(context[:conn], author), scope: Revix.People.Scope.for_person(author)}
    end

    test "adds a companion and returns companions list", %{
      conn: conn,
      checkin: checkin,
      companion: companion
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(
          "/api/entry_people",
          Jason.encode!(%{entry_uri: checkin.uri, person_uri: companion.uri})
        )

      assert %{"companions" => [_], "count" => 1, "total" => 1} = json_response(conn, 200)
    end

    test "is idempotent when companion already exists", %{
      conn: conn,
      checkin: checkin,
      companion: companion,
      scope: scope
    } do
      {:ok, _} = EntryPeople.add_companion(scope, checkin.uri, companion.uri)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(
          "/api/entry_people",
          Jason.encode!(%{entry_uri: checkin.uri, person_uri: companion.uri})
        )

      assert %{"count" => 1} = json_response(conn, 200)
    end

    test "returns 403 when trying to add self as companion", %{
      conn: conn,
      checkin: checkin,
      author: author
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(
          "/api/entry_people",
          Jason.encode!(%{entry_uri: checkin.uri, person_uri: author.uri})
        )

      assert %{"error" => _} = json_response(conn, 403)
    end

    test "returns error when required params are missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post("/api/entry_people", Jason.encode!(%{}))

      assert %{"error" => _} = json_response(conn, 422)
    end
  end

  describe "POST /api/entry_people (authenticated as non-author)" do
    setup %{companion: companion} = context do
      %{conn: log_in_person(context[:conn], companion)}
    end

    test "returns 403 when non-author tries to add a companion", %{
      conn: conn,
      checkin: checkin
    } do
      third = person_fixture()

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(
          "/api/entry_people",
          Jason.encode!(%{entry_uri: checkin.uri, person_uri: third.uri})
        )

      assert %{"error" => _} = json_response(conn, 403)
    end
  end

  describe "DELETE /api/entry_people (authenticated as author)" do
    setup %{author: author} = context do
      %{conn: log_in_person(context[:conn], author), scope: Revix.People.Scope.for_person(author)}
    end

    test "removes a companion and returns updated companions list", %{
      conn: conn,
      checkin: checkin,
      companion: companion,
      scope: scope
    } do
      {:ok, _} = EntryPeople.add_companion(scope, checkin.uri, companion.uri)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> delete(
          "/api/entry_people",
          Jason.encode!(%{entry_uri: checkin.uri, person_uri: companion.uri})
        )

      assert %{"companions" => [], "count" => 0} = json_response(conn, 200)
      assert EntryPeople.get_companions_for_entry(checkin.uri) == []
    end

    test "returns 422 when companion does not exist", %{
      conn: conn,
      checkin: checkin,
      companion: companion
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> delete(
          "/api/entry_people",
          Jason.encode!(%{entry_uri: checkin.uri, person_uri: companion.uri})
        )

      assert %{"error" => _} = json_response(conn, 422)
    end

    test "hard deletes the record from DB", %{
      conn: conn,
      checkin: checkin,
      companion: companion,
      scope: scope
    } do
      {:ok, _} = EntryPeople.add_companion(scope, checkin.uri, companion.uri)

      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> delete(
        "/api/entry_people",
        Jason.encode!(%{entry_uri: checkin.uri, person_uri: companion.uri})
      )

      assert Revix.Repo.all(Revix.EntryPeople.EntryPerson) == []
    end

    test "returns error when required params are missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> delete("/api/entry_people", Jason.encode!(%{}))

      assert %{"error" => _} = json_response(conn, 422)
    end
  end
end
