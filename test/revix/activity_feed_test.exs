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

    test "passes through non-like activities unchanged" do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      activities = [{:checkin, checkin}]
      grouped = ActivityFeed.group_activities(activities)

      assert [{:checkin, ^checkin}] = grouped
    end

    test "converts a single like into a like_group with count 1" do
      like = like_fixture(%{object_uri: "https://example.com/entries/abc"})
      grouped = ActivityFeed.group_activities([{:like, like}])

      assert [{:like_group, group}] = grouped
      assert group.count == 1
      assert group.object_uri == like.object_uri
    end

    test "groups two likes on the same object into one like_group with count 2" do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      person1 = person_fixture()
      person2 = person_fixture()
      like1 = like_fixture(%{author_uri: person1.uri, object_uri: checkin.uri})
      like2 = like_fixture(%{author_uri: person2.uri, object_uri: checkin.uri})

      grouped = ActivityFeed.group_activities([{:like, like1}, {:like, like2}])

      assert [{:like_group, group}] = grouped
      assert group.count == 2
      assert length(group.authors) == 2
    end

    test "keeps likes on different objects as separate like_groups" do
      place = place_fixture()
      checkin1 = checkin_fixture(%{place_uri: place.uri})
      checkin2 = checkin_fixture(%{place_uri: place.uri})

      person1 = person_fixture()
      person2 = person_fixture()
      like1 = like_fixture(%{author_uri: person1.uri, object_uri: checkin1.uri})
      like2 = like_fixture(%{author_uri: person2.uri, object_uri: checkin2.uri})

      grouped = ActivityFeed.group_activities([{:like, like1}, {:like, like2}])

      assert length(grouped) == 2
      assert Enum.all?(grouped, fn {type, _} -> type == :like_group end)
    end

    test "like_group latest_at is the most recent like's published_at_utc" do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      person1 = person_fixture()
      person2 = person_fixture()
      like1 = like_fixture(%{author_uri: person1.uri, object_uri: checkin.uri})

      # Ensure person2's like has a later timestamp
      :timer.sleep(1_100)
      like2 = like_fixture(%{author_uri: person2.uri, object_uri: checkin.uri})

      grouped = ActivityFeed.group_activities([{:like, like1}, {:like, like2}])
      assert [{:like_group, group}] = grouped

      assert DateTime.compare(group.latest_at, like1.published_at_utc) == :gt
    end

    test "converts a single comment into a comment_group with count 1" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "Hello"})

      grouped = ActivityFeed.group_activities([{:comment, comment}])

      assert [{:comment_group, group}] = grouped
      assert group.count == 1
      assert group.root_uri == checkin.uri
    end

    test "groups two comments on the same checkin into one comment_group with count 2" do
      scope1 = person_scope_fixture()
      scope2 = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment1 = create_comment(scope1, checkin, %{"content" => "First"})
      comment2 = create_comment(scope2, checkin, %{"content" => "Second"})

      grouped = ActivityFeed.group_activities([{:comment, comment1}, {:comment, comment2}])

      assert [{:comment_group, group}] = grouped
      assert group.count == 2
      assert length(group.authors) == 2
    end

    test "keeps comments on different checkins as separate comment_groups" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin1 = checkin_fixture(%{place_uri: place.uri})
      checkin2 = checkin_fixture(%{place_uri: place.uri})
      comment1 = create_comment(scope, checkin1, %{"content" => "On first"})
      comment2 = create_comment(scope, checkin2, %{"content" => "On second"})

      grouped = ActivityFeed.group_activities([{:comment, comment1}, {:comment, comment2}])

      assert length(grouped) == 2
      assert Enum.all?(grouped, fn {type, _} -> type == :comment_group end)
    end

    test "comment_group latest_at is the most recent comment's published_at_utc" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment1 = create_comment(scope, checkin, %{"content" => "First"})

      :timer.sleep(1_100)
      comment2 = create_comment(scope, checkin, %{"content" => "Second"})

      grouped = ActivityFeed.group_activities([{:comment, comment1}, {:comment, comment2}])
      assert [{:comment_group, group}] = grouped

      assert DateTime.compare(group.latest_at, comment1.published_at_utc) == :gt
    end

    test "groups a reply-to-comment with the original comment under the checkin root" do
      scope1 = person_scope_fixture()
      scope2 = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope1, checkin, %{"content" => "Top comment"})
      _reply = create_reply(scope2, comment, %{"content" => "A reply"})

      # Fetch with full preloads so in_reply_to chain is loaded on the reply
      activities = ActivityFeed.build_feed_activities(scope1, 50)
      comment_groups = for {:comment_group, g} <- activities, do: g

      assert length(comment_groups) == 1
      assert hd(comment_groups).root_uri == checkin.uri
      assert hd(comment_groups).count == 2
    end

    test "mixed activities (checkin + two likes on same checkin + two comments on same checkin) sorts correctly" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      like1 = like_fixture(%{object_uri: checkin.uri})
      like2 = like_fixture(%{object_uri: checkin.uri})
      comment1 = create_comment(scope, checkin, %{"content" => "Hello"})
      comment2 = create_comment(scope, checkin, %{"content" => "World"})

      activities = [
        {:checkin, checkin},
        {:like, like1},
        {:like, like2},
        {:comment, comment1},
        {:comment, comment2}
      ]

      grouped = ActivityFeed.group_activities(activities)

      # Should have checkin, one like_group, one comment_group = 3 items
      assert length(grouped) == 3
      types = Enum.map(grouped, &elem(&1, 0))
      assert :like_group in types
      assert :checkin in types
      assert :comment_group in types
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
      like_groups = for {:like_group, g} <- activities, do: g
      assert like_groups == []
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
      like_groups = for {:like_group, _} <- activities, do: :found
      assert :found in like_groups
    end

    test "excludes replies for unauthenticated scope" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "Top comment"})
      _reply = create_reply(scope, comment, %{"content" => "A reply"})

      activities = ActivityFeed.build_feed_activities(nil, 50)
      comment_groups = for {:comment_group, g} <- activities, do: g
      # Comment appears grouped under the checkin root
      assert Enum.any?(comment_groups, &(&1.root_uri == checkin.uri))
      # Reply is excluded entirely — no second group
      assert length(comment_groups) == 1
    end

    test "includes replies for authenticated scope and merges them into the same group" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "Top comment"})
      _reply = create_reply(scope, comment, %{"content" => "A reply"})

      activities = ActivityFeed.build_feed_activities(scope, 50)
      comment_groups = for {:comment_group, g} <- activities, do: g
      # Both comment and reply share checkin as root — one group with count 2
      assert length(comment_groups) == 1
      assert hd(comment_groups).root_uri == checkin.uri
      assert hd(comment_groups).count == 2
    end

    test "groups multiple local likes on same object" do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      person1 = person_fixture()
      person2 = person_fixture()
      like_fixture(%{author_uri: person1.uri, object_uri: checkin.uri})
      like_fixture(%{author_uri: person2.uri, object_uri: checkin.uri})

      activities = ActivityFeed.build_feed_activities(nil, 50)
      like_groups = for {:like_group, g} <- activities, g.object_uri == checkin.uri, do: g

      assert length(like_groups) == 1
      assert hd(like_groups).count == 2
    end

    test "groups multiple comments on the same checkin into one comment_group" do
      scope1 = person_scope_fixture()
      scope2 = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      create_comment(scope1, checkin, %{"content" => "First"})
      create_comment(scope2, checkin, %{"content" => "Second"})

      activities = ActivityFeed.build_feed_activities(nil, 50)

      comment_groups =
        for {:comment_group, g} <- activities, g.root_uri == checkin.uri, do: g

      assert length(comment_groups) == 1
      assert hd(comment_groups).count == 2
    end
  end

  # ── build_person_activities/3 ─────────────────────────────────────────────

  # ── comment_root_uri/1 ────────────────────────────────────────────────────

  describe "comment_root_uri/1" do
    test "returns in_reply_to_uri when in_reply_to association is not preloaded" do
      uri = "https://example.com/checkins/abc"
      assert ActivityFeed.comment_root_uri(%{in_reply_to_uri: uri}) == uri
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

  # ── activity_timestamp fallback via group_activities ──────────────────────

  describe "group_activities/1 — activity_timestamp checkin fallback" do
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

    test "excludes replies for unauthenticated scope" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "Top comment"})
      _reply = create_reply(scope, comment, %{"content" => "A reply"})

      activities = ActivityFeed.build_person_activities(scope.person, nil, 50)
      comment_groups = for {:comment_group, g} <- activities, do: g

      assert Enum.any?(comment_groups, &(&1.root_uri == checkin.uri))
      assert length(comment_groups) == 1
    end

    test "includes replies when scope matches person and merges into same group" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = create_comment(scope, checkin, %{"content" => "Top comment"})
      _reply = create_reply(scope, comment, %{"content" => "A reply"})

      activities = ActivityFeed.build_person_activities(scope.person, scope, 50)
      comment_groups = for {:comment_group, g} <- activities, do: g

      assert length(comment_groups) == 1
      assert hd(comment_groups).root_uri == checkin.uri
      assert hd(comment_groups).count == 2
    end

    test "groups likes by the person on the same object" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      like_fixture(%{author_uri: scope.person.uri, object_uri: checkin.uri})

      activities = ActivityFeed.build_person_activities(scope.person, nil, 50)
      like_groups = for {:like_group, g} <- activities, do: g

      assert length(like_groups) == 1
    end

    test "groups multiple comments by the person on the same checkin into one comment_group" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin1 = checkin_fixture(%{place_uri: place.uri})
      checkin2 = checkin_fixture(%{place_uri: place.uri})
      create_comment(scope, checkin1, %{"content" => "First on checkin1"})
      create_comment(scope, checkin1, %{"content" => "Second on checkin1"})
      create_comment(scope, checkin2, %{"content" => "Only on checkin2"})

      activities = ActivityFeed.build_person_activities(scope.person, nil, 50)
      comment_groups = for {:comment_group, g} <- activities, do: g

      # Two separate groups: one for each checkin
      assert length(comment_groups) == 2
      group1 = Enum.find(comment_groups, &(&1.root_uri == checkin1.uri))
      assert group1.count == 2
      group2 = Enum.find(comment_groups, &(&1.root_uri == checkin2.uri))
      assert group2.count == 1
    end
  end
end
