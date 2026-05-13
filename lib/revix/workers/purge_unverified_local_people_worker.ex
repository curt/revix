defmodule Revix.Workers.PurgeUnverifiedLocalPeopleWorker do
  use Oban.Worker, queue: :federation

  alias Revix.People

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    days =
      Application.get_env(:revix, :purge_unverified_local_people)[:grace_period_days] || 7

    {:ok, _count} = People.purge_unverified_local_people(days)
    :ok
  end
end
