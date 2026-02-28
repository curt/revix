defmodule RevixWeb.IdenticonControllerTest do
  use RevixWeb.ConnCase, async: true

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  describe "GET /identicon/:id" do
    test "returns PNG with correct content type", %{conn: conn} do
      conn = get(conn, ~p"/identicon/ABcDeFgHiJk")
      assert conn.status == 200
      assert response_content_type(conn, :png) =~ "image/png"
      assert <<@png_signature, _::binary>> = conn.resp_body
    end

    test "sets long-term cache headers", %{conn: conn} do
      conn = get(conn, ~p"/identicon/ABcDeFgHiJk")
      [cache_control] = get_resp_header(conn, "cache-control")
      assert cache_control =~ "public"
      assert cache_control =~ "max-age=31536000"
      assert cache_control =~ "immutable"
    end

    test "sets ETag header", %{conn: conn} do
      conn = get(conn, ~p"/identicon/ABcDeFgHiJk")
      assert [~s("identicon-ABcDeFgHiJk-128")] == get_resp_header(conn, "etag")
    end

    test "returns 304 when ETag matches", %{conn: conn} do
      conn =
        conn
        |> put_req_header("if-none-match", ~s("identicon-ABcDeFgHiJk-128"))
        |> get(~p"/identicon/ABcDeFgHiJk")

      assert conn.status == 304
    end

    test "accepts size query parameter", %{conn: conn} do
      conn = get(conn, "/identicon/ABcDeFgHiJk?size=64")
      assert conn.status == 200
      assert [~s("identicon-ABcDeFgHiJk-64")] == get_resp_header(conn, "etag")
    end

    test "clamps size to maximum 256", %{conn: conn} do
      conn = get(conn, "/identicon/ABcDeFgHiJk?size=512")
      assert [~s("identicon-ABcDeFgHiJk-256")] == get_resp_header(conn, "etag")
    end

    test "returns same image for same identifier", %{conn: conn} do
      conn1 = get(conn, ~p"/identicon/ABcDeFgHiJk")
      conn2 = get(conn, ~p"/identicon/ABcDeFgHiJk")
      assert conn1.resp_body == conn2.resp_body
    end

    test "returns different images for different identifiers", %{conn: conn} do
      conn1 = get(conn, ~p"/identicon/ABcDeFgHiJk")
      conn2 = get(conn, ~p"/identicon/ZyXwVuTsRqP")
      refute conn1.resp_body == conn2.resp_body
    end
  end
end
