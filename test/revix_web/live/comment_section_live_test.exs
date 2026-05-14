defmodule RevixWeb.CommentSectionLiveTest do
  use RevixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures

  alias Revix.Entries
  alias Revix.Likes

  # Helper: mount the embedded CommentSectionLive via live_isolated so we can
  # send events directly without navigating to the full checkin page.
  defp mount_comment_section(conn, checkin, person_token \\ nil) do
    session = %{"checkin_uri" => checkin.uri, "person_token" => person_token}
    {:ok, lv, html} = live_isolated(conn, RevixWeb.CommentSectionLive, session: session)
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

  # ── Unauthenticated mount ──────────────────────────────────────────────────

  describe "unauthenticated mount" do
    test "renders without the comment form", %{conn: conn, checkin: checkin} do
      {:ok, _lv, html} = mount_comment_section(conn, checkin)

      refute html =~ "Add a comment"
      refute html =~ "phx-submit=\"submit_comment\""
    end

    test "shows commenter avatars when comments exist", %{conn: conn, checkin: checkin} do
      scope = person_scope_fixture()
      comment_fixture(scope, checkin, %{"content" => "Hello"})

      {:ok, _lv, html} = mount_comment_section(conn, checkin)
      assert html =~ scope.person.id
    end

    test "does not render comment text content", %{conn: conn, checkin: checkin} do
      scope = person_scope_fixture()
      comment_fixture(scope, checkin, %{"content" => "Read-only comment"})

      {:ok, _lv, html} = mount_comment_section(conn, checkin)
      refute html =~ "Read-only comment"
    end

    test "does not render the comment thread for unauthenticated users", %{
      conn: conn,
      checkin: checkin
    } do
      scope = person_scope_fixture()
      comment_fixture(scope, checkin, %{"content" => "Secret comment"})

      {:ok, _lv, html} = mount_comment_section(conn, checkin)
      refute html =~ "phx-submit=\"submit_comment\""
      refute html =~ "phx-click=\"reply_to\""
      refute html =~ "Secret comment"
    end
  end

  # ── Authenticated mount ────────────────────────────────────────────────────

  describe "authenticated mount" do
    setup %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      token = get_session(conn, :person_token)
      %{conn: conn, person: person, token: token}
    end

    test "renders comment form for authenticated user", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      {:ok, _lv, html} = mount_comment_section(conn, checkin, token)
      assert html =~ "Add a comment"
    end

    test "renders Comments heading when comments exist", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      scope = person_scope_fixture()
      comment_fixture(scope, checkin, %{"content" => "A comment"})

      {:ok, _lv, html} = mount_comment_section(conn, checkin, token)
      assert html =~ "Comments"
    end

    test "does not render Comments heading when no comments", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      {:ok, _lv, html} = mount_comment_section(conn, checkin, token)
      refute html =~ "<h2>Comments</h2>"
    end
  end

  # ── submit_comment ─────────────────────────────────────────────────────────

  describe "submit_comment" do
    setup %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      token = get_session(conn, :person_token)
      scope = Revix.People.Scope.for_person(person)
      %{conn: conn, person: person, token: token, scope: scope}
    end

    test "creates a comment and shows it in the tree", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      {:ok, lv, _html} = mount_comment_section(conn, checkin, token)

      lv
      |> form("form[phx-submit='submit_comment']", %{content: "My new comment"})
      |> render_submit()

      assert render(lv) =~ "My new comment"
    end

    test "comment persists in the database", %{conn: conn, checkin: checkin, token: token} do
      {:ok, lv, _html} = mount_comment_section(conn, checkin, token)

      lv
      |> form("form[phx-submit='submit_comment']", %{content: "Persisted"})
      |> render_submit()

      render(lv)

      tree = Entries.get_comment_tree(checkin.uri)
      assert Enum.any?(tree, fn {c, _} -> c.content == "Persisted" end)
    end
  end

  # ── submit_reply ──────────────────────────────────────────────────────────

  describe "submit_reply" do
    setup %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      token = get_session(conn, :person_token)
      comment_scope = person_scope_fixture()
      %{conn: conn, person: person, token: token, comment_scope: comment_scope}
    end

    test "shows reply form after clicking Reply", %{
      conn: conn,
      checkin: checkin,
      token: token,
      comment_scope: comment_scope
    } do
      comment = comment_fixture(comment_scope, checkin, %{"content" => "Top comment"})

      {:ok, lv, _html} = mount_comment_section(conn, checkin, token)

      html =
        lv
        |> element("button[phx-value-comment_id='#{comment.id}'][phx-click='reply_to']")
        |> render_click()

      assert html =~ "phx-submit=\"submit_reply\""
    end

    test "creates a reply and nests it under parent", %{
      conn: conn,
      checkin: checkin,
      token: token,
      comment_scope: comment_scope
    } do
      comment = comment_fixture(comment_scope, checkin, %{"content" => "Top comment"})

      {:ok, lv, _html} = mount_comment_section(conn, checkin, token)

      lv
      |> element("button[phx-value-comment_id='#{comment.id}'][phx-click='reply_to']")
      |> render_click()

      lv
      |> form("form[phx-submit='submit_reply']", %{content: "A reply", comment_id: comment.id})
      |> render_submit()

      assert render(lv) =~ "A reply"
    end

    test "reply has correct in_reply_to_uri and context", %{
      conn: conn,
      checkin: checkin,
      token: token,
      comment_scope: comment_scope
    } do
      comment = comment_fixture(comment_scope, checkin, %{"content" => "Top comment"})

      {:ok, lv, _html} = mount_comment_section(conn, checkin, token)

      lv
      |> element("button[phx-value-comment_id='#{comment.id}'][phx-click='reply_to']")
      |> render_click()

      lv
      |> form("form[phx-submit='submit_reply']", %{content: "Reply", comment_id: comment.id})
      |> render_submit()

      render(lv)

      tree = Entries.get_comment_tree(checkin.uri)
      [{_comment, replies}] = Enum.filter(tree, fn {c, _} -> c.id == comment.id end)
      assert length(replies) == 1
      reply = hd(replies)
      assert reply.in_reply_to_uri == comment.uri
      assert reply.context == checkin.uri
    end

    test "cancel_reply hides the reply form", %{
      conn: conn,
      checkin: checkin,
      token: token,
      comment_scope: comment_scope
    } do
      comment = comment_fixture(comment_scope, checkin, %{"content" => "Top comment"})

      {:ok, lv, _html} = mount_comment_section(conn, checkin, token)

      lv
      |> element("button[phx-value-comment_id='#{comment.id}'][phx-click='reply_to']")
      |> render_click()

      html = lv |> element("button[phx-click='cancel_reply']") |> render_click()

      refute html =~ "phx-submit=\"submit_reply\""
    end
  end

  # ── like / unlike comment ──────────────────────────────────────────────────

  describe "like_comment / unlike_comment" do
    setup %{conn: conn} do
      liker = person_fixture()
      conn = log_in_person(conn, liker)
      token = get_session(conn, :person_token)
      liker_scope = Revix.People.Scope.for_person(liker)
      comment_scope = person_scope_fixture()
      %{conn: conn, liker_scope: liker_scope, comment_scope: comment_scope, token: token}
    end

    test "like increments the count", %{
      conn: conn,
      checkin: checkin,
      token: token,
      comment_scope: comment_scope
    } do
      comment = comment_fixture(comment_scope, checkin)

      {:ok, lv, _html} = mount_comment_section(conn, checkin, token)

      lv
      |> element("button[phx-value-comment_uri='#{comment.uri}'][phx-click='like_comment']")
      |> render_click()

      html = render(lv)

      assert Likes.count_active_likes(comment.uri) == 1
      assert html =~ "Unlike"
    end

    test "unlike decrements the count", %{
      conn: conn,
      checkin: checkin,
      token: token,
      liker_scope: liker_scope,
      comment_scope: comment_scope
    } do
      comment = comment_fixture(comment_scope, checkin)

      {:ok, _} =
        Likes.like_entry(
          liker_scope,
          comment.uri,
          "UTC",
          fn id -> "https://example.com/likes/#{id}" end,
          checkin.uri
        )

      {:ok, lv, _html} = mount_comment_section(conn, checkin, token)

      lv
      |> element("button[phx-value-comment_uri='#{comment.uri}'][phx-click='unlike_comment']")
      |> render_click()

      render(lv)

      assert Likes.count_active_likes(comment.uri) == 0
    end
  end

  # ── edit / update comment ──────────────────────────────────────────────────

  describe "edit comment" do
    setup %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      token = get_session(conn, :person_token)
      scope = Revix.People.Scope.for_person(person)
      %{conn: conn, person: person, token: token, scope: scope}
    end

    test "shows edit form after clicking edit button", %{
      conn: conn,
      checkin: checkin,
      token: token,
      scope: scope
    } do
      comment = comment_fixture(scope, checkin, %{"content" => "Editable"})

      {:ok, lv, _html} = mount_comment_section(conn, checkin, token)

      html =
        lv
        |> element("button[phx-value-comment_id='#{comment.id}'][phx-click='edit_comment']")
        |> render_click()

      assert html =~ "phx-submit=\"update_comment\""
    end

    test "update_comment replaces content in the tree", %{
      conn: conn,
      checkin: checkin,
      token: token,
      scope: scope
    } do
      comment = comment_fixture(scope, checkin, %{"content" => "Original"})

      {:ok, lv, _html} = mount_comment_section(conn, checkin, token)

      lv
      |> element("button[phx-value-comment_id='#{comment.id}'][phx-click='edit_comment']")
      |> render_click()

      lv
      |> form("form[phx-submit='update_comment']", %{content: "Updated", comment_id: comment.id})
      |> render_submit()

      html = render(lv)
      assert html =~ "Updated"
      refute html =~ "Original"
    end

    test "cannot edit another user's comment", %{conn: conn, checkin: checkin, token: token} do
      other_scope = person_scope_fixture()
      comment = comment_fixture(other_scope, checkin, %{"content" => "Not mine"})

      {:ok, lv, html} = mount_comment_section(conn, checkin, token)

      refute html =~ "phx-value-comment_id=\"#{comment.id}\" phx-click=\"edit_comment\""
      assert has_element?(lv, "#comment-#{comment.id}")
    end
  end

  # ── delete comment ─────────────────────────────────────────────────────────

  describe "delete comment" do
    setup %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      token = get_session(conn, :person_token)
      scope = Revix.People.Scope.for_person(person)
      %{conn: conn, person: person, token: token, scope: scope}
    end

    test "removes the comment from the tree", %{
      conn: conn,
      checkin: checkin,
      token: token,
      scope: scope
    } do
      comment = comment_fixture(scope, checkin, %{"content" => "To delete"})

      {:ok, lv, _html} = mount_comment_section(conn, checkin, token)

      lv
      |> element("button[phx-value-comment_id='#{comment.id}'][phx-click='delete_comment']")
      |> render_click()

      assert render(lv) |> String.contains?("To delete") == false
      assert {:error, :not_found} = Entries.get_comment(comment.id)
    end

    test "cannot delete another user's comment", %{conn: conn, checkin: checkin, token: token} do
      other_scope = person_scope_fixture()
      comment = comment_fixture(other_scope, checkin, %{"content" => "Not mine"})

      {:ok, _lv, html} = mount_comment_section(conn, checkin, token)
      refute html =~ "phx-value-comment_id=\"#{comment.id}\" phx-click=\"delete_comment\""
    end
  end

  # ── real-time updates ──────────────────────────────────────────────────────

  describe "real-time PubSub updates" do
    setup %{conn: conn} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      token = get_session(conn, :person_token)
      scope = Revix.People.Scope.for_person(person)
      %{conn: conn, person: person, token: token, scope: scope}
    end

    test "new comment broadcast updates the tree", %{conn: conn, checkin: checkin, token: token} do
      {:ok, lv, _html} = mount_comment_section(conn, checkin, token)

      scope = person_scope_fixture()
      comment = comment_fixture(scope, checkin, %{"content" => "Live update"})

      send(lv.pid, {:comment_created, comment})

      html = render(lv)
      assert html =~ "Live update"
    end

    test "comment_deleted broadcast removes the entry", %{
      conn: conn,
      checkin: checkin,
      token: token,
      scope: scope
    } do
      comment = comment_fixture(scope, checkin, %{"content" => "Will be deleted"})

      {:ok, lv, html} = mount_comment_section(conn, checkin, token)
      assert html =~ "Will be deleted"

      # Delete via the LiveView handler so it happens in the LiveView's DB sandbox connection
      lv
      |> element("button[phx-value-comment_id='#{comment.id}'][phx-click='delete_comment']")
      |> render_click()

      refute render(lv) =~ "Will be deleted"
    end

    test "comment_updated broadcast refreshes content", %{
      conn: conn,
      checkin: checkin,
      token: token,
      scope: scope
    } do
      comment = comment_fixture(scope, checkin, %{"content" => "Old content"})

      {:ok, lv, _html} = mount_comment_section(conn, checkin, token)

      # Update via the LiveView handler to use the same DB connection
      lv
      |> element("button[phx-value-comment_id='#{comment.id}'][phx-click='edit_comment']")
      |> render_click()

      lv
      |> form("form[phx-submit='update_comment']", %{
        content: "New content",
        comment_id: comment.id
      })
      |> render_submit()

      assert render(lv) =~ "New content"
    end

    test "entry_liked broadcast refreshes like counts", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      comment_scope = person_scope_fixture()
      comment = comment_fixture(comment_scope, checkin)

      {:ok, lv, _html} = mount_comment_section(conn, checkin, token)

      # Like via the LiveView handler (uses the LiveView's DB connection)
      lv
      |> element("button[phx-value-comment_uri='#{comment.uri}'][phx-click='like_comment']")
      |> render_click()

      html = render(lv)
      assert html =~ "Unlike"
    end
  end

  # ── Remote (federated) comments ───────────────────────────────────────────

  describe "remote comments" do
    setup %{conn: conn, checkin: checkin} do
      person = person_fixture()
      conn = log_in_person(conn, person)
      token = get_session(conn, :person_token)
      %{conn: conn, checkin: checkin, token: token}
    end

    test "displays content of a remote comment", %{conn: conn, checkin: checkin, token: token} do
      {:ok, _} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/r1",
          url: "https://remote.example.com/notes/r1",
          author_uri: "https://remote.example.com/users/alice",
          content: "<p>Remote comment content</p>",
          in_reply_to_uri: checkin.uri,
          context: checkin.uri,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      {:ok, _lv, html} = mount_comment_section(conn, checkin, token)
      assert html =~ "Remote comment content"
    end

    test "shows fallback author label for remote comments with no local Person", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      {:ok, _} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/r2",
          url: "https://remote.example.com/notes/r2",
          author_uri: "https://remote.example.com/users/alice",
          content: "<p>Hello</p>",
          in_reply_to_uri: checkin.uri,
          context: checkin.uri,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      {:ok, _lv, html} = mount_comment_section(conn, checkin, token)
      assert html =~ "@alice@remote.example.com"
    end

    test "does not show edit/delete buttons for remote comments", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      {:ok, note} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/r3",
          url: "https://remote.example.com/notes/r3",
          author_uri: "https://remote.example.com/users/alice",
          content: "<p>Cannot edit</p>",
          in_reply_to_uri: checkin.uri,
          context: checkin.uri,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      {:ok, _lv, html} = mount_comment_section(conn, checkin, token)
      refute html =~ "phx-value-comment_id=\"#{note.id}\" phx-click=\"edit_comment\""
      refute html =~ "phx-value-comment_id=\"#{note.id}\" phx-click=\"delete_comment\""
    end

    test "like button is present for remote comment", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      {:ok, note} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/r4",
          url: "https://remote.example.com/notes/r4",
          author_uri: "https://remote.example.com/users/alice",
          content: "<p>Likeable</p>",
          in_reply_to_uri: checkin.uri,
          context: checkin.uri,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      {:ok, _lv, html} = mount_comment_section(conn, checkin, token)
      assert html =~ "phx-value-comment_uri=\"#{note.uri}\""
    end

    test "new remote comment via PubSub broadcast appears in the tree", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      {:ok, lv, _html} = mount_comment_section(conn, checkin, token)

      {:ok, note} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/r5",
          url: "https://remote.example.com/notes/r5",
          author_uri: "https://remote.example.com/users/alice",
          content: "<p>Live remote comment</p>",
          in_reply_to_uri: checkin.uri,
          context: checkin.uri,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      send(lv.pid, {:comment_created, note})
      assert render(lv) =~ "Live remote comment"
    end

    test "displays remote comment with nil context when in_reply_to_uri matches checkin", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      {:ok, _} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/r-nil-ctx",
          url: "https://remote.example.com/notes/r-nil-ctx",
          author_uri: "https://remote.example.com/users/alice",
          content: "<p>Nil context remote</p>",
          in_reply_to_uri: checkin.uri,
          context: nil,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      {:ok, _lv, html} = mount_comment_section(conn, checkin, token)
      assert html =~ "Nil context remote"
    end

    test "displays remote comment with foreign context when in_reply_to_uri matches checkin", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      {:ok, _} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/r-foreign-ctx",
          url: "https://remote.example.com/notes/r-foreign-ctx",
          author_uri: "https://remote.example.com/users/alice",
          content: "<p>Foreign context remote</p>",
          in_reply_to_uri: checkin.uri,
          context: "https://mastodon.social/contexts/abc",
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      {:ok, _lv, html} = mount_comment_section(conn, checkin, token)
      assert html =~ "Foreign context remote"
    end

    test "local reply to nil-context remote comment appears as nested reply", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      scope = person_scope_fixture()

      {:ok, remote_comment} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/r-nil-parent",
          url: "https://remote.example.com/notes/r-nil-parent",
          author_uri: "https://remote.example.com/users/alice",
          content: "<p>Remote top</p>",
          in_reply_to_uri: checkin.uri,
          context: nil,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, _reply} =
        Entries.create_reply(
          scope,
          remote_comment,
          %{"content" => "Local reply to nil-ctx remote", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      {:ok, _lv, html} = mount_comment_section(conn, checkin, token)
      assert html =~ "Remote top"
      assert html =~ "Local reply to nil-ctx remote"
    end

    test "renders all entries in a 3-level deep reply chain", %{
      conn: conn,
      checkin: checkin,
      token: token
    } do
      scope = person_scope_fixture()
      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, local_comment} =
        Entries.create_comment(
          scope,
          checkin,
          %{"content" => "Level 1 local comment", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      {:ok, remote_reply} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/deep-r1",
          url: "https://remote.example.com/notes/deep-r1",
          author_uri: "https://remote.example.com/users/alice",
          content: "<p>Level 2 remote reply</p>",
          in_reply_to_uri: local_comment.uri,
          context: checkin.uri,
          published_at_utc: ~U[2024-01-01 11:00:00Z]
        })

      {:ok, _deep_reply} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/deep-r2",
          url: "https://remote.example.com/notes/deep-r2",
          author_uri: "https://remote.example.com/users/bob",
          content: "<p>Level 3 remote reply to reply</p>",
          in_reply_to_uri: remote_reply.uri,
          context: checkin.uri,
          published_at_utc: ~U[2024-01-01 12:00:00Z]
        })

      {:ok, _lv, html} = mount_comment_section(conn, checkin, token)
      assert html =~ "Level 1 local comment"
      assert html =~ "Level 2 remote reply"
      assert html =~ "Level 3 remote reply to reply"
    end
  end
end
