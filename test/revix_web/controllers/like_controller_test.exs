defmodule RevixWeb.LikeControllerTest do
  use RevixWeb.ConnCase, async: true

  import Revix.PlacesFixtures
  import Revix.EntriesFixtures

  alias Revix.Likes

  setup do
    place = place_fixture()
    checkin = checkin_fixture(%{place_uri: place.uri})
    %{checkin: checkin}
  end

  describe "POST /api/likes (unauthenticated)" do
    test "redirects to sign in", %{conn: conn, checkin: checkin} do
      conn =
        post(conn, "/api/likes", %{
          object_uri: checkin.uri,
          published_tz: "UTC"
        })

      assert redirected_to(conn) =~ "/people/signin"
    end
  end

  describe "POST /api/likes (authenticated)" do
    setup :register_and_log_in_person

    test "creates a like and returns liked: true with count", %{conn: conn, checkin: checkin} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post("/api/likes", Jason.encode!(%{object_uri: checkin.uri, published_tz: "UTC"}))

      assert %{"liked" => true, "count" => 1} = json_response(conn, 200)
    end

    test "is idempotent when already liked", %{conn: conn, checkin: checkin, scope: scope} do
      {:ok, _} =
        Likes.like_entry(scope, checkin.uri, "UTC")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post("/api/likes", Jason.encode!(%{object_uri: checkin.uri, published_tz: "UTC"}))

      assert %{"liked" => true, "count" => 1} = json_response(conn, 200)
    end

    test "re-likes an object that was previously unliked", %{
      conn: conn,
      checkin: checkin,
      scope: scope
    } do
      {:ok, _} =
        Likes.like_entry(scope, checkin.uri, "UTC")

      {:ok, _} = Likes.unlike_entry(scope, checkin.uri)

      assert Likes.liked_by?(scope.person.uri, checkin.uri) == false

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post("/api/likes", Jason.encode!(%{object_uri: checkin.uri, published_tz: "UTC"}))

      assert %{"liked" => true, "count" => 1} = json_response(conn, 200)
      assert Likes.liked_by?(scope.person.uri, checkin.uri) == true
    end

    test "returns 403 when liking own entry (self-like)", %{
      conn: conn,
      scope: scope
    } do
      place = place_fixture()
      own_checkin = checkin_fixture(%{place_uri: place.uri, author_uri: scope.person.uri})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post("/api/likes", Jason.encode!(%{object_uri: own_checkin.uri, published_tz: "UTC"}))

      assert %{"error" => _} = json_response(conn, 403)
    end

    test "returns error when required params are missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post("/api/likes", Jason.encode!(%{}))

      assert %{"error" => _} = json_response(conn, 422)
    end
  end

  describe "DELETE /api/likes (unauthenticated)" do
    test "redirects to sign in", %{conn: conn, checkin: checkin} do
      conn = delete(conn, "/api/likes", %{object_uri: checkin.uri})
      assert redirected_to(conn) =~ "/people/signin"
    end
  end

  describe "DELETE /api/likes (authenticated)" do
    setup :register_and_log_in_person

    test "unlikes and returns liked: false with count", %{
      conn: conn,
      checkin: checkin,
      scope: scope
    } do
      {:ok, _} =
        Likes.like_entry(scope, checkin.uri, "UTC")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> delete("/api/likes", Jason.encode!(%{object_uri: checkin.uri}))

      assert %{"liked" => false, "count" => 0} = json_response(conn, 200)
      assert Likes.liked_by?(scope.person.uri, checkin.uri) == false
    end

    test "returns error when no active like exists", %{conn: conn, checkin: checkin} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> delete("/api/likes", Jason.encode!(%{object_uri: checkin.uri}))

      assert %{"error" => _} = json_response(conn, 422)
    end

    test "unlike persists unlike_at in DB (soft delete)", %{
      conn: conn,
      checkin: checkin,
      scope: scope
    } do
      {:ok, _} =
        Likes.like_entry(scope, checkin.uri, "UTC")

      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> delete("/api/likes", Jason.encode!(%{object_uri: checkin.uri}))

      # The like record still exists but has unliked_at set
      likes = Revix.Repo.all(Revix.Likes.Like)
      assert [like] = likes
      assert like.unliked_at != nil
    end
  end
end
