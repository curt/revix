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

  # ── Initial render ────────────────────────────────────────────────────────

  describe "initial render" do
    test "renders home page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Home Page"
    end

    test "renders empty feed with no activity", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html
    end

    test "displays checkin with place name and verb", %{conn: conn} do
      place = place_fixture(%{name: "Disneyland"})
      checkin_fixture(%{place_uri: place.uri})

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Disneyland"
      assert html =~ "checked into"
    end

    test "displays checkin author display name", %{conn: conn} do
      person = person_fixture()
      {:ok, person} = Revix.People.update_person_display_name(person, %{display_name: "Alice"})
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Alice"
    end

    test "displays checkin date and timezone abbreviation", %{conn: conn} do
      place = place_fixture()

      checkin_fixture(%{
        place_uri: place.uri,
        starts_at_utc: ~U[2026-02-16 18:37:00Z],
        starts_at_local: ~N[2026-02-16 10:37:00],
        starts_tz: "America/Los_Angeles"
      })

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "2026-02-16"
      assert html =~ "10:37 PST"
    end

    test "links to author profile from checkin", %{conn: conn} do
      person = person_fixture()
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri, author_uri: person.uri})

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ ~s(href="http://localhost:4000/people/#{person.id}")
    end

    test "links to the checkin URL", %{conn: conn} do
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri, url: "http://example.com/123"})

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "http://example.com/123"
    end

    test "shows 'somewhere' when checkin has no place", %{conn: conn} do
      checkin_fixture(%{place_uri: "https://example.com/places/nonexistent"})

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "somewhere"
    end

    test "still shows checkin when author is unresolvable", %{conn: conn} do
      place = place_fixture(%{name: "Ghost Place"})
      checkin_fixture(%{place_uri: place.uri, author_uri: "https://example.com/people/ghost"})

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "checked into"
      assert html =~ "Ghost Place"
    end
  end

  # ── Like activity ─────────────────────────────────────────────────────────

  describe "like activity" do
    setup do
      place = place_fixture(%{name: "The Coffee Shop"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      %{place: place, checkin: checkin}
    end

    test "displays like verb and heart icon", %{conn: conn, checkin: checkin} do
      like_fixture(%{object_uri: checkin.uri})

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "liked"
      assert html =~ "hero-heart-solid"
    end

    test "displays liked place name when object resolves to a checkin with a place", %{
      conn: conn,
      checkin: checkin,
      place: place
    } do
      like_fixture(%{object_uri: checkin.uri})

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ place.name
    end

    test "shows 'a checkin' when liked object has no resolvable place", %{conn: conn} do
      like_fixture(%{object_uri: "https://example.com/entries/nonexistent"})

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "a checkin"
    end

    test "groups two likes on same checkin into one row", %{conn: conn, checkin: checkin} do
      person1 = person_fixture()
      person2 = person_fixture()
      like_fixture(%{author_uri: person1.uri, object_uri: checkin.uri})
      like_fixture(%{author_uri: person2.uri, object_uri: checkin.uri})

      {:ok, _lv, html} = live(conn, ~p"/")
      like_count = html |> String.split("hero-heart-solid") |> length() |> Kernel.-(1)
      assert like_count == 1
    end

    test "hides remote likes from unauthenticated visitors", %{conn: conn, checkin: checkin} do
      {:ok, _like} =
        Likes.upsert_inbound_like(%{
          author_uri: "https://remote.example/users/alice",
          object_uri: checkin.uri,
          like_uri: "https://remote.example/likes/1"
        })

      {:ok, _lv, html} = live(conn, ~p"/")
      refute html =~ "hero-heart-solid"
    end

    test "shows remote likes to authenticated users", %{conn: conn, checkin: checkin} do
      person = person_fixture()

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

    test "displays like date and timezone", %{conn: conn, checkin: checkin} do
      like_fixture(%{object_uri: checkin.uri, published_tz: "America/New_York"})

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ ~r/\d{4}-\d{2}-\d{2}/
      assert html =~ ~r/E[SD]T/
    end
  end

  # ── Comment activity ──────────────────────────────────────────────────────

  describe "comment activity" do
    setup do
      scope = Revix.People.Scope.for_person(person_fixture())
      place = place_fixture(%{name: "The Diner"})
      checkin = checkin_fixture(%{place_uri: place.uri})
      %{scope: scope, place: place, checkin: checkin}
    end

    test "displays comment verb for top-level comment", %{
      conn: conn,
      scope: scope,
      checkin: checkin
    } do
      create_comment(scope, checkin, %{"content" => "Nice spot!"})

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "commented on"
    end

    test "displays comment author name", %{conn: conn, checkin: checkin} do
      person = person_fixture()
      {:ok, person} = Revix.People.update_person_display_name(person, %{display_name: "Carol"})
      scope = Revix.People.Scope.for_person(person)
      create_comment(scope, checkin, %{"content" => "Great!"})

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Carol"
    end

    test "links to the parent checkin place", %{
      conn: conn,
      scope: scope,
      checkin: checkin,
      place: place
    } do
      create_comment(scope, checkin, %{"content" => "Love it"})

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ place.name
    end

    test "shows 'a checkin' when comment has no resolvable parent place", %{
      conn: conn,
      scope: scope
    } do
      orphan_checkin = checkin_fixture(%{place_uri: "https://example.com/places/gone"})
      create_comment(scope, orphan_checkin, %{"content" => "Still here"})

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "a checkin"
    end

    test "hides replies from unauthenticated visitors", %{
      conn: conn,
      scope: scope,
      checkin: checkin
    } do
      comment = create_comment(scope, checkin, %{"content" => "Top comment"})
      _reply = create_reply(scope, comment, %{"content" => "A reply"})

      {:ok, _lv, html} = live(conn, ~p"/")
      # Top-level comment should show up
      assert html =~ "commented on"
      # The reply HTML should not be present as a feed item (it is a note whose parent is a note)
      # We verify by checking comment count in the feed - should only see 1 comment activity
      comment_count = html |> String.split("commented on") |> length() |> Kernel.-(1)
      assert comment_count == 1
    end

    test "groups reply with parent comment under same checkin root for authenticated users", %{
      conn: conn,
      checkin: checkin
    } do
      person = person_fixture()
      other_person = person_fixture()
      scope_other = Revix.People.Scope.for_person(other_person)

      comment =
        create_comment(Revix.People.Scope.for_person(person), checkin, %{
          "content" => "Top comment"
        })

      _reply = create_reply(scope_other, comment, %{"content" => "A reply"})

      conn = log_in_person(conn, person)
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "commented on"
      # Reply is merged into the same group — no separate "replied to" row
      refute html =~ "replied to"
      comment_count = html |> String.split("commented on") |> length() |> Kernel.-(1)
      assert comment_count == 1
    end

    test "groups two comments on same checkin into one row", %{
      conn: conn,
      checkin: checkin
    } do
      scope2 = Revix.People.Scope.for_person(person_fixture())
      scope3 = Revix.People.Scope.for_person(person_fixture())
      create_comment(scope2, checkin, %{"content" => "First"})
      create_comment(scope3, checkin, %{"content" => "Second"})

      {:ok, _lv, html} = live(conn, ~p"/")
      comment_count = html |> String.split("commented on") |> length() |> Kernel.-(1)
      assert comment_count == 1
    end
  end

  # ── Live updates (PubSub) ─────────────────────────────────────────────────

  describe "live updates" do
    test "prepends new checkin after broadcast", %{conn: conn} do
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

    test "unauthenticated: new remote like is not prepended", %{conn: conn} do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, lv, _html} = live(conn, ~p"/")
      Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)

      {:ok, _like} =
        Likes.upsert_inbound_like(%{
          author_uri: "https://remote.example/users/alice",
          object_uri: checkin.uri,
          like_uri: "https://remote.example/likes/3"
        })

      html = render(lv)
      refute html =~ "hero-heart-solid"
    end

    test "authenticated: new like on existing group updates the group", %{conn: conn} do
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
      assert like_count == 1
    end

    test "authenticated: second comment on same checkin merges into existing group", %{conn: conn} do
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
      assert comment_count == 1
    end
  end
end
