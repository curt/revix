defmodule RevixWeb.Live.ActivityFeedHelpersTest do
  use Revix.DataCase, async: true

  import Revix.PlacesFixtures
  import Revix.EntriesFixtures
  import Revix.LikesFixtures

  alias RevixWeb.Live.ActivityFeedHelpers, as: Helpers

  describe "next_cursor/2" do
    test "returns the current cursor when the page is empty" do
      assert Helpers.next_cursor([], nil) == nil
      assert Helpers.next_cursor([], ~U[2026-01-01 00:00:00Z]) == ~U[2026-01-01 00:00:00Z]
    end

    test "returns the activity_timestamp of the last activity in the page" do
      checkin = checkin_fixture(%{place_uri: place_fixture().uri})
      like = like_fixture(%{object_uri: checkin.uri})

      activities = [{:checkin, checkin}, {:like, like}]

      assert Helpers.next_cursor(activities, nil) == like.published_at_utc
    end
  end
end
