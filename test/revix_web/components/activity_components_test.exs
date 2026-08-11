defmodule RevixWeb.ActivityComponentsTest do
  use RevixWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Revix.PeopleFixtures

  alias RevixWeb.ActivityComponents

  describe "activity_feed/1" do
    test "renders all activity variants as timeline rows" do
      now_local = ~N[2026-05-26 10:00:00]
      now_utc = ~U[2026-05-26 10:00:00Z]
      author = person_fixture()

      activities = [
        {:checkin,
         %{
           author: author,
           url: "https://example.com/checkins/1",
           place: %{name: "Cafe"},
           companions: [],
           starts_at_local: now_local,
           starts_tz: "UTC",
           starts_at_utc: now_utc
         }},
        {:post,
         %{
           author: author,
           url: "https://example.com/posts/1",
           name: "Post One",
           published_at_local: now_local,
           published_tz: "UTC",
           published_at_utc: now_utc
         }},
        {:draft,
         %{
           type: :post,
           author: author,
           url: "https://example.com/posts/2",
           name: "Draft One",
           updated_at: ~N[2026-05-26 11:00:00]
         }},
        {:like,
         %{
           author: author,
           object: %{
             type: :checkin,
             place: %{name: "Cafe"},
             url: "https://example.com/checkins/1"
           },
           published_at_local: now_local,
           published_tz: "UTC",
           published_at_utc: now_utc
         }},
        {:comment,
         %{
           id: "c-feed",
           author: author,
           in_reply_to: %{
             type: :checkin,
             url: "https://example.com/checkins/1",
             place: %{name: "Cafe"}
           },
           published_at_local: now_local,
           published_tz: "UTC",
           published_at_utc: now_utc
         }}
      ]

      html = render_component(&ActivityComponents.activity_feed/1, activities: activities)

      assert html =~ "checked into"
      assert html =~ "posted"
      assert html =~ "Draft"
      assert html =~ "liked"
      assert html =~ "commented on"
    end

    test "renders one <li> per activity with timeline structure" do
      author = person_fixture()
      now_local = ~N[2026-05-26 10:00:00]
      now_utc = ~U[2026-05-26 10:00:00Z]

      activities = [
        {:post,
         %{
           author: author,
           url: "https://example.com/posts/1",
           name: "First",
           published_at_local: now_local,
           published_tz: "UTC",
           published_at_utc: now_utc
         }},
        {:post,
         %{
           author: author,
           url: "https://example.com/posts/2",
           name: "Second",
           published_at_local: now_local,
           published_tz: "UTC",
           published_at_utc: now_utc
         }}
      ]

      html = render_component(&ActivityComponents.activity_feed/1, activities: activities)

      assert html =~ "timeline timeline-vertical"
      assert html =~ "timeline-start"
      assert html =~ "timeline-middle"
      assert (html |> String.split("<li") |> length()) - 1 == 2
    end

    test "renders no like_group or comment_group markup" do
      html = render_component(&ActivityComponents.activity_feed/1, activities: [])
      refute html =~ "like_group"
      refute html =~ "comment_group"
    end
  end

  describe "like activity targets" do
    test "renders liked comment path for note likes" do
      html =
        render_component(&ActivityComponents.like_activity/1,
          like: %{
            author: nil,
            object: %{type: :note, url: "https://example.com/notes/1"},
            published_at_local: ~N[2026-05-26 10:00:00],
            published_tz: "UTC",
            published_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "liked"
      assert html =~ "a comment"
    end

    test "falls back to a checkin label when object has no place" do
      html =
        render_component(&ActivityComponents.like_activity/1,
          like: %{
            author: nil,
            object: %{type: :checkin, url: "https://example.com/checkins/1", place: nil},
            published_at_local: ~N[2026-05-26 10:00:00],
            published_tz: "UTC",
            published_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "a checkin"
    end

    test "never shows a snippet, even when the liked object has content" do
      html =
        render_component(&ActivityComponents.like_activity/1,
          like: %{
            author: nil,
            object: %{
              type: :checkin,
              url: "https://example.com/checkins/1",
              place: nil,
              content: "This should never appear"
            },
            published_at_local: ~N[2026-05-26 10:00:00],
            published_tz: "UTC",
            published_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      refute html =~ "This should never appear"
      refute html =~ "text-xs italic opacity-50"
    end
  end

  describe "checkin/post/draft rendering details" do
    test "checkin companions show overflow badge" do
      companions = for _ <- 1..6, do: %{person: person_fixture()}

      html =
        render_component(&ActivityComponents.checkin_activity/1,
          checkin: %{
            author: person_fixture(),
            place: %{name: "Cafe"},
            url: "https://example.com/checkins/1",
            companions: companions,
            starts_at_local: ~N[2026-05-26 10:00:00],
            starts_tz: "UTC",
            starts_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "with"
      assert html =~ "+1"
    end

    test "companions render before the content snippet" do
      companion = person_fixture()

      html =
        render_component(&ActivityComponents.checkin_activity/1,
          checkin: %{
            author: person_fixture(),
            place: %{name: "Cafe"},
            url: "https://example.com/checkins/1",
            companions: [%{person: companion}],
            content: "Great coffee.",
            starts_at_local: ~N[2026-05-26 10:00:00],
            starts_tz: "UTC",
            starts_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      with_index = :binary.match(html, "with") |> elem(0)
      snippet_index = :binary.match(html, "Great coffee.") |> elem(0)
      assert with_index < snippet_index
    end

    test "checkin without place falls back to somewhere/name" do
      html =
        render_component(&ActivityComponents.checkin_activity/1,
          checkin: %{
            author: nil,
            place: nil,
            name: nil,
            companions: [],
            starts_at_local: ~N[2026-05-26 10:00:00],
            starts_tz: "UTC",
            starts_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "somewhere"
    end

    test "checkin with content shows a snippet" do
      html =
        render_component(&ActivityComponents.checkin_activity/1,
          checkin: %{
            author: nil,
            url: "https://example.com/checkins/1",
            place: %{name: "Cafe"},
            name: nil,
            companions: [],
            content: "Great coffee and even better pastries.",
            starts_at_local: ~N[2026-05-26 10:00:00],
            starts_tz: "UTC",
            starts_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "Great coffee and even better pastries."
    end

    test "checkin without content shows no snippet" do
      html =
        render_component(&ActivityComponents.checkin_activity/1,
          checkin: %{
            author: nil,
            url: "https://example.com/checkins/1",
            place: %{name: "Cafe"},
            name: nil,
            companions: [],
            content: nil,
            starts_at_local: ~N[2026-05-26 10:00:00],
            starts_tz: "UTC",
            starts_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      refute html =~ "text-xs italic opacity-50"
    end

    test "post with content shows a snippet" do
      html =
        render_component(&ActivityComponents.post_activity/1,
          post: %{
            author: nil,
            url: "https://example.com/posts/1",
            name: "My Trip",
            content: "We drove up the coast and stopped for lunch."
          }
        )

      assert html =~ "We drove up the coast and stopped for lunch."
    end

    test "snippet renders the same typography as content_html (dashes and smart quotes)" do
      html =
        render_component(&ActivityComponents.checkin_activity/1,
          checkin: %{
            author: nil,
            url: "https://example.com/checkins/1",
            place: %{name: "Cafe"},
            name: nil,
            companions: [],
            content: ~s(Getting --- "toasty!"),
            starts_at_local: ~N[2026-05-26 10:00:00],
            starts_tz: "UTC",
            starts_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "Getting — “toasty!”"
      refute html =~ "---"
      refute html =~ ~s("toasty)
    end

    test "snippet does not double-escape HTML entities" do
      html =
        render_component(&ActivityComponents.checkin_activity/1,
          checkin: %{
            author: nil,
            url: "https://example.com/checkins/1",
            place: %{name: "Cafe"},
            name: nil,
            companions: [],
            content: "Salt & pepper",
            starts_at_local: ~N[2026-05-26 10:00:00],
            starts_tz: "UTC",
            starts_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "Salt &amp; pepper"
      refute html =~ "&amp;amp;"
    end

    test "long content is truncated with an ellipsis" do
      long_content = Enum.map_join(1..50, " ", fn i -> "word#{i}" end)

      html =
        render_component(&ActivityComponents.post_activity/1,
          post: %{
            author: nil,
            url: "https://example.com/posts/1",
            name: "My Trip",
            content: long_content
          }
        )

      assert html =~ "…"
      refute html =~ "word50"
    end

    test "draft activity content links to the post" do
      html =
        render_component(&ActivityComponents.draft_activity/1,
          post: %{
            author: nil,
            url: "https://example.com/posts/2",
            name: "Draft Post"
          }
        )

      assert html =~ "drafted"
      assert html =~ "Draft Post"
    end

    test "draft badge and updated date render via the timeline start slot" do
      author = person_fixture()

      activities = [
        {:draft,
         %{
           type: :post,
           author: author,
           url: "https://example.com/posts/2",
           name: "Draft Post",
           updated_at: ~N[2026-05-26 11:00:00]
         }}
      ]

      html = render_component(&ActivityComponents.activity_feed/1, activities: activities)

      assert html =~ "Draft"
      assert html =~ "Updated 2026-05-26"
    end
  end

  describe "avatar_image/1" do
    test "renders a 64x64 img with the person's avatar" do
      person = person_fixture()
      html = render_component(&ActivityComponents.avatar_image/1, person: person)

      assert html =~ ~s(width="64")
      assert html =~ ~s(height="64")
    end

    test "defaults alt to display name" do
      {:ok, person} =
        person_fixture() |> Revix.People.update_person_display_name(%{display_name: "Erin"})

      html = render_component(&ActivityComponents.avatar_image/1, person: person)
      assert html =~ ~s(alt="Erin")
    end

    test "defaults alt to username when display name is blank" do
      person =
        person_fixture()
        |> Ecto.Changeset.change(username: "frank")
        |> Revix.Repo.update!()

      html = render_component(&ActivityComponents.avatar_image/1, person: person)
      assert html =~ ~s(alt="frank")
    end

    test "defaults alt to empty string when display name and username are both blank" do
      person = person_fixture()
      html = render_component(&ActivityComponents.avatar_image/1, person: person)
      assert html =~ ~s(alt="")
    end

    test "explicit alt attr overrides the default" do
      person = person_fixture()
      html = render_component(&ActivityComponents.avatar_image/1, person: person, alt: "Custom")

      assert html =~ ~s(alt="Custom")
    end
  end

  describe "avatar helpers" do
    test "activity_avatar renders nothing for nil author" do
      html = render_component(&ActivityComponents.activity_avatar/1, author: nil)
      assert html == ""
    end

    test "activity_avatar sets alt to the author's display name" do
      {:ok, author} =
        person_fixture() |> Revix.People.update_person_display_name(%{display_name: "Erin"})

      html = render_component(&ActivityComponents.activity_avatar/1, author: author)
      assert html =~ ~s(alt="Erin")
    end

    test "activity_avatar falls back to username for alt when display name is blank" do
      author =
        person_fixture()
        |> Ecto.Changeset.change(username: "frank")
        |> Revix.Repo.update!()

      html = render_component(&ActivityComponents.activity_avatar/1, author: author)
      assert html =~ ~s(alt="frank")
    end
  end

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

    test "shows a snippet of the comment's own content" do
      html =
        render_component(&ActivityComponents.comment_activity/1,
          comment: %{
            id: "c-snip",
            author: nil,
            content: "Totally agree with this take.",
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

      assert html =~ "Totally agree with this take."
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
        render_component(&ActivityComponents.comment_activity/1,
          comment: %{
            id: "c3",
            author: nil,
            in_reply_to: %{type: :post, url: "https://example.com/posts/2", name: nil},
            published_at_local: ~N[2026-05-26 10:00:00],
            published_tz: "UTC",
            published_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "commented on"
      assert html =~ "a post"
      assert html =~ ~s(href="https://example.com/posts/2#comment-c3")
    end

    test "falls back to generic label when in_reply_to shape is unknown" do
      html =
        render_component(&ActivityComponents.comment_activity/1,
          comment: %{
            id: "c4",
            author: nil,
            in_reply_to: %{type: :other_thing, url: "https://example.com/x"},
            published_at_local: ~N[2026-05-26 10:00:00],
            published_tz: "UTC",
            published_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "commented on"
      assert html =~ "an entry"
    end

    test "uses checkin fallback label when comment root checkin has no place" do
      html =
        render_component(&ActivityComponents.comment_activity/1,
          comment: %{
            id: "c7",
            author: nil,
            in_reply_to: %{type: :checkin, url: "https://example.com/checkins/3", place: nil},
            published_at_local: ~N[2026-05-26 10:00:00],
            published_tz: "UTC",
            published_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "commented on"
      assert html =~ "a checkin"
      assert html =~ ~s(href="https://example.com/checkins/3#comment-c7")
    end

    test "does not build comment anchor when comment id is not a binary" do
      html =
        render_component(&ActivityComponents.comment_activity/1,
          comment: %{
            id: nil,
            author: nil,
            in_reply_to: %{type: :post, url: "https://example.com/posts/7", name: "Post Seven"},
            published_at_local: ~N[2026-05-26 10:00:00],
            published_tz: "UTC",
            published_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "commented on"
      assert html =~ "Post Seven"
      refute html =~ "#comment-"
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

    test "walks nested note parents and links to root checkin" do
      html =
        render_component(&ActivityComponents.comment_activity/1,
          comment: %{
            id: "c6",
            author: nil,
            in_reply_to: %{
              type: :note,
              in_reply_to: %{
                type: :note,
                in_reply_to: %{
                  type: :checkin,
                  url: "https://example.com/checkins/root",
                  place: %{name: "Root Place"}
                }
              }
            },
            published_at_local: ~N[2026-05-26 10:00:00],
            published_tz: "UTC",
            published_at_utc: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "commented on"
      assert html =~ "Root Place"
      assert html =~ ~s(href="https://example.com/checkins/root#comment-c6")
    end
  end
end
