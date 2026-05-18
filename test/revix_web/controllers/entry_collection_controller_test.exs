defmodule RevixWeb.EntryCollectionControllerTest do
  use RevixWeb.ConnCase

  import Revix.EntriesFixtures
  import Revix.LikesFixtures
  import Revix.PeopleFixtures

  describe "GET /entries/:id/likes" do
    test "returns an OrderedCollection with like_uri items", %{conn: conn} do
      checkin = checkin_fixture()
      like = like_fixture(%{object_uri: checkin.uri})

      conn =
        conn
        |> put_req_header("accept", "application/activity+json")
        |> get("/entries/#{checkin.id}/likes?_format=activity")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/activity+json"

      body = Jason.decode!(conn.resp_body)
      assert body["type"] == "OrderedCollection"
      assert body["totalItems"] == 1
      assert body["orderedItems"] == [like.like_uri]
    end

    test "returns empty OrderedCollection when entry has no likes", %{conn: conn} do
      checkin = checkin_fixture()

      conn =
        conn
        |> put_req_header("accept", "application/activity+json")
        |> get("/entries/#{checkin.id}/likes?_format=activity")

      body = Jason.decode!(conn.resp_body)
      assert body["type"] == "OrderedCollection"
      assert body["totalItems"] == 0
      assert body["orderedItems"] == []
    end

    test "returns 404 for unknown entry id", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/activity+json")
        |> get("/entries/aaaaaaaaaaa/likes?_format=activity")

      assert conn.status == 404
    end
  end

  describe "GET /entries/:id/replies" do
    test "returns an OrderedCollection with reply URIs", %{conn: conn} do
      scope = person_scope_fixture()
      checkin = checkin_fixture()
      comment = comment_fixture(scope, checkin)

      conn =
        conn
        |> put_req_header("accept", "application/activity+json")
        |> get("/entries/#{checkin.id}/replies?_format=activity")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/activity+json"

      body = Jason.decode!(conn.resp_body)
      assert body["type"] == "OrderedCollection"
      assert body["totalItems"] == 1
      assert body["orderedItems"] == [comment.uri]
    end

    test "returns empty OrderedCollection when entry has no replies", %{conn: conn} do
      checkin = checkin_fixture()

      conn =
        conn
        |> put_req_header("accept", "application/activity+json")
        |> get("/entries/#{checkin.id}/replies?_format=activity")

      body = Jason.decode!(conn.resp_body)
      assert body["type"] == "OrderedCollection"
      assert body["totalItems"] == 0
      assert body["orderedItems"] == []
    end

    test "returns 404 for unknown entry id", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "application/activity+json")
        |> get("/entries/aaaaaaaaaaa/replies?_format=activity")

      assert conn.status == 404
    end
  end
end
