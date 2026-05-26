defmodule Revix.Workers.DeliverEntryWorker do
  use Oban.Worker, queue: :federation, max_attempts: 1

  import Ecto.Query

  alias Revix.{Federation, Follows, People, Repo}
  alias Revix.Entries.Entry
  alias Revix.Media.EntryImage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"entry_id" => id, "activity_type" => type}}) do
    entry =
      Entry
      |> where([e], e.id == ^id)
      |> preload(^entry_preloads())
      |> Repo.one!()

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
      "object" => build_object(entry),
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => [RevixWeb.CanonicalRoutes.person_followers_url(entry.author.id)]
    }
    |> Revix.ActivityPub.contextify()
  end

  defp build_object(%Entry{type: :checkin} = entry),
    do: Revix.ActivityPub.to_checkin_activity(entry)

  defp build_object(%Entry{type: :post} = entry), do: Revix.ActivityPub.to_post_activity(entry)
  defp build_object(%Entry{type: :note} = entry), do: Revix.ActivityPub.to_note_activity(entry)

  defp entry_preloads do
    [
      :author,
      :place,
      entry_places: [:place],
      entry_images: ordered_entry_images_query()
    ]
  end

  defp ordered_entry_images_query do
    from(ei in EntryImage, order_by: [asc: ei.position], preload: [:image])
  end
end
