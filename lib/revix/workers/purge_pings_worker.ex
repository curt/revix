defmodule Revix.Workers.PurgePingsWorker do
  use Oban.Worker, queue: :federation

  alias Revix.Pings

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    days = Application.get_env(:revix, :pings)[:retention_days] || 7
    {:ok, _count} = Pings.purge_older_than(days)
    :ok
  end
end
