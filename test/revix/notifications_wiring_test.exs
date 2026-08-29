defmodule Revix.NotificationsWiringTest do
  @moduledoc """
  Verifies that the triggering contexts call `Revix.Notifications` on the
  success path (and not on failure paths), using the Mox mock as the impl.
  """
  use Revix.DataCase, async: false

  import Mox
  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures

  alias Revix.Entries
  alias Revix.Likes
  alias Revix.People

  setup :verify_on_exit!

  setup do
    Application.put_env(:revix, :notifications_impl, Revix.NotificationsMock)
    on_exit(fn -> Application.delete_env(:revix, :notifications_impl) end)
    # person_fixture -> magic-link login fires notify_registration; allow it.
    stub(Revix.NotificationsMock, :notify_registration, fn _ -> :ok end)
    stub(Revix.NotificationsMock, :notify_new_entry, fn _ -> :ok end)
    stub(Revix.NotificationsMock, :notify_like, fn _ -> :ok end)
    stub(Revix.NotificationsMock, :notify_reply, fn _ -> :ok end)
    :ok
  end

  defp checkin_uri(id), do: "https://example.com/checkins/#{id}"
  defp checkin_url(id, _slug), do: "https://example.com/checkins/#{id}"

  describe "Entries" do
    test "create_local_checkin fires notify_new_entry" do
      test_pid = self()
      scope = person_scope_fixture()
      place = place_fixture()

      expect(Revix.NotificationsMock, :notify_new_entry, fn entry ->
        send(test_pid, {:notified, entry.type})
        :ok
      end)

      attrs = %{
        "starts_at_local" => NaiveDateTime.add(NaiveDateTime.utc_now(:second), -30, :minute),
        "starts_tz" => "Etc/UTC",
        "content" => "hello"
      }

      {:ok, _checkin} =
        Entries.create_local_checkin(scope, place, attrs, &checkin_uri/1, &checkin_url/2)

      assert_receive {:notified, :checkin}
    end

    test "the LiveView publish flow (enqueue_delivery: false then enqueue_delivery/2) fires notify_new_entry once" do
      test_pid = self()
      scope = person_scope_fixture()
      place = place_fixture()

      expect(Revix.NotificationsMock, :notify_new_entry, 1, fn entry ->
        send(test_pid, {:notified, entry.type})
        :ok
      end)

      attrs = %{
        "starts_at_local" => NaiveDateTime.add(NaiveDateTime.utc_now(:second), -30, :minute),
        "starts_tz" => "Etc/UTC",
        "content" => "with a companion"
      }

      companion = person_fixture()

      # mirrors CheckinNewLive: create with companions, delivery deferred, then
      # the LiveView enqueues delivery itself after the transaction commits
      {:ok, checkin} =
        Entries.create_local_checkin_with_companions(
          scope,
          place,
          attrs,
          &checkin_uri/1,
          &checkin_url/2,
          [companion.uri],
          mode: :publish,
          enqueue_delivery: false
        )

      Entries.enqueue_delivery(checkin, "Create")

      assert_receive {:notified, :checkin}
    end

    test "create_local_post_with_companions LiveView flow fires notify_new_entry once" do
      test_pid = self()
      scope = person_scope_fixture()
      companion = person_fixture()

      expect(Revix.NotificationsMock, :notify_new_entry, 1, fn entry ->
        send(test_pid, {:notified, entry.type})
        :ok
      end)

      post_uri = fn id -> "https://example.com/posts/#{id}" end
      post_url = fn %{id: id} -> "https://example.com/posts/#{id}" end

      {:ok, post} =
        Entries.create_local_post_with_companions(
          scope,
          %{"name" => "Owner post", "content" => "body", "published_tz" => "UTC"},
          post_uri,
          post_url,
          [companion.uri],
          [],
          mode: :publish,
          enqueue_delivery: false
        )

      Entries.enqueue_delivery(post, "Create")

      assert_receive {:notified, :post}
    end

    test "an entry update does not fire notify_new_entry" do
      scope = person_scope_fixture()
      place = place_fixture()

      # exactly zero notify_new_entry calls across create + update
      expect(Revix.NotificationsMock, :notify_new_entry, 1, fn _ -> :ok end)

      attrs = %{
        "starts_at_local" => NaiveDateTime.add(NaiveDateTime.utc_now(:second), -30, :minute),
        "starts_tz" => "Etc/UTC",
        "content" => "original"
      }

      {:ok, checkin} =
        Entries.create_local_checkin(scope, place, attrs, &checkin_uri/1, &checkin_url/2)

      {:ok, _updated} =
        Entries.update_local_checkin(checkin, %{"content" => "edited"}, scope.role)
    end

    test "create_comment fires notify_reply" do
      test_pid = self()
      scope = person_scope_fixture()
      checkin = checkin_fixture()

      expect(Revix.NotificationsMock, :notify_reply, fn note ->
        send(test_pid, {:reply, note.type})
        :ok
      end)

      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, _comment} =
        Entries.create_comment(
          scope,
          checkin,
          %{"content" => "hi", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      assert_receive {:reply, :note}
    end

    test "create_inbound_note fires notify_reply" do
      test_pid = self()
      parent = checkin_fixture()

      expect(Revix.NotificationsMock, :notify_reply, fn _note ->
        send(test_pid, :inbound_reply)
        :ok
      end)

      {:ok, _note} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/1",
          url: "https://remote.example.com/notes/1",
          author_uri: "https://remote.example.com/users/rae",
          in_reply_to_uri: parent.uri,
          context: parent.context,
          content: "remote comment",
          published_at_utc: DateTime.utc_now(:second)
        })

      assert_receive :inbound_reply
    end

    test "an inbound remote reply to a local comment fires notify_reply with the descendant note" do
      test_pid = self()
      author_scope = person_scope_fixture()
      checkin = checkin_fixture(%{author_uri: author_scope.person.uri})
      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, comment} =
        Entries.create_comment(
          author_scope,
          checkin,
          %{"content" => "local comment", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      expect(Revix.NotificationsMock, :notify_reply, fn note ->
        send(test_pid, {:inbound_descendant_reply, note.in_reply_to_uri})
        :ok
      end)

      {:ok, _note} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/deep",
          url: "https://remote.example.com/notes/deep",
          author_uri: "https://remote.example.com/users/rae",
          in_reply_to_uri: comment.uri,
          context: checkin.context,
          content: "remote reply to the comment",
          published_at_utc: DateTime.utc_now(:second)
        })

      assert_receive {:inbound_descendant_reply, in_reply_to}
      assert in_reply_to == comment.uri
    end
  end

  describe "Likes" do
    test "like_entry fires notify_like" do
      test_pid = self()
      liker = person_scope_fixture()
      checkin = checkin_fixture()

      expect(Revix.NotificationsMock, :notify_like, fn like ->
        send(test_pid, {:liked, like.object_uri})
        :ok
      end)

      {:ok, _like} = Likes.like_entry(liker, checkin.uri, "UTC")
      assert_receive {:liked, object_uri}
      assert object_uri == checkin.uri
    end

    test "a self-like does not fire notify_like" do
      author = person_scope_fixture()
      own_checkin = checkin_fixture(%{author_uri: author.person.uri})

      # expect exactly zero calls; verify_on_exit! enforces it.
      expect(Revix.NotificationsMock, :notify_like, 0, fn _ -> :ok end)

      assert {:error, :self_like} = Likes.like_entry(author, own_checkin.uri, "UTC")
    end

    test "upsert_inbound_like fires notify_like for a remote like" do
      test_pid = self()
      checkin = checkin_fixture()

      expect(Revix.NotificationsMock, :notify_like, fn like ->
        send(test_pid, {:inbound_liked, like.object_uri})
        :ok
      end)

      {:ok, _like} =
        Likes.upsert_inbound_like(%{
          author_uri: "https://remote.example.com/users/rae",
          object_uri: checkin.uri,
          like_uri: "https://remote.example.com/likes/1"
        })

      assert_receive {:inbound_liked, object_uri}
      assert object_uri == checkin.uri
    end
  end

  describe "People registration" do
    test "completing magic-link confirmation fires notify_registration" do
      test_pid = self()
      person = unconfirmed_person_fixture()

      expect(Revix.NotificationsMock, :notify_registration, fn confirmed ->
        send(test_pid, {:registered, confirmed.id})
        :ok
      end)

      token =
        extract_person_token(fn url -> People.deliver_login_instructions(person, url) end)

      {:ok, {_person, _}} = People.login_person_by_magic_link(token)
      assert_receive {:registered, id}
      assert id == person.id
    end
  end
end
