defmodule RevixWeb.SitemapControllerTest do
  use RevixWeb.ConnCase, async: true

  import Revix.PlacesFixtures
  import Revix.EntriesFixtures

  describe "GET /sitemap.xml — index" do
    test "returns 200 with XML content type", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")
      assert conn.status == 200
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/xml"
    end

    test "returns XML declaration and sitemapindex root", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")
      body = response(conn, 200)
      assert body =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
      assert body =~ ~s(xmlns="http://www.sitemaps.org/schemas/sitemap/0.9")
      assert body =~ "<sitemapindex"
      assert body =~ "</sitemapindex>"
    end

    test "includes loc for each sub-sitemap", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")
      body = response(conn, 200)
      assert body =~ "/sitemap/places.xml"
      assert body =~ "/sitemap/checkins.xml"
      assert body =~ "/sitemap/posts.xml"
    end

    test "is accessible without authentication", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")
      assert conn.status == 200
    end
  end

  describe "GET /sitemap/places.xml" do
    test "returns 200 with XML content type", %{conn: conn} do
      conn = get(conn, "/sitemap/places.xml")
      assert conn.status == 200
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/xml"
    end

    test "returns XML declaration and urlset root", %{conn: conn} do
      conn = get(conn, "/sitemap/places.xml")
      body = response(conn, 200)
      assert body =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
      assert body =~ "<urlset"
    end

    test "returns no url entries when empty", %{conn: conn} do
      conn = get(conn, "/sitemap/places.xml")
      body = response(conn, 200)
      refute body =~ "<url>"
    end

    test "includes place URL", %{conn: conn} do
      place = place_fixture(%{slug: "coffee-shop"})
      conn = get(conn, "/sitemap/places.xml")
      body = response(conn, 200)
      assert body =~ "<url>"
      assert body =~ "/places/#{place.id}/coffee-shop"
    end

    test "includes lastmod in date-only format", %{conn: conn} do
      _place = place_fixture()
      conn = get(conn, "/sitemap/places.xml")
      body = response(conn, 200)
      assert body =~ ~r/<lastmod>\d{4}-\d{2}-\d{2}<\/lastmod>/
    end

    test "orders places newest first", %{conn: conn} do
      older = place_fixture(%{inserted_at: ~U[2026-01-01 10:00:00Z]})
      newer = place_fixture(%{inserted_at: ~U[2026-06-01 10:00:00Z]})

      conn = get(conn, "/sitemap/places.xml")
      body = response(conn, 200)

      newer_pos = :binary.match(body, "/places/#{newer.id}") |> elem(0)
      older_pos = :binary.match(body, "/places/#{older.id}") |> elem(0)
      assert newer_pos < older_pos
    end
  end

  describe "GET /sitemap/checkins.xml" do
    test "returns 200 with XML content type", %{conn: conn} do
      conn = get(conn, "/sitemap/checkins.xml")
      assert conn.status == 200
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/xml"
    end

    test "returns no url entries when empty", %{conn: conn} do
      conn = get(conn, "/sitemap/checkins.xml")
      body = response(conn, 200)
      refute body =~ "<url>"
    end

    test "includes checkin URL", %{conn: conn} do
      checkin = checkin_fixture()
      conn = get(conn, "/sitemap/checkins.xml")
      body = response(conn, 200)
      assert body =~ "/checkins/#{checkin.id}"
    end

    test "includes lastmod in date-only format", %{conn: conn} do
      _checkin = checkin_fixture()
      conn = get(conn, "/sitemap/checkins.xml")
      body = response(conn, 200)
      assert body =~ ~r/<lastmod>\d{4}-\d{2}-\d{2}<\/lastmod>/
    end

    test "orders checkins newest first", %{conn: conn} do
      older = checkin_fixture(%{starts_at_utc: ~U[2026-01-01 10:00:00Z]})
      newer = checkin_fixture(%{starts_at_utc: ~U[2026-06-01 10:00:00Z]})

      conn = get(conn, "/sitemap/checkins.xml")
      body = response(conn, 200)

      newer_pos = :binary.match(body, "/checkins/#{newer.id}") |> elem(0)
      older_pos = :binary.match(body, "/checkins/#{older.id}") |> elem(0)
      assert newer_pos < older_pos
    end
  end

  describe "GET /sitemap/posts.xml" do
    test "returns 200 with XML content type", %{conn: conn} do
      conn = get(conn, "/sitemap/posts.xml")
      assert conn.status == 200
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/xml"
    end

    test "returns no url entries when empty", %{conn: conn} do
      conn = get(conn, "/sitemap/posts.xml")
      body = response(conn, 200)
      refute body =~ "<url>"
    end

    test "includes post URL", %{conn: conn} do
      post = post_fixture()
      conn = get(conn, "/sitemap/posts.xml")
      body = response(conn, 200)
      assert body =~ "/posts/#{post.id}"
    end

    test "includes lastmod in date-only format", %{conn: conn} do
      _post = post_fixture()
      conn = get(conn, "/sitemap/posts.xml")
      body = response(conn, 200)
      assert body =~ ~r/<lastmod>\d{4}-\d{2}-\d{2}<\/lastmod>/
    end

    test "orders posts newest first", %{conn: conn} do
      older = post_fixture(%{published_at_utc: ~U[2026-02-01 10:00:00Z]})
      newer = post_fixture(%{published_at_utc: ~U[2026-05-01 10:00:00Z]})

      conn = get(conn, "/sitemap/posts.xml")
      body = response(conn, 200)

      newer_pos = :binary.match(body, "/posts/#{newer.id}") |> elem(0)
      older_pos = :binary.match(body, "/posts/#{older.id}") |> elem(0)
      assert newer_pos < older_pos
    end
  end
end
