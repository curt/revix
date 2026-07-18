defmodule RevixWeb.CreditsControllerTest do
  use RevixWeb.ConnCase, async: true

  describe "GET /credits" do
    test "renders credits page with version and system info", %{conn: conn} do
      conn = get(conn, ~p"/credits")
      html = html_response(conn, 200)
      assert html =~ "Revix"
      assert html =~ "Elixir"
    end

    test "sets the page title", %{conn: conn} do
      conn = get(conn, ~p"/credits")
      assert html_response(conn, 200) =~ "Credits · Revix"
    end

    test "sets the meta description", %{conn: conn} do
      conn = get(conn, ~p"/credits")
      response = html_response(conn, 200)
      assert response =~ ~s(name="description")
      assert response =~ "Version and system diagnostics for Revix."
    end

    test "sets x-robots-tag to noindex, follow", %{conn: conn} do
      conn = get(conn, ~p"/credits")
      assert get_resp_header(conn, "x-robots-tag") == ["noindex, follow"]
    end
  end

  describe "GET /credits head links" do
    test "includes a self-referential canonical link", %{conn: conn} do
      conn = get(conn, ~p"/credits")
      response = html_response(conn, 200)
      assert response =~ ~s(rel="canonical")
      assert response =~ ~s(href="#{RevixWeb.CanonicalRoutes.credits_url()}")
    end
  end

  describe "GET /credits OpenGraph" do
    test "includes og:type, og:title, og:description, og:url meta tags", %{conn: conn} do
      conn = get(conn, ~p"/credits")
      response = html_response(conn, 200)

      assert response =~ ~s(property="og:type")
      assert response =~ ~s(property="og:title")
      assert response =~ ~s(content="Credits")
      assert response =~ ~s(property="og:description")
      assert response =~ ~s(content="Version and system diagnostics for Revix.")
      assert response =~ ~s(property="og:url")
      assert response =~ ~s(content="#{RevixWeb.CanonicalRoutes.credits_url()}")
    end
  end

  describe "GET /credits TwitterCard" do
    test "includes twitter:card, twitter:title, twitter:description meta tags", %{conn: conn} do
      conn = get(conn, ~p"/credits")
      response = html_response(conn, 200)

      assert response =~ ~s(name="twitter:card")
      assert response =~ ~s(content="summary")
      assert response =~ ~s(name="twitter:title")
      assert response =~ ~s(content="Credits")
      assert response =~ ~s(name="twitter:description")
      assert response =~ ~s(content="Version and system diagnostics for Revix.")
    end
  end
end
