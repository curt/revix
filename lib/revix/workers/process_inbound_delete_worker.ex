defmodule Revix.Workers.ProcessInboundDeleteWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.{Entries, People}
  alias Revix.People.Person

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

  defp dispatch(uri, actor_uri) do
    case People.get_person_by_uri(uri) do
      {:ok, person} -> delete_person(person, actor_uri)
      {:error, :not_found} -> delete_entry(uri, actor_uri)
    end
  end

  defp delete_person(%Person{origin: :remote, uri: uri} = person, uri),
    do: People.delete_remote_person(person)

  defp delete_person(_, _), do: :ok

  defp delete_entry(uri, actor_uri) do
    case Entries.delete_inbound_note(uri, actor_uri) do
      {:ok, _} -> :ok
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_object_uri(uri) when is_binary(uri), do: uri
  defp extract_object_uri(%{"id" => id}) when is_binary(id), do: id
  defp extract_object_uri(_), do: nil
end
