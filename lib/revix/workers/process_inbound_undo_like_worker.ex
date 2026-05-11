defmodule Revix.Workers.ProcessInboundUndoLikeWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.Likes

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => activity, "person_id" => _person_id}}) do
    actor_uri = activity["actor"]

    result =
      case activity["object"] do
        uri when is_binary(uri) ->
          Likes.undo_inbound_like(uri)

        %{"id" => like_uri} when is_binary(like_uri) ->
          Likes.undo_inbound_like(like_uri)

        %{"actor" => ^actor_uri, "object" => object_uri} when is_binary(object_uri) ->
          Likes.undo_inbound_like(actor_uri, object_uri)

        _ ->
          :ok
      end

    case result do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
