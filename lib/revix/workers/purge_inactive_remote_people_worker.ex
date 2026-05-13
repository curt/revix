defmodule Revix.Workers.PurgeInactiveRemotePeopleWorker do
  use Oban.Worker, queue: :federation

  alias Revix.People

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    hours =
      Application.get_env(:revix, :purge_inactive_remote_people)[:grace_period_hours] || 24

    {:ok, _count} = People.purge_inactive_remote_people(hours)
    :ok
  end
end
