defmodule RevixWeb.ActivityComponentsTest do
  use RevixWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Revix.PeopleFixtures

  alias RevixWeb.ActivityComponents

  describe "activity_feed/1" do
    test "renders all activity variants" do
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
        {:like_group,
         %{
           object: %{
             type: :checkin,
             place: %{name: "Cafe"},
             url: "https://example.com/checkins/1"
           },
           root_entry: nil,
           authors: [author],
           latest_published_at_local: now_local,
           latest_published_tz: "UTC",
           latest_at: now_utc
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
         }},
        {:comment_group,
         %{
           root: %{type: :post, url: "https://example.com/posts/9", name: "Root Post"},
           latest_comment_id: "cg-feed",
           authors: [author],
           latest_published_at_local: now_local,
           latest_published_tz: "UTC",
           latest_at: now_utc
         }}
      ]

      html = render_component(&ActivityComponents.activity_feed/1, activities: activities)

      assert html =~ "checked into"
      assert html =~ "posted"
      assert html =~ "Draft"
      assert html =~ "liked"
      assert html =~ "commented on"
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
  end

  describe "like_group activity targets" do
    test "renders root_entry post fallback label" do
      html =
        render_component(&ActivityComponents.like_group_activity/1,
          group: %{
            root_entry: %{
              type: :post,
              url: "https://example.com/posts/root",
              name: nil,
              place: nil
            },
            object: nil,
            authors: [],
            latest_published_at_local: ~N[2026-05-26 10:00:00],
            latest_published_tz: "UTC",
            latest_at: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "liked a comment on"
      assert html =~ "a post"
    end

    test "falls back to a checkin when object has no place and no root_entry" do
      html =
        render_component(&ActivityComponents.like_group_activity/1,
          group: %{
            root_entry: nil,
            object: %{type: :checkin, url: "https://example.com/checkins/1", place: nil},
            authors: [],
            latest_published_at_local: ~N[2026-05-26 10:00:00],
            latest_published_tz: "UTC",
            latest_at: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "liked"
      assert html =~ "a checkin"
    end

    test "renders root_entry checkin place when present" do
      html =
        render_component(&ActivityComponents.like_group_activity/1,
          group: %{
            root_entry: %{
              type: :checkin,
              url: "https://example.com/checkins/root",
              place: %{name: "Root Cafe"}
            },
            object: nil,
            authors: [],
            latest_published_at_local: ~N[2026-05-26 10:00:00],
            latest_published_tz: "UTC",
            latest_at: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "liked a comment on"
      assert html =~ "Root Cafe"
    end

    test "falls back when root_entry place association is not loaded" do
      html =
        render_component(&ActivityComponents.like_group_activity/1,
          group: %{
            root_entry: %{
              type: :checkin,
              url: "https://example.com/checkins/root",
              place: %Ecto.Association.NotLoaded{
                __field__: :place,
                __owner__: Revix.Entries.Entry,
                __cardinality__: :one
              },
              name: nil
            },
            object: nil,
            authors: [],
            latest_published_at_local: ~N[2026-05-26 10:00:00],
            latest_published_tz: "UTC",
            latest_at: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "liked a comment on"
      assert html =~ "a post"
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

    test "checkin without place falls back to somewhere/name without timestamp" do
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
      refute html =~ "2026-05-26"
    end

    test "draft activity renders badge and updated date" do
      html =
        render_component(&ActivityComponents.draft_activity/1,
          post: %{
            author: nil,
            url: "https://example.com/posts/2",
            name: "Draft Post",
            updated_at: ~N[2026-05-26 11:00:00]
          }
        )

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
    test "avatar_group renders overflow count" do
      authors = for _ <- 1..4, do: person_fixture()
      html = render_component(&ActivityComponents.avatar_group/1, authors: authors, max: 3)
      assert html =~ "+1"
    end

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

    test "uses checkin fallback label when comment-group root checkin has no place" do
      html =
        render_component(&ActivityComponents.comment_group_activity/1,
          group: %{
            root: %{type: :checkin, url: "https://example.com/checkins/3", place: nil},
            latest_comment_id: "c7",
            authors: [],
            latest_published_at_local: ~N[2026-05-26 10:00:00],
            latest_published_tz: "UTC",
            latest_at: ~U[2026-05-26 10:00:00Z]
          }
        )

      assert html =~ "commented on"
      assert html =~ "a checkin"
      assert html =~ ~s(href="https://example.com/checkins/3#comment-c7")
    end

    test "does not build comment anchor when latest_comment_id is not a binary" do
      html =
        render_component(&ActivityComponents.comment_group_activity/1,
          group: %{
            root: %{type: :post, url: "https://example.com/posts/7", name: "Post Seven"},
            latest_comment_id: nil,
            authors: [],
            latest_published_at_local: ~N[2026-05-26 10:00:00],
            latest_published_tz: "UTC",
            latest_at: ~U[2026-05-26 10:00:00Z]
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
