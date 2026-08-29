defmodule Revix.Workers.PurgeSentNotificationsWorker do
  use Oban.Worker, queue: :federation

  alias Revix.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    hours = Application.get_env(:revix, :notifications)[:retention_hours] || 168
    {:ok, _count} = Notifications.purge_sent_older_than_hours(hours)
    :ok
  end
end
