defmodule RevixWeb.NodeInfoControllerTest do
  use RevixWeb.ConnCase, async: true

  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures

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
      assert body["services"]["outbound"] == ["atom1.0", "rss2.0"]
      assert body["services"]["inbound"] == []
      assert body["openRegistrations"] == false
    end

    test "returns nodeinfo 2.1 document", %{conn: conn} do
      conn = get(conn, "/nodeinfo/2.1")
      body = json_response(conn, 200)
      assert body["version"] == "2.1"
    end

    test "reports the real software version and repository", %{conn: conn} do
      conn = get(conn, "/nodeinfo/2.1")
      body = json_response(conn, 200)

      assert body["software"]["version"] == to_string(Application.spec(:revix, :vsn))
      refute body["software"]["version"] == "pre-alpha"
      assert body["software"]["repository"] == "https://github.com/curt/revix"
      assert body["software"]["homepage"] =~ "http"
    end

    test "includes required usage counts reflecting local content", %{conn: conn} do
      person = person_fixture()
      place = place_fixture()
      scope = person_scope_fixture(person)
      checkin = checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})
      _post = post_fixture(%{author_uri: person.uri, published_tz: "UTC"})
      _comment = comment_fixture(scope, checkin, %{"content" => "hi"})

      conn = get(conn, "/nodeinfo/2.0")
      body = json_response(conn, 200)

      assert body["usage"]["users"]["total"] >= 1
      assert body["usage"]["localPosts"] >= 2
      assert body["usage"]["localComments"] >= 1
    end

    test "includes metadata with the site name and description", %{conn: conn} do
      {:ok, _site} =
        Revix.Sites.update_site(RevixWeb.CanonicalRoutes.home_url(), %{
          title: "My Journal",
          description: "A cozy corner of the fediverse."
        })

      conn = get(conn, "/nodeinfo/2.1")
      body = json_response(conn, 200)

      assert body["metadata"]["nodeName"] == "My Journal"
      assert body["metadata"]["nodeDescription"] == "A cozy corner of the fediverse."
    end
  end
end
