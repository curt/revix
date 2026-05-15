defmodule Revix.ActivityLogs do
  import Ecto.Query
  alias Revix.Repo
  alias Revix.ActivityLogs.ActivityLog

  def log_inbound(activity, enqueued?, request_id) do
    status = if enqueued?, do: "enqueued", else: "unhandled"

    %ActivityLog{}
    |> ActivityLog.create_changeset(%{
      direction: :inbound,
      activity_type: activity["type"],
      object_type: object_type(activity["object"]),
      actor_uri: activity["actor"],
      activity_uri: activity["id"],
      body: Jason.encode!(activity),
      status: status,
      request_id: request_id
    })
    |> Repo.insert()
  end

  defp object_type(%{"type" => type}), do: type
  defp object_type(_), do: nil

  def recent_inbound(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Repo.all(
      from l in ActivityLog,
        where: l.direction == :inbound,
        order_by: [desc: l.inserted_at],
        limit: ^limit
    )
  end

  def purge_older_than_hours(hours) when is_integer(hours) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours * 3600, :second)
    {count, _} = Repo.delete_all(from l in ActivityLog, where: l.inserted_at < ^cutoff)
    {:ok, count}
  end
end
