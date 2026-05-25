defmodule Revix.LikesTest do
  use Revix.DataCase, async: true

  import Revix.PeopleFixtures
  import Revix.EntriesFixtures
  import Revix.PlacesFixtures

  alias Revix.Likes
  alias Revix.Likes.Like

  setup do
    scope = person_scope_fixture()
    place = place_fixture()
    checkin = checkin_fixture(%{place_uri: place.uri})
    %{scope: scope, checkin: checkin}
  end

  describe "like_entry/3 self-like prohibition" do
    setup do
      author_scope = person_scope_fixture()
      place = place_fixture()
      own_checkin = checkin_fixture(%{place_uri: place.uri, author_uri: author_scope.person.uri})
      %{author_scope: author_scope, own_checkin: own_checkin}
    end

    test "returns {:error, :self_like} when author likes their own entry", %{
      author_scope: author_scope,
      own_checkin: own_checkin
    } do
      assert {:error, :self_like} =
               Likes.like_entry(author_scope, own_checkin.uri, "UTC")
    end

    test "does not create a like record on self-like attempt", %{
      author_scope: author_scope,
      own_checkin: own_checkin
    } do
      Likes.like_entry(author_scope, own_checkin.uri, "UTC")
      assert Likes.count_active_likes(own_checkin.uri) == 0
    end

    test "allows a different person to like the same entry", %{
      scope: scope,
      own_checkin: own_checkin
    } do
      assert {:ok, _like} = Likes.like_entry(scope, own_checkin.uri, "UTC")
    end
  end

  describe "like_entry/3" do
    test "creates a new like for a never-liked object", %{scope: scope, checkin: checkin} do
      assert {:ok, %Like{} = like} =
               Likes.like_entry(scope, checkin.uri, "America/New_York")

      assert like.author_uri == scope.person.uri
      assert like.object_uri == checkin.uri
      assert like.origin == :local
      assert like.published_tz == "America/New_York"
      assert like.published_at_utc != nil
      assert like.published_at_local != nil
      assert like.unliked_at == nil
    end

    test "is idempotent when already liked", %{scope: scope, checkin: checkin} do
      {:ok, original} = Likes.like_entry(scope, checkin.uri, "UTC")
      {:ok, second} = Likes.like_entry(scope, checkin.uri, "UTC")

      assert original.id == second.id
      assert second.unliked_at == nil
    end

    test "re-likes after unlike: clears unliked_at and updates published_at", %{
      scope: scope,
      checkin: checkin
    } do
      {:ok, like} = Likes.like_entry(scope, checkin.uri, "UTC")

      t_original = ~U[2024-01-01 10:00:00Z]
      Revix.Repo.update!(Ecto.Changeset.change(like, published_at_utc: t_original))

      {:ok, unliked} = Likes.unlike_entry(scope, checkin.uri)
      assert unliked.unliked_at != nil

      {:ok, re_liked} = Likes.like_entry(scope, checkin.uri, "America/Chicago")

      assert re_liked.id == like.id
      assert re_liked.unliked_at == nil
      assert re_liked.published_tz == "America/Chicago"
      assert DateTime.compare(re_liked.published_at_utc, t_original) == :gt
    end

    test "stores correct local time for timezone", %{scope: scope, checkin: checkin} do
      {:ok, like} = Likes.like_entry(scope, checkin.uri, "America/New_York")

      # Local time should differ from UTC for non-UTC timezones
      # (UTC offset for America/New_York is -5 or -4 hours)
      utc_naive = DateTime.to_naive(like.published_at_utc)
      assert NaiveDateTime.diff(utc_naive, like.published_at_local, :hour) in -6..6
    end
  end

  describe "unlike_entry/2" do
    test "sets unliked_at on an active like", %{scope: scope, checkin: checkin} do
      {:ok, _like} = Likes.like_entry(scope, checkin.uri, "UTC")
      assert {:ok, unliked} = Likes.unlike_entry(scope, checkin.uri)

      assert %Like{} = unliked
      assert unliked.unliked_at != nil
      assert %DateTime{} = unliked.unliked_at
    end

    test "returns error when no active like exists", %{scope: scope, checkin: checkin} do
      assert {:error, :not_found} = Likes.unlike_entry(scope, checkin.uri)
    end

    test "returns error after already unliked", %{scope: scope, checkin: checkin} do
      {:ok, _like} = Likes.like_entry(scope, checkin.uri, "UTC")
      {:ok, _unliked} = Likes.unlike_entry(scope, checkin.uri)

      assert {:error, :not_found} = Likes.unlike_entry(scope, checkin.uri)
    end
  end

  describe "liked_by?/2" do
    test "returns true for an active like", %{scope: scope, checkin: checkin} do
      {:ok, _like} = Likes.like_entry(scope, checkin.uri, "UTC")
      assert Likes.liked_by?(scope.person.uri, checkin.uri) == true
    end

    test "returns false when not liked", %{scope: scope, checkin: checkin} do
      assert Likes.liked_by?(scope.person.uri, checkin.uri) == false
    end

    test "returns false after unliking", %{scope: scope, checkin: checkin} do
      {:ok, _like} = Likes.like_entry(scope, checkin.uri, "UTC")
      {:ok, _unliked} = Likes.unlike_entry(scope, checkin.uri)

      assert Likes.liked_by?(scope.person.uri, checkin.uri) == false
    end

    test "returns true again after re-liking", %{scope: scope, checkin: checkin} do
      {:ok, _like} = Likes.like_entry(scope, checkin.uri, "UTC")
      {:ok, _unliked} = Likes.unlike_entry(scope, checkin.uri)
      {:ok, _re_liked} = Likes.like_entry(scope, checkin.uri, "UTC")

      assert Likes.liked_by?(scope.person.uri, checkin.uri) == true
    end

    test "returns false for nil author_uri", %{checkin: checkin} do
      assert Likes.liked_by?(nil, checkin.uri) == false
    end
  end

  describe "count_active_likes/1" do
    test "returns 0 when no likes exist", %{checkin: checkin} do
      assert Likes.count_active_likes(checkin.uri) == 0
    end

    test "counts only active (non-unliked) likes", %{checkin: checkin} do
      scope1 = person_scope_fixture()
      scope2 = person_scope_fixture()
      scope3 = person_scope_fixture()

      {:ok, _} = Likes.like_entry(scope1, checkin.uri, "UTC")
      {:ok, _} = Likes.like_entry(scope2, checkin.uri, "UTC")
      {:ok, _} = Likes.like_entry(scope3, checkin.uri, "UTC")

      # Unlike one of them
      {:ok, _} = Likes.unlike_entry(scope2, checkin.uri)

      assert Likes.count_active_likes(checkin.uri) == 2
    end

    test "count increases after re-like", %{checkin: checkin} do
      scope = person_scope_fixture()

      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC")
      assert Likes.count_active_likes(checkin.uri) == 1

      {:ok, _} = Likes.unlike_entry(scope, checkin.uri)
      assert Likes.count_active_likes(checkin.uri) == 0

      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC")
      assert Likes.count_active_likes(checkin.uri) == 1
    end
  end

  describe "count_active_likes_by_object_uris/1" do
    test "returns empty map for empty list" do
      assert Likes.count_active_likes_by_object_uris([]) == %{}
    end

    test "returns counts only for uris with active likes" do
      place = place_fixture()
      checkin1 = checkin_fixture(%{place_uri: place.uri})
      checkin2 = checkin_fixture(%{place_uri: place.uri})
      checkin3 = checkin_fixture(%{place_uri: place.uri})

      scope = person_scope_fixture()
      {:ok, _} = Likes.like_entry(scope, checkin1.uri, "UTC")
      {:ok, _} = Likes.like_entry(scope, checkin1.uri, "UTC")
      scope2 = person_scope_fixture()
      {:ok, _} = Likes.like_entry(scope2, checkin1.uri, "UTC")
      {:ok, _} = Likes.like_entry(scope2, checkin2.uri, "UTC")

      # Unlike the checkin2 like
      {:ok, _} = Likes.unlike_entry(scope2, checkin2.uri)

      counts =
        Likes.count_active_likes_by_object_uris([checkin1.uri, checkin2.uri, checkin3.uri])

      assert counts[checkin1.uri] == 2
      refute Map.has_key?(counts, checkin2.uri)
      refute Map.has_key?(counts, checkin3.uri)
    end
  end

  describe "get_active_likes_for_entry/1" do
    test "returns empty list when no likes exist", %{checkin: checkin} do
      assert Likes.get_active_likes_for_entry(checkin.uri) == []
    end

    test "excludes unliked likes", %{checkin: checkin} do
      scope1 = person_scope_fixture()
      scope2 = person_scope_fixture()

      {:ok, _} = Likes.like_entry(scope1, checkin.uri, "UTC")
      {:ok, _} = Likes.like_entry(scope2, checkin.uri, "UTC")
      {:ok, _} = Likes.unlike_entry(scope1, checkin.uri)

      likes = Likes.get_active_likes_for_entry(checkin.uri)
      assert length(likes) == 1
      assert hd(likes).author_uri == scope2.person.uri
    end

    test "preloads authors", %{scope: scope, checkin: checkin} do
      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC")

      likes = Likes.get_active_likes_for_entry(checkin.uri)
      assert [like] = likes
      assert %Revix.People.Person{} = like.author
      assert like.author.uri == scope.person.uri
    end

    test "includes re-liked entries (unliked then re-liked)", %{scope: scope, checkin: checkin} do
      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC")
      {:ok, _} = Likes.unlike_entry(scope, checkin.uri)
      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC")

      likes = Likes.get_active_likes_for_entry(checkin.uri)
      assert length(likes) == 1
    end
  end

  describe "get_recent_likes/1" do
    test "returns only active likes", %{scope: scope, checkin: checkin} do
      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC")
      {:ok, _} = Likes.unlike_entry(scope, checkin.uri)

      scope2 = person_scope_fixture()
      {:ok, _} = Likes.like_entry(scope2, checkin.uri, "UTC")

      recent = Likes.get_recent_likes(10)
      assert length(recent) == 1
      assert hd(recent).author_uri == scope2.person.uri
    end

    test "preloads authors and object entries", %{scope: scope, checkin: checkin} do
      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC")

      recent = Likes.get_recent_likes(10)
      assert [like] = recent
      assert %Revix.People.Person{} = like.author
    end
  end

  describe "get_recent_likes_for_person/2" do
    test "returns only likes by the given person", %{scope: scope, checkin: checkin} do
      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC")

      other_scope = person_scope_fixture()
      {:ok, _} = Likes.like_entry(other_scope, checkin.uri, "UTC")

      likes = Likes.get_recent_likes_for_person(scope.person)
      assert length(likes) == 1
      assert hd(likes).author_uri == scope.person.uri
    end

    test "returns empty list when person has no likes", %{scope: scope} do
      assert [] = Likes.get_recent_likes_for_person(scope.person)
    end

    test "orders most recent first", %{scope: scope} do
      place = place_fixture()
      checkin1 = checkin_fixture(%{place_uri: place.uri})
      checkin2 = checkin_fixture(%{place_uri: place.uri})

      {:ok, like1} = Likes.like_entry(scope, checkin1.uri, "UTC")
      {:ok, like2} = Likes.like_entry(scope, checkin2.uri, "UTC")

      likes = Likes.get_recent_likes_for_person(scope.person)
      assert length(likes) == 2
      # Most recently published first
      assert hd(likes).id == like2.id or
               DateTime.compare(
                 likes |> hd() |> Map.get(:published_at_utc),
                 like1.published_at_utc
               ) != :lt
    end

    test "defaults to a limit of 50", %{scope: scope} do
      place = place_fixture()

      for _ <- 1..51 do
        checkin = checkin_fixture(%{place_uri: place.uri})
        Likes.like_entry(scope, checkin.uri, "UTC")
      end

      likes = Likes.get_recent_likes_for_person(scope.person)
      assert length(likes) == 50
    end

    test "respects custom limit in opts", %{scope: scope} do
      place = place_fixture()

      for _ <- 1..5 do
        checkin = checkin_fixture(%{place_uri: place.uri})
        Likes.like_entry(scope, checkin.uri, "UTC")
      end

      likes = Likes.get_recent_likes_for_person(scope.person, limit: 3)
      assert length(likes) == 3
    end

    test "excludes unliked (soft-deleted) likes", %{scope: scope, checkin: checkin} do
      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC")
      {:ok, _} = Likes.unlike_entry(scope, checkin.uri)

      likes = Likes.get_recent_likes_for_person(scope.person)
      assert likes == []
    end

    test "populates :object virtual field with the liked entry and its place", %{
      scope: scope,
      checkin: checkin
    } do
      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC")

      [like] = Likes.get_recent_likes_for_person(scope.person)
      assert %Revix.Entries.Entry{} = like.object
      assert %Revix.Places.Place{} = like.object.place
    end

    test "sets :object to nil when liked entry does not exist locally", %{scope: scope} do
      {:ok, _} =
        Likes.like_entry(scope, "https://remote.example.com/entries/xyz", "UTC")

      [like] = Likes.get_recent_likes_for_person(scope.person)
      assert is_nil(like.object)
    end

    test "preloads author", %{scope: scope, checkin: checkin} do
      {:ok, _} = Likes.like_entry(scope, checkin.uri, "UTC")

      [like] = Likes.get_recent_likes_for_person(scope.person)
      assert %Revix.People.Person{} = like.author
      assert like.author.id == scope.person.id
    end
  end

  describe "like_entry/4 (with context broadcast)" do
    setup do
      scope = person_scope_fixture()
      other_scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri, author_uri: other_scope.person.uri})
      comment_scope = person_scope_fixture()
      comment = comment_fixture(comment_scope, checkin)
      %{scope: scope, checkin: checkin, comment: comment}
    end

    test "creates a like for the comment URI", %{scope: scope, checkin: checkin, comment: comment} do
      assert {:ok, %Like{}} =
               Likes.like_entry(scope, comment.uri, "UTC", checkin.uri)

      assert Likes.liked_by?(scope.person.uri, comment.uri)
    end

    test "returns error :self_like if person authored the comment", %{checkin: checkin} do
      author_scope = person_scope_fixture()
      comment = comment_fixture(author_scope, checkin)

      assert {:error, :self_like} =
               Likes.like_entry(author_scope, comment.uri, "UTC", checkin.uri)
    end

    test "is idempotent on repeated likes", %{scope: scope, checkin: checkin, comment: comment} do
      {:ok, _} = Likes.like_entry(scope, comment.uri, "UTC", checkin.uri)
      assert {:ok, _} = Likes.like_entry(scope, comment.uri, "UTC", checkin.uri)
      assert Likes.count_active_likes(comment.uri) == 1
    end
  end

  describe "upsert_inbound_like/1" do
    @remote_actor "https://remote.example.com/users/alice"
    @remote_like_uri "https://remote.example.com/users/alice/likes/1"

    test "creates a new like when none exists", %{checkin: checkin} do
      assert {:ok, %Like{} = like} =
               Likes.upsert_inbound_like(%{
                 author_uri: @remote_actor,
                 object_uri: checkin.uri,
                 like_uri: @remote_like_uri
               })

      assert like.author_uri == @remote_actor
      assert like.object_uri == checkin.uri
      assert like.like_uri == @remote_like_uri
      assert like.origin == :remote
      assert like.published_tz == "UTC"
      assert is_nil(like.unliked_at)
    end

    test "is idempotent when an active like already exists", %{checkin: checkin} do
      {:ok, original} =
        Likes.upsert_inbound_like(%{
          author_uri: @remote_actor,
          object_uri: checkin.uri,
          like_uri: @remote_like_uri
        })

      {:ok, second} =
        Likes.upsert_inbound_like(%{
          author_uri: @remote_actor,
          object_uri: checkin.uri,
          like_uri: @remote_like_uri
        })

      assert original.id == second.id
      assert is_nil(second.unliked_at)
    end

    test "re-likes after an unlike: clears unliked_at and updates published_at", %{
      checkin: checkin
    } do
      {:ok, like} =
        Likes.upsert_inbound_like(%{
          author_uri: @remote_actor,
          object_uri: checkin.uri,
          like_uri: @remote_like_uri
        })

      t_original = ~U[2024-01-01 10:00:00Z]
      Revix.Repo.update!(Ecto.Changeset.change(like, published_at_utc: t_original))

      Revix.Repo.update!(Revix.Likes.Like.unlike_changeset(like))

      {:ok, re_liked} =
        Likes.upsert_inbound_like(%{
          author_uri: @remote_actor,
          object_uri: checkin.uri,
          like_uri: @remote_like_uri
        })

      assert re_liked.id == like.id
      assert is_nil(re_liked.unliked_at)
      assert DateTime.compare(re_liked.published_at_utc, t_original) == :gt
    end
  end

  describe "unlike_entry/3 (with context broadcast)" do
    setup do
      scope = person_scope_fixture()
      other_scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri, author_uri: other_scope.person.uri})
      comment_scope = person_scope_fixture()
      comment = comment_fixture(comment_scope, checkin)
      {:ok, _} = Likes.like_entry(scope, comment.uri, "UTC", checkin.uri)
      %{scope: scope, checkin: checkin, comment: comment}
    end

    test "removes the active like for the comment URI", %{
      scope: scope,
      checkin: checkin,
      comment: comment
    } do
      assert {:ok, _} = Likes.unlike_entry(scope, comment.uri, checkin.uri)
      refute Likes.liked_by?(scope.person.uri, comment.uri)
    end

    test "returns error :not_found when no active like exists", %{
      scope: scope,
      checkin: checkin,
      comment: comment
    } do
      {:ok, _} = Likes.unlike_entry(scope, comment.uri, checkin.uri)
      assert {:error, :not_found} = Likes.unlike_entry(scope, comment.uri, checkin.uri)
    end
  end

  # ── get_like_with_object/1 ────────────────────────────────────────────────

  describe "get_like_with_object/1" do
    test "returns nil when the like id does not exist" do
      nonexistent_id = Revix.Ecto.Base58Id.autogenerate()
      assert is_nil(Likes.get_like_with_object(nonexistent_id))
    end

    test "returns nil when the like has been unliked", %{scope: scope, checkin: checkin} do
      {:ok, like} = Likes.like_entry(scope, checkin.uri, "UTC")
      {:ok, _} = Likes.unlike_entry(scope, checkin.uri)
      assert is_nil(Likes.get_like_with_object(like.id))
    end

    test "returns enriched like with :object populated when found and active",
         %{scope: scope, checkin: checkin} do
      {:ok, like} = Likes.like_entry(scope, checkin.uri, "UTC")
      result = Likes.get_like_with_object(like.id)
      assert result != nil
      assert result.id == like.id
      assert is_nil(result.unliked_at)
      assert %Revix.Entries.Entry{} = result.object
      assert result.object.uri == checkin.uri
    end
  end
end
