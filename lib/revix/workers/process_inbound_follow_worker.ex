defmodule Revix.Workers.ProcessInboundFollowWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.Follows

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => %{"object" => following_uri} = activity}})
      when is_binary(following_uri) do
    follower_uri = activity["actor"]
    {_id, fallback_uri} = Revix.ActivityPub.TagUri.generate("follow")
    follow_uri = if is_binary(activity["id"]), do: activity["id"], else: fallback_uri

    case Follows.upsert_inbound_follow(%{
           uri: follow_uri,
           follower_uri: follower_uri,
           following_uri: following_uri
         }) do
      {:ok, _follow} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{}), do: {:error, :invalid_activity}
end
