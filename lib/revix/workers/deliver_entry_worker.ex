defmodule Revix.Workers.DeliverEntryWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  alias Revix.{Federation, Follows, People, Repo}
  alias Revix.Entries.Entry

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"entry_id" => id, "activity_type" => type}}) do
    entry = Repo.get!(Entry, id)

    with {:ok, actor} <- People.get_local_person_by_uri(entry.author_uri) do
      activity = build_activity(type, entry)
      followers = Follows.get_followers_for_person(entry.author_uri)

      Enum.each(followers, fn follow ->
        case Federation.resolve_inbox(follow.follower_uri) do
          {:ok, inbox_url} -> Federation.deliver(activity, inbox_url, actor)
          _ -> :ok
        end
      end)
    end

    :ok
  end

  defp build_activity("Create", entry), do: wrap("Create", entry)
  defp build_activity("Update", entry), do: wrap("Update", entry)

  defp build_activity("Delete", entry) do
    %{
      "type" => "Delete",
      "id" => entry.uri <> "#delete",
      "actor" => entry.author_uri,
      "object" => entry.uri
    }
    |> Revix.ActivityPub.contextify()
  end

  defp wrap(type, entry) do
    %{
      "type" => type,
      "id" => entry.uri <> "#" <> String.downcase(type),
      "actor" => entry.author_uri,
      "object" => build_object(entry)
    }
    |> Revix.ActivityPub.contextify()
  end

  defp build_object(entry) do
    %{
      "type" => "Note",
      "id" => entry.uri,
      "url" => entry.url,
      "attributedTo" => entry.author_uri,
      "content" => entry.content_html,
      "inReplyTo" => entry.in_reply_to_uri,
      "context" => entry.context,
      "published" => entry.published_at_utc && DateTime.to_iso8601(entry.published_at_utc)
    }
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end
end
