defmodule Revix.NotificationsFixtures do
  @moduledoc """
  Test helpers for the `Revix.Notifications` context.
  """

  import Ecto.Query

  alias Revix.Notifications
  alias Revix.Notifications.Notification
  alias Revix.PeopleFixtures
  alias Revix.Repo

  @doc """
  Inserts a `Notification` row directly. `attrs` is a map with atom keys, merged
  over the defaults.
  """
  def notification_fixture(attrs \\ %{}) do
    id = Revix.Ecto.Base58Id.autogenerate()

    defaults = %{
      id: id,
      recipient_uri: "https://example.com/people/recipient-#{System.unique_integer([:positive])}",
      type: :like,
      subject_uri: "https://example.com/entries/subject-#{System.unique_integer([:positive])}",
      actor_uri: "https://example.com/people/actor",
      summary: "Someone liked your post",
      url: "https://example.com/entries/subject"
    }

    {:ok, notification} =
      %Notification{}
      |> Ecto.Changeset.change(Map.merge(defaults, attrs))
      |> Repo.insert()

    notification
  end

  @doc """
  A confirmed local person with a chosen notification cadence (default `:daily`).
  """
  def subscriber_fixture(schedule \\ :daily, attrs \\ %{}) do
    person = PeopleFixtures.person_fixture(attrs)
    {:ok, person} = Notifications.set_schedule(person, schedule)
    person
  end

  @doc """
  Backdates a notification's `inserted_at` so it falls outside the send offset.
  """
  def backdate_notification(%Notification{id: id}, minutes_ago) do
    at = DateTime.add(DateTime.utc_now(:second), -minutes_ago * 60, :second)
    Repo.update_all(from(n in Notification, where: n.id == ^id), set: [inserted_at: at])
  end
end
