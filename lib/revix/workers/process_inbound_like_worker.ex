defmodule Revix.Workers.ProcessInboundLikeWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.Likes

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

      case Likes.create_inbound_like(%{
             author_uri: actor_uri,
             object_uri: object_uri,
             like_uri: like_uri
           }) do
        {:ok, _like} ->
          :ok

        {:error, %Ecto.Changeset{errors: errors}} ->
          cond do
            unique_error?(errors, :author_uri) -> :ok
            unique_error?(errors, :like_uri) -> :ok
            true -> {:error, :changeset_error}
          end
      end
    end
  end

  defp generate_like_uri do
    authority = System.get_env("REVIX_HOST", "revix")
    "tag:#{authority},#{Date.utc_today()}:like:#{Revix.Ecto.Base58Id.autogenerate()}"
  end

  defp unique_error?(errors, field) do
    Enum.any?(errors, fn
      {^field, {"has already been taken", _}} -> true
      _ -> false
    end)
  end
end
