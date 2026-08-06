defmodule RevixWeb.Live.ActivityFeedHelpers do
  alias Revix.ActivityFeed

  @doc """
  Computes the next pagination cursor from a freshly-loaded page of activities,
  falling back to the current cursor when the page is empty.
  """
  def next_cursor([], cursor), do: cursor

  def next_cursor(activities, _cursor) do
    activities
    |> List.last()
    |> ActivityFeed.activity_timestamp()
  end
end
