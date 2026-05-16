defmodule Revix.LikesFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Revix.Likes` context.
  """

  alias Revix.Likes
  alias Revix.PeopleFixtures

  @doc """
  Creates an active (non-unliked) like.

  Accepts optional attrs:
  - `:author_uri` — defaults to a newly created person's URI
  - `:object_uri` — defaults to a placeholder URI
  - `:published_tz` — defaults to "UTC"

  Returns the `%Likes.Like{}` struct.
  """
  def like_fixture(attrs \\ %{}) do
    scope =
      if Map.has_key?(attrs, :author_uri) do
        person = PeopleFixtures.person_scope_fixture()
        %{person | person: %{person.person | uri: attrs.author_uri}}
      else
        PeopleFixtures.person_scope_fixture()
      end

    object_uri = Map.get(attrs, :object_uri, "https://example.com/entries/default")
    timezone = Map.get(attrs, :published_tz, "UTC")

    {:ok, like} = Likes.like_entry(scope, object_uri, timezone)
    like
  end
end
