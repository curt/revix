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
end
