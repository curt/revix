defmodule Revix.URLs do
  @moduledoc """
  The absolute URLs the domain layer needs, without depending on the web layer.

  Each function delegates to the module configured as `config :revix, :urls`:
  the web layer's canonical routes module, which owns the routes. The domain
  calls these instead of the web layer, so it has no compile-time dependency
  on it.
  """

  @callback person_inbox_url(id :: String.t()) :: String.t()
  @callback person_outbox_url(id :: String.t()) :: String.t()
  @callback person_followers_url(id :: String.t()) :: String.t()
  @callback person_following_url(id :: String.t()) :: String.t()
  @callback person_liked_url(id :: String.t()) :: String.t()
  @callback entry_likes_url(id :: String.t()) :: String.t()
  @callback entry_replies_url(id :: String.t()) :: String.t()
  @callback avatar_url(person :: Revix.People.Person.t()) :: String.t()
  @callback home_url() :: String.t()
  @callback notification_settings_url() :: String.t()
  @callback absolute_url(path :: String.t()) :: String.t()
  @callback local_host() :: String.t()

  def person_inbox_url(id), do: impl().person_inbox_url(id)
  def person_outbox_url(id), do: impl().person_outbox_url(id)
  def person_followers_url(id), do: impl().person_followers_url(id)
  def person_following_url(id), do: impl().person_following_url(id)
  def person_liked_url(id), do: impl().person_liked_url(id)
  def entry_likes_url(id), do: impl().entry_likes_url(id)
  def entry_replies_url(id), do: impl().entry_replies_url(id)
  def avatar_url(person), do: impl().avatar_url(person)
  def home_url, do: impl().home_url()
  def notification_settings_url, do: impl().notification_settings_url()

  @doc "A path on this site, as an absolute URL."
  def absolute_url(path), do: impl().absolute_url(path)

  @doc "This site's host, for telling local URLs from remote ones."
  def local_host, do: impl().local_host()

  defp impl, do: Application.fetch_env!(:revix, :urls)
end
