defmodule Revix.Workers.ProcessInboundLikeWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.{Entries, Likes}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => activity, "person_id" => _person_id}}) do
    actor_uri = activity["actor"]
    object_uri = activity["object"]

    unless is_binary(object_uri) do
      {:error, :invalid_activity}
    else
      like_uri =
        case activity["id"] do
          id when is_binary(id) -> id
          _ -> elem(Revix.ActivityPub.TagUri.generate("like"), 1)
        end

      case Likes.upsert_inbound_like(%{
             author_uri: actor_uri,
             object_uri: object_uri,
             like_uri: like_uri
           }) do
        {:ok, like} ->
          broadcast_like(object_uri, actor_uri)
          broadcast_feed_like(like)
          :ok

        {:error, %Ecto.Changeset{errors: [{:like_uri, {"has already been taken", _}} | _]}} ->
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp broadcast_like(object_uri, author_uri) do
    case Entries.get_entry_context_uri(object_uri) do
      nil ->
        :ok

      context_uri ->
        Phoenix.PubSub.broadcast(
          Revix.PubSub,
          "context:#{context_uri}",
          {:entry_liked, object_uri, author_uri}
        )
    end
  end

  defp broadcast_feed_like(like) do
    Phoenix.PubSub.broadcast(Revix.PubSub, "feed", {:like_created, like})
  end
end
