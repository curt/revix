defmodule RevixWeb.ActivityComponentsTest do
  use RevixWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias RevixWeb.ActivityComponents

  describe "comment activity targets" do
    test "renders checkin place link for comment on checkin" do
      html =
        render_component(&ActivityComponents.comment_activity/1,
          comment: %{
            id: "c1",
            author: nil,
            in_reply_to: %{
              type: :checkin,
              url: "https://example.com/checkins/1",
              place: %{name: "Cafe Place"}
            },
            published_at_local: ~N[2026-05-26 10:00:00],
            published_tz: "UTC",
            published_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "commented on"
      assert html =~ "Cafe Place"
      assert html =~ ~s(href="https://example.com/checkins/1#comment-c1")
    end

    test "renders post title link for comment on post" do
      html =
        render_component(&ActivityComponents.comment_activity/1,
          comment: %{
            id: "c2",
            author: nil,
            in_reply_to: %{type: :post, url: "https://example.com/posts/1", name: "Post Title"},
            published_at_local: ~N[2026-05-26 10:00:00],
            published_tz: "UTC",
            published_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "commented on"
      assert html =~ "Post Title"
      assert html =~ ~s(href="https://example.com/posts/1#comment-c2")
    end

    test "falls back to 'a post' label when post has no name" do
      html =
        render_component(&ActivityComponents.comment_group_activity/1,
          group: %{
            root: %{type: :post, url: "https://example.com/posts/2", name: nil},
            latest_comment_id: "c3",
            authors: [],
            latest_published_at_local: ~N[2026-05-26 10:00:00],
            latest_published_tz: "UTC",
            latest_at: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "commented on"
      assert html =~ "a post"
      assert html =~ ~s(href="https://example.com/posts/2#comment-c3")
    end

    test "falls back to generic label when root shape is unknown" do
      html =
        render_component(&ActivityComponents.comment_group_activity/1,
          group: %{
            root: %{foo: :bar},
            latest_comment_id: "c4",
            authors: [],
            latest_published_at_local: ~N[2026-05-26 10:00:00],
            latest_published_tz: "UTC",
            latest_at: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "commented on"
      assert html =~ "an entry"
      refute html =~ "#comment-c4"
    end

    test "shows replied to for replies to notes" do
      html =
        render_component(&ActivityComponents.comment_activity/1,
          comment: %{
            id: "c5",
            author: nil,
            in_reply_to: %{type: :note, author: nil},
            published_at_local: ~N[2026-05-26 10:00:00],
            published_tz: "UTC",
            published_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "replied to"
      refute html =~ "commented on"
    end
  end
end
