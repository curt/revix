defmodule Revix.ActivityLogsTest do
  use Revix.DataCase, async: true

  alias Revix.ActivityLogs
  alias Revix.ActivityLogs.ActivityLog

  @actor_uri "https://remote.example.com/users/alice"
  @activity_uri "https://remote.example.com/activities/1"

  defp create_activity(opts \\ []) do
    %{
      "type" => Keyword.get(opts, :type, "Create"),
      "id" => Keyword.get(opts, :id, @activity_uri),
      "actor" => Keyword.get(opts, :actor, @actor_uri),
      "object" => Keyword.get(opts, :object, %{"type" => "Note", "id" => "#{@actor_uri}/notes/1"})
    }
  end

  describe "log_inbound/3" do
    test "inserts a row with status 'enqueued' when enqueued? is true" do
      activity = create_activity()
      assert {:ok, log} = ActivityLogs.log_inbound(activity, true, nil)
      assert log.status == "enqueued"
      assert log.direction == :inbound
    end

    test "inserts a row with status 'unhandled' when enqueued? is false" do
      activity = create_activity()
      assert {:ok, log} = ActivityLogs.log_inbound(activity, false, nil)
      assert log.status == "unhandled"
    end

    test "stores actor_uri, activity_type, object_type, activity_uri" do
      activity =
        create_activity(
          type: "Create",
          object: %{"type" => "Note", "id" => "#{@actor_uri}/notes/99"}
        )

      assert {:ok, log} = ActivityLogs.log_inbound(activity, true, nil)
      assert log.actor_uri == @actor_uri
      assert log.activity_type == "Create"
      assert log.object_type == "Note"
      assert log.activity_uri == @activity_uri
    end

    test "stores nil object_type when object is not a map" do
      activity = create_activity() |> Map.put("object", "https://example.com/note/1")
      assert {:ok, log} = ActivityLogs.log_inbound(activity, true, nil)
      assert is_nil(log.object_type)
    end

    test "stores nil object_type for activities with no object field" do
      activity = %{"type" => "Follow", "id" => @activity_uri, "actor" => @actor_uri}
      assert {:ok, log} = ActivityLogs.log_inbound(activity, true, nil)
      assert is_nil(log.object_type)
    end

    test "stores the full body as JSON" do
      activity = create_activity()
      assert {:ok, log} = ActivityLogs.log_inbound(activity, true, nil)
      decoded = Jason.decode!(log.body)
      assert decoded["type"] == "Create"
      assert decoded["actor"] == @actor_uri
    end

    test "stores request_id when provided" do
      activity = create_activity()
      assert {:ok, log} = ActivityLogs.log_inbound(activity, true, "GK-2yXCCtUZRbVUAAAki")
      assert log.request_id == "GK-2yXCCtUZRbVUAAAki"
    end

    test "stores nil request_id when not provided" do
      activity = create_activity()
      assert {:ok, log} = ActivityLogs.log_inbound(activity, true, nil)
      assert is_nil(log.request_id)
    end
  end

  describe "recent_inbound/1" do
    test "returns inbound logs ordered by inserted_at descending" do
      {:ok, first} =
        ActivityLogs.log_inbound(create_activity(id: "#{@activity_uri}/1"), true, nil)

      Revix.Repo.update_all(
        from(l in ActivityLog, where: l.id == ^first.id),
        set: [inserted_at: ~U[2026-01-01 00:00:00Z]]
      )

      {:ok, second} =
        ActivityLogs.log_inbound(create_activity(id: "#{@activity_uri}/2"), true, nil)

      logs = ActivityLogs.recent_inbound()
      ids = Enum.map(logs, & &1.id)
      assert Enum.find_index(ids, &(&1 == second.id)) < Enum.find_index(ids, &(&1 == first.id))
    end

    test "only returns inbound direction rows" do
      {:ok, _log} = ActivityLogs.log_inbound(create_activity(), true, nil)

      # Insert a fake outbound row directly to verify filtering
      %ActivityLog{}
      |> ActivityLog.create_changeset(%{
        direction: :outbound,
        activity_type: "Create",
        actor_uri: @actor_uri,
        activity_uri: "#{@activity_uri}/out",
        body: "{}",
        status: "enqueued"
      })
      |> Repo.insert!()

      logs = ActivityLogs.recent_inbound()
      assert Enum.all?(logs, &(&1.direction == :inbound))
    end

    test "respects limit option" do
      for i <- 1..5 do
        ActivityLogs.log_inbound(create_activity(id: "#{@activity_uri}/#{i}"), true, nil)
      end

      logs = ActivityLogs.recent_inbound(limit: 3)
      assert length(logs) == 3
    end

    test "returns empty list when no inbound logs exist" do
      assert [] = ActivityLogs.recent_inbound()
    end
  end

  describe "purge_older_than_hours/1" do
    test "deletes rows older than the given number of hours" do
      {:ok, old} =
        ActivityLogs.log_inbound(create_activity(id: "#{@activity_uri}/old"), true, nil)

      # Backdate the row to simulate age
      cutoff = DateTime.add(DateTime.utc_now(), -5 * 3600, :second)
      Repo.update_all(from(l in ActivityLog, where: l.id == ^old.id), set: [inserted_at: cutoff])

      {:ok, count} = ActivityLogs.purge_older_than_hours(1)
      assert count >= 1
      assert is_nil(Repo.get(ActivityLog, old.id))
    end

    test "keeps rows within the retention window" do
      {:ok, recent} =
        ActivityLogs.log_inbound(create_activity(id: "#{@activity_uri}/recent"), true, nil)

      {:ok, _count} = ActivityLogs.purge_older_than_hours(72)
      assert Repo.get(ActivityLog, recent.id)
    end

    test "returns {:ok, count} with number of deleted rows" do
      {:ok, old} =
        ActivityLogs.log_inbound(create_activity(id: "#{@activity_uri}/cnt"), true, nil)

      cutoff = DateTime.add(DateTime.utc_now(), -5 * 3600, :second)
      Repo.update_all(from(l in ActivityLog, where: l.id == ^old.id), set: [inserted_at: cutoff])

      assert {:ok, 1} = ActivityLogs.purge_older_than_hours(1)
    end

    test "returns {:ok, 0} when nothing to delete" do
      assert {:ok, 0} = ActivityLogs.purge_older_than_hours(72)
    end
  end
end
