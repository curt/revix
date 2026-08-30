defmodule Revix.Repo.Migrations.BackfillRemotePeopleNotificationSchedule do
  use Ecto.Migration

  import Ecto.Query

  # notification_schedule defaults to "daily", which is meaningless for a remote
  # person (they are never a digest recipient). Set existing remote people to
  # "none"; scoped to "daily" so a deliberately-set value is never clobbered.
  def up do
    Revix.Repo.update_all(
      from(p in "people",
        where: p.origin == "remote" and p.notification_schedule == "daily"
      ),
      set: [notification_schedule: "none"]
    )
  end

  # Remote people belong at "none"; leaving them there on rollback is correct.
  def down, do: :ok
end
