defmodule RevixWeb.NodeInfoControllerTest do
  use RevixWeb.ConnCase, async: true

  describe "GET /.well-known/nodeinfo" do
    test "returns links for both 2.0 and 2.1", %{conn: conn} do
      conn = get(conn, "/.well-known/nodeinfo")
      assert %{"links" => links} = json_response(conn, 200)
      versions = Enum.map(links, & &1["rel"])
      assert "http://nodeinfo.diaspora.software/ns/schema/2.0" in versions
      assert "http://nodeinfo.diaspora.software/ns/schema/2.1" in versions
    end
  end

  describe "GET /nodeinfo/:version" do
    test "returns nodeinfo 2.0 document", %{conn: conn} do
      conn = get(conn, "/nodeinfo/2.0")
      body = json_response(conn, 200)
      assert body["version"] == "2.0"
      assert body["software"]["name"] == "Revix"
      assert "activitypub" in body["protocols"]
    end

    test "returns nodeinfo 2.1 document", %{conn: conn} do
      conn = get(conn, "/nodeinfo/2.1")
      body = json_response(conn, 200)
      assert body["version"] == "2.1"
    end
  end
end
