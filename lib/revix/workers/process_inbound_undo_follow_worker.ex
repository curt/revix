defmodule Revix.Workers.ProcessInboundUndoFollowWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.Follows

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => activity, "person_id" => _person_id}}) do
    activity["actor"]
    |> undo(activity["object"])
    |> normalize_result()
  end

  defp undo(_actor_uri, uri) when is_binary(uri), do: Follows.undo_inbound_follow(uri)

  defp undo(_actor_uri, %{"id" => follow_uri}) when is_binary(follow_uri),
    do: Follows.undo_inbound_follow(follow_uri)

  defp undo(actor_uri, %{"actor" => actor_uri, "object" => following_uri})
       when is_binary(following_uri),
       do: Follows.undo_inbound_follow(actor_uri, following_uri)

  defp undo(_actor_uri, _object), do: :ok

  defp normalize_result({:ok, _follow}), do: :ok
  defp normalize_result(:ok), do: :ok
  defp normalize_result({:error, :not_found}), do: :ok
  defp normalize_result({:error, reason}), do: {:error, reason}
end
