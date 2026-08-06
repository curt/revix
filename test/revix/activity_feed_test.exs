defmodule Revix.ActivityFeedTest do
  use Revix.DataCase, async: true

  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures
  import Revix.LikesFixtures

  alias Revix.ActivityFeed
  alias Revix.Entries
  alias Revix.People.Scope

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

  # ── group_activities/1 ────────────────────────────────────────────────────

  describe "group_activities/1" do
    test "returns empty list for empty input" do
      assert ActivityFeed.group_activities([]) == []
    end

    test "passes through checkins unchanged" do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      activities = [{:checkin, checkin}]
      grouped = ActivityFeed.group_activities(activities)

      assert [{:checkin, ^checkin}] = grouped
    end

    test "passes through each like as its own entry" do
      like = like_fixture(%{object_uri: "https://example.com/entries/abc"})
      grouped = ActivityFeed.group_activities([{:like, like}])

      assert [{:like, ^like}] = grouped
    end

    test "keeps two likes on the same object as two separate entries" do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      person1 = person_fixture()
      person2 = person_fixture()
      like1 = like_fixture(%{author_uri: person1.uri, object_uri: checkin.uri})
      like2 = like_fixture(%{author_uri: person2.uri, object_uri: checkin.uri})

      grouped = ActivityFeed.group_activities([{:like, like1}, {:like, like2}])

      assert length(grouped) == 2
      assert Enum.all?(grouped, fn {type, _} -> type == :like end)
    end

    test "passes through each comment as its own entry" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "Hello"})

      grouped = ActivityFeed.group_activities([{:comment, comment}])

      assert [{:comment, ^comment}] = grouped
    end

    test "keeps two comments on the same checkin as two separate entries" do
      scope1 = person_scope_fixture()
      scope2 = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment1 = create_comment(scope1, checkin, %{"content" => "First"})
      comment2 = create_comment(scope2, checkin, %{"content" => "Second"})

      grouped = ActivityFeed.group_activities([{:comment, comment1}, {:comment, comment2}])

      assert length(grouped) == 2
      assert Enum.all?(grouped, fn {type, _} -> type == :comment end)
    end

    test "a reply-to-comment appears alongside the original comment, not merged" do
      scope1 = person_scope_fixture()
      scope2 = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope1, checkin, %{"content" => "Top comment"})
      reply = create_reply(scope2, comment, %{"content" => "A reply"})

      {activities, _has_more} = ActivityFeed.build_feed_activities(scope1, nil, 50)
      comment_ids = for {:comment, c} <- activities, do: c.id

      assert comment.id in comment_ids
      assert reply.id in comment_ids
    end

    test "sorts mixed activities by timestamp descending" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      like1 = like_fixture(%{object_uri: checkin.uri})
      :timer.sleep(1_100)
      like2 = like_fixture(%{object_uri: checkin.uri})
      comment1 = create_comment(scope, checkin, %{"content" => "Hello"})

      activities = [
        {:checkin, checkin},
        {:like, like1},
        {:like, like2},
        {:comment, comment1}
      ]

      grouped = ActivityFeed.group_activities(activities)

      # Every activity passes through — no merging into synthetic rows.
      assert length(grouped) == 4
      timestamps = Enum.map(grouped, &ActivityFeed.activity_timestamp/1)
      assert timestamps == Enum.sort(timestamps, {:desc, DateTime})
    end
  end

  # ── build_feed_activities/2 ───────────────────────────────────────────────

  describe "build_feed_activities/2" do
    test "includes local checkins for unauthenticated scope" do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      activities = ActivityFeed.build_feed_activities(nil, 50)
      checkin_ids = for {:checkin, c} <- activities, do: c.id
      assert checkin.id in checkin_ids
    end

    test "hides remote likes for unauthenticated scope" do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, _} =
        Revix.Likes.upsert_inbound_like(%{
          author_uri: "https://remote.example/users/alice",
          object_uri: checkin.uri,
          like_uri: "https://remote.example/likes/1"
        })

      activities = ActivityFeed.build_feed_activities(nil, 50)
      likes = for {:like, l} <- activities, do: l
      assert likes == []
    end

    test "includes remote likes for authenticated scope" do
      person = person_fixture()
      scope = Scope.for_person(person)
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, _} =
        Revix.Likes.upsert_inbound_like(%{
          author_uri: "https://remote.example/users/bob",
          object_uri: checkin.uri,
          like_uri: "https://remote.example/likes/2"
        })

      activities = ActivityFeed.build_feed_activities(scope, 50)
      assert Enum.any?(activities, fn {type, _} -> type == :like end)
    end

    test "excludes all comments for unauthenticated scope (including top-level)" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "Top comment"})
      _reply = create_reply(scope, comment, %{"content" => "A reply"})

      activities = ActivityFeed.build_feed_activities(nil, 50)
      comments = for {:comment, c} <- activities, do: c
      assert comments == []
    end

    test "includes replies for authenticated scope as their own entries" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "Top comment"})
      reply = create_reply(scope, comment, %{"content" => "A reply"})

      activities = ActivityFeed.build_feed_activities(scope, 50)
      comment_ids = for {:comment, c} <- activities, do: c.id
      assert comment.id in comment_ids
      assert reply.id in comment_ids
    end

    test "includes each local like on the same object as its own entry" do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      person1 = person_fixture()
      person2 = person_fixture()
      like_fixture(%{author_uri: person1.uri, object_uri: checkin.uri})
      like_fixture(%{author_uri: person2.uri, object_uri: checkin.uri})

      activities = ActivityFeed.build_feed_activities(nil, 50)
      likes = for {:like, l} <- activities, l.object_uri == checkin.uri, do: l

      assert length(likes) == 2
    end

    test "includes each comment on the same checkin as its own entry (authenticated)" do
      scope1 = person_scope_fixture()
      scope2 = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      create_comment(scope1, checkin, %{"content" => "First"})
      create_comment(scope2, checkin, %{"content" => "Second"})

      activities = ActivityFeed.build_feed_activities(scope1, 50)

      comments = for {:comment, c} <- activities, c.in_reply_to_uri == checkin.uri, do: c

      assert length(comments) == 2
    end

    test "includes posts for the home feed" do
      post = post_fixture()

      activities = ActivityFeed.build_feed_activities(nil, 50)
      post_ids = for {:post, p} <- activities, do: p.id
      assert post.id in post_ids
    end
  end

  # ── build_feed_activities/2 — unauthenticated filtering ──────────────────

  describe "build_feed_activities/2 — unauthenticated filtering" do
    test "excludes all comments for unauthenticated scope" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      create_comment(scope, checkin, %{"content" => "top level"})

      activities = ActivityFeed.build_feed_activities(nil, 50)
      assert Enum.all?(activities, fn {type, _} -> type != :comment end)
    end

    test "excludes likes on notes for unauthenticated scope" do
      scope = person_scope_fixture()
      liker = person_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "a comment"})
      like_fixture(%{author_uri: liker.uri, object_uri: comment.uri})

      activities = ActivityFeed.build_feed_activities(nil, 50)
      likes = for {:like, l} <- activities, do: l
      assert likes == []
    end

    test "includes likes on checkins for unauthenticated scope" do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      like_fixture(%{object_uri: checkin.uri})

      activities = ActivityFeed.build_feed_activities(nil, 50)
      likes = for {:like, l} <- activities, do: l
      assert length(likes) == 1
    end

    test "includes comments and note-likes for authenticated scope" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "a comment"})
      like_fixture(%{object_uri: comment.uri})

      activities = ActivityFeed.build_feed_activities(scope, 50)
      assert Enum.any?(activities, fn {type, _} -> type == :comment end)
      assert Enum.any?(activities, fn {type, _} -> type == :like end)
    end

    test "like on a note-like has :object pointing to the comment" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "a comment"})
      like_fixture(%{object_uri: comment.uri})

      activities = ActivityFeed.build_feed_activities(scope, 50)
      likes = for {:like, l} <- activities, do: l
      assert length(likes) == 1
      like = hd(likes)
      assert like.object != nil
      assert like.object.id == comment.id
    end

    test "like on a checkin has :object pointing to the checkin" do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      like_fixture(%{object_uri: checkin.uri})

      activities = ActivityFeed.build_feed_activities(nil, 50)
      likes = for {:like, l} <- activities, do: l
      assert length(likes) == 1
      assert hd(likes).object.id == checkin.id
    end
  end

  # ── build_person_activities/3 — unauthenticated filtering ────────────────

  describe "build_person_activities/3 — unauthenticated filtering" do
    test "excludes all comments for unauthenticated scope" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      create_comment(scope, checkin, %{"content" => "top level"})

      activities = ActivityFeed.build_person_activities(scope.person, nil, 50)
      assert Enum.all?(activities, fn {type, _} -> type != :comment end)
    end

    test "excludes likes on notes for unauthenticated scope" do
      scope = person_scope_fixture()
      liker = person_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "a comment"})
      like_fixture(%{author_uri: liker.uri, object_uri: comment.uri})

      activities = ActivityFeed.build_person_activities(scope.person, nil, 50)
      likes = for {:like, l} <- activities, do: l
      assert likes == []
    end

    test "includes comments and note-likes for authenticated scope" do
      scope = person_scope_fixture()
      other_scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      _comment = create_comment(scope, checkin, %{"content" => "my comment"})
      other_comment = create_comment(other_scope, checkin, %{"content" => "other comment"})
      like_fixture(%{author_uri: scope.person.uri, object_uri: other_comment.uri})

      activities = ActivityFeed.build_person_activities(scope.person, scope, 50)
      assert Enum.any?(activities, fn {type, _} -> type == :comment end)
      assert Enum.any?(activities, fn {type, _} -> type == :like end)
    end

    test "includes posts for the unauthenticated person feed" do
      scope = person_scope_fixture()
      post = post_fixture(%{author_uri: scope.person.uri})

      activities = ActivityFeed.build_person_activities(scope.person, nil, 50)
      post_ids = for {:post, p} <- activities, do: p.id
      assert post.id in post_ids
    end
  end

  # ── comment_root_uri/1 ────────────────────────────────────────────────────

  describe "comment_root_uri/1" do
    test "returns in_reply_to_uri when in_reply_to association is not preloaded" do
      uri = "https://example.com/checkins/abc"
      assert ActivityFeed.comment_root_uri(%{in_reply_to_uri: uri}) == uri
    end

    test "resolves root URI by walking in_reply_to_uri chain for deep replies" do
      scope = person_scope_fixture()
      other_scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "level 1"})
      reply = create_reply(other_scope, comment, %{"content" => "level 2"})
      deep_reply = create_reply(scope, reply, %{"content" => "level 3"})

      assert ActivityFeed.comment_root_uri(%{in_reply_to_uri: deep_reply.uri}) == checkin.uri
    end
  end

  # ── comment_root/1 ────────────────────────────────────────────────────────

  describe "comment_root/1" do
    test "returns nil when in_reply_to is nil" do
      assert ActivityFeed.comment_root(%{in_reply_to: nil}) == nil
    end

    test "returns nil for a struct without in_reply_to key (catch-all clause)" do
      assert ActivityFeed.comment_root(%{in_reply_to_uri: "https://example.com/checkins/x"}) ==
               nil
    end
  end

  # ── comment_root/1 — resolves root entry for a note-like's :object ─────────

  describe "comment_root/1 — note-like root entry resolution" do
    test "resolves root entry to the checkin for a note-like" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "hi"})

      like_fixture(%{object_uri: comment.uri})
      [like] = Revix.Likes.get_recent_likes(10, include_remote: true)

      root = ActivityFeed.comment_root(like.object)
      assert root != nil
      assert root.id == checkin.id
    end

    test "returns nil root entry for a checkin-like (object.in_reply_to is nil)" do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      like_fixture(%{object_uri: checkin.uri})
      [like] = Revix.Likes.get_recent_likes(10, include_remote: true)

      assert ActivityFeed.comment_root(like.object) == nil
    end

    test "resolves root entry via context fallback for a deep note-like" do
      scope = person_scope_fixture()
      other_scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "level 1"})
      reply = create_reply(other_scope, comment, %{"content" => "level 2"})
      deep_reply = create_reply(scope, reply, %{"content" => "level 3"})

      like_fixture(%{author_uri: other_scope.person.uri, object_uri: deep_reply.uri})
      [like] = Revix.Likes.get_recent_likes(10, include_remote: true)

      root = ActivityFeed.comment_root(like.object)
      assert root != nil
      assert root.id == checkin.id
      assert match?(%Revix.Places.Place{}, root.place)
    end
  end

  # ── activity_timestamp/1 ───────────────────────────────────────────────────

  describe "activity_timestamp/1" do
    test "sorts checkin by published_at_utc when starts_at_utc is nil" do
      earlier = %Revix.Entries.Entry{
        id: "aaa",
        type: :checkin,
        starts_at_utc: nil,
        published_at_utc: ~U[2026-01-01 10:00:00Z],
        published_at_local: ~N[2026-01-01 10:00:00],
        published_tz: "UTC",
        updated_at: ~U[2026-01-01 10:00:00Z]
      }

      later = %Revix.Entries.Entry{
        id: "bbb",
        type: :checkin,
        starts_at_utc: nil,
        published_at_utc: ~U[2026-06-01 10:00:00Z],
        published_at_local: ~N[2026-06-01 10:00:00],
        published_tz: "UTC",
        updated_at: ~U[2026-06-01 10:00:00Z]
      }

      [{:checkin, first} | _] =
        ActivityFeed.group_activities([{:checkin, earlier}, {:checkin, later}])

      assert first.id == "bbb"
    end
  end

  # ── build_person_activities/3 — draft visibility ──────────────────────────

  describe "build_person_activities/3 — draft visibility" do
    test "excludes drafts when scope person does not match the viewed person" do
      scope = person_scope_fixture()
      other_scope = person_scope_fixture()
      _draft = draft_post_fixture(%{author_uri: other_scope.person.uri})

      activities = ActivityFeed.build_person_activities(other_scope.person, scope, 50)
      assert Enum.all?(activities, fn {type, _} -> type != :draft end)
    end

    test "includes drafts when scope person matches the viewed person" do
      scope = person_scope_fixture()
      draft = draft_post_fixture(%{author_uri: scope.person.uri})

      activities = ActivityFeed.build_person_activities(scope.person, scope, 50)
      draft_ids = for {:draft, d} <- activities, do: d.id
      assert draft.id in draft_ids
    end
  end

  describe "build_person_activities/3" do
    test "only includes activities by the given person" do
      scope = person_scope_fixture()
      other_scope = person_scope_fixture()
      place = place_fixture()
      my_checkin = checkin_fixture(%{place_uri: place.uri, author_uri: scope.person.uri})
      other_checkin = checkin_fixture(%{place_uri: place.uri, author_uri: other_scope.person.uri})

      activities = ActivityFeed.build_person_activities(scope.person, nil, 50)
      checkin_ids = for {:checkin, c} <- activities, do: c.id

      assert my_checkin.id in checkin_ids
      refute other_checkin.id in checkin_ids
    end

    test "only includes posts by the given person" do
      scope = person_scope_fixture()
      other_scope = person_scope_fixture()
      my_post = post_fixture(%{author_uri: scope.person.uri})
      other_post = post_fixture(%{author_uri: other_scope.person.uri})

      activities = ActivityFeed.build_person_activities(scope.person, nil, 50)
      post_ids = for {:post, p} <- activities, do: p.id

      assert my_post.id in post_ids
      refute other_post.id in post_ids
    end

    test "excludes all comments for unauthenticated scope (including top-level)" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "Top comment"})
      _reply = create_reply(scope, comment, %{"content" => "A reply"})

      activities = ActivityFeed.build_person_activities(scope.person, nil, 50)
      comments = for {:comment, c} <- activities, do: c
      assert comments == []
    end

    test "includes replies when scope matches person as their own entries" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "Top comment"})
      reply = create_reply(scope, comment, %{"content" => "A reply"})

      activities = ActivityFeed.build_person_activities(scope.person, scope, 50)
      comment_ids = for {:comment, c} <- activities, do: c.id

      assert comment.id in comment_ids
      assert reply.id in comment_ids
    end

    test "includes each like by the person on the same object as its own entry" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin1 = checkin_fixture(%{place_uri: place.uri})
      checkin2 = checkin_fixture(%{place_uri: place.uri})
      like_fixture(%{author_uri: scope.person.uri, object_uri: checkin1.uri})
      like_fixture(%{author_uri: scope.person.uri, object_uri: checkin2.uri})

      activities = ActivityFeed.build_person_activities(scope.person, nil, 50)
      likes = for {:like, l} <- activities, do: l

      assert length(likes) == 2
    end

    test "includes each comment by the person on the same checkin as its own entry" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin1 = checkin_fixture(%{place_uri: place.uri})
      checkin2 = checkin_fixture(%{place_uri: place.uri})
      create_comment(scope, checkin1, %{"content" => "First on checkin1"})
      create_comment(scope, checkin1, %{"content" => "Second on checkin1"})
      create_comment(scope, checkin2, %{"content" => "Only on checkin2"})

      activities = ActivityFeed.build_person_activities(scope.person, scope, 50)
      comments = for {:comment, c} <- activities, do: c

      assert length(comments) == 3
      on_checkin1 = Enum.count(comments, &(&1.in_reply_to_uri == checkin1.uri))
      assert on_checkin1 == 2
    end
  end

  # ── build_feed_activities/3 — cursor pagination ───────────────────────────

  describe "build_feed_activities/3 — cursor pagination" do
    defp checkin_at(place, offset_seconds) do
      time = DateTime.add(DateTime.utc_now(:second), offset_seconds, :second)

      checkin_fixture(%{
        place_uri: place.uri,
        starts_at_utc: time,
        published_at_utc: time
      })
    end

    test "first page returns page_size items and has_more true when more exist" do
      place = place_fixture()
      for i <- 1..5, do: checkin_at(place, -i)

      {activities, has_more} = ActivityFeed.build_feed_activities(nil, nil, 3)

      assert length(activities) == 3
      assert has_more == true
    end

    test "second page (cursor from first page) returns the next items with no overlap" do
      place = place_fixture()
      checkins = for i <- 5..1//-1, do: checkin_at(place, -i)
      checkin_ids = Enum.map(checkins, & &1.id) |> MapSet.new()

      {page1, true} = ActivityFeed.build_feed_activities(nil, nil, 3)
      cursor = page1 |> List.last() |> ActivityFeed.activity_timestamp()

      {page2, has_more} = ActivityFeed.build_feed_activities(nil, cursor, 3)

      page1_ids = for {:checkin, c} <- page1, do: c.id
      page2_ids = for {:checkin, c} <- page2, do: c.id

      assert MapSet.disjoint?(MapSet.new(page1_ids), MapSet.new(page2_ids))
      assert length(page2_ids) == 2
      assert has_more == false
      assert MapSet.new(page1_ids ++ page2_ids) == checkin_ids
    end

    test "has_more is false on the last page" do
      place = place_fixture()
      for i <- 1..2, do: checkin_at(place, -i)

      {activities, has_more} = ActivityFeed.build_feed_activities(nil, nil, 10)

      assert length(activities) == 2
      assert has_more == false
    end

    test "returns empty page and has_more false past the end of data" do
      place = place_fixture()
      checkin_at(place, -1)

      {page1, _} = ActivityFeed.build_feed_activities(nil, nil, 10)
      cursor = page1 |> List.last() |> ActivityFeed.activity_timestamp()

      {activities, has_more} = ActivityFeed.build_feed_activities(nil, cursor, 10)

      assert activities == []
      assert has_more == false
    end

    test "drafts are only included on the first page" do
      scope = person_scope_fixture()
      place = place_fixture()
      draft = draft_post_fixture(%{author_uri: scope.person.uri})
      for i <- 1..3, do: checkin_at(place, -i)

      {page1, true} = ActivityFeed.build_feed_activities(scope, nil, 2)
      cursor = page1 |> List.last() |> ActivityFeed.activity_timestamp()
      {page2, _has_more} = ActivityFeed.build_feed_activities(scope, cursor, 2)

      draft_ids_page1 = for {:draft, d} <- page1, do: d.id
      draft_ids_page2 = for {:draft, d} <- page2, do: d.id

      assert draft.id in draft_ids_page1
      assert draft_ids_page2 == []
    end
  end

  # ── build_person_activities/4 — cursor pagination ─────────────────────────

  describe "build_person_activities/4 — cursor pagination" do
    test "second page returns items older than the cursor with no overlap" do
      scope = person_scope_fixture()
      place = place_fixture()

      checkins =
        for i <- 5..1//-1 do
          time = DateTime.add(DateTime.utc_now(:second), -i, :second)

          checkin_fixture(%{
            place_uri: place.uri,
            author_uri: scope.person.uri,
            starts_at_utc: time,
            published_at_utc: time
          })
        end

      checkin_ids = checkins |> Enum.map(& &1.id) |> MapSet.new()

      {page1, true} = ActivityFeed.build_person_activities(scope.person, nil, nil, 3)
      cursor = page1 |> List.last() |> ActivityFeed.activity_timestamp()

      {page2, has_more} = ActivityFeed.build_person_activities(scope.person, nil, cursor, 3)

      page1_ids = for {:checkin, c} <- page1, do: c.id
      page2_ids = for {:checkin, c} <- page2, do: c.id

      assert MapSet.disjoint?(MapSet.new(page1_ids), MapSet.new(page2_ids))
      assert has_more == false
      assert MapSet.new(page1_ids ++ page2_ids) == checkin_ids
    end

    test "posts are included in paginated pages" do
      scope = person_scope_fixture()
      post = post_fixture(%{author_uri: scope.person.uri})

      {page1, _has_more} = ActivityFeed.build_person_activities(scope.person, nil, nil, 50)
      post_ids = for {:post, p} <- page1, do: p.id
      assert post.id in post_ids
    end
  end

  # ── take_page/2 ────────────────────────────────────────────────────────────

  describe "take_page/2" do
    test "splits a probe-sized list into page and has_more" do
      {page, has_more} = ActivityFeed.take_page([1, 2, 3, 4], 3)
      assert page == [1, 2, 3]
      assert has_more == true
    end

    test "has_more is false when the list is exactly page_size" do
      {page, has_more} = ActivityFeed.take_page([1, 2, 3], 3)
      assert page == [1, 2, 3]
      assert has_more == false
    end
  end
end
