defmodule Revix.Notifications.Behaviour do
  alias Revix.Entries.Entry
  alias Revix.EntryPeople.EntryPerson
  alias Revix.Likes.Like
  alias Revix.People.Person

  @callback notify_new_entry(entry :: Entry.t()) :: :ok

  @callback notify_like(like :: Like.t()) :: :ok

  @callback notify_reply(note :: Entry.t()) :: :ok

  @callback notify_registration(new_person :: Person.t()) :: :ok

  @callback notify_companion_tag(entry_person :: EntryPerson.t()) :: :ok

  @callback notify_entry_companions(entry :: Entry.t()) :: :ok

  @callback retract_companion_tag(entry_uri :: String.t(), person_uri :: String.t()) :: :ok
end
