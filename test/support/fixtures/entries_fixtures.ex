defmodule Revix.EntriesFixtures do
  alias Revix.Repo
  alias Revix.Entries
  alias Revix.Entries.Entry

  def checkin_fixture(attrs \\ %{}) do
    id = Revix.Ecto.Base58Id.autogenerate()
    {_convo_id, context_uri} = Revix.ActivityPub.TagUri.generate("convo")

    author_uri =
      if Map.has_key?(attrs, :author_uri) do
        attrs.author_uri
      else
        person = Revix.PeopleFixtures.person_fixture()
        person.uri
      end

    {:ok, entry} =
      %Entry{}
      |> Ecto.Changeset.change(
        Map.merge(
          %{
            id: id,
            uri: "https://example.com/checkins/#{id}",
            url: "https://example.com/checkins/#{id}",
            context: context_uri,
            type: :checkin,
            origin: :local,
            author_uri: author_uri,
            place_uri: "https://example.com/places/default",
            starts_at_utc: DateTime.utc_now(:second),
            starts_at_local: NaiveDateTime.utc_now(:second),
            starts_tz: "America/New_York",
            published_at_utc: DateTime.utc_now(:second),
            published_at_local: NaiveDateTime.utc_now(:second),
            published_tz: "America/New_York"
          },
          attrs
        )
      )
      |> Repo.insert()

    entry
  end

  def post_fixture(attrs \\ %{}) do
    id = Revix.Ecto.Base58Id.autogenerate()
    {_convo_id, context_uri} = Revix.ActivityPub.TagUri.generate("convo")

    author_uri =
      if Map.has_key?(attrs, :author_uri) do
        attrs.author_uri
      else
        person = Revix.PeopleFixtures.person_fixture()
        person.uri
      end

    {:ok, entry} =
      %Entry{}
      |> Ecto.Changeset.change(
        Map.merge(
          %{
            id: id,
            uri: "https://example.com/posts/#{id}",
            url: "https://example.com/posts/#{id}",
            context: context_uri,
            type: :post,
            origin: :local,
            author_uri: author_uri,
            published_at_utc: DateTime.utc_now(:second),
            published_at_local: NaiveDateTime.utc_now(:second),
            published_tz: "America/New_York"
          },
          attrs
        )
      )
      |> Repo.insert()

    entry
  end

  def draft_post_fixture(attrs \\ %{}) do
    id = Revix.Ecto.Base58Id.autogenerate()
    {_convo_id, context_uri} = Revix.ActivityPub.TagUri.generate("convo")

    author_uri =
      if Map.has_key?(attrs, :author_uri) do
        attrs.author_uri
      else
        person = Revix.PeopleFixtures.person_fixture()
        person.uri
      end

    {:ok, entry} =
      %Entry{}
      |> Ecto.Changeset.change(
        Map.merge(
          %{
            id: id,
            uri: "https://example.com/posts/#{id}",
            url: "https://example.com/posts/#{id}",
            context: context_uri,
            type: :post,
            origin: :local,
            author_uri: author_uri
          },
          attrs
        )
      )
      |> Repo.insert()

    entry
  end

  def comment_fixture(scope, checkin, attrs \\ %{}) do
    merged = Map.merge(%{"content" => "A test comment.", "published_tz" => "UTC"}, attrs)
    uri_fn = fn id -> "https://example.com/notes/#{id}" end
    {:ok, comment} = Entries.create_comment(scope, checkin, merged, uri_fn, uri_fn)
    comment
  end

  def reply_fixture(scope, parent_comment, attrs \\ %{}) do
    merged = Map.merge(%{"content" => "A test reply.", "published_tz" => "UTC"}, attrs)
    uri_fn = fn id -> "https://example.com/notes/#{id}" end
    {:ok, reply} = Entries.create_reply(scope, parent_comment, merged, uri_fn, uri_fn)
    reply
  end
end
