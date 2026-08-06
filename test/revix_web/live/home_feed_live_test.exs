defmodule RevixWeb.HomeFeedLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures
  import Revix.LikesFixtures

  alias Revix.Entries
  alias Revix.Likes

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

  # ── Initial render (unauthenticated — static HTML via PageController) ──────

  describe "unauthenticated initial render" do
    test "renders home page", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Revix"
    end

    test "renders empty feed with no activity", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200)
    end

    test "displays checkin with place name and verb", %{conn: conn} do
      place = place_fixture(%{name: "Disneyland"})
      checkin_fixture(%{place_uri: place.uri})

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      assert html =~ "Disneyland"
      assert html =~ "checked into"
    end

    test "displays checkin author display name", %{conn: conn} do
      person = person_fixture()
      {:ok, person} = Revix.People.update_person_display_name(person, %{display_name: "Alice"})
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Alice"
    end

    test "displays checkin date and timezone abbreviation", %{conn: conn} do
      place = place_fixture()

      checkin_fixture(%{
        place_uri: place.uri,
        starts_at_utc: ~U[2026-02-16 18:37:00Z],
        starts_at_local: ~N[2026-02-16 10:37:00],
        starts_tz: "America/Los_Angeles"
      })

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      assert html =~ "2026-02-16"
      assert html =~ "10:37 PST"
    end

    test "links to author profile from checkin", %{conn: conn} do
      person = person_fixture()
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ ~s(href="http://localhost:4000/people/#{person.id}")
    end

    test "links to the checkin URL", %{conn: conn} do
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri, url: "http://example.com/123"})

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "http://example.com/123"
    end

    test "shows 'somewhere' when checkin has no place", %{conn: conn} do
      checkin_fixture(%{place_uri: "https://example.com/places/nonexistent"})

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "somewhere"
    end

    test "still shows checkin when author is unresolvable", %{conn: conn} do
      place = place_fixture(%{name: "Ghost Place"})
      checkin_fixture(%{place_uri: place.uri, author_uri: "https://example.com/people/ghost"})

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      assert html =~ "checked into"
      assert html =~ "Ghost Place"
    end

    test "hides comments from unauthenticated visitors", %{conn: conn} do
      scope = Revix.People.Scope.for_person(person_fixture())
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      create_comment(scope, checkin, %{"content" => "Nice spot!"})

      conn = get(conn, ~p"/")
      refute html_response(conn, 200) =~ "commented on"
    end

    test "hides likes on notes from unauthenticated visitors", %{conn: conn} do
      scope = Revix.People.Scope.for_person(person_fixture())
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "Nice spot!"})
      like_fixture(%{object_uri: comment.uri})

      conn = get(conn, ~p"/")
      refute html_response(conn, 200) =~ "hero-heart-solid"
    end
  end

  # ── Like activity (unauthenticated static) ────────────────────────────────

  describe "unauthenticated like activity" do
    setup do
      place = place_fixture(%{name: "The Coffee Shop"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      %{place: place, checkin: checkin}
    end

    test "displays like verb and heart icon", %{conn: conn, checkin: checkin} do
      like_fixture(%{object_uri: checkin.uri})

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      assert html =~ "liked"
      assert html =~ "hero-heart-solid"
    end

    test "displays liked place name when object resolves to a checkin with a place", %{
      conn: conn,
      checkin: checkin,
      place: place
    } do
      like_fixture(%{object_uri: checkin.uri})

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ place.name
    end

    test "shows 'a checkin' when liked object has no resolvable place", %{conn: conn} do
      like_fixture(%{object_uri: "https://example.com/entries/nonexistent"})

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "a checkin"
    end

    test "shows two likes on the same checkin as two separate rows", %{
      conn: conn,
      checkin: checkin
    } do
      person1 = person_fixture()
      person2 = person_fixture()
      like_fixture(%{author_uri: person1.uri, object_uri: checkin.uri})
      like_fixture(%{author_uri: person2.uri, object_uri: checkin.uri})

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      like_count = html |> String.split("hero-heart-solid") |> length() |> Kernel.-(1)
      assert like_count == 2
    end

    test "hides remote likes from unauthenticated visitors", %{conn: conn, checkin: checkin} do
      {:ok, _like} =
        Likes.upsert_inbound_like(%{
          author_uri: "https://remote.example/users/alice",
          object_uri: checkin.uri,
          like_uri: "https://remote.example/likes/1"
        })

      conn = get(conn, ~p"/")
      refute html_response(conn, 200) =~ "hero-heart-solid"
    end

    test "displays like date and timezone", %{conn: conn, checkin: checkin} do
      like_fixture(%{object_uri: checkin.uri, published_tz: "America/New_York"})

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      assert html =~ ~r/\d{4}-\d{2}-\d{2}/
      assert html =~ ~r/E[SD]T/
    end
  end

  # ── Authenticated initial render (LiveView) ───────────────────────────────

  describe "authenticated initial render" do
    test "renders home page via LiveView", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Revix"
    end

    test "sets page_title and meta_description from site settings", %{conn: conn} do
      Revix.Sites.update_site(RevixWeb.CanonicalRoutes.home_url(), %{
        title: "Authed Title",
        description: "Authed description"
      })

      person = person_fixture()
      conn = log_in_person(conn, person)
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "<title"
      assert html =~ "Authed Title"
      assert html =~ "Authed description"
    end

    test "shows remote likes to authenticated users", %{conn: conn} do
      person = person_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, _like} =
        Likes.upsert_inbound_like(%{
          author_uri: "https://remote.example/users/alice",
          object_uri: checkin.uri,
          like_uri: "https://remote.example/likes/2"
        })

      conn = log_in_person(conn, person)
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "hero-heart-solid"
    end

    test "shows comments to authenticated users", %{conn: conn} do
      person = person_fixture()
      scope = Revix.People.Scope.for_person(person_fixture())
      place = place_fixture(%{name: "The Diner"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "Nice spot!"})

      conn = log_in_person(conn, person)
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "commented on"
      assert html =~ place.name
      assert html =~ ~s(href="#{checkin.url}#comment-#{comment.id}")
    end

    test "shows post comment target link to authenticated users", %{conn: conn} do
      person = person_fixture()
      commenter_scope = Revix.People.Scope.for_person(person_fixture())
      post = post_fixture(%{name: "Feed Post Title"})

      comment =
        create_comment(commenter_scope, post, %{
          "content" => "Great post!"
        })

      conn = log_in_person(conn, person)
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "commented on"
      assert html =~ "Feed Post Title"
      assert html =~ ~s(href="#{post.url}#comment-#{comment.id}")
    end

    test "shows likes on comments to authenticated users linking to the comment", %{conn: conn} do
      person = person_fixture()
      scope = Revix.People.Scope.for_person(person_fixture())
      place = place_fixture(%{name: "Comment Root Place"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "Nice!"})
      like_fixture(%{object_uri: comment.uri})

      conn = log_in_person(conn, person)
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "liked"
      assert html =~ "a comment"
      assert html =~ ~s(href="#{comment.url}")
    end

    test "shows two comments on same checkin as two separate rows", %{conn: conn} do
      person = person_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      scope2 = Revix.People.Scope.for_person(person_fixture())
      scope3 = Revix.People.Scope.for_person(person_fixture())
      create_comment(scope2, checkin, %{"content" => "First"})
      create_comment(scope3, checkin, %{"content" => "Second"})

      conn = log_in_person(conn, person)
      {:ok, _lv, html} = live(conn, ~p"/")
      comment_count = html |> String.split("commented on") |> length() |> Kernel.-(1)
      assert comment_count == 2
    end

    test "shows a reply alongside its parent comment as separate rows", %{conn: conn} do
      person = person_fixture()
      other_person = person_fixture()
      scope_other = Revix.People.Scope.for_person(other_person)
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      comment =
        create_comment(Revix.People.Scope.for_person(person), checkin, %{
          "content" => "Top comment"
        })

      _reply = create_reply(scope_other, comment, %{"content" => "A reply"})

      conn = log_in_person(conn, person)
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "commented on"
      refute html =~ "replied to"
      comment_count = html |> String.split("commented on") |> length() |> Kernel.-(1)
      assert comment_count == 2
    end
  end

  # ── Live updates (PubSub) — authenticated only ───────────────────────────

  describe "live updates" do
    test "prepends new checkin after broadcast", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      {:ok, lv, _html} = live(conn, ~p"/")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)

      scope = person_scope_fixture()
      place = place_fixture(%{name: "New Place"})
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
      assert html =~ "New Place"
    end

    test "authenticated: new like on same checkin appears as a second row", %{conn: conn} do
      person = person_fixture()
      person2 = person_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      scope1 = Revix.People.Scope.for_person(person)
      {:ok, _like1} = Likes.like_entry(scope1, checkin.uri, "UTC")

      conn = log_in_person(conn, person)
      {:ok, lv, html} = live(conn, ~p"/")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)

      like_count_before = html |> String.split("hero-heart-solid") |> length() |> Kernel.-(1)
      assert like_count_before == 1

      scope2 = Revix.People.Scope.for_person(person2)
      {:ok, _like2} = Likes.like_entry(scope2, checkin.uri, "UTC")
      render(lv)

      html = render(lv)
      like_count = html |> String.split("hero-heart-solid") |> length() |> Kernel.-(1)
      assert like_count == 2
    end

    test "prepends new post after broadcast", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      {:ok, lv, _html} = live(conn, ~p"/")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)

      scope = Revix.People.Scope.for_person(person)
      uri_fn = fn id -> "https://example.com/posts/#{id}" end
      url_fn = fn %{id: id} -> "https://example.com/posts/#{id}" end

      {:ok, _post} =
        Entries.create_local_post(
          scope,
          %{"published_tz" => "UTC", "content" => "Fresh post content"},
          uri_fn,
          url_fn
        )

      render(lv)
      assert render(lv) =~ "posted"
    end

    test "ignores unknown messages without crashing", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      {:ok, lv, _html} = live(conn, ~p"/")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)
      html_before = render(lv)
      send(lv.pid, {:unknown_event, "ignored"})
      assert render(lv) == html_before
    end

    test "does not change feed when like was unliked before handle_info fetch", %{conn: conn} do
      person = person_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      conn = log_in_person(conn, person)
      {:ok, lv, _html} = live(conn, ~p"/")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)

      scope = Revix.People.Scope.for_person(person)
      {:ok, like} = Likes.like_entry(scope, checkin.uri, "UTC")
      {:ok, _} = Likes.unlike_entry(scope, checkin.uri)

      render(lv)

      html_before = render(lv)
      send(lv.pid, {:like_created, like})
      assert render(lv) == html_before
    end

    test "authenticated: second comment on same checkin appears as a second row", %{conn: conn} do
      person = person_fixture()
      person2 = person_fixture()
      place = place_fixture(%{name: "Comment Merge Place"})
      checkin = checkin_fixture(%{place_uri: place.uri})

      scope1 = Revix.People.Scope.for_person(person)
      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, _c1} =
        Entries.create_comment(
          scope1,
          checkin,
          %{"published_tz" => "UTC", "content" => "First"},
          uri_fn,
          uri_fn
        )

      conn = log_in_person(conn, person)
      {:ok, lv, html} = live(conn, ~p"/")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)

      assert html =~ "commented on"

      scope2 = Revix.People.Scope.for_person(person2)

      {:ok, _c2} =
        Entries.create_comment(
          scope2,
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

    defp checkin_at(place, offset_seconds) do
      time = DateTime.add(DateTime.utc_now(:second), offset_seconds, :second)

      checkin_fixture(%{
        place_uri: place.uri,
        starts_at_utc: time,
        published_at_utc: time
      })
    end

    test "shows the sentinel when more activities exist beyond the first page", %{conn: conn} do
      person = person_fixture()
      place = place_fixture()
      for i <- 1..3, do: checkin_at(place, -i)

      conn = log_in_person(conn, person)
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "activity-feed-sentinel"
    end

    test "hides the sentinel when no more activities exist", %{conn: conn} do
      person = person_fixture()
      place = place_fixture()
      checkin_at(place, -1)

      conn = log_in_person(conn, person)
      {:ok, _lv, html} = live(conn, ~p"/")
      refute html =~ "activity-feed-sentinel"
    end

    test "load_more appends the next page and updates has_more", %{conn: conn} do
      person = person_fixture()
      place = place_fixture()
      [c1, _c2, _c3] = for i <- 3..1//-1, do: checkin_at(place, -i)

      conn = log_in_person(conn, person)
      {:ok, lv, html} = live(conn, ~p"/")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)

      refute html =~ c1.url
      assert html =~ "activity-feed-sentinel"

      html_after = render_hook(lv, "load_more", %{})

      assert html_after =~ c1.url
      refute html_after =~ "activity-feed-sentinel"
    end
  end
end
