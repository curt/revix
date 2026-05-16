defmodule RevixWeb.FollowingLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Revix.PeopleFixtures

  alias Revix.Follows
  alias Revix.Follows.Follow
  alias Revix.Repo

  setup do
    Req.Test.stub(:federation, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/plain")
      |> Plug.Conn.send_resp(202, "")
    end)

    :ok
  end

  describe "/following" do
    test "redirects unauthenticated user to sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/following")
      assert path =~ "/people/signin"
    end

    test "renders for any authenticated user (not owner-only)", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)

      {:ok, _lv, html} = live(conn, ~p"/following")

      assert html =~ "Following"
    end

    test "shows empty state when not following anyone", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)

      {:ok, _lv, html} = live(conn, ~p"/following")

      assert html =~ "Not following anyone yet"
    end

    test "follow event creates a follow record", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)

      {:ok, lv, _html} = live(conn, ~p"/following")

      target_uri = "https://remote.example.com/users/alice"

      html =
        lv
        |> form("form", %{"target_uri" => target_uri})
        |> render_submit()

      assert html =~ "Follow request sent"
      assert Follows.following?(person.uri, target_uri)
    end

    test "follow event shows self-follow error", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)

      {:ok, lv, _html} = live(conn, ~p"/following")

      html =
        lv
        |> form("form", %{"target_uri" => person.uri})
        |> render_submit()

      assert html =~ "cannot follow yourself"
    end

    test "unfollow event soft-deletes the follow", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      scope = person_scope_fixture(person)

      target_uri = "https://remote.example.com/users/alice"
      {:ok, _} = Follows.follow(scope, target_uri)

      {:ok, lv, _html} = live(conn, ~p"/following")

      html =
        lv
        |> element("button[phx-click='unfollow'][phx-value-following_uri='#{target_uri}']")
        |> render_click()

      assert html =~ "Unfollowed"
      refute Follows.following?(person.uri, target_uri)
    end

    test "accept event sets accepted_at and enqueues DeliverAcceptFollowWorker", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)

      Application.put_env(:revix, :follows, auto_accept: false)
      on_exit(fn -> Application.put_env(:revix, :follows, auto_accept: true) end)

      follower_uri = "https://remote.example.com/users/bob"
      id = Revix.Ecto.Base58Id.autogenerate()

      follow =
        Repo.insert!(%Follow{
          id: id,
          uri: "https://remote.example.com/follows/#{id}",
          follower_uri: follower_uri,
          following_uri: person.uri,
          origin: :remote
        })

      {:ok, lv, _html} = live(conn, ~p"/following")

      # Switch to followers tab to reveal the Accept button
      lv
      |> element("button[phx-click='switch_tab'][phx-value-tab='followers']")
      |> render_click()

      html =
        lv
        |> element("button[phx-click='accept'][phx-value-follow_id='#{follow.id}']")
        |> render_click()

      render(lv)

      assert html =~ "Follower accepted"
      assert Repo.get!(Follow, follow.id).accepted_at != nil

      assert_enqueued(
        worker: Revix.Workers.DeliverAcceptFollowWorker,
        args: %{"follow_id" => follow.id}
      )
    end

    test "tab switch shows followers tab", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)

      {:ok, lv, _html} = live(conn, ~p"/following")

      html =
        lv
        |> element("button[phx-click='switch_tab'][phx-value-tab='followers']")
        |> render_click()

      assert html =~ "No followers yet"
    end

    test "unfollow shows not-found error when not following that URI", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)

      {:ok, lv, _html} = live(conn, ~p"/following")

      html =
        render_hook(lv, "unfollow", %{
          "following_uri" => "https://remote.example.com/users/nobody"
        })

      assert html =~ "Follow not found"
    end

    test "accept shows not-found error when follow ID does not exist", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)

      {:ok, lv, _html} = live(conn, ~p"/following")

      nonexistent_id = Revix.Ecto.Base58Id.autogenerate()
      html = render_hook(lv, "accept", %{"follow_id" => nonexistent_id})

      assert html =~ "Follow not found"
    end

    test "followers tab renders URI fallback when follower has no person record", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)

      Application.put_env(:revix, :follows, auto_accept: false)
      on_exit(fn -> Application.put_env(:revix, :follows, auto_accept: true) end)

      follower_uri = "https://remote.example.com/users/unknown-person"
      id = Revix.Ecto.Base58Id.autogenerate()

      Repo.insert!(%Follow{
        id: id,
        uri: "https://remote.example.com/follows/#{id}",
        follower_uri: follower_uri,
        following_uri: person.uri,
        origin: :remote
      })

      {:ok, lv, _html} = live(conn, ~p"/following")

      html =
        lv
        |> element("button[phx-click='switch_tab'][phx-value-tab='followers']")
        |> render_click()

      assert html =~ follower_uri
    end

    test "PubSub :follows_updated refreshes the follow lists", %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      scope = person_scope_fixture(person)

      {:ok, lv, _html} = live(conn, ~p"/following")
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

      target_uri = "https://remote.example.com/users/carol"
      {:ok, _} = Follows.follow(scope, target_uri)

      Phoenix.PubSub.broadcast(Revix.PubSub, "follows:#{person.uri}", :follows_updated)
      render(lv)

      assert render(lv) =~ target_uri
    end
  end
end
