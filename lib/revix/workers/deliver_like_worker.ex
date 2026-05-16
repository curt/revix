defmodule Revix.Workers.DeliverLikeWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.{Entries, Federation, Likes, People, Repo}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"like_id" => id}}) do
    like = Repo.get!(Likes.Like, id)

    case Entries.get_entry_by_uri(like.object_uri) do
      {:ok, _local_entry} ->
        :ok

      {:error, :not_found} ->
        with {:ok, actor} <- People.get_local_person_by_uri(like.author_uri),
             {:ok, inbox_url} <- resolve_object_inbox(like.object_uri) do
          Federation.deliver(build_activity(like), inbox_url, actor)
        end
    end
  end

  defp resolve_object_inbox(object_uri) do
    with {:ok, object} <- Federation.fetch_actor(object_uri),
         attributed_to when is_binary(attributed_to) <- object["attributedTo"] do
      Federation.resolve_inbox(attributed_to)
    else
      _ -> {:error, :no_attributed_to}
    end
  end

  defp build_activity(like) do
    %{
      "type" => "Like",
      "id" => like.like_uri,
      "actor" => like.author_uri,
      "object" => like.object_uri
    }
    |> Revix.ActivityPub.contextify()
  end
end
