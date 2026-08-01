defmodule RevixWeb.Live.ActivityFeedHelpersTest do
  use Revix.DataCase, async: true

  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures
  import Revix.LikesFixtures

  alias Revix.Entries
  alias Revix.Likes
  alias RevixWeb.Live.ActivityFeedHelpers, as: Helpers

  defp fetch_like_with_object(like_id) do
    Likes.get_like_with_object(like_id)
  end

  defp fetch_comment(comment_id) do
    {:ok, comment} = Entries.get_comment_for_feed(comment_id)
    comment
  end

  describe "merge_like/3" do
    test "adds a new like_group when no existing group matches the object" do
      checkin = checkin_fixture(%{place_uri: place_fixture().uri})
      {:ok, like} = Likes.like_entry(person_scope_fixture(), checkin.uri, "UTC")
      full_like = fetch_like_with_object(like.id)

      activities = Helpers.merge_like([], 10, full_like)

      assert [{:like_group, group}] = activities
      assert group.object_uri == checkin.uri
      assert group.count == 1
    end

    test "merges into an existing like_group for the same object" do
      checkin = checkin_fixture(%{place_uri: place_fixture().uri})
      scope1 = person_scope_fixture()
      scope2 = person_scope_fixture()

      {:ok, like1} = Likes.like_entry(scope1, checkin.uri, "UTC")
      full_like1 = fetch_like_with_object(like1.id)
      activities = Helpers.merge_like([], 10, full_like1)

      {:ok, like2} = Likes.like_entry(scope2, checkin.uri, "UTC")
      full_like2 = fetch_like_with_object(like2.id)
      activities = Helpers.merge_like(activities, 10, full_like2)

      assert [{:like_group, group}] = activities
      assert group.count == 2
    end

    test "respects the limit by truncating the result", %{} do
      checkin1 = checkin_fixture(%{place_uri: place_fixture().uri})
      checkin2 = checkin_fixture(%{place_uri: place_fixture().uri})

      {:ok, like1} = Likes.like_entry(person_scope_fixture(), checkin1.uri, "UTC")
      full_like1 = fetch_like_with_object(like1.id)
      activities = Helpers.merge_like([{:checkin, checkin2}], 1, full_like1)

      assert length(activities) == 1
    end
  end

  describe "merge_comment/3" do
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

    test "adds a new comment_group when no existing group matches the root" do
      scope = person_scope_fixture()
      checkin = checkin_fixture(%{place_uri: place_fixture().uri})
      comment = create_comment(scope, checkin, %{"content" => "Hello"})
      full_comment = fetch_comment(comment.id)

      activities = Helpers.merge_comment([], 10, full_comment)

      assert [{:comment_group, group}] = activities
      assert group.root_uri == checkin.uri
      assert group.count == 1
    end

    test "merges into an existing comment_group for the same root" do
      scope1 = person_scope_fixture()
      scope2 = person_scope_fixture()
      checkin = checkin_fixture(%{place_uri: place_fixture().uri})

      comment1 = create_comment(scope1, checkin, %{"content" => "First"})
      activities = Helpers.merge_comment([], 10, fetch_comment(comment1.id))

      comment2 = create_comment(scope2, checkin, %{"content" => "Second"})
      activities = Helpers.merge_comment(activities, 10, fetch_comment(comment2.id))

      assert [{:comment_group, group}] = activities
      assert group.count == 2
    end
  end

  describe "next_cursor/2" do
    test "returns the current cursor when the page is empty" do
      assert Helpers.next_cursor([], nil) == nil
      assert Helpers.next_cursor([], ~U[2026-01-01 00:00:00Z]) == ~U[2026-01-01 00:00:00Z]
    end

    test "returns the activity_timestamp of the last activity in the page" do
      checkin = checkin_fixture(%{place_uri: place_fixture().uri})
      like = like_fixture(%{object_uri: checkin.uri})

      activities = [{:checkin, checkin}, {:like_group, %{latest_at: like.published_at_utc}}]

      assert Helpers.next_cursor(activities, nil) == like.published_at_utc
    end
  end
end
