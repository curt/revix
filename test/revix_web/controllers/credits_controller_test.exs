defmodule RevixWeb.CreditsControllerTest do
  use RevixWeb.ConnCase, async: true

  describe "GET /credits" do
    test "renders credits page with version and system info", %{conn: conn} do
      conn = get(conn, ~p"/credits")
      html = html_response(conn, 200)
      assert html =~ "Revix"
      assert html =~ "Elixir"
    end
  end
end
