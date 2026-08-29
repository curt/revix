defmodule Revix.Workers.NotificationDigestWorkerTest do
  use Revix.DataCase, async: false

  import Revix.NotificationsFixtures
  import Swoosh.TestAssertions
  import ExUnit.CaptureLog

  alias Revix.Notifications.Notification
  alias Revix.Workers.NotificationDigestWorker

  setup do
    original = Application.get_env(:revix, :notifications)
    Application.put_env(:revix, :notifications, Keyword.put(original, :send_offset_minutes, 0))
    on_exit(fn -> Application.put_env(:revix, :notifications, original) end)
    :ok
  end

  describe "perform/1" do
    test "delivers a digest, stamps the rows, and logs a summary at :info" do
      sub = subscriber_fixture(:daily)
      n = notification_fixture(%{recipient_uri: sub.uri, summary: "Ada liked your post"})
      flush_emails()

      log =
        with_log_level(:info, fn ->
          capture_log(fn ->
            assert :ok = perform_job(NotificationDigestWorker, %{"schedule" => "daily"})
          end)
        end)

      assert_email_sent(fn email ->
        assert email.subject =~ "activity"
        assert email.text_body =~ "Ada liked your post"
      end)

      assert Repo.get!(Notification, n.id).sent_at != nil
      assert log =~ "notification digest (daily)"
      assert log =~ "sent: 1"
    end

    test "a quiet run logs at :debug, not :info" do
      _sub = subscriber_fixture(:none)
      flush_emails()

      log =
        with_log_level(:debug, fn ->
          capture_log(fn ->
            assert :ok = perform_job(NotificationDigestWorker, %{"schedule" => "hourly"})
          end)
        end)

      assert_no_email_sent()
      assert log =~ "[debug]"
      assert log =~ "nothing to send"
      refute log =~ "[info]"
    end

    test "cancels on an invalid schedule arg" do
      assert {:cancel, _} = perform_job(NotificationDigestWorker, %{"schedule" => "yearly"})
    end

    test "cancels when the schedule arg is missing" do
      assert {:cancel, _} = perform_job(NotificationDigestWorker, %{})
    end

    test "clears its Logger metadata after the run" do
      _sub = subscriber_fixture(:none)
      flush_emails()

      assert :ok = perform_job(NotificationDigestWorker, %{"schedule" => "daily"})
      refute Keyword.has_key?(Logger.metadata(), :notification_digest)
    end
  end

  describe "purge worker" do
    test "PurgeSentNotificationsWorker deletes old sent rows" do
      sub = subscriber_fixture(:daily)
      old = notification_fixture(%{recipient_uri: sub.uri})

      long_ago = DateTime.add(DateTime.utc_now(), -400 * 3600, :second)
      Repo.update_all(from(n in Notification, where: n.id == ^old.id), set: [sent_at: long_ago])

      assert :ok = perform_job(Revix.Workers.PurgeSentNotificationsWorker, %{})
      refute Repo.get(Notification, old.id)
    end
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  # The test env pins the Logger primary level to :warning, which drops
  # :info/:debug before capture_log can see them. Temporarily lower it.
  defp with_log_level(level, fun) do
    previous = Logger.level()
    Logger.configure(level: level)

    try do
      fun.()
    after
      Logger.configure(level: previous)
    end
  end
end
