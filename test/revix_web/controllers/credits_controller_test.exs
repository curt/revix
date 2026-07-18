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
  end
end
