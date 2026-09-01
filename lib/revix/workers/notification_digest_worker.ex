defmodule Revix.Workers.NotificationDigestWorker do
  @moduledoc """
  Per-cadence digest fan-out. Registered in the `crontab` once per schedule
  (`hourly` / `daily` / `weekly`); each run delivers one digest email to every
  subscriber on that cadence who has unsent notifications.

  This worker is the composition root: it pulls the web-layer settings URL and
  site title and hands them to the pure `Revix.Notifications` context.
  """

  use Oban.Worker, queue: :mailers, max_attempts: 3

  require Logger

  alias Revix.Notifications
  alias Revix.Sites
  alias RevixWeb.CanonicalRoutes

  @schedules ~w(hourly daily weekly monthly)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"schedule" => schedule}}) when schedule in @schedules do
    # Oban reuses processes; clear our key after the run so it does not bleed
    # into the next job on this process.
    Logger.metadata(notification_digest: schedule)
    site = Sites.get_site_or_default(CanonicalRoutes.home_url())

    summary =
      Notifications.deliver_digests(String.to_existing_atom(schedule), DateTime.utc_now(),
        settings_url: CanonicalRoutes.notification_settings_url(),
        site_title: site.title
      )

    log_summary(schedule, summary)
    :ok
  after
    Logger.metadata(notification_digest: nil)
  end

  def perform(%Oban.Job{args: args}) do
    {:cancel, "invalid schedule arg: #{inspect(args)}"}
  end

  # Quiet runs (nothing sent, nothing deferred) log at :debug so hourly cron on a
  # low-traffic instance does not spam :info. Any activity logs at :info.
  defp log_summary(schedule, %{sent: 0, skipped: 0}) do
    Logger.debug("notification digest (#{schedule}): nothing to send")
  end

  defp log_summary(schedule, summary) do
    Logger.info("notification digest (#{schedule}): #{inspect(summary)}")
  end
end
