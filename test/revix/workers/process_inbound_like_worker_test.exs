defmodule Revix.Workers.ProcessInboundLikeWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.ProcessInboundLikeWorker
  alias Revix.Likes.Like

  import Revix.PeopleFixtures

  @actor_uri "https://remote.example.com/users/alice"
  @object_uri "https://example.com/entries/abc123"
  @like_uri "https://remote.example.com/users/alice/likes/xyz789"

  defp base_activity do
    %{
      "type" => "Like",
      "id" => @like_uri,
      "actor" => @actor_uri,
      "object" => @object_uri
    }
  end

  describe "perform/1" do
    test "creates a remote Like record from a valid activity" do
      person = person_fixture()

      assert :ok =
               perform_job(ProcessInboundLikeWorker, %{
                 "activity" => base_activity(),
                 "person_id" => person.id
               })

      like = Repo.get_by!(Like, like_uri: @like_uri)
      assert like.author_uri == @actor_uri
      assert like.object_uri == @object_uri
      assert like.origin == :remote
      assert like.published_tz == "UTC"
      assert is_nil(like.unliked_at)
    end

    test "generates a like_uri when the activity has no id" do
      person = person_fixture()

      activity = Map.delete(base_activity(), "id")

      assert :ok =
               perform_job(ProcessInboundLikeWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })

      like = Repo.one!(from l in Like, where: l.author_uri == ^@actor_uri)
      assert String.starts_with?(like.like_uri, "tag:")
    end

    test "is idempotent when the same author_uri/object_uri already exists" do
      person = person_fixture()

      assert :ok =
               perform_job(ProcessInboundLikeWorker, %{
                 "activity" => base_activity(),
                 "person_id" => person.id
               })

      assert :ok =
               perform_job(ProcessInboundLikeWorker, %{
                 "activity" => base_activity(),
                 "person_id" => person.id
               })

      assert Repo.aggregate(from(l in Like, where: l.author_uri == ^@actor_uri), :count) == 1
    end

    test "is idempotent when like_uri already exists with a different actor" do
      person = person_fixture()

      # First insert succeeds
      assert :ok =
               perform_job(ProcessInboundLikeWorker, %{
                 "activity" => base_activity(),
                 "person_id" => person.id
               })

      # Second insert with same like_uri but different actor+object would
      # hit the like_uri unique constraint
      duplicate_activity = %{
        "type" => "Like",
        "id" => @like_uri,
        "actor" => "https://remote.example.com/users/bob",
        "object" => "https://example.com/entries/other"
      }

      assert :ok =
               perform_job(ProcessInboundLikeWorker, %{
                 "activity" => duplicate_activity,
                 "person_id" => person.id
               })

      assert Repo.aggregate(from(l in Like, where: l.like_uri == ^@like_uri), :count) == 1
    end

    test "re-likes after an unlike: clears unliked_at" do
      person = person_fixture()

      assert :ok =
               perform_job(ProcessInboundLikeWorker, %{
                 "activity" => base_activity(),
                 "person_id" => person.id
               })

      like = Repo.get_by!(Like, like_uri: @like_uri)
      Repo.update!(Like.unlike_changeset(like))

      assert :ok =
               perform_job(ProcessInboundLikeWorker, %{
                 "activity" => base_activity(),
                 "person_id" => person.id
               })

      re_liked = Repo.get!(Like, like.id)
      assert is_nil(re_liked.unliked_at)
      assert Repo.aggregate(from(l in Like, where: l.author_uri == ^@actor_uri), :count) == 1
    end

    test "returns error when object is missing" do
      person = person_fixture()

      activity = Map.delete(base_activity(), "object")

      assert {:error, :invalid_activity} =
               perform_job(ProcessInboundLikeWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })
    end

    test "returns error when object is not a string" do
      person = person_fixture()

      activity = Map.put(base_activity(), "object", %{"id" => @object_uri})

      assert {:error, :invalid_activity} =
               perform_job(ProcessInboundLikeWorker, %{
                 "activity" => activity,
                 "person_id" => person.id
               })
    end
  end
end
