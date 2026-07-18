defmodule RevixWeb.RobotsControllerTest do
  use RevixWeb.ConnCase, async: true

  describe "GET /robots.txt" do
    test "returns 200 with text/plain content type", %{conn: conn} do
      conn = get(conn, "/robots.txt")
      assert conn.status == 200
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "text/plain"
    end

    test "allows all crawlers", %{conn: conn} do
      conn = get(conn, "/robots.txt")
      body = response(conn, 200)
      assert body =~ "User-agent: *"
      assert body =~ "Allow: /"
    end

    test "includes an absolute Sitemap directive", %{conn: conn} do
      conn = get(conn, "/robots.txt")
      body = response(conn, 200)
      assert body =~ "Sitemap: #{RevixWeb.Endpoint.url()}/sitemap.xml"
    end

    test "is accessible without authentication", %{conn: conn} do
      conn = get(conn, "/robots.txt")
      assert conn.status == 200
    end
  end
end
