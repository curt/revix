defmodule Revix.Workers.PurgeActivityLogsWorker do
  use Oban.Worker, queue: :federation

  alias Revix.ActivityLogs

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    hours = Application.get_env(:revix, :activity_logs)[:retention_hours] || 72
    {:ok, _count} = ActivityLogs.purge_older_than_hours(hours)
    :ok
  end
end
