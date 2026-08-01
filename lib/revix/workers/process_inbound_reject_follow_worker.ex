defmodule Revix.Workers.ProcessInboundRejectFollowWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.Follows
  alias Revix.Workers.InboundFollowResponseHelpers

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => activity, "person_id" => _person_id}}) do
    InboundFollowResponseHelpers.perform(activity, &Follows.reject_outbound_follow/2)
  end
end
