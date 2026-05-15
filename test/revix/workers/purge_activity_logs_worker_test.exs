defmodule Revix.Workers.PurgeActivityLogsWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.ActivityLogs
  alias Revix.ActivityLogs.ActivityLog
  alias Revix.Workers.PurgeActivityLogsWorker

  @actor_uri "https://remote.example.com/users/alice"
  @activity_uri "https://remote.example.com/activities/purge"

  defp activity(id_suffix) do
    %{
      "type" => "Follow",
      "id" => "#{@activity_uri}/#{id_suffix}",
      "actor" => @actor_uri
    }
  end

  defp backdate(log, hours_ago) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours_ago * 3600, :second)
    Repo.update_all(from(l in ActivityLog, where: l.id == ^log.id), set: [inserted_at: cutoff])
  end

  describe "perform/1" do
    test "deletes rows older than the configured retention_hours" do
      {:ok, old} = ActivityLogs.log_inbound(activity("old"), true, nil)
      backdate(old, 100)

      assert :ok = perform_job(PurgeActivityLogsWorker, %{})
      assert is_nil(Repo.get(ActivityLog, old.id))
    end

    test "keeps rows within the retention window" do
      {:ok, recent} = ActivityLogs.log_inbound(activity("recent"), true, nil)

      assert :ok = perform_job(PurgeActivityLogsWorker, %{})
      assert Repo.get(ActivityLog, recent.id)
    end

    test "uses Application.get_env retention_hours" do
      original = Application.get_env(:revix, :activity_logs)

      try do
        Application.put_env(:revix, :activity_logs, retention_hours: 2)

        {:ok, old} = ActivityLogs.log_inbound(activity("env-old"), true, nil)
        backdate(old, 3)

        {:ok, fresh} = ActivityLogs.log_inbound(activity("env-fresh"), true, nil)
        backdate(fresh, 1)

        assert :ok = perform_job(PurgeActivityLogsWorker, %{})

        assert is_nil(Repo.get(ActivityLog, old.id))
        assert Repo.get(ActivityLog, fresh.id)
      after
        Application.put_env(:revix, :activity_logs, original)
      end
    end
  end
end
