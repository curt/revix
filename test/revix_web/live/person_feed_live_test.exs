defmodule RevixWeb.PersonFeedLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures
  import Revix.LikesFixtures

  alias Revix.Entries
  alias Revix.Likes
  alias Revix.Repo

  defp set_username(person, username) do
    person
    |> Ecto.Changeset.change(username: username)
    |> Repo.update!()
  end

  defp create_comment(scope, checkin, attrs) do
    uri_fn = fn id -> "https://example.com/notes/#{id}" end

    {:ok, comment} =
      Entries.create_comment(
        scope,
        checkin,
        Map.merge(%{"published_tz" => "UTC"}, attrs),
        uri_fn,
        uri_fn
      )

    comment
  end

  defp create_reply(scope, comment, attrs) do
    uri_fn = fn id -> "https://example.com/notes/#{id}" end

    {:ok, reply} =
      Entries.create_reply(
        scope,
        comment,
        Map.merge(%{"published_tz" => "UTC"}, attrs),
        uri_fn,
        uri_fn
      )

    reply
  end

  # ── Basic rendering ───────────────────────────────────────────────────────

  describe "GET /people/:id" do
    test "renders the person page", %{conn: conn} do
      person = person_fixture()
      conn = get(conn, ~p"/people/#{person.id}")
      assert html_response(conn, 200)
    end

    test "redirects to /@username when person has a username", %{conn: conn} do
      person = person_fixture() |> set_username("alice")
      conn = get(conn, ~p"/people/#{person.id}")
      assert redirected_to(conn) == "/@alice"
    end

    test "returns 404 for unknown person id", %{conn: conn} do
      nonexistent_id = Revix.Ecto.Base58Id.autogenerate()
      conn = get(conn, ~p"/people/#{nonexistent_id}")
      assert conn.status == 404
    end

    test "displays person display name", %{conn: conn} do
      person = person_fixture()
      {:ok, person} = Revix.People.update_person_display_name(person, %{display_name: "Diana"})
      _person = set_username(person, "diana")

      conn = get(conn, "/@diana")
      assert html_response(conn, 200) =~ "Diana"
    end
  end

  # ── Person activity ───────────────────────────────────────────────────────

  describe "person activity" do
    setup do
      person = person_fixture()
      place = place_fixture(%{name: "The Venue"})
      %{person: person, place: place}
    end

    test "displays the person's checkins", %{conn: conn, person: person, place: place} do
      checkin_fixture(%{author_uri: person.uri, place_uri: place.uri})

      conn = get(conn, ~p"/people/#{person.id}")
      response = html_response(conn, 200)
      assert response =~ "checked into"
      assert response =~ place.name
    end

    test "displays the person's posts", %{conn: conn, person: person} do
      post = post_fixture(%{author_uri: person.uri, name: "My Travel Post"})

      conn = get(conn, ~p"/people/#{person.id}")
      response = html_response(conn, 200)
      assert response =~ "posted"
      assert response =~ post.name
    end

    test "displays the person's likes", %{conn: conn, person: person, place: place} do
      checkin = checkin_fixture(%{place_uri: place.uri})
      like_fixture(%{author_uri: person.uri, object_uri: checkin.uri})

      conn = get(conn, ~p"/people/#{person.id}")
      response = html_response(conn, 200)
      assert response =~ "liked"
      assert response =~ place.name
    end

    test "does not display comments for unauthenticated visitors", %{
      conn: conn,
      person: person,
      place: place
    } do
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = Revix.People.Scope.for_person(person)
      create_comment(scope, checkin, %{"content" => "Great spot!"})

      conn = get(conn, ~p"/people/#{person.id}")
      refute html_response(conn, 200) =~ "commented on"
    end

    test "does not display other people's activity", %{conn: conn, person: person, place: place} do
      other_person = person_fixture()
      checkin_fixture(%{author_uri: other_person.uri, place_uri: place.uri})

      conn = get(conn, ~p"/people/#{person.id}")
      refute html_response(conn, 200) =~ "checked into"
    end

    test "groups the person's likes on the same object into one row", %{
      conn: conn,
      person: person,
      place: place
    } do
      checkin = checkin_fixture(%{place_uri: place.uri})
      person2 = person_fixture()
      like_fixture(%{author_uri: person.uri, object_uri: checkin.uri})
      like_fixture(%{author_uri: person2.uri, object_uri: checkin.uri})

      # Only 1 like is by the person under view; it should appear as a single like row
      conn = get(conn, ~p"/people/#{person.id}")
      html = html_response(conn, 200)
      assert html =~ "hero-heart-solid"
      like_count = html |> String.split("hero-heart-solid") |> length() |> Kernel.-(1)
      assert like_count == 1
    end

    test "shows each of the person's comments on the same checkin as its own row (authenticated)",
         %{
           conn: conn,
           person: person,
           place: place
         } do
      checkin1 = checkin_fixture(%{place_uri: place.uri})
      checkin2 = checkin_fixture(%{place_uri: place.uri})
      scope = Revix.People.Scope.for_person(person)
      create_comment(scope, checkin1, %{"content" => "First on checkin1"})
      create_comment(scope, checkin1, %{"content" => "Second on checkin1"})
      create_comment(scope, checkin2, %{"content" => "Only on checkin2"})

      conn = log_in_person(conn, person)
      conn = get(conn, ~p"/people/#{person.id}")
      html = html_response(conn, 200)
      comment_count = html |> String.split("commented on") |> length() |> Kernel.-(1)
      assert comment_count == 3
    end

    test "authenticated viewer sees comment link to checkin target", %{
      conn: conn,
      person: person,
      place: place
    } do
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = Revix.People.Scope.for_person(person)
      comment = create_comment(scope, checkin, %{"content" => "Checkin comment"})

      conn = log_in_person(conn, person_fixture())
      conn = get(conn, ~p"/people/#{person.id}")
      html = html_response(conn, 200)

      assert html =~ "commented on"
      assert html =~ place.name
      assert html =~ ~s(href="#{checkin.url}#comment-#{comment.id}")
    end

    test "authenticated viewer sees comment link to post target", %{conn: conn, person: person} do
      post = post_fixture(%{author_uri: person_fixture().uri, name: "Person Feed Post"})
      scope = Revix.People.Scope.for_person(person)
      comment = create_comment(scope, post, %{"content" => "Post comment"})

      conn = log_in_person(conn, person_fixture())
      conn = get(conn, ~p"/people/#{person.id}")
      html = html_response(conn, 200)

      assert html =~ "commented on"
      assert html =~ "Person Feed Post"
      assert html =~ ~s(href="#{post.url}#comment-#{comment.id}")
    end
  end

  # ── Reply visibility ──────────────────────────────────────────────────────

  describe "reply visibility on person page" do
    setup do
      person = person_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope = Revix.People.Scope.for_person(person)
      %{person: person, checkin: checkin, scope: scope}
    end

    test "hides all comments and replies from unauthenticated visitors", %{
      conn: conn,
      person: person,
      checkin: checkin,
      scope: scope
    } do
      comment = create_comment(scope, checkin, %{"content" => "Top comment"})
      _reply = create_reply(scope, comment, %{"content" => "A reply"})

      conn = get(conn, ~p"/people/#{person.id}")
      html = html_response(conn, 200)
      refute html =~ "commented on"
      refute html =~ "replied to"
    end

    test "shows a reply alongside its parent comment as separate rows when viewing own profile",
         %{
           conn: conn,
           person: person,
           checkin: checkin,
           scope: scope
         } do
      comment = create_comment(scope, checkin, %{"content" => "Top comment"})
      _reply = create_reply(scope, comment, %{"content" => "A reply"})

      conn = log_in_person(conn, person)
      conn = get(conn, ~p"/people/#{person.id}")
      html = html_response(conn, 200)
      assert html =~ "commented on"
      refute html =~ "replied to"
      comment_count = html |> String.split("commented on") |> length() |> Kernel.-(1)
      assert comment_count == 2
    end
  end

  # ── ActivityPub & GeoJSON ─────────────────────────────────────────────────

  describe "mount when person not found" do
    test "redirects to / for an unknown person_id via live mount", %{conn: conn} do
      viewer = person_fixture()
      token = Revix.People.generate_person_session_token(viewer)
      nonexistent_id = Revix.Ecto.Base58Id.autogenerate()

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live_isolated(conn, RevixWeb.PersonFeedLive,
                 session: %{"person_id" => nonexistent_id, "person_token" => token}
               )
    end
  end

  describe "GET /people/:id ActivityPub format" do
    test "includes icon with Image type and url", %{conn: conn} do
      person = person_fixture()

      conn = get(conn, "/people/#{person.id}?_format=activity")
      response = json_response(conn, 200)

      assert %{"type" => "Image", "mediaType" => "image/png", "url" => url} = response["icon"]
      assert String.starts_with?(url, "http")
    end
  end

  describe "GET /people/:id GeoJSON format" do
    test "returns GeoJSON for geo format", %{conn: conn} do
      person = person_fixture()

      conn = get(conn, "/people/#{person.id}?_format=geo")
      response = json_response(conn, 200)
      assert response["type"] == "FeatureCollection"
    end
  end

  # ── Live updates ──────────────────────────────────────────────────────────

  describe "live updates on person page" do
    test "prepends new checkin by the person after broadcast", %{conn: conn} do
      person = person_fixture()
      scope = Revix.People.Scope.for_person(person)

      conn = log_in_person(conn, person)
      {:ok, lv, _html} = live(conn, ~p"/people/#{person.id}")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)

      place = place_fixture(%{name: "Live Update Place"})
      uri_fn = fn id -> "https://example.com/checkins/#{id}" end
      url_fn = fn id, _slug -> "https://example.com/checkins/#{id}" end

      {:ok, _checkin} =
        Entries.create_local_checkin(
          scope,
          place,
          %{
            "starts_tz" => "UTC",
            "starts_at_local" =>
              NaiveDateTime.utc_now()
              |> NaiveDateTime.truncate(:second)
              |> NaiveDateTime.to_iso8601()
          },
          uri_fn,
          url_fn
        )

      render(lv)
      html = render(lv)
      assert html =~ "Live Update Place"
    end

    test "does not prepend checkins by other people", %{conn: conn} do
      person = person_fixture()
      other_scope = person_scope_fixture()

      conn = log_in_person(conn, person)
      {:ok, lv, _html} = live(conn, ~p"/people/#{person.id}")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)

      place = place_fixture(%{name: "Other Person Place"})
      uri_fn = fn id -> "https://example.com/checkins/#{id}" end
      url_fn = fn id, _slug -> "https://example.com/checkins/#{id}" end

      {:ok, _checkin} =
        Entries.create_local_checkin(
          other_scope,
          place,
          %{
            "starts_tz" => "UTC",
            "starts_at_local" =>
              NaiveDateTime.utc_now()
              |> NaiveDateTime.truncate(:second)
              |> NaiveDateTime.to_iso8601()
          },
          uri_fn,
          url_fn
        )

      render(lv)
      html = render(lv)
      refute html =~ "Other Person Place"
    end

    test "authenticated: new like by person updates the feed", %{conn: conn} do
      person = person_fixture()
      scope = Revix.People.Scope.for_person(person)
      place = place_fixture(%{name: "Liked Place"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      conn = log_in_person(conn, person)
      {:ok, lv, html} = live(conn, ~p"/people/#{person.id}")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)

      refute html =~ "hero-heart-solid"

      {:ok, _like} = Likes.like_entry(scope, checkin.uri, "UTC")
      render(lv)

      html = render(lv)
      assert html =~ "hero-heart-solid"
    end

    test "prepends new post by the viewed person after broadcast", %{conn: conn} do
      person = person_fixture()
      scope = Revix.People.Scope.for_person(person)
      conn = log_in_person(conn, person)
      {:ok, lv, _html} = live(conn, ~p"/people/#{person.id}")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)

      uri_fn = fn id -> "https://example.com/posts/#{id}" end
      url_fn = fn %{id: id} -> "https://example.com/posts/#{id}" end

      {:ok, _post} =
        Entries.create_local_post(
          scope,
          %{"published_tz" => "UTC", "content" => "My new post"},
          uri_fn,
          url_fn
        )

      render(lv)
      assert render(lv) =~ "posted"
    end

    test "does not prepend a post by a different person", %{conn: conn} do
      person = person_fixture()
      other_scope = person_scope_fixture()
      conn = log_in_person(conn, person)
      {:ok, lv, _html} = live(conn, ~p"/people/#{person.id}")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)

      uri_fn = fn id -> "https://example.com/posts/#{id}" end
      url_fn = fn %{id: id} -> "https://example.com/posts/#{id}" end

      {:ok, _post} =
        Entries.create_local_post(
          other_scope,
          %{"published_tz" => "UTC", "content" => "Other person post"},
          uri_fn,
          url_fn
        )

      render(lv)
      refute render(lv) =~ "Other person post"
    end

    test "ignores unknown messages without crashing", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      {:ok, lv, _html} = live(conn, ~p"/people/#{person.id}")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)
      html_before = render(lv)
      send(lv.pid, {:unexpected_msg, "data"})
      assert render(lv) == html_before
    end

    test "authenticated: person's second comment on same checkin appears as a second row",
         %{conn: conn} do
      person = person_fixture()
      scope = Revix.People.Scope.for_person(person)
      place = place_fixture(%{name: "Comment Group Place"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, _c1} =
        Entries.create_comment(
          scope,
          checkin,
          %{"published_tz" => "UTC", "content" => "First"},
          uri_fn,
          uri_fn
        )

      conn = log_in_person(conn, person)
      {:ok, lv, html} = live(conn, ~p"/people/#{person.id}")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)

      assert html =~ "commented on"
      comment_count_before = html |> String.split("commented on") |> length() |> Kernel.-(1)
      assert comment_count_before == 1

      {:ok, _c2} =
        Entries.create_comment(
          scope,
          checkin,
          %{"published_tz" => "UTC", "content" => "Second"},
          uri_fn,
          uri_fn
        )

      render(lv)

      html = render(lv)
      comment_count = html |> String.split("commented on") |> length() |> Kernel.-(1)
      assert comment_count == 2
    end
  end

  # ── Infinite scroll (load_more) — authenticated only ──────────────────────

  describe "load_more" do
    setup do
      Application.put_env(:revix, :home, activity_limit: 2)
      on_exit(fn -> Application.put_env(:revix, :home, activity_limit: 50) end)
      :ok
    end

    defp checkin_at(person, place, offset_seconds) do
      time = DateTime.add(DateTime.utc_now(:second), offset_seconds, :second)

      checkin_fixture(%{
        author_uri: person.uri,
        place_uri: place.uri,
        starts_at_utc: time,
        published_at_utc: time
      })
    end

    test "shows the sentinel when more activities exist beyond the first page", %{conn: conn} do
      person = person_fixture()
      place = place_fixture()
      for i <- 1..3, do: checkin_at(person, place, -i)

      conn = log_in_person(conn, person)
      {:ok, _lv, html} = live(conn, ~p"/people/#{person.id}")
      assert html =~ "activity-feed-sentinel"
    end

    test "hides the sentinel when no more activities exist", %{conn: conn} do
      person = person_fixture()
      place = place_fixture()
      checkin_at(person, place, -1)

      conn = log_in_person(conn, person)
      {:ok, _lv, html} = live(conn, ~p"/people/#{person.id}")
      refute html =~ "activity-feed-sentinel"
    end

    test "load_more appends the next page and updates has_more", %{conn: conn} do
      person = person_fixture()
      place = place_fixture()
      [c1, _c2, _c3] = for i <- 3..1//-1, do: checkin_at(person, place, -i)

      conn = log_in_person(conn, person)
      {:ok, lv, html} = live(conn, ~p"/people/#{person.id}")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)

      refute html =~ c1.url
      assert html =~ "activity-feed-sentinel"

      html_after = render_hook(lv, "load_more", %{})

      assert html_after =~ c1.url
      refute html_after =~ "activity-feed-sentinel"
    end
  end
end
