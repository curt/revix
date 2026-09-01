defmodule Revix.NotificationsTest do
  use Revix.DataCase, async: true

  import Revix.PeopleFixtures
  import Revix.EntriesFixtures
  import Revix.PlacesFixtures
  import Revix.NotificationsFixtures
  import Swoosh.TestAssertions
  import ExUnit.CaptureLog

  alias Revix.Entries.Entry
  alias Revix.Follows.Follow
  alias Revix.Likes
  alias Revix.Likes.Like
  alias Revix.Notifications
  alias Revix.Notifications.Notification
  alias Revix.People

  # Prevent the real registration hook (fired by person_fixture -> magic link
  # login) from adding noise; each test opts back into the real context.
  setup do
    Application.put_env(:revix, :notifications_impl, __MODULE__.NoopNotifications)
    on_exit(fn -> Application.delete_env(:revix, :notifications_impl) end)
    :ok
  end

  defmodule NoopNotifications do
    @behaviour Revix.Notifications.Behaviour
    def notify_new_entry(_), do: :ok
    def notify_like(_), do: :ok
    def notify_reply(_), do: :ok
    def notify_registration(_), do: :ok
  end

  defp owner_fixture(attrs \\ %{}) do
    person = person_fixture(attrs)
    {:ok, person} = People.set_person_role(person, :owner)
    person
  end

  defp rows_for(recipient_uri) do
    Repo.all(from n in Notification, where: n.recipient_uri == ^recipient_uri)
  end

  describe "set_schedule/2" do
    test "updates the person's cadence" do
      person = person_fixture()
      assert {:ok, updated} = Notifications.set_schedule(person, :weekly)
      assert updated.notification_schedule == :weekly
      assert People.get_person_by_email(person.email).notification_schedule == :weekly
    end

    test "accepts the monthly cadence" do
      person = person_fixture()
      assert {:ok, updated} = Notifications.set_schedule(person, :monthly)
      assert updated.notification_schedule == :monthly
      assert People.get_person_by_email(person.email).notification_schedule == :monthly
    end

    test "rejects an invalid cadence" do
      person = person_fixture()
      assert {:error, changeset} = Notifications.set_schedule(person, :yearly)
      assert %{notification_schedule: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "get_schedule/1 and schedule_options/0" do
    test "reads the cadence off the struct" do
      person = person_fixture()
      assert Notifications.get_schedule(person) == :daily
    end

    test "schedule_options/0 covers every cadence" do
      values = Enum.map(Notifications.schedule_options(), fn {_label, value} -> value end)
      assert values == [:hourly, :daily, :weekly, :monthly, :none]
    end
  end

  describe "notify_new_entry/1 - owner posts" do
    test "notifies every eligible subscriber except the author" do
      owner = owner_fixture()
      sub_a = subscriber_fixture(:daily)
      sub_b = subscriber_fixture(:hourly)
      _opted_out = subscriber_fixture(:none)
      _unconfirmed = unconfirmed_person_fixture()

      checkin = checkin_fixture(%{author_uri: owner.uri})
      assert :ok = Notifications.notify_new_entry(checkin)

      assert [%Notification{type: :owner_entry}] = rows_for(sub_a.uri)
      assert [%Notification{type: :owner_entry}] = rows_for(sub_b.uri)
      assert rows_for(owner.uri) == []
    end

    test "does not notify opted-out or unconfirmed people" do
      owner = owner_fixture()
      opted_out = subscriber_fixture(:none)
      unconfirmed = unconfirmed_person_fixture()

      post = post_fixture(%{author_uri: owner.uri})
      assert :ok = Notifications.notify_new_entry(post)

      assert rows_for(opted_out.uri) == []
      assert rows_for(unconfirmed.uri) == []
    end

    test "does nothing for a non-owner author with no followers" do
      author = person_fixture()
      _sub = subscriber_fixture(:daily)

      post = post_fixture(%{author_uri: author.uri})
      assert :ok = Notifications.notify_new_entry(post)

      assert Repo.aggregate(Notification, :count) == 0
    end

    test "does nothing for an unpublished (draft) owner post" do
      owner = owner_fixture()
      _sub = subscriber_fixture(:daily)

      draft = draft_post_fixture(%{author_uri: owner.uri})
      assert :ok = Notifications.notify_new_entry(draft)

      assert Repo.aggregate(Notification, :count) == 0
    end
  end

  describe "notify_new_entry/1 - followed authors" do
    test "notifies local followers of any entry type" do
      author = person_fixture()
      follower = subscriber_fixture(:daily)
      insert_follow(follower.uri, author.uri)

      note = post_fixture(%{author_uri: author.uri})
      assert :ok = Notifications.notify_new_entry(note)

      assert [%Notification{type: :followed_entry}] = rows_for(follower.uri)
    end

    test "a follower who is also an owner gets exactly one row" do
      author = person_fixture()
      owner_follower = owner_fixture()
      {:ok, _} = Notifications.set_schedule(owner_follower, :daily)
      insert_follow(owner_follower.uri, author.uri)

      # author is NOT an owner, so owner_entry does not apply; only followed_entry
      post = post_fixture(%{author_uri: author.uri})
      assert :ok = Notifications.notify_new_entry(post)

      assert [%Notification{type: :followed_entry}] = rows_for(owner_follower.uri)
    end

    test "owner author who is also followed yields a single owner_entry row" do
      owner = owner_fixture()
      follower = subscriber_fixture(:daily)
      insert_follow(follower.uri, owner.uri)

      checkin = checkin_fixture(%{author_uri: owner.uri})
      assert :ok = Notifications.notify_new_entry(checkin)

      assert [%Notification{type: :owner_entry}] = rows_for(follower.uri)
    end

    test "Alice following owner Bob gets exactly one row for Bob's post" do
      bob = owner_fixture()
      {:ok, bob} = People.set_person_role(bob, :owner)
      alice = subscriber_fixture(:daily)
      insert_follow(alice.uri, bob.uri)

      post = post_fixture(%{author_uri: bob.uri, name: "Bob goes to Rome"})
      assert :ok = Notifications.notify_new_entry(post)

      assert [%Notification{type: :owner_entry, subject_uri: subject}] = rows_for(alice.uri)
      assert subject == post.uri
    end
  end

  describe "notify_like/1" do
    setup do
      author = person_fixture()
      liker = person_fixture()
      checkin = checkin_fixture(%{author_uri: author.uri})
      {:ok, author} = Notifications.set_schedule(author, :daily)
      %{author: author, liker: liker, checkin: checkin}
    end

    test "notifies the liked entry's author, not the liker", ctx do
      like = %Like{
        like_uri: "https://example.com/likes/1",
        author_uri: ctx.liker.uri,
        object_uri: ctx.checkin.uri
      }

      assert :ok = Notifications.notify_like(like)

      assert [%Notification{type: :like, summary: summary, url: url}] = rows_for(ctx.author.uri)
      assert summary =~ "liked a post in a conversation you're part of"
      assert url == ctx.checkin.url
      assert rows_for(ctx.liker.uri) == []
    end

    test "notifies every ancestor author when a descendant comment is liked", ctx do
      commenter = person_fixture()
      {:ok, commenter} = Notifications.set_schedule(commenter, :daily)

      comment =
        insert_note(%{
          author_uri: commenter.uri,
          in_reply_to_uri: ctx.checkin.uri,
          context: ctx.checkin.context
        })

      like = %Like{
        like_uri: "https://example.com/likes/2",
        author_uri: ctx.liker.uri,
        object_uri: comment.uri
      }

      assert :ok = Notifications.notify_like(like)

      assert [%Notification{}] = rows_for(commenter.uri)
      assert [%Notification{}] = rows_for(ctx.author.uri)
    end

    test "is a no-op and never raises when the liked object does not exist", ctx do
      like = %Like{
        like_uri: "https://example.com/likes/3",
        author_uri: ctx.liker.uri,
        object_uri: "https://example.com/entries/missing"
      }

      assert :ok = Notifications.notify_like(like)
      assert Repo.aggregate(Notification, :count) == 0
    end

    test "two different likes on the same entry yield one row for the author", ctx do
      other_liker = person_fixture()

      like_a = %Like{
        like_uri: "https://example.com/likes/a",
        author_uri: ctx.liker.uri,
        object_uri: ctx.checkin.uri
      }

      like_b = %Like{
        like_uri: "https://example.com/likes/b",
        author_uri: other_liker.uri,
        object_uri: ctx.checkin.uri
      }

      assert :ok = Notifications.notify_like(like_a)
      assert :ok = Notifications.notify_like(like_b)

      assert [%Notification{subject_uri: subject}] = rows_for(ctx.author.uri)
      assert subject == ctx.checkin.uri
    end

    test "logs a warning and does not raise when a row fails to insert", ctx do
      # note.uri is the subject_uri; nil trips the changeset's validate_required,
      # while in_reply_to_uri still resolves so there is a recipient to emit for.
      note = %Entry{
        uri: nil,
        author_uri: "https://remote.example.com/users/x",
        in_reply_to_uri: ctx.checkin.uri
      }

      log =
        capture_log(fn ->
          assert :ok = Notifications.notify_reply(note)
        end)

      assert log =~ "notification emit failed"
      assert log =~ "type=reply"
      assert log =~ "recipient=#{ctx.author.uri}"
      assert Repo.aggregate(Notification, :count) == 0
    end
  end

  describe "notify_reply/1" do
    test "notifies ancestor authors and root companions, not the replier" do
      author = subscriber_fixture(:daily)
      commenter = subscriber_fixture(:daily)
      companion = subscriber_fixture(:daily)
      replier = person_fixture()

      checkin = checkin_fixture(%{author_uri: author.uri})
      Repo.insert!(companion_row(checkin.uri, companion.uri))

      comment =
        insert_note(%{
          author_uri: commenter.uri,
          in_reply_to_uri: checkin.uri,
          context: checkin.context
        })

      reply =
        insert_note(%{
          author_uri: replier.uri,
          in_reply_to_uri: comment.uri,
          context: checkin.context
        })

      assert :ok = Notifications.notify_reply(reply)

      assert [%Notification{type: :reply, summary: summary}] = rows_for(author.uri)
      assert summary =~ "commented in a conversation you're part of"
      assert [%Notification{type: :reply}] = rows_for(commenter.uri)
      assert [%Notification{type: :reply}] = rows_for(companion.uri)
      assert rows_for(replier.uri) == []
    end

    test "notifies people who liked an entry in the thread" do
      root_author = subscriber_fixture(:daily)
      root_liker = subscriber_fixture(:daily)
      descendant_liker = subscriber_fixture(:daily)
      replier = person_fixture()

      checkin = checkin_fixture(%{author_uri: root_author.uri})

      comment =
        insert_note(%{
          author_uri: root_author.uri,
          in_reply_to_uri: checkin.uri,
          context: checkin.context
        })

      Likes.like_entry(person_scope_fixture(root_liker), checkin.uri, "UTC")
      Likes.like_entry(person_scope_fixture(descendant_liker), comment.uri, "UTC")

      reply =
        insert_note(%{
          author_uri: replier.uri,
          in_reply_to_uri: comment.uri,
          context: checkin.context
        })

      assert :ok = Notifications.notify_reply(reply)

      assert [%Notification{type: :reply}] = rows_for(root_liker.uri)
      assert [%Notification{type: :reply}] = rows_for(descendant_liker.uri)
    end

    test "a liker who is also the replier is not self-notified" do
      root_author = subscriber_fixture(:daily)
      liker_replier = person_fixture()

      checkin = checkin_fixture(%{author_uri: root_author.uri})
      Likes.like_entry(person_scope_fixture(liker_replier), checkin.uri, "UTC")

      reply =
        insert_note(%{
          author_uri: liker_replier.uri,
          in_reply_to_uri: checkin.uri,
          context: checkin.context
        })

      assert :ok = Notifications.notify_reply(reply)
      assert rows_for(liker_replier.uri) == []
    end

    test "with no in_reply_to_uri it does nothing" do
      author = person_fixture()

      note = %Entry{
        uri: "https://example.com/notes/x",
        author_uri: author.uri,
        in_reply_to_uri: nil
      }

      assert :ok = Notifications.notify_reply(note)
      assert Repo.aggregate(Notification, :count) == 0
    end

    test "with a parent uri that does not exist it does nothing" do
      author = person_fixture()

      note = %Entry{
        uri: "https://example.com/notes/y",
        author_uri: author.uri,
        in_reply_to_uri: "https://example.com/notes/missing"
      }

      assert :ok = Notifications.notify_reply(note)
      assert Repo.aggregate(Notification, :count) == 0
    end

    test "excludes ancestor authors who are remote" do
      remote_author_uri = "https://remote.example.com/users/rae"
      commenter = subscriber_fixture(:daily)
      replier = person_fixture()

      checkin = checkin_fixture(%{author_uri: remote_author_uri})

      comment =
        insert_note(%{
          author_uri: commenter.uri,
          in_reply_to_uri: checkin.uri,
          context: checkin.context
        })

      reply =
        insert_note(%{
          author_uri: replier.uri,
          in_reply_to_uri: comment.uri,
          context: checkin.context
        })

      assert :ok = Notifications.notify_reply(reply)

      assert rows_for(remote_author_uri) == []
      assert [%Notification{}] = rows_for(commenter.uri)
    end

    test "stops walking the ancestor chain at the configured depth limit" do
      Application.put_env(:revix, :notification_ancestor_depth_limit, 1)
      on_exit(fn -> Application.delete_env(:revix, :notification_ancestor_depth_limit) end)

      root_author = subscriber_fixture(:daily)
      mid_author = subscriber_fixture(:daily)
      replier = person_fixture()

      checkin = checkin_fixture(%{author_uri: root_author.uri})

      mid =
        insert_note(%{
          author_uri: mid_author.uri,
          in_reply_to_uri: checkin.uri,
          context: checkin.context
        })

      reply =
        insert_note(%{
          author_uri: replier.uri,
          in_reply_to_uri: mid.uri,
          context: checkin.context
        })

      assert :ok = Notifications.notify_reply(reply)

      # depth 0 = mid (notified); depth 1 hits the limit, so root_author is not reached
      assert [%Notification{}] = rows_for(mid_author.uri)
      assert rows_for(root_author.uri) == []
    end
  end

  describe "notify_registration/1" do
    test "notifies owners only, not the new person or non-owners" do
      owner = owner_fixture()
      {:ok, _} = Notifications.set_schedule(owner, :daily)
      _regular = subscriber_fixture(:daily)
      newcomer = person_fixture()

      assert :ok = Notifications.notify_registration(newcomer)

      assert [%Notification{type: :registration}] = rows_for(owner.uri)
      assert rows_for(newcomer.uri) == []
    end
  end

  describe "self-exclusion — user A never receives a notification they initiated" do
    test "an owner publishing their own post is not notified about it" do
      owner = owner_fixture()
      {:ok, owner} = People.set_person_role(owner, :owner)
      {:ok, owner} = Notifications.set_schedule(owner, :daily)
      _other_sub = subscriber_fixture(:daily)

      post = post_fixture(%{author_uri: owner.uri})
      assert :ok = Notifications.notify_new_entry(post)

      assert rows_for(owner.uri) == []
    end

    test "an author who follows themselves is not notified about their own entry" do
      author = subscriber_fixture(:daily)
      # a self-follow should never produce a self-notification
      insert_follow(author.uri, author.uri)

      post = post_fixture(%{author_uri: author.uri})
      assert :ok = Notifications.notify_new_entry(post)

      assert rows_for(author.uri) == []
    end

    test "liking your own entry produces no notification for you" do
      author = subscriber_fixture(:daily)
      checkin = checkin_fixture(%{author_uri: author.uri})

      like = %Like{
        like_uri: "https://example.com/likes/self",
        author_uri: author.uri,
        object_uri: checkin.uri
      }

      assert :ok = Notifications.notify_like(like)
      assert rows_for(author.uri) == []
    end

    test "liking a descendant of your own entry does not notify you as an ancestor author" do
      author = subscriber_fixture(:daily)
      checkin = checkin_fixture(%{author_uri: author.uri})

      # the author comments on their own checkin, then likes that comment
      own_comment =
        insert_note(%{
          author_uri: author.uri,
          in_reply_to_uri: checkin.uri,
          context: checkin.context
        })

      like = %Like{
        like_uri: "https://example.com/likes/self-descendant",
        author_uri: author.uri,
        object_uri: own_comment.uri
      }

      assert :ok = Notifications.notify_like(like)
      assert rows_for(author.uri) == []
    end

    test "replying in your own thread produces no notification for you" do
      author = subscriber_fixture(:daily)
      checkin = checkin_fixture(%{author_uri: author.uri})

      own_reply =
        insert_note(%{
          author_uri: author.uri,
          in_reply_to_uri: checkin.uri,
          context: checkin.context
        })

      assert :ok = Notifications.notify_reply(own_reply)
      assert rows_for(author.uri) == []
    end

    test "a companion replying on a thread they are tagged in is not self-notified" do
      author = subscriber_fixture(:daily)
      companion = subscriber_fixture(:daily)
      checkin = checkin_fixture(%{author_uri: author.uri})
      Repo.insert!(companion_row(checkin.uri, companion.uri))

      companion_reply =
        insert_note(%{
          author_uri: companion.uri,
          in_reply_to_uri: checkin.uri,
          context: checkin.context
        })

      assert :ok = Notifications.notify_reply(companion_reply)

      assert rows_for(companion.uri) == []
      assert [%Notification{type: :reply}] = rows_for(author.uri)
    end

    test "an owner completing their own registration is not notified about it" do
      owner = owner_fixture()
      {:ok, owner} = People.set_person_role(owner, :owner)
      {:ok, owner} = Notifications.set_schedule(owner, :daily)

      assert :ok = Notifications.notify_registration(owner)
      assert rows_for(owner.uri) == []
    end
  end

  describe "summary rendering" do
    test "owner_entry summary includes the post title and a body excerpt" do
      owner = owner_fixture(%{email: unique_person_email()})
      {:ok, owner} = People.set_person_role(owner, :owner)
      sub = subscriber_fixture(:daily)

      post =
        post_fixture(%{
          author_uri: owner.uri,
          name: "My Trip",
          content: "Rome was incredible for the food alone."
        })

      assert :ok = Notifications.notify_new_entry(post)

      assert [%Notification{summary: summary}] = rows_for(sub.uri)
      assert summary =~ "published a post: My Trip — Rome was incredible for the food alone."
    end

    test "owner_entry summary uses just the title when a post has no body" do
      owner = owner_fixture()
      {:ok, owner} = People.set_person_role(owner, :owner)
      sub = subscriber_fixture(:daily)

      post = post_fixture(%{author_uri: owner.uri, name: "Weeknotes 14", content: nil})
      assert :ok = Notifications.notify_new_entry(post)

      assert [%Notification{summary: summary}] = rows_for(sub.uri)
      assert summary =~ "published a post: Weeknotes 14"
      refute summary =~ "—"
    end

    test "owner_entry summary uses a body excerpt for a title-less checkin, or the bare noun" do
      owner = owner_fixture()
      {:ok, owner} = People.set_person_role(owner, :owner)
      sub_a = subscriber_fixture(:daily)

      with_content = checkin_fixture(%{author_uri: owner.uri, content: "great espresso downtown"})
      assert :ok = Notifications.notify_new_entry(with_content)
      assert [%Notification{summary: s1}] = rows_for(sub_a.uri)
      assert s1 =~ "published a checkin: great espresso downtown"

      sub_b = subscriber_fixture(:daily)
      blank = checkin_fixture(%{author_uri: owner.uri, content: nil})
      assert :ok = Notifications.notify_new_entry(blank)
      assert [%Notification{summary: s2}] = rows_for(sub_b.uri)
      assert String.ends_with?(s2, "published a checkin")
    end

    test "checkin summary is prefixed with the place name" do
      owner = owner_fixture()
      {:ok, owner} = People.set_person_role(owner, :owner)
      sub = subscriber_fixture(:daily)

      place = place_fixture(%{name: "Blue Bottle Coffee"})

      checkin =
        checkin_fixture(%{
          author_uri: owner.uri,
          place_uri: place.uri,
          content: "third time this week"
        })

      assert :ok = Notifications.notify_new_entry(checkin)

      assert [%Notification{summary: summary}] = rows_for(sub.uri)
      assert summary =~ "published a checkin: Blue Bottle Coffee — third time this week"
    end

    test "like summary falls back to the URI when the actor is unknown" do
      author = subscriber_fixture(:daily)
      checkin = checkin_fixture(%{author_uri: author.uri})

      like = %Like{
        like_uri: "https://example.com/likes/unknown",
        author_uri: "https://remote.example.com/users/ghost",
        object_uri: checkin.uri
      }

      assert :ok = Notifications.notify_like(like)
      assert [%Notification{summary: summary}] = rows_for(author.uri)
      assert summary =~ "ghost"
    end

    test "author name falls back to username when display_name is blank" do
      owner = owner_fixture()
      {:ok, owner} = People.set_person_role(owner, :owner)

      {:ok, _} =
        owner |> Ecto.Changeset.change(display_name: nil, username: "bobby") |> Repo.update()

      sub = subscriber_fixture(:daily)

      post = post_fixture(%{author_uri: owner.uri, name: "Trip"})
      assert :ok = Notifications.notify_new_entry(post)

      assert [%Notification{summary: summary}] = rows_for(sub.uri)
      assert summary =~ "bobby"
    end

    test "snippet is omitted when the content renders to an empty snippet" do
      owner = owner_fixture()
      {:ok, owner} = People.set_person_role(owner, :owner)
      sub = subscriber_fixture(:daily)

      # a fenced code block yields no snippet text from Snippet.snippify/2
      code_only = checkin_fixture(%{author_uri: owner.uri, name: nil, content: "```\ncode\n```"})
      assert :ok = Notifications.notify_new_entry(code_only)

      assert [%Notification{summary: summary}] = rows_for(sub.uri)
      assert summary =~ "published a checkin"
      refute summary =~ ": "
    end

    test "like url is the liked entry's human URL" do
      author = subscriber_fixture(:daily)

      checkin =
        checkin_fixture(%{
          author_uri: author.uri,
          url: "https://example.com/checkins/pretty-slug"
        })

      like = %Like{
        like_uri: "https://example.com/likes/1",
        author_uri: "https://remote.example.com/users/x",
        object_uri: checkin.uri
      }

      assert :ok = Notifications.notify_like(like)

      assert [%Notification{url: "https://example.com/checkins/pretty-slug"}] =
               rows_for(author.uri)
    end
  end

  describe "emit idempotency" do
    test "calling the same notification twice inserts one row" do
      owner = owner_fixture()
      sub = subscriber_fixture(:daily)
      checkin = checkin_fixture(%{author_uri: owner.uri})

      assert :ok = Notifications.notify_new_entry(checkin)
      assert :ok = Notifications.notify_new_entry(checkin)

      assert [%Notification{}] = rows_for(sub.uri)
    end
  end

  describe "deliver_digests/3" do
    setup do
      put_send_offset(0)
      sub = subscriber_fixture(:daily)
      # Drain auth emails delivered to the test process during fixture setup.
      flush_emails()
      %{sub: sub}
    end

    test "builds one email covering all pending rows and stamps them", %{sub: sub} do
      n1 =
        notification_fixture(%{
          recipient_uri: sub.uri,
          type: :like,
          summary: "Ada liked your post"
        })

      n2 = notification_fixture(%{recipient_uri: sub.uri, type: :reply, summary: "Bo commented"})

      summary =
        Notifications.deliver_digests(:daily, DateTime.utc_now(),
          settings_url: "https://example.com/settings/notifications",
          site_title: "Revix"
        )

      assert summary == %{sent: 1, skipped: 0}

      assert_email_sent(fn email ->
        assert {"", sub.email} in email.to
        assert email.subject =~ "Revix activity"
        assert email.subject =~ "UTC"
        assert email.text_body =~ "Ada liked your post"
        assert email.text_body =~ "Bo commented"
        assert email.html_body =~ "Ada liked your post"

        assert {:ok, "<https://example.com/settings/notifications>"} =
                 Map.fetch(email.headers, "List-Unsubscribe")
      end)

      assert Repo.get!(Notification, n1.id).sent_at != nil
      assert Repo.get!(Notification, n2.id).sent_at != nil
    end

    test "brands the From name with the site title when one is given", %{sub: sub} do
      notification_fixture(%{recipient_uri: sub.uri, summary: "Ada liked your post"})

      assert %{sent: 1} =
               Notifications.deliver_digests(:daily, DateTime.utc_now(),
                 site_title: "Curt's Place"
               )

      assert_email_sent(fn email -> assert {"Curt's Place", _addr} = email.from end)
    end

    test "falls back to the default From name when no site title is given", %{sub: sub} do
      notification_fixture(%{recipient_uri: sub.uri, summary: "Ada liked your post"})

      assert %{sent: 1} = Notifications.deliver_digests(:daily, DateTime.utc_now())

      assert_email_sent(fn email -> assert {"Revix", _addr} = email.from end)
    end

    test "omits the List-Unsubscribe header and link when no settings_url is given", %{sub: sub} do
      notification_fixture(%{recipient_uri: sub.uri, summary: "Ada liked your post", url: nil})

      assert %{sent: 1} = Notifications.deliver_digests(:daily, DateTime.utc_now())

      assert_email_sent(fn email ->
        assert :error = Map.fetch(email.headers, "List-Unsubscribe")
        assert email.text_body =~ "Ada liked your post"
        assert email.text_body =~ "account settings"
      end)
    end

    test "renders every notification type in one digest", %{sub: sub} do
      for type <- [:owner_entry, :followed_entry, :reply, :like, :registration] do
        notification_fixture(%{
          recipient_uri: sub.uri,
          type: type,
          subject_uri: "https://example.com/s/#{type}",
          summary: "a #{type} happened"
        })
      end

      assert %{sent: 1} = Notifications.deliver_digests(:daily, DateTime.utc_now())

      assert_email_sent(fn email ->
        for type <- [:owner_entry, :followed_entry, :reply, :like, :registration] do
          assert email.text_body =~ "a #{type} happened"
        end
      end)
    end

    test "skips a subscriber with no pending rows", %{sub: sub} do
      summary = Notifications.deliver_digests(:daily, DateTime.utc_now())
      assert summary == %{sent: 0, skipped: 1}
      assert rows_for(sub.uri) == []
      assert_no_email_sent()
    end

    test "a subject with rows of two types appears once, keeping the higher-priority line",
         %{sub: sub} do
      subject = "https://example.com/entries/shared-#{System.unique_integer([:positive])}"

      kept =
        notification_fixture(%{
          recipient_uri: sub.uri,
          type: :owner_entry,
          subject_uri: subject,
          summary: "Bob published a post: Rome"
        })

      collapsed =
        notification_fixture(%{
          recipient_uri: sub.uri,
          type: :followed_entry,
          subject_uri: subject,
          summary: "Bob posted a post: Rome"
        })

      assert %{sent: 1} = Notifications.deliver_digests(:daily, DateTime.utc_now())

      assert_email_sent(fn email ->
        # higher-priority (owner_entry) line kept, lower-priority one dropped
        assert email.text_body =~ "Bob published a post: Rome"
        refute email.text_body =~ "Bob posted a post: Rome"
        # the subject's summary text occurs exactly once in each body
        assert body_count(email.text_body, "Rome") == 1
        assert body_count(email.html_body, "Rome") == 1
      end)

      # both rows are stamped so neither resurfaces next run
      assert Repo.get!(Notification, kept.id).sent_at != nil
      assert Repo.get!(Notification, collapsed.id).sent_at != nil
    end

    test "excludes rows newer than the send offset", %{sub: sub} do
      put_send_offset(30)

      old = notification_fixture(%{recipient_uri: sub.uri, summary: "old"})
      backdate_notification(old, 60)
      fresh = notification_fixture(%{recipient_uri: sub.uri, summary: "fresh"})

      Notifications.deliver_digests(:daily, DateTime.utc_now())

      assert Repo.get!(Notification, old.id).sent_at != nil
      assert Repo.get!(Notification, fresh.id).sent_at == nil
    end

    test "does not include a subscriber on a different cadence" do
      weekly = subscriber_fixture(:weekly)
      notification_fixture(%{recipient_uri: weekly.uri})
      flush_emails()

      summary = Notifications.deliver_digests(:daily, DateTime.utc_now())
      assert summary.sent == 0
      assert_no_email_sent()
    end

    test "does not resend already-sent rows", %{sub: sub} do
      n = notification_fixture(%{recipient_uri: sub.uri})

      Repo.update_all(from(x in Notification, where: x.id == ^n.id),
        set: [sent_at: DateTime.utc_now(:second)]
      )

      summary = Notifications.deliver_digests(:daily, DateTime.utc_now())
      assert summary == %{sent: 0, skipped: 1}
      assert_no_email_sent()
    end

    test "leaves rows unsent when delivery fails", %{sub: sub} do
      n = notification_fixture(%{recipient_uri: sub.uri})

      summary =
        discard_log(fn ->
          Notifications.deliver_digests(:daily, DateTime.utc_now(), mailer: __MODULE__.FailMailer)
        end)

      assert summary == %{sent: 0, skipped: 1}
      assert Repo.get!(Notification, n.id).sent_at == nil
    end

    test "logs a warning identifying the recipient and deferred count on delivery failure",
         %{sub: sub} do
      notification_fixture(%{recipient_uri: sub.uri})
      notification_fixture(%{recipient_uri: sub.uri})

      log =
        capture_log(fn ->
          Notifications.deliver_digests(:daily, DateTime.utc_now(), mailer: __MODULE__.FailMailer)
        end)

      assert log =~ "notification digest delivery failed"
      assert log =~ "recipient=#{sub.uri}"
      assert log =~ "deferred=2"
    end

    test "one subscriber whose send raises does not abort the batch", %{sub: sub_ok} do
      sub_bad = subscriber_fixture(:daily)
      n_ok = notification_fixture(%{recipient_uri: sub_ok.uri, summary: "ok row"})
      n_bad = notification_fixture(%{recipient_uri: sub_bad.uri, summary: "bad row"})
      flush_emails()

      Process.put(:raise_digest_for, sub_bad.email)

      summary =
        discard_log(fn ->
          Notifications.deliver_digests(:daily, DateTime.utc_now(),
            mailer: __MODULE__.SelectiveRaiseMailer
          )
        end)

      assert summary == %{sent: 1, skipped: 1}
      # the healthy subscriber's rows were still delivered and stamped
      assert Repo.get!(Notification, n_ok.id).sent_at != nil
      # the crashing subscriber's rows stay unsent for the next run
      assert Repo.get!(Notification, n_bad.id).sent_at == nil
    end
  end

  describe "purge_sent_older_than_hours/1" do
    test "deletes only rows sent before the cutoff" do
      sub = subscriber_fixture(:daily)
      old = notification_fixture(%{recipient_uri: sub.uri})
      recent = notification_fixture(%{recipient_uri: sub.uri})
      pending = notification_fixture(%{recipient_uri: sub.uri})

      long_ago = DateTime.add(DateTime.utc_now(), -200 * 3600, :second)
      Repo.update_all(from(n in Notification, where: n.id == ^old.id), set: [sent_at: long_ago])

      Repo.update_all(from(n in Notification, where: n.id == ^recent.id),
        set: [sent_at: DateTime.utc_now(:second)]
      )

      assert {:ok, 1} = Notifications.purge_sent_older_than_hours(168)
      refute Repo.get(Notification, old.id)
      assert Repo.get(Notification, recent.id)
      assert Repo.get(Notification, pending.id)
    end
  end

  ## Helpers

  defp insert_follow(follower_uri, following_uri) do
    id = Revix.Ecto.Base58Id.autogenerate()

    Repo.insert!(%Follow{
      id: id,
      uri: "https://example.com/follows/#{id}",
      follower_uri: follower_uri,
      following_uri: following_uri,
      origin: :remote,
      accepted_at: DateTime.utc_now(:second)
    })
  end

  defp insert_note(attrs) do
    id = Revix.Ecto.Base58Id.autogenerate()

    defaults = %{
      id: id,
      uri: "https://example.com/notes/#{id}",
      url: "https://example.com/notes/#{id}",
      type: :note,
      origin: :local,
      content: "a note",
      published_at_utc: DateTime.utc_now(:second),
      published_at_local: NaiveDateTime.utc_now(:second),
      published_tz: "UTC"
    }

    {:ok, note} =
      %Entry{} |> Ecto.Changeset.change(Map.merge(defaults, attrs)) |> Repo.insert()

    note
  end

  defp companion_row(entry_uri, person_uri) do
    %Revix.EntryPeople.EntryPerson{
      id: Revix.Ecto.Base58Id.autogenerate(),
      entry_uri: entry_uri,
      person_uri: person_uri,
      type: :companion,
      origin: :local
    }
  end

  defmodule FailMailer do
    def deliver(_email), do: {:error, :smtp_down}
  end

  # Raises for the address stashed in the caller's process dict, delivers otherwise.
  defmodule SelectiveRaiseMailer do
    def deliver(email) do
      {_, to} = List.first(email.to)

      if to == Process.get(:raise_digest_for) do
        raise "boom for #{to}"
      else
        {:ok, %{}}
      end
    end
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  defp body_count(body, needle) do
    body |> String.split(needle) |> length() |> Kernel.-(1)
  end

  # Runs `fun`, swallowing its log output, and returns `fun`'s result.
  defp discard_log(fun) do
    {result, _log} = ExUnit.CaptureLog.with_log(fun)
    result
  end

  # Overrides only :send_offset_minutes in the :notifications config for this test.
  defp put_send_offset(minutes) do
    original = Application.get_env(:revix, :notifications)

    Application.put_env(
      :revix,
      :notifications,
      Keyword.put(original, :send_offset_minutes, minutes)
    )

    on_exit(fn -> Application.put_env(:revix, :notifications, original) end)
  end
end
