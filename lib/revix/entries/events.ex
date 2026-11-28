defmodule Revix.Entries.Events do
  @moduledoc false
  # Side effects shared by Revix.Entries and its submodules: PubSub broadcasts,
  # outbound delivery, and subscriber notifications.
  alias Revix.Entries.Entry

  def broadcast_context(context_uri, event) do
    Phoenix.PubSub.broadcast(Revix.PubSub, "context:#{context_uri}", event)
  end

  def broadcast_feed(event) do
    Phoenix.PubSub.broadcast(Revix.PubSub, "feed", event)
  end

  # Single chokepoint for outbound federation delivery. Every publish path lands
  # here exactly once (LiveView flows call it after their transaction commits via
  # `enqueue_delivery/2`; simpler flows via `maybe_enqueue_create/3`), so the
  # subscriber-notification trigger lives here too.
  def enqueue_deliver_entry(entry, type) do
    %{"entry_id" => entry.id, "activity_type" => type}
    |> Revix.Workers.DeliverEntryWorker.new()
    |> Oban.insert()

    maybe_notify_subscribers(entry, type)
  end

  # Subscriber notifications for checkins/posts. First publication notifies (and
  # fans out to any companions attached while the entry was still a draft); a
  # later edit rewrites the snippet on rows that haven't been delivered yet. A
  # deletion of any entry type (comments included) drops its undelivered rows.
  def maybe_notify_subscribers(%Entry{type: type} = entry, "Create")
      when type in [:post, :checkin] do
    notifications().notify_new_entry(entry)
    notifications().notify_entry_companions(entry)
    :ok
  end

  def maybe_notify_subscribers(%Entry{type: type} = entry, "Update")
      when type in [:post, :checkin] do
    notifications().refresh_entry_notifications(entry)
    :ok
  end

  def maybe_notify_subscribers(%Entry{} = entry, "Delete") do
    notifications().retract_entry_notifications([entry.uri])
    :ok
  end

  def maybe_notify_subscribers(_entry, _type), do: :ok

  def notifications, do: Application.get_env(:revix, :notifications_impl, Revix.Notifications)

  def tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  def tap_ok(result, _fun), do: result
end
