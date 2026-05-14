defmodule Revix.Workers.DeliverAcceptFollowWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.{Federation, Follows, People, Repo}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"follow_id" => id}}) do
    follow = Repo.get!(Follows.Follow, id)

    with {:ok, actor} <- People.get_local_person_by_uri(follow.following_uri),
         {:ok, inbox_url} <- Federation.resolve_inbox(follow.follower_uri) do
      Federation.deliver(build_activity(follow, actor), inbox_url, actor)
    end
  end

  defp build_activity(follow, actor) do
    %{
      "type" => "Accept",
      "id" => actor.uri <> "/accepts/" <> follow.id,
      "actor" => follow.following_uri,
      "object" => %{
        "type" => "Follow",
        "id" => follow.uri,
        "actor" => follow.follower_uri,
        "object" => follow.following_uri
      }
    }
    |> Revix.ActivityPub.contextify()
  end
end
