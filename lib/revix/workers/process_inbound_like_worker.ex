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
          _ -> generate_like_uri()
        end

      case Likes.upsert_inbound_like(%{
             author_uri: actor_uri,
             object_uri: object_uri,
             like_uri: like_uri
           }) do
        {:ok, _like} ->
          broadcast_like(object_uri, actor_uri)
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

  defp generate_like_uri do
    authority = System.get_env("REVIX_HOST", "revix")
    "tag:#{authority},#{Date.utc_today()}:like:#{Revix.Ecto.Base58Id.autogenerate()}"
  end
end
