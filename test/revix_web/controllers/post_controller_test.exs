defmodule RevixWeb.PostControllerTest do
  use RevixWeb.ConnCase

  import Revix.EntriesFixtures
  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.MediaFixtures

  alias Revix.Likes
  alias Revix.Media

  # ── GET /posts ────────────────────────────────────────────────────────────────

  describe "GET /posts" do
    test "renders posts index", %{conn: conn} do
      post = post_fixture(%{name: "My First Post"})
      conn = get(conn, ~p"/posts")
      assert html_response(conn, 200) =~ post.name
    end

    test "renders empty index when no posts exist", %{conn: conn} do
      conn = get(conn, ~p"/posts")
      assert html_response(conn, 200)
    end

    test "author avatar has an alt attribute", %{conn: conn} do
      author = person_fixture()
      {:ok, author} = Revix.People.update_person_display_name(author, %{display_name: "Iris"})
      post_fixture(%{name: "My First Post", author_uri: author.uri})

      conn = get(conn, ~p"/posts")
      assert html_response(conn, 200) =~ ~s(alt="Iris")
    end

    test "renders post dates", %{conn: conn} do
      post_fixture(%{published_at_local: ~N[2026-05-10 12:00:00]})
      conn = get(conn, ~p"/posts")
      assert html_response(conn, 200) =~ "2026-05-10"
    end

    test "renders like count for liked posts", %{conn: conn} do
      post = post_fixture()
      scope = person_scope_fixture()

      {:ok, _} = Likes.like_entry(scope, post.uri, "UTC", post.uri)

      conn = get(conn, ~p"/posts")
      assert html_response(conn, 200) =~ "hero-heart"
    end

    test "does not render like icon when count is zero", %{conn: conn} do
      post_fixture()
      conn = get(conn, ~p"/posts")
      refute html_response(conn, 200) =~ ~s(hero-heart" class="w-4 h-4 inline)
    end

    test "returns GeoJSON FeatureCollection for geo format", %{conn: conn} do
      place = place_fixture(%{name: "Writing Nook"})
      post = post_fixture()
      {:ok, _} = Revix.EntryPlaces.add_place(post.uri, place.uri)

      conn = get(conn, "/posts?_format=geo")
      response = json_response(conn, 200)
      assert response["type"] == "FeatureCollection"
    end

    test "includes post place as a map feature", %{conn: conn} do
      place = place_fixture(%{name: "Writing Nook"})
      post = post_fixture()
      {:ok, _} = Revix.EntryPlaces.add_place(post.uri, place.uri)

      conn = get(conn, "/posts?_format=geo")
      response = json_response(conn, 200)
      names = Enum.map(response["features"], & &1["properties"]["name"])
      assert "Writing Nook" in names
    end

    test "returns empty features list when posts have no places", %{conn: conn} do
      post_fixture()

      conn = get(conn, "/posts?_format=geo")
      response = json_response(conn, 200)
      assert response["features"] == []
    end

    test "sets the page title", %{conn: conn} do
      conn = get(conn, ~p"/posts")
      assert html_response(conn, 200) =~ "Posts · Revix"
    end

    test "uses the configured site title instead of Revix", %{conn: conn} do
      Revix.Sites.update_site(RevixWeb.CanonicalRoutes.home_url(), %{title: "My Site"})
      conn = get(conn, ~p"/posts")
      assert html_response(conn, 200) =~ "Posts · My Site"
    end

    test "sets the meta description", %{conn: conn} do
      conn = get(conn, ~p"/posts")
      response = html_response(conn, 200)
      assert response =~ ~s(name="description")
      assert response =~ "Posts from the Revix community."
    end

    test "sets x-robots-tag to index, follow", %{conn: conn} do
      conn = get(conn, ~p"/posts")
      assert get_resp_header(conn, "x-robots-tag") == ["index, follow"]
    end

    test "renders an h1", %{conn: conn} do
      post_fixture(%{name: "My First Post"})
      conn = get(conn, ~p"/posts")
      assert html_response(conn, 200) =~ "<h1"
    end
  end

  describe "GET /posts head links" do
    test "includes a self-referential canonical link", %{conn: conn} do
      conn = get(conn, ~p"/posts")
      response = html_response(conn, 200)
      assert response =~ ~s(rel="canonical")
      assert response =~ ~s(href="#{RevixWeb.CanonicalRoutes.posts_index_url()}")
    end
  end

  describe "GET /posts OpenGraph" do
    test "includes og:type, og:title, og:description, og:url meta tags", %{conn: conn} do
      conn = get(conn, ~p"/posts")
      response = html_response(conn, 200)

      assert response =~ ~s(property="og:type")
      assert response =~ ~s(property="og:title")
      assert response =~ ~s(content="Posts")
      assert response =~ ~s(property="og:description")
      assert response =~ ~s(content="Posts from the Revix community.")
      assert response =~ ~s(property="og:url")
      assert response =~ ~s(content="#{RevixWeb.CanonicalRoutes.posts_index_url()}")
    end
  end

  describe "GET /posts TwitterCard" do
    test "includes twitter:card, twitter:title, twitter:description meta tags", %{conn: conn} do
      conn = get(conn, ~p"/posts")
      response = html_response(conn, 200)

      assert response =~ ~s(name="twitter:card")
      assert response =~ ~s(content="summary")
      assert response =~ ~s(name="twitter:title")
      assert response =~ ~s(content="Posts")
      assert response =~ ~s(name="twitter:description")
      assert response =~ ~s(content="Posts from the Revix community.")
    end
  end

  # ── GET /posts/:id ────────────────────────────────────────────────────────────

  describe "GET /posts/:id" do
    test "redirects to canonical dated-slug URL", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Hello World",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, ~p"/posts/#{post.id}")
      assert redirected_to(conn, 301) =~ "/posts/#{post.id}/2026/05/10/hello-world"
    end

    test "redirects to id-slug URL when name is blank", %{conn: conn} do
      post =
        post_fixture(%{
          name: nil,
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, ~p"/posts/#{post.id}")
      assert redirected_to(conn, 301) =~ "/posts/#{post.id}/2026/05/10/#{post.id}"
    end

    test "renders post at canonical URL", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      assert html_response(conn, 200) =~ "My Post"
    end

    test "renders post content", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Content Post",
          content_html: "<p>Hello post world!</p>",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/content-post")
      assert html_response(conn, 200) =~ "Hello post world!"
    end

    test "renders published date and time", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Dated Post",
          published_at_utc: ~U[2026-05-10 14:00:00Z],
          published_at_local: ~N[2026-05-10 10:00:00],
          published_tz: "America/New_York"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/dated-post")
      response = html_response(conn, 200)
      assert response =~ "2026-05-10"
      assert response =~ "10:00 EDT"
    end

    test "redirects when wrong slug", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Right Slug",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/wrong-slug")
      assert redirected_to(conn, 301) =~ "/posts/#{post.id}/2026/05/10/right-slug"
    end

    test "redirects when wrong date", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2025/01/01/my-post")
      assert redirected_to(conn, 301) =~ "/posts/#{post.id}/2026/05/10/my-post"
    end

    test "returns 404 for nonexistent post", %{conn: conn} do
      conn = get(conn, ~p"/posts/11111111111")
      assert conn.status == 404
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/plain"
    end

    test "embeds EntryLikeLive LiveView mount stub", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Like Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/like-post")
      response = html_response(conn, 200)
      assert response =~ "like-section"
      assert response =~ "phx-session"
    end

    test "embeds comment section LiveView mount stub", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Comment Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/comment-post")
      assert html_response(conn, 200) =~ "comment-section"
    end

    test "shows edit link for author when authenticated", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)

      post =
        post_fixture(%{
          name: "Edit Post",
          author_uri: person.uri,
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/edit-post")
      assert html_response(conn, 200) =~ "Edit"
    end

    test "does not show edit link for non-author", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Others Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/others-post")
      refute html_response(conn, 200) =~ ~s(href="/posts/#{post.id}/edit")
    end

    test "includes unencoded BlogPosting JSON-LD in head", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      response = html_response(conn, 200)

      assert response =~ ~s(type="application/ld+json")
      assert response =~ ~s("@type":"BlogPosting")
      assert response =~ ~s("headline":"My Post")
      assert response =~ "2026-05-10"
    end

    test "omits headline from JSON-LD when post has no name", %{conn: conn} do
      post =
        post_fixture(%{
          name: nil,
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/#{post.id}")
      response = html_response(conn, 200)

      assert response =~ ~s(type="application/ld+json")
      assert response =~ ~s("@type":"BlogPosting")
      refute response =~ ~s("headline")
    end
  end

  # ── GET /posts/:id image attachments ─────────────────────────────────────────

  describe "GET /posts/:id image attachments" do
    test "attachment link uses :large version not :original", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Photo Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(post.id, image.id, 0)

      conn = get(conn, "/posts/#{post.id}/2026/05/10/photo-post")
      html = html_response(conn, 200)

      assert html =~ "uploads/images/#{image.id}/large"
      refute html =~ "uploads/images/#{image.id}/original"
    end

    test "renders no width/height attributes when dimensions have not been captured", %{
      conn: conn
    } do
      post =
        post_fixture(%{
          name: "Photo Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(post.id, image.id, 0)

      conn = get(conn, "/posts/#{post.id}/2026/05/10/photo-post")
      html = html_response(conn, 200)

      attachment_img = extract_attachment_img(html)

      refute attachment_img =~ "width="
      refute attachment_img =~ "height="
      refute attachment_img =~ "srcset="
      refute attachment_img =~ "sizes="
    end

    test "renders width/height matching the real captured dimensions", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Photo Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      upload = %Plug.Upload{
        path: "test/support/fixtures/test_large.jpg",
        filename: "photo.jpg",
        content_type: "image/jpeg"
      }

      {:ok, [_image]} = Media.create_and_attach_images(post.id, post.author_uri, [upload])

      conn = get(conn, "/posts/#{post.id}/2026/05/10/photo-post")
      html = html_response(conn, 200)

      attachment_img = extract_attachment_img(html)

      assert attachment_img =~ ~s(width="800")
      assert attachment_img =~ ~s(height="400")
    end

    test "renders srcset/sizes matching the real captured dimensions", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Photo Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      upload = %Plug.Upload{
        path: "test/support/fixtures/test_large.jpg",
        filename: "photo.jpg",
        content_type: "image/jpeg"
      }

      {:ok, [image]} = Media.create_and_attach_images(post.id, post.author_uri, [upload])

      conn = get(conn, "/posts/#{post.id}/2026/05/10/photo-post")
      html = html_response(conn, 200)

      attachment_img = extract_attachment_img(html)

      assert attachment_img =~ "sizes=\"(max-width: 800px) 100vw, 800px\""
      assert attachment_img =~ "uploads/images/#{image.id}/medium.jpg"
      assert attachment_img =~ "800w"
      assert attachment_img =~ "uploads/images/#{image.id}/large.jpg"
      assert attachment_img =~ "1200w"
    end
  end

  defp extract_attachment_img(html) do
    [_, after_figure] = String.split(html, "<figure", parts: 2)
    [_, rest] = String.split(after_figure, "<img", parts: 2)
    [img, _] = String.split(rest, ">", parts: 2)
    img
  end

  # ── GET /posts/:id owner actions ──────────────────────────────────────────────

  describe "GET /posts/:id owner actions" do
    setup :register_and_log_in_person

    test "owner sees re-transform button when post has images", %{conn: conn, person: person} do
      {:ok, _} = Revix.People.set_person_role(person, :owner)

      post =
        post_fixture(%{
          name: "Photo Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(post.id, image.id, 0)

      conn = get(conn, "/posts/#{post.id}/2026/05/10/photo-post")
      assert html_response(conn, 200) =~ "Re-transform photos"
    end

    test "non-owner does not see re-transform button", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Photo Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(post.id, image.id, 0)

      conn = get(conn, "/posts/#{post.id}/2026/05/10/photo-post")
      refute html_response(conn, 200) =~ "Re-transform photos"
    end

    test "owner does not see re-transform button when post has no images", %{
      conn: conn,
      person: person
    } do
      {:ok, _} = Revix.People.set_person_role(person, :owner)

      post =
        post_fixture(%{
          name: "No Photos",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/no-photos")
      refute html_response(conn, 200) =~ "Re-transform photos"
    end
  end

  # ── POST /posts/:id/retransform_images ────────────────────────────────────────

  describe "POST /posts/:id/retransform_images" do
    setup :register_and_log_in_person

    test "owner redirects to post with success flash", %{conn: conn, person: person} do
      {:ok, _} = Revix.People.set_person_role(person, :owner)
      post = post_fixture()

      conn = post(conn, ~p"/posts/#{post.id}/retransform_images")
      assert redirected_to(conn) == ~p"/posts/#{post.id}"
      assert conn.assigns.flash["info"] == "Photos re-transformed."
    end

    test "non-owner is redirected to home with error", %{conn: conn} do
      post = post_fixture()

      conn = post(conn, ~p"/posts/#{post.id}/retransform_images")
      assert redirected_to(conn) == ~p"/"
      assert conn.assigns.flash["error"] == "Not authorized."
    end

    test "owner gets error flash for nonexistent post", %{conn: conn, person: person} do
      {:ok, _} = Revix.People.set_person_role(person, :owner)
      conn = post(conn, ~p"/posts/11111111111/retransform_images")
      assert redirected_to(conn) == ~p"/posts"
      assert conn.assigns.flash["error"] == "Post not found."
    end

    test "owner gets error flash for tombstoned post", %{conn: conn, person: person} do
      {:ok, _} = Revix.People.set_person_role(person, :owner)
      post = post_fixture()
      {:ok, _} = Revix.Entries.tombstone_entry(post)

      conn = post(conn, ~p"/posts/#{post.id}/retransform_images")
      assert redirected_to(conn) == ~p"/posts"
      assert conn.assigns.flash["error"] == "Post has been deleted."
    end
  end

  describe "POST /posts/:id/retransform_images (unauthenticated)" do
    test "redirects to sign-in", %{conn: conn} do
      post = post_fixture()
      conn = post(conn, ~p"/posts/#{post.id}/retransform_images")
      assert redirected_to(conn) =~ "/people/signin"
    end
  end

  # ── GET /posts/:id?_format=geo ────────────────────────────────────────────────

  describe "GET /posts/:id geo format" do
    test "returns GeoJSON FeatureCollection", %{conn: conn} do
      place = place_fixture()

      post =
        post_fixture(%{
          name: "Geo Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      Revix.EntryPlaces.add_place(post.uri, place.uri)

      conn = get(conn, "/posts/#{post.id}?_format=geo")
      body = json_response(conn, 200)
      assert body["type"] == "FeatureCollection"
      assert length(body["features"]) == 1
      feature = hd(body["features"])
      assert feature["properties"]["name"] == place.name
      assert feature["properties"]["focus"] == true
    end

    test "returns empty feature list when post has no places", %{conn: conn} do
      post =
        post_fixture(%{
          name: "No Place Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}?_format=geo")
      body = json_response(conn, 200)
      assert body["type"] == "FeatureCollection"
      assert body["features"] == []
    end

    test "skips canonical redirect for geo requests", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Redirect Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2099/01/01/wrong-slug?_format=geo")
      assert json_response(conn, 200)["type"] == "FeatureCollection"
    end
  end

  # ── GET /posts/:id?_format=activity ──────────────────────────────────────────

  describe "GET /posts/:id activity format" do
    test "returns ActivityStreams Note", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Hello World",
          published_at_utc: ~U[2026-05-10 14:00:00Z],
          published_at_local: ~N[2026-05-10 10:00:00],
          published_tz: "America/New_York"
        })

      conn =
        conn
        |> put_req_header("accept", "application/activity+json")
        |> get("/posts/#{post.id}?_format=activity")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/activity+json"

      body = Jason.decode!(conn.resp_body)
      assert body["type"] == "Note"
      assert body["id"] == post.uri
      assert body["url"] == post.url
      assert body["attributedTo"] == post.author_uri
      assert body["published"] == "2026-05-10T14:00:00Z"
      assert body["name"] == "Hello World"
      assert body["to"] == ["https://www.w3.org/ns/activitystreams#Public"]
      assert body["cc"] == [post.author_uri <> "/followers"]
      refute Map.has_key?(body, "tag")

      assert body["@context"] == [
               "https://www.w3.org/ns/activitystreams",
               %{"schema" => "https://schema.org/", "sameAs" => "schema:sameAs"}
             ]
    end

    test "omits name field when post has no title", %{conn: conn} do
      post = post_fixture(%{name: nil, published_tz: "UTC"})

      conn = get(conn, "/posts/#{post.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      refute Map.has_key?(body, "name")
    end

    test "includes content when post has content", %{conn: conn} do
      post =
        post_fixture(%{
          content: "Some thoughts.",
          content_html: "<p>Some thoughts.</p>",
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      assert body["content"] == "<p>Some thoughts.</p>"
      assert body["mediaType"] == "text/html"
    end

    test "includes location array when post has places", %{conn: conn} do
      place = place_fixture(%{name: "The Library"})
      post = post_fixture(%{published_tz: "UTC"})
      Revix.EntryPlaces.add_place(post.uri, place.uri)

      conn = get(conn, "/posts/#{post.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      assert is_list(body["location"])
      [location] = body["location"]
      assert location["type"] == "Place"
      assert location["id"] == place.uri
      assert location["name"] == place.name
      refute Map.has_key?(location, "sameAs")
    end

    test "location includes sameAs when place has OSM data", %{conn: conn} do
      place = place_fixture(%{name: "The Library", osm_type: :relation, osm_id: 77777})
      post = post_fixture(%{published_tz: "UTC"})
      Revix.EntryPlaces.add_place(post.uri, place.uri)

      conn = get(conn, "/posts/#{post.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      [location] = body["location"]
      assert location["sameAs"] == "https://www.openstreetmap.org/relation/77777"
    end

    test "omits location when post has no places", %{conn: conn} do
      post = post_fixture(%{published_tz: "UTC"})

      conn = get(conn, "/posts/#{post.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      refute Map.has_key?(body, "location")
    end

    test "skips canonical redirect for activity requests", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Activity Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2099/01/01/wrong-slug?_format=activity")
      body = Jason.decode!(conn.resp_body)
      assert body["type"] == "Note"
    end

    test "includes attachment when post has images", %{conn: conn} do
      post = post_fixture()
      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(post.id, image.id, 0)

      conn = get(conn, "/posts/#{post.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      assert [attachment] = body["attachment"]
      assert attachment["type"] == "Document"
      assert attachment["mediaType"] == image.content_type
      assert is_binary(attachment["url"])
    end

    test "omits attachment key when post has no images", %{conn: conn} do
      post = post_fixture()

      conn = get(conn, "/posts/#{post.id}?_format=activity")
      body = Jason.decode!(conn.resp_body)

      refute Map.has_key?(body, "attachment")
    end
  end

  describe "GET /posts/:id tombstoned" do
    test "returns 410 for HTML format", %{conn: conn} do
      post = post_fixture()
      {:ok, _} = Revix.Entries.tombstone_entry(post)

      conn = get(conn, ~p"/posts/#{post.id}")
      assert conn.status == 410
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/plain"
    end

    test "returns 410 for geo format", %{conn: conn} do
      post = post_fixture()
      {:ok, _} = Revix.Entries.tombstone_entry(post)

      conn = get(conn, "/posts/#{post.id}?_format=geo")
      assert conn.status == 410
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    end

    test "returns a Tombstone ActivityStreams object for activity format", %{conn: conn} do
      post = post_fixture()
      {:ok, _} = Revix.Entries.tombstone_entry(post)

      conn =
        conn
        |> put_req_header("accept", "application/activity+json")
        |> get("/posts/#{post.id}?_format=activity")

      assert conn.status == 410
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/activity+json"

      body = Jason.decode!(conn.resp_body)
      assert body["type"] == "Tombstone"
      assert body["id"] == post.uri
      assert body["formerType"] == "Note"
      assert body["deleted"]
    end
  end

  describe "GET /posts/:id head links" do
    test "includes canonical link with dated-slug URL", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      response = html_response(conn, 200)
      assert response =~ ~s(rel="canonical")
      assert response =~ ~s(href="#{RevixWeb.CanonicalRoutes.post_url(post)}")
    end

    test "includes activity+json alternate link with slug-free URI", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      response = html_response(conn, 200)
      assert response =~ ~s(rel="alternate")
      assert response =~ ~s(type="application/activity+json")
      assert response =~ ~s(href="#{RevixWeb.CanonicalRoutes.post_uri(post)}")
    end
  end

  describe "GET /posts/:id OpenGraph" do
    test "includes og:type, og:url meta tags", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      response = html_response(conn, 200)

      assert response =~ ~s(property="og:type")
      assert response =~ ~s(property="og:url")
    end

    test "includes og:title when post has name", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      response = html_response(conn, 200)

      assert response =~ ~s(property="og:title")
      assert response =~ ~s(content="My Post")
    end

    test "includes og:image when post has images", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Image Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(post.id, image.id, 0)

      conn = get(conn, "/posts/#{post.id}/2026/05/10/image-post")
      assert html_response(conn, 200) =~ ~s(property="og:image")
    end

    test "omits og:image when post has no images", %{conn: conn} do
      post =
        post_fixture(%{
          name: "No Image Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/no-image-post")
      refute html_response(conn, 200) =~ ~s(property="og:image")
    end
  end

  describe "GET /posts/:id TwitterCard" do
    test "uses summary_large_image and twitter:image when post has images", %{conn: conn} do
      post =
        post_fixture(%{
          name: "Image Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(post.id, image.id, 0)

      conn = get(conn, "/posts/#{post.id}/2026/05/10/image-post")
      response = html_response(conn, 200)

      assert response =~ ~s(name="twitter:card")
      assert response =~ ~s(content="summary_large_image")
      assert response =~ ~s(name="twitter:image")
    end

    test "uses summary and omits twitter:image when post has no images", %{conn: conn} do
      post =
        post_fixture(%{
          name: "No Image Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/no-image-post")
      response = html_response(conn, 200)

      assert response =~ ~s(name="twitter:card")
      assert response =~ ~s(content="summary")
      refute response =~ ~s(content="summary_large_image")
      refute response =~ ~s(name="twitter:image")
    end
  end

  describe "GET /posts/:id page title" do
    test "sets the page title to the post name", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      assert html_response(conn, 200) =~ "My Post · Revix"
    end

    test "uses the configured site title instead of Revix", %{conn: conn} do
      Revix.Sites.update_site(RevixWeb.CanonicalRoutes.home_url(), %{title: "My Site"})

      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      assert html_response(conn, 200) =~ "My Post · My Site"
    end

    test "falls back to a generic title when the post has no name", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      draft = draft_post_fixture(%{author_uri: person.uri})

      conn = get(conn, "/posts/#{draft.id}")
      assert html_response(conn, 200) =~ "Post · Revix"
    end

    test "renders an h1 even when the post has no name", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      draft = draft_post_fixture(%{author_uri: person.uri})

      conn = get(conn, "/posts/#{draft.id}")
      assert html_response(conn, 200) =~ "<h1"
    end
  end

  describe "GET /posts/:id meta description" do
    test "sets the meta description from post summary", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          summary: "A short trip recap.",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      response = html_response(conn, 200)

      assert response =~ ~s(name="description")
      assert response =~ "A short trip recap."
    end

    test "omits the meta description tag when post has no summary", %{conn: conn} do
      post =
        post_fixture(%{
          name: "No Summary Post",
          summary: nil,
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/no-summary-post")
      refute html_response(conn, 200) =~ ~s(name="description")
    end
  end

  describe "GET /posts/:id robots" do
    test "sets x-robots-tag to index, follow", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      assert get_resp_header(conn, "x-robots-tag") == ["index, follow"]
    end
  end

  describe "GET /posts/:id semantic structure" do
    test "wraps the post's own content in an article element", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      assert html_response(conn, 200) =~ "<article"
    end
  end

  describe "GET /posts/:id microformats" do
    test "root element has h-entry class", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      assert html_response(conn, 200) =~ ~s(class="mx-auto max-w-7xl h-entry")
    end

    test "u-uid link contains post uri", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      response = html_response(conn, 200)
      assert response =~ ~s(class="u-uid")
      assert response =~ post.uri
    end

    test "post title has p-name class", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      assert html_response(conn, 200) =~ ~s(p-name)
    end

    test "dt-published time element contains ISO 8601 UTC datetime", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          published_at_utc: ~U[2026-05-10 14:00:00Z],
          published_at_local: ~N[2026-05-10 10:00:00],
          published_tz: "America/New_York"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      response = html_response(conn, 200)
      assert response =~ ~s(class="dt-published")
      assert response =~ ~s(datetime="2026-05-10T14:00:00Z")
    end

    test "author block has p-author h-card classes", %{conn: conn} do
      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      assert html_response(conn, 200) =~ ~s(class="p-author h-card")
    end

    test "place links have p-location class", %{conn: conn} do
      place = place_fixture(%{name: "The Library"})

      post =
        post_fixture(%{
          name: "My Post",
          published_at_local: ~N[2026-05-10 12:00:00],
          published_tz: "UTC"
        })

      Revix.EntryPlaces.add_place(post.uri, place.uri)

      conn = get(conn, "/posts/#{post.id}/2026/05/10/my-post")
      assert html_response(conn, 200) =~ ~s(class="p-location")
    end
  end

  # ── Draft post access ────────────────────────────────────────────────────────

  describe "draft post visibility" do
    test "GET /posts does not show drafts to anonymous visitors", %{conn: conn} do
      person = person_fixture()
      _draft = draft_post_fixture(%{author_uri: person.uri, name: "Secret Draft"})

      conn = get(conn, "/posts")
      refute html_response(conn, 200) =~ "Secret Draft"
    end

    test "GET /posts shows drafts to the author", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      _draft = draft_post_fixture(%{author_uri: person.uri, name: "My Draft"})

      conn = get(conn, "/posts")
      html = html_response(conn, 200)
      assert html =~ "My Draft"
      assert html =~ "Draft"
    end

    test "GET /posts does not show another person's drafts", %{conn: conn} do
      author = person_fixture()
      viewer = person_fixture()
      conn = log_in_person(conn, viewer)
      _draft = draft_post_fixture(%{author_uri: author.uri, name: "Hidden Draft"})

      conn = get(conn, "/posts")
      refute html_response(conn, 200) =~ "Hidden Draft"
    end

    test "GET /posts/:id for draft returns 404 to anonymous", %{conn: conn} do
      person = person_fixture()
      draft = draft_post_fixture(%{author_uri: person.uri})
      conn = get(conn, "/posts/#{draft.id}")
      assert conn.status == 404
    end

    test "GET /posts/:id for draft renders for the author", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      draft = draft_post_fixture(%{author_uri: person.uri})

      conn = get(conn, "/posts/#{draft.id}")
      assert html_response(conn, 200)
    end

    test "GET /posts/:id for draft returns 404 to a different logged-in person", %{conn: conn} do
      author = person_fixture()
      viewer = person_fixture()
      conn = log_in_person(conn, viewer)
      draft = draft_post_fixture(%{author_uri: author.uri})
      conn = get(conn, "/posts/#{draft.id}")
      assert conn.status == 404
    end
  end
end
