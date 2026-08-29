defmodule Revix.Notifications.Behaviour do
  alias Revix.Entries.Entry
  alias Revix.Likes.Like
  alias Revix.People.Person

  @callback notify_new_entry(entry :: Entry.t()) :: :ok

  @callback notify_like(like :: Like.t()) :: :ok

  @callback notify_reply(note :: Entry.t()) :: :ok

  @callback notify_registration(new_person :: Person.t()) :: :ok
end
