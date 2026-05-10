defmodule RevixWeb.EntryLikeLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures

  alias Revix.Likes

  defp mount_entry_like(conn, entry, person_token \\ nil) do
    session = %{
      "entry_uri" => entry.uri,
      "entry_author_uri" => entry.author_uri,
      "person_token" => person_token
    }

    {:ok, lv, html} = live_isolated(conn, RevixWeb.EntryLikeLive, session: session)
    Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)
    pid = lv.pid

    on_exit(fn ->
      ref = Process.monitor(pid)
      Process.exit(pid, :shutdown)

      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after
        500 -> :ok
      end
    end)

    {:ok, lv, html}
  end

  setup do
    place = place_fixture(%{slug: "test-place"})
    checkin = checkin_fixture(%{place_uri: place.uri})
    %{place: place, checkin: checkin}
  end

  # ── Unauthenticated mount ────────────────────────────────────────────────────

  describe "unauthenticated mount" do
    test "renders without a Like button", %{conn: conn, checkin: checkin} do
      {:ok, _lv, html} = mount_entry_like(conn, checkin)
      refute html =~ "phx-click=\"like\""
      refute html =~ "phx-click=\"unlike\""
    end

    test "shows liker avatars when likes exist", %{conn: conn, checkin: checkin} do
      liker_scope = person_scope_fixture()
      {:ok, _} = Likes.like_entry(liker_scope, checkin.uri, "UTC", checkin.uri)

      {:ok, _lv, html} = mount_entry_like(conn, checkin)
      assert html =~ liker_scope.person.id
    end

    test "renders nothing extra when no likes", %{conn: conn, checkin: checkin} do
      {:ok, _lv, html} = mount_entry_like(conn, checkin)
      refute html =~ "avatar"
    end
  end

  # ── Authenticated mount ──────────────────────────────────────────────────────

  describe "authenticated mount" do
    setup %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      token = get_session(conn, :person_token)
      %{conn: conn, person: person, token: token}
    end

    test "renders Like button for non-author", %{conn: conn, checkin: checkin, token: token} do
      {:ok, _lv, html} = mount_entry_like(conn, checkin, token)
      assert html =~ "Like"
      assert html =~ "phx-click=\"like\""
    end

    test "renders Unlike button when already liked", %{
      conn: conn,
      checkin: checkin,
      token: token,
      person: person
    } do
      scope = Revix.People.Scope.for_person(person)
      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC", checkin.uri)

      {:ok, _lv, html} = mount_entry_like(conn, checkin, token)
      assert html =~ "Unlike"
      assert html =~ "phx-click=\"unlike\""
    end

    test "author cannot like their own entry", %{conn: conn} do
      author = person_fixture()
      author_conn = log_in_person(conn, author)
      author_token = get_session(author_conn, :person_token)

      author_checkin = checkin_fixture(%{author_uri: author.uri})

      {:ok, _lv, html} = mount_entry_like(author_conn, author_checkin, author_token)
      assert html =~ "disabled"
    end
  end

  # ── like / unlike events ─────────────────────────────────────────────────────

  describe "like / unlike" do
    setup %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      token = get_session(conn, :person_token)
      scope = Revix.People.Scope.for_person(person)
      %{conn: conn, person: person, token: token, scope: scope}
    end

    test "like event creates a like and shows Unlike button", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      {:ok, lv, _html} = mount_entry_like(conn, checkin, token)

      lv |> element("button[phx-click='like']") |> render_click()
      html = render(lv)

      assert Likes.count_active_likes(checkin.uri) == 1
      assert html =~ "Unlike"
    end

    test "unlike event removes the like", %{
      conn: conn,
      checkin: checkin,
      token: token,
      scope: scope
    } do
      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC", checkin.uri)

      {:ok, lv, _html} = mount_entry_like(conn, checkin, token)

      lv |> element("button[phx-click='unlike']") |> render_click()
      render(lv)

      assert Likes.count_active_likes(checkin.uri) == 0
    end
  end

  # ── real-time updates ────────────────────────────────────────────────────────

  describe "real-time PubSub updates" do
    setup %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      token = get_session(conn, :person_token)
      scope = Revix.People.Scope.for_person(person)
      %{conn: conn, person: person, token: token, scope: scope}
    end

    test "entry_liked broadcast updates the liker avatars", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      {:ok, lv, _html} = mount_entry_like(conn, checkin, token)

      liker_scope = person_scope_fixture()
      {:ok, _} = Likes.like_entry(liker_scope, checkin.uri, "UTC", checkin.uri)

      send(lv.pid, {:entry_liked, checkin.uri, liker_scope.person.uri})
      html = render(lv)

      assert html =~ liker_scope.person.id
    end

    test "entry_unliked broadcast removes the liker avatar", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      liker_scope = person_scope_fixture()
      {:ok, _} = Likes.like_entry(liker_scope, checkin.uri, "UTC", checkin.uri)

      {:ok, lv, html} = mount_entry_like(conn, checkin, token)
      assert html =~ liker_scope.person.id

      lv |> element("button[phx-click='like']") |> render_click()

      Likes.unlike_entry(liker_scope, checkin.uri, checkin.uri)
      send(lv.pid, {:entry_unliked, checkin.uri, liker_scope.person.uri})
      html = render(lv)

      refute html =~ liker_scope.person.id
    end
  end
end
