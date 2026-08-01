defmodule Revix.Workers.ProcessInboundUpdateActorWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.People

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity" => activity, "person_id" => _person_id}}) do
    actor_uri = activity["actor"]
    object_uri = extract_object_uri(activity["object"])

    with uri when is_binary(uri) <- object_uri,
         actor when is_binary(actor) <- actor_uri do
      dispatch(uri, actor)
    else
      _ -> {:error, :invalid_activity}
    end
  end

  defp dispatch(uri, actor_uri) when uri == actor_uri do
    case People.get_or_fetch_person_by_uri(uri, force_refresh: true) do
      {:ok, _person} -> :ok
      {:error, :actor_id_origin_mismatch} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp dispatch(_uri, _actor_uri), do: :ok

  defp extract_object_uri(uri) when is_binary(uri), do: uri
  defp extract_object_uri(%{"id" => id}) when is_binary(id), do: id
  defp extract_object_uri(_), do: nil
end
