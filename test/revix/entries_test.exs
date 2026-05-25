defmodule Revix.EntriesCheckinDisplayContentTest do
  use ExUnit.Case, async: true

  alias Revix.Entries
  alias Revix.Entries.Entry
  alias Revix.Places.Place

  @base %Entry{
    content: nil,
    content_html: nil,
    name: nil,
    place: nil,
    starts_at_local: nil,
    starts_at_utc: nil,
    starts_tz: nil
  }

  describe "checkin_display_content/1" do
    test "returns html content when present and non-blank" do
      checkin = %{@base | content: "Great place", content_html: "<p>Great place</p>"}
      assert Entries.checkin_display_content(checkin) == "<p>Great place</p>"
    end

    test "falls back to plain content when html is nil" do
      checkin = %{@base | content: "Just text", content_html: nil}
      assert Entries.checkin_display_content(checkin) == "Just text"
    end

    test "generates default when content is nil" do
      checkin = %{@base | name: "My Spot", starts_at_utc: ~U[2026-02-19 12:00:00Z]}

      assert Entries.checkin_display_content(checkin) ==
               "Checked into My Spot 2026-02-19 12:00 UTC."
    end

    test "generates default when content is blank whitespace" do
      checkin = %{
        @base
        | content: "   ",
          name: "My Spot",
          starts_at_utc: ~U[2026-02-19 12:00:00Z]
      }

      assert Entries.checkin_display_content(checkin) ==
               "Checked into My Spot 2026-02-19 12:00 UTC."
    end

    test "uses place name over entry name in default" do
      place = %Place{name: "Test Cafe", uri: nil, url: nil, coordinates: nil, content: nil}
      checkin = %{@base | name: "fallback", place: place, starts_at_utc: ~U[2026-02-19 12:00:00Z]}

      assert Entries.checkin_display_content(checkin) ==
               "Checked into Test Cafe 2026-02-19 12:00 UTC."
    end

    test "falls back to 'somewhere' when no name is available" do
      assert Entries.checkin_display_content(@base) == "Checked into somewhere."
    end

    test "uses local wall clock time when starts_at_local and starts_tz are present" do
      checkin = %{
        @base
        | starts_at_local: ~N[2026-02-19 05:00:00],
          starts_tz: "America/Denver",
          starts_at_utc: ~U[2026-02-19 12:00:00Z]
      }

      assert Entries.checkin_display_content(checkin) ==
               "Checked into somewhere 2026-02-19 05:00 MST."
    end

    test "falls back to UTC when local time is unavailable" do
      checkin = %{@base | starts_at_utc: ~U[2026-02-19 12:00:00Z]}

      assert Entries.checkin_display_content(checkin) ==
               "Checked into somewhere 2026-02-19 12:00 UTC."
    end
  end
end

defmodule Revix.EntriesTest do
  use Revix.DataCase

  alias Revix.Entries
  alias Revix.Entries.Entry
  alias Revix.People
  alias Revix.People.Scope
  alias Revix.Repo

  import Revix.PeopleFixtures
  import Revix.PlacesFixtures
  import Revix.EntriesFixtures
  import RevixWeb.CanonicalRoutes

  alias Revix.EntryPeople
  alias Revix.EntryPeople.EntryPerson

  defp create_comment(scope, checkin, attrs) do
    uri_fn = fn id -> "https://example.com/notes/#{id}" end
    Entries.create_comment(scope, checkin, attrs, uri_fn, uri_fn)
  end

  describe "get_local_checkins/0" do
    test "returns local checkins ordered most recent first" do
      old =
        checkin_fixture(%{
          starts_at_utc: ~U[2026-01-01 10:00:00Z],
          starts_at_local: ~N[2026-01-01 05:00:00]
        })

      new =
        checkin_fixture(%{
          starts_at_utc: ~U[2026-01-15 10:00:00Z],
          starts_at_local: ~N[2026-01-15 05:00:00]
        })

      assert [first, second] = Entries.get_local_checkins()
      assert first.id == new.id
      assert second.id == old.id
    end

    test "excludes remote checkins" do
      checkin_fixture(%{origin: :remote})

      assert [] = Entries.get_local_checkins()
    end

    test "excludes non-checkin entry types" do
      checkin_fixture(%{
        type: :note,
        place_uri: nil,
        starts_at_utc: nil,
        starts_at_local: nil,
        starts_tz: nil
      })

      assert [] = Entries.get_local_checkins()
    end

    test "returns empty list when no checkins exist" do
      assert [] = Entries.get_local_checkins()
    end
  end

  describe "get_local_checkins_for_place/1" do
    test "returns checkins for the given place" do
      place = %Revix.Places.Place{uri: "https://example.com/places/cafe"}
      checkin_fixture(%{place_uri: place.uri})
      checkin_fixture(%{place_uri: "https://example.com/places/other"})

      assert [entry] = Entries.get_local_checkins_for_place(place)
      assert entry.place_uri == place.uri
    end

    test "returns checkins ordered most recent first" do
      place = %Revix.Places.Place{uri: "https://example.com/places/cafe"}

      old =
        checkin_fixture(%{
          place_uri: place.uri,
          starts_at_utc: ~U[2026-01-01 10:00:00Z],
          starts_at_local: ~N[2026-01-01 05:00:00]
        })

      new =
        checkin_fixture(%{
          place_uri: place.uri,
          starts_at_utc: ~U[2026-01-15 10:00:00Z],
          starts_at_local: ~N[2026-01-15 05:00:00]
        })

      assert [first, second] = Entries.get_local_checkins_for_place(place)
      assert first.id == new.id
      assert second.id == old.id
    end

    test "excludes remote checkins for the place" do
      place = %Revix.Places.Place{uri: "https://example.com/places/cafe"}
      checkin_fixture(%{place_uri: place.uri, origin: :remote})

      assert [] = Entries.get_local_checkins_for_place(place)
    end

    test "returns empty list when no checkins exist for place" do
      place = %Revix.Places.Place{uri: "https://example.com/places/nowhere"}

      assert [] = Entries.get_local_checkins_for_place(place)
    end
  end

  describe "get_recent_checkins/1" do
    test "returns local checkins ordered most recent first" do
      old =
        checkin_fixture(%{
          starts_at_utc: ~U[2026-01-01 10:00:00Z],
          starts_at_local: ~N[2026-01-01 05:00:00]
        })

      new =
        checkin_fixture(%{
          starts_at_utc: ~U[2026-01-15 10:00:00Z],
          starts_at_local: ~N[2026-01-15 05:00:00]
        })

      assert [first, second] = Entries.get_recent_checkins()
      assert first.id == new.id
      assert second.id == old.id
    end

    test "respects the limit parameter" do
      for i <- 1..5 do
        checkin_fixture(%{
          starts_at_utc: DateTime.add(~U[2026-01-01 10:00:00Z], i, :day),
          starts_at_local: NaiveDateTime.add(~N[2026-01-01 05:00:00], i, :day)
        })
      end

      assert checkins = Entries.get_recent_checkins(3)
      assert length(checkins) == 3
    end

    test "defaults to 50 limit" do
      checkin_fixture()

      assert [_] = Entries.get_recent_checkins()
    end

    test "excludes remote checkins" do
      checkin_fixture(%{origin: :remote})

      assert [] = Entries.get_recent_checkins()
    end

    test "excludes non-checkin entry types" do
      checkin_fixture(%{
        type: :note,
        place_uri: nil,
        starts_at_utc: nil,
        starts_at_local: nil,
        starts_tz: nil
      })

      assert [] = Entries.get_recent_checkins()
    end

    test "returns empty list when no checkins exist" do
      assert [] = Entries.get_recent_checkins()
    end

    test "preloads place and author associations" do
      place = Revix.PlacesFixtures.place_fixture()
      checkin_fixture(%{place_uri: place.uri})

      assert [checkin] = Entries.get_recent_checkins()
      assert %Revix.Places.Place{} = checkin.place
      assert %Revix.People.Person{} = checkin.author
    end
  end

  describe "companion preloads on checkin queries" do
    setup do
      author_scope = person_scope_fixture()
      companion = person_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri, author_uri: author_scope.person.uri})
      {:ok, _} = EntryPeople.add_companion(author_scope, checkin.uri, companion.uri)
      %{author_scope: author_scope, checkin: checkin, companion: companion, place: place}
    end

    test "get_recent_checkins/1 preloads companions with person", %{
      checkin: checkin,
      companion: companion
    } do
      assert [loaded] = Entries.get_recent_checkins()
      assert loaded.id == checkin.id
      assert [%EntryPerson{} = ep] = loaded.companions
      assert %Revix.People.Person{} = ep.person
      assert ep.person.id == companion.id
    end

    test "get_local_checkins/0 preloads companions with person", %{
      checkin: checkin,
      companion: companion
    } do
      assert [loaded] = Entries.get_local_checkins()
      assert loaded.id == checkin.id
      assert [%EntryPerson{} = ep] = loaded.companions
      assert ep.person.id == companion.id
    end

    test "get_local_checkin/1 preloads companions with person", %{
      checkin: checkin,
      companion: companion
    } do
      assert {:ok, loaded} = Entries.get_local_checkin(checkin.id)
      assert [%EntryPerson{} = ep] = loaded.companions
      assert %Revix.People.Person{} = ep.person
      assert ep.person.id == companion.id
    end

    test "get_local_checkins_for_place/1 preloads companions with person", %{
      checkin: checkin,
      companion: companion,
      place: place
    } do
      assert [loaded] = Entries.get_local_checkins_for_place(place)
      assert loaded.id == checkin.id
      assert [%EntryPerson{} = ep] = loaded.companions
      assert ep.person.id == companion.id
    end

    test "checkins with no companions have an empty companions list", %{place: place} do
      no_companion_checkin = checkin_fixture(%{place_uri: place.uri})
      assert {:ok, loaded} = Entries.get_local_checkin(no_companion_checkin.id)
      assert loaded.companions == []
    end

    test "companions list only includes companion-type entry_people", %{
      author_scope: author_scope,
      checkin: checkin
    } do
      assert {:ok, loaded} = Entries.get_local_checkin(checkin.id)
      assert Enum.all?(loaded.companions, &(&1.type == :companion))
      _ = author_scope
    end
  end

  describe "get_recent_checkins_for_person/2" do
    setup do
      person = person_fixture()
      other_person = person_fixture()
      place = place_fixture()
      %{person: person, other_person: other_person, place: place}
    end

    test "returns only checkins by the given person", %{
      person: person,
      other_person: other_person,
      place: place
    } do
      checkin_fixture(%{author_uri: person.uri, place_uri: place.uri})
      checkin_fixture(%{author_uri: other_person.uri, place_uri: place.uri})

      assert [checkin] = Entries.get_recent_checkins_for_person(person)
      assert checkin.author_uri == person.uri
    end

    test "returns empty list when person has no checkins", %{person: person} do
      assert [] = Entries.get_recent_checkins_for_person(person)
    end

    test "returns checkins ordered most recent first", %{person: person, place: place} do
      old =
        checkin_fixture(%{
          author_uri: person.uri,
          place_uri: place.uri,
          starts_at_utc: ~U[2026-01-01 10:00:00Z],
          starts_at_local: ~N[2026-01-01 05:00:00]
        })

      new =
        checkin_fixture(%{
          author_uri: person.uri,
          place_uri: place.uri,
          starts_at_utc: ~U[2026-01-15 10:00:00Z],
          starts_at_local: ~N[2026-01-15 05:00:00]
        })

      assert [first, second] = Entries.get_recent_checkins_for_person(person)
      assert first.id == new.id
      assert second.id == old.id
    end

    test "defaults to a limit of 50", %{person: person, place: place} do
      for i <- 1..60 do
        checkin_fixture(%{
          author_uri: person.uri,
          place_uri: place.uri,
          starts_at_utc: DateTime.add(~U[2026-01-01 10:00:00Z], i, :hour),
          starts_at_local: NaiveDateTime.add(~N[2026-01-01 05:00:00], i, :hour)
        })
      end

      assert checkins = Entries.get_recent_checkins_for_person(person)
      assert length(checkins) == 50
    end

    test "respects a custom limit in opts", %{person: person, place: place} do
      for i <- 1..10 do
        checkin_fixture(%{
          author_uri: person.uri,
          place_uri: place.uri,
          starts_at_utc: DateTime.add(~U[2026-01-01 10:00:00Z], i, :hour),
          starts_at_local: NaiveDateTime.add(~N[2026-01-01 05:00:00], i, :hour)
        })
      end

      assert checkins = Entries.get_recent_checkins_for_person(person, limit: 3)
      assert length(checkins) == 3
    end

    test "excludes remote checkins", %{person: person, place: place} do
      checkin_fixture(%{author_uri: person.uri, place_uri: place.uri, origin: :remote})

      assert [] = Entries.get_recent_checkins_for_person(person)
    end

    test "excludes non-checkin entry types", %{person: person} do
      checkin_fixture(%{
        author_uri: person.uri,
        type: :note,
        place_uri: nil,
        starts_at_utc: nil,
        starts_at_local: nil,
        starts_tz: nil
      })

      assert [] = Entries.get_recent_checkins_for_person(person)
    end

    test "preloads place and author associations", %{person: person, place: place} do
      checkin_fixture(%{author_uri: person.uri, place_uri: place.uri})

      assert [checkin] = Entries.get_recent_checkins_for_person(person)
      assert %Revix.Places.Place{} = checkin.place
      assert %Revix.People.Person{} = checkin.author
    end
  end

  describe "create_local_checkin/3" do
    test "creates a local checkin with valid attributes" do
      person = Revix.PeopleFixtures.person_fixture()
      scope = Revix.People.Scope.for_person(person)
      place = Revix.PlacesFixtures.place_fixture()
      recent = NaiveDateTime.add(NaiveDateTime.utc_now(:second), -30, :minute)

      attrs = %{
        "starts_at_local" => recent,
        "starts_tz" => "Etc/UTC",
        "content" => "Great coffee here!"
      }

      assert {:ok, %Entry{} = entry} =
               Entries.create_local_checkin(scope, place, attrs, &checkin_uri/1, &checkin_url/2)

      assert entry.type == :checkin
      assert entry.origin == :local
      assert entry.author_uri == person.uri
      assert entry.place_uri == place.uri
      assert entry.content == "Great coffee here!"
      assert entry.content_html =~ "Great coffee here!"
      assert String.length(entry.id) == 11
      assert entry.uri =~ "/checkins/#{entry.id}"
      assert entry.url =~ "/checkins/#{entry.id}"
      assert String.starts_with?(entry.context, "tag:")
      assert %DateTime{} = entry.published_at_utc
      assert %NaiveDateTime{} = entry.published_at_local
      assert entry.published_tz == "Etc/UTC"
    end

    test "creates a checkin without content" do
      person = Revix.PeopleFixtures.person_fixture()
      scope = Revix.People.Scope.for_person(person)
      place = Revix.PlacesFixtures.place_fixture()
      recent = NaiveDateTime.add(NaiveDateTime.utc_now(:second), -30, :minute)

      attrs = %{
        "starts_at_local" => recent,
        "starts_tz" => "Etc/UTC"
      }

      assert {:ok, %Entry{} = entry} =
               Entries.create_local_checkin(scope, place, attrs, &checkin_uri/1, &checkin_url/2)

      assert entry.content == nil
      assert entry.content_html == nil
    end

    test "returns error with invalid timezone" do
      person = Revix.PeopleFixtures.person_fixture()
      scope = Revix.People.Scope.for_person(person)
      place = Revix.PlacesFixtures.place_fixture()

      attrs = %{
        "starts_at_local" => ~N[2026-02-16 10:30:00],
        "starts_tz" => "Invalid/Timezone"
      }

      assert {:error, changeset} =
               Entries.create_local_checkin(scope, place, attrs, &checkin_uri/1, &checkin_url/2)

      assert "is not a valid timezone" in errors_on(changeset).starts_tz
    end

    test "returns error without required fields" do
      person = Revix.PeopleFixtures.person_fixture()
      scope = Revix.People.Scope.for_person(person)
      place = Revix.PlacesFixtures.place_fixture()

      assert {:error, changeset} =
               Entries.create_local_checkin(scope, place, %{}, &checkin_uri/1, &checkin_url/2)

      assert "can't be blank" in errors_on(changeset).starts_at_local
      assert "can't be blank" in errors_on(changeset).starts_tz
    end
  end

  describe "change_checkin/2" do
    test "returns a changeset" do
      changeset = Entries.change_checkin(:owner)
      assert %Ecto.Changeset{} = changeset
    end

    test "pre-populates attrs when provided" do
      changeset = Entries.change_checkin(:owner, %{"content" => "hello"})
      assert Ecto.Changeset.get_change(changeset, :content) == "hello"
    end
  end

  describe "change_checkin_for_update/1" do
    test "returns a changeset for the given entry" do
      checkin = checkin_fixture()
      assert %Ecto.Changeset{data: %Entry{}} = Entries.change_checkin_for_update(checkin)
    end

    test "changeset data matches the provided entry" do
      checkin = checkin_fixture()
      changeset = Entries.change_checkin_for_update(checkin)
      assert changeset.data.id == checkin.id
    end
  end

  describe "update_local_checkin/2" do
    test "updates the content of a checkin" do
      checkin = checkin_fixture()
      assert {:ok, updated} = Entries.update_local_checkin(checkin, %{"content" => "Updated!"})
      assert updated.content == "Updated!"
      assert updated.content_html =~ "Updated!"
    end

    test "clears content when given an empty string" do
      checkin = checkin_fixture(%{content: "original"})
      assert {:ok, updated} = Entries.update_local_checkin(checkin, %{"content" => ""})
      assert updated.content == nil
    end

    test "persists changes to the database" do
      checkin = checkin_fixture()
      assert {:ok, _} = Entries.update_local_checkin(checkin, %{"content" => "Persisted"})
      {:ok, reloaded} = Entries.get_local_checkin(checkin.id)
      assert reloaded.content == "Persisted"
    end

    test "owner starts_tz change does not affect published_at_utc" do
      checkin = checkin_fixture()
      original_published_utc = checkin.published_at_utc

      assert {:ok, updated} =
               Entries.update_local_checkin(
                 checkin,
                 %{"starts_at_local" => ~N[2026-01-01 12:00:00], "starts_tz" => "America/Denver"},
                 :owner
               )

      assert updated.published_at_utc == original_published_utc
    end
  end

  describe "get_entry_by_uri/1" do
    test "returns ok with the entry for a valid uri" do
      checkin = checkin_fixture()
      assert {:ok, %Entry{} = found} = Entries.get_entry_by_uri(checkin.uri)
      assert found.id == checkin.id
    end

    test "returns error not_found for a nonexistent uri" do
      assert {:error, :not_found} = Entries.get_entry_by_uri("https://example.com/missing")
    end

    test "works for any entry type, not just checkins" do
      note =
        checkin_fixture(%{
          type: :note,
          place_uri: nil,
          starts_at_utc: nil,
          starts_at_local: nil,
          starts_tz: nil
        })

      assert {:ok, found} = Entries.get_entry_by_uri(note.uri)
      assert found.id == note.id
    end
  end

  describe "get_entry_context_uri/1" do
    test "returns the entry's own URI for a top-level checkin" do
      checkin = checkin_fixture()
      assert Entries.get_entry_context_uri(checkin.uri) == checkin.context
    end

    test "returns the root checkin context for a comment" do
      scope = person_scope_fixture()
      checkin = checkin_fixture()
      comment = comment_fixture(scope, checkin)
      assert Entries.get_entry_context_uri(comment.uri) == checkin.context
    end

    test "returns nil for an unknown URI" do
      assert Entries.get_entry_context_uri("https://example.com/nonexistent") == nil
    end

    test "returns the entry's own URI when context is nil" do
      checkin = checkin_fixture()
      Repo.update_all(from(e in Entry, where: e.id == ^checkin.id), set: [context: nil])
      assert Entries.get_entry_context_uri(checkin.uri) == checkin.uri
    end
  end

  describe "get_local_checkin/1" do
    test "returns ok with the checkin for a valid id" do
      checkin = checkin_fixture()

      assert {:ok, %Entry{} = found} = Entries.get_local_checkin(checkin.id)
      assert found.id == checkin.id
    end

    test "returns error not_found for nonexistent id" do
      assert {:error, :not_found} = Entries.get_local_checkin("11111111111")
    end

    test "returns error not_found for a remote checkin" do
      checkin = checkin_fixture(%{origin: :remote})

      assert {:error, :not_found} = Entries.get_local_checkin(checkin.id)
    end

    test "returns error not_found for a non-checkin entry" do
      entry =
        checkin_fixture(%{
          type: :note,
          place_uri: nil,
          starts_at_utc: nil,
          starts_at_local: nil,
          starts_tz: nil
        })

      assert {:error, :not_found} = Entries.get_local_checkin(entry.id)
    end
  end

  describe "create_comment/5" do
    setup do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      %{scope: scope, checkin: checkin}
    end

    test "creates a :note entry with correct fields", %{scope: scope, checkin: checkin} do
      assert {:ok, %Entry{} = comment} =
               create_comment(scope, checkin, %{
                 "content" => "Great place!",
                 "published_tz" => "America/New_York"
               })

      assert comment.type == :note
      assert comment.origin == :local
      assert comment.author_uri == scope.person.uri
      assert comment.in_reply_to_uri == checkin.uri
      assert comment.context == checkin.context
      assert comment.published_tz == "America/New_York"
      assert comment.published_at_utc != nil
      assert comment.published_at_local != nil
      assert comment.content == "Great place!"
      assert comment.content_html != nil
      assert String.contains?(comment.uri, "/notes/")
    end

    test "enforces comment_max_length for :user role", %{scope: scope, checkin: checkin} do
      long_content = String.duplicate("a", 2001)

      assert {:error, changeset} =
               create_comment(scope, checkin, %{
                 "content" => long_content,
                 "published_tz" => "UTC"
               })

      assert %{content: [_ | _]} = errors_on(changeset)
    end

    test "allows content over limit for :owner role", %{checkin: checkin} do
      owner_person = person_fixture()
      {:ok, owner_person} = People.set_person_role(owner_person, :owner)
      owner_scope = Scope.for_person(owner_person)
      long_content = String.duplicate("a", 2001)

      assert {:ok, comment} =
               create_comment(owner_scope, checkin, %{
                 "content" => long_content,
                 "published_tz" => "UTC"
               })

      assert String.length(comment.content) == 2001
    end

    test "requires content", %{scope: scope, checkin: checkin} do
      assert {:error, changeset} =
               create_comment(scope, checkin, %{
                 "content" => "",
                 "published_tz" => "UTC"
               })

      assert %{content: [_ | _]} = errors_on(changeset)
    end

    test "requires published_tz", %{scope: scope, checkin: checkin} do
      assert {:error, changeset} =
               create_comment(scope, checkin, %{"content" => "Hello"})

      assert %{published_tz: [_ | _]} = errors_on(changeset)
    end
  end

  describe "get_comments_for_entry/1" do
    setup do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      %{scope: scope, checkin: checkin}
    end

    test "returns comments in forward chronological order", %{scope: scope, checkin: checkin} do
      t1 = ~U[2024-01-01 10:00:00Z]
      t2 = ~U[2024-01-01 11:00:00Z]

      {:ok, first} =
        create_comment(scope, checkin, %{"content" => "First", "published_tz" => "UTC"})

      {:ok, second} =
        create_comment(scope, checkin, %{"content" => "Second", "published_tz" => "UTC"})

      Revix.Repo.update!(Ecto.Changeset.change(first, published_at_utc: t1))
      Revix.Repo.update!(Ecto.Changeset.change(second, published_at_utc: t2))

      comments = Entries.get_comments_for_entry(checkin.uri)

      assert length(comments) == 2
      assert hd(comments).id == first.id
      assert List.last(comments).id == second.id
    end

    test "only returns comments for the given entry", %{scope: scope, checkin: checkin} do
      other_checkin = checkin_fixture(%{place_uri: "https://example.com/places/other"})

      create_comment(scope, checkin, %{
        "content" => "For checkin",
        "published_tz" => "UTC"
      })

      create_comment(scope, other_checkin, %{
        "content" => "Other",
        "published_tz" => "UTC"
      })

      comments = Entries.get_comments_for_entry(checkin.uri)
      assert length(comments) == 1
      assert hd(comments).content == "For checkin"
    end

    test "preloads author", %{scope: scope, checkin: checkin} do
      create_comment(scope, checkin, %{"content" => "Hello", "published_tz" => "UTC"})
      [comment] = Entries.get_comments_for_entry(checkin.uri)
      assert comment.author != nil
      assert comment.author.uri == scope.person.uri
    end
  end

  describe "update_comment/2" do
    setup do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, comment} =
        create_comment(scope, checkin, %{"content" => "Original", "published_tz" => "UTC"})

      %{comment: comment}
    end

    test "updates content and content_html", %{comment: comment} do
      assert {:ok, updated} = Entries.update_comment(comment, %{"content" => "Updated text"})
      assert updated.content == "Updated text"
      assert String.contains?(updated.content_html, "Updated text")
    end

    test "requires content to be non-empty", %{comment: comment} do
      assert {:error, changeset} = Entries.update_comment(comment, %{"content" => ""})
      assert %{content: [_ | _]} = errors_on(changeset)
    end

    test "content update preserves published_at_utc", %{comment: comment} do
      original_utc = comment.published_at_utc

      assert {:ok, updated} = Entries.update_comment(comment, %{"content" => "Edited"})

      assert updated.published_at_utc == original_utc
    end
  end

  describe "delete_comment/1" do
    setup do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, comment} =
        create_comment(scope, checkin, %{
          "content" => "To delete",
          "published_tz" => "UTC"
        })

      %{comment: comment}
    end

    test "deletes the comment", %{comment: comment} do
      assert {:ok, _} = Entries.delete_comment(comment)
      assert {:error, :not_found} = Entries.get_comment(comment.id)
    end
  end

  describe "get_comment/1" do
    setup do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, comment} =
        create_comment(scope, checkin, %{"content" => "Hi", "published_tz" => "UTC"})

      %{comment: comment}
    end

    test "returns ok with the comment for a valid id", %{comment: comment} do
      assert {:ok, %Entry{} = found} = Entries.get_comment(comment.id)
      assert found.id == comment.id
    end

    test "returns error not_found for a nonexistent id" do
      assert {:error, :not_found} = Entries.get_comment("11111111111")
    end

    test "returns error not_found for an entry that is not a note" do
      checkin = checkin_fixture()
      assert {:error, :not_found} = Entries.get_comment(checkin.id)
    end
  end

  describe "change_comment_for_update/1" do
    test "returns a changeset for the given comment" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, comment} =
        create_comment(scope, checkin, %{"content" => "Hi", "published_tz" => "UTC"})

      assert %Ecto.Changeset{data: %Entry{}} = Entries.change_comment_for_update(comment)
    end

    test "changeset data matches the provided comment" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, comment} =
        create_comment(scope, checkin, %{"content" => "Hi", "published_tz" => "UTC"})

      changeset = Entries.change_comment_for_update(comment)
      assert changeset.data.id == comment.id
    end
  end

  describe "get_recent_comments/1" do
    test "returns recent comments with author and in_reply_to preloaded" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, _comment} =
        create_comment(scope, checkin, %{"content" => "Hello", "published_tz" => "UTC"})

      [comment] = Entries.get_recent_comments(10)
      assert comment.author != nil
      assert comment.in_reply_to != nil
    end

    test "respects the limit parameter" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      for i <- 1..5 do
        {:ok, comment} =
          create_comment(scope, checkin, %{
            "content" => "Comment #{i}",
            "published_tz" => "UTC"
          })

        t = DateTime.add(~U[2024-01-01 10:00:00Z], i, :hour)
        Revix.Repo.update!(Ecto.Changeset.change(comment, published_at_utc: t))
      end

      assert length(Entries.get_recent_comments(3)) == 3
    end

    test "excludes non-note entry types" do
      checkin_fixture()
      assert [] = Entries.get_recent_comments(10)
    end

    test "defaults to 50 limit" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, _} =
        create_comment(scope, checkin, %{"content" => "One", "published_tz" => "UTC"})

      assert [_] = Entries.get_recent_comments()
    end

    test "returns comments ordered most recent first" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, first} =
        create_comment(scope, checkin, %{"content" => "First", "published_tz" => "UTC"})

      {:ok, second} =
        create_comment(scope, checkin, %{"content" => "Second", "published_tz" => "UTC"})

      t1 = ~U[2024-01-01 10:00:00Z]
      t2 = ~U[2024-01-01 11:00:00Z]
      Revix.Repo.update!(Ecto.Changeset.change(first, published_at_utc: t1))
      Revix.Repo.update!(Ecto.Changeset.change(second, published_at_utc: t2))

      [newest, oldest] = Entries.get_recent_comments(10)
      assert newest.id == second.id
      assert oldest.id == first.id
    end
  end

  describe "get_recent_comments_for_person/2" do
    test "returns only comments by the given person" do
      scope = person_scope_fixture()
      other_scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, _} =
        create_comment(scope, checkin, %{"content" => "Mine", "published_tz" => "UTC"})

      {:ok, _} =
        create_comment(other_scope, checkin, %{
          "content" => "Theirs",
          "published_tz" => "UTC"
        })

      comments = Entries.get_recent_comments_for_person(scope.person)
      assert length(comments) == 1
      assert hd(comments).author_uri == scope.person.uri
    end

    test "returns empty list when person has no comments" do
      scope = person_scope_fixture()
      assert [] = Entries.get_recent_comments_for_person(scope.person)
    end

    test "orders most recent first" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, first} =
        create_comment(scope, checkin, %{"content" => "First", "published_tz" => "UTC"})

      {:ok, second} =
        create_comment(scope, checkin, %{"content" => "Second", "published_tz" => "UTC"})

      t1 = ~U[2024-01-01 10:00:00Z]
      t2 = ~U[2024-01-01 11:00:00Z]
      Revix.Repo.update!(Ecto.Changeset.change(first, published_at_utc: t1))
      Revix.Repo.update!(Ecto.Changeset.change(second, published_at_utc: t2))

      [newest, oldest] = Entries.get_recent_comments_for_person(scope.person)
      assert newest.id == second.id
      assert oldest.id == first.id
    end

    test "defaults to a limit of 50" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      for i <- 1..51 do
        create_comment(scope, checkin, %{
          "content" => "Comment #{i}",
          "published_tz" => "UTC"
        })
      end

      comments = Entries.get_recent_comments_for_person(scope.person)
      assert length(comments) == 50
    end

    test "respects custom limit in opts" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      for i <- 1..5 do
        create_comment(scope, checkin, %{
          "content" => "Comment #{i}",
          "published_tz" => "UTC"
        })
      end

      comments = Entries.get_recent_comments_for_person(scope.person, limit: 3)
      assert length(comments) == 3
    end

    test "excludes non-note entry types authored by the person" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin_fixture(%{place_uri: place.uri, author_uri: scope.person.uri})

      comments = Entries.get_recent_comments_for_person(scope.person)
      assert comments == []
    end

    test "preloads author and in_reply_to with place" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, _} =
        create_comment(scope, checkin, %{"content" => "Hi", "published_tz" => "UTC"})

      [comment] = Entries.get_recent_comments_for_person(scope.person)
      assert %Revix.People.Person{} = comment.author
      assert comment.author.id == scope.person.id
      assert %Revix.Entries.Entry{} = comment.in_reply_to
      assert %Revix.Places.Place{} = comment.in_reply_to.place
    end
  end

  describe "backfill_timezone/3" do
    # Denver, CO coordinates used as the default place in fixtures
    @denver_coords %Geo.Point{coordinates: {-104.9903, 39.7392}, srid: 4326}
    # Boulder, CO (~40km from Denver)
    @boulder_coords %Geo.Point{coordinates: {-105.2705, 40.0150}, srid: 4326}

    defp utc_checkin_fixture(place, overrides \\ %{}) do
      checkin_fixture(
        Map.merge(
          %{
            place_uri: place.uri,
            starts_at_utc: ~U[2026-01-15 15:30:00Z],
            starts_at_local: ~N[2026-01-15 15:30:00],
            starts_tz: "Etc/UTC",
            published_at_utc: ~U[2026-01-15 16:00:00Z],
            published_at_local: ~N[2026-01-15 16:00:00],
            published_tz: "Etc/UTC"
          },
          overrides
        )
      )
    end

    test "returns error for an invalid timezone" do
      assert {:error, :invalid_timezone} =
               Entries.backfill_timezone({39.7392, -104.9903}, "Not/ATimezone")
    end

    test "updates starts and published local times and tz fields for a checkin within radius" do
      place = place_fixture(%{coordinates: @denver_coords})
      checkin = utc_checkin_fixture(place)

      assert {:ok, 1} = Entries.backfill_timezone({39.7392, -104.9903}, "America/Denver")

      updated = Repo.get!(Entry, checkin.id)
      assert updated.starts_tz == "America/Denver"
      assert updated.published_tz == "America/Denver"
      # America/Denver is UTC-7 in winter; 15:30 UTC = 08:30 local
      assert updated.starts_at_local == ~N[2026-01-15 08:30:00]
      # 16:00 UTC = 09:00 local
      assert updated.published_at_local == ~N[2026-01-15 09:00:00]
    end

    test "updates ends fields when ends_at_utc is present" do
      place = place_fixture(%{coordinates: @denver_coords})

      checkin =
        utc_checkin_fixture(place, %{
          ends_at_utc: ~U[2026-01-15 17:00:00Z],
          ends_at_local: ~N[2026-01-15 17:00:00],
          ends_tz: "Etc/UTC"
        })

      assert {:ok, 1} = Entries.backfill_timezone({39.7392, -104.9903}, "America/Denver")

      updated = Repo.get!(Entry, checkin.id)
      assert updated.ends_tz == "America/Denver"
      # 17:00 UTC = 10:00 local (UTC-7)
      assert updated.ends_at_local == ~N[2026-01-15 10:00:00]
    end

    test "does not update ends fields when ends_at_utc is nil" do
      place = place_fixture(%{coordinates: @denver_coords})
      checkin = utc_checkin_fixture(place)

      assert {:ok, 1} = Entries.backfill_timezone({39.7392, -104.9903}, "America/Denver")

      updated = Repo.get!(Entry, checkin.id)
      assert updated.ends_tz == nil
      assert updated.ends_at_local == nil
    end

    test "skips checkins outside the radius" do
      near_place = place_fixture(%{coordinates: @denver_coords})
      far_place = place_fixture(%{coordinates: @boulder_coords})

      utc_checkin_fixture(near_place)
      far_checkin = utc_checkin_fixture(far_place)

      # default 20km radius — Boulder (~40km) should be excluded
      assert {:ok, 1} = Entries.backfill_timezone({39.7392, -104.9903}, "America/Denver")

      not_updated = Repo.get!(Entry, far_checkin.id)
      assert not_updated.starts_tz == "Etc/UTC"
    end

    test "skips checkins with a non-UTC timezone" do
      place = place_fixture(%{coordinates: @denver_coords})

      already_set =
        utc_checkin_fixture(place, %{
          starts_tz: "America/Chicago",
          published_tz: "America/Chicago"
        })

      assert {:ok, 0} = Entries.backfill_timezone({39.7392, -104.9903}, "America/Denver")

      not_updated = Repo.get!(Entry, already_set.id)
      assert not_updated.starts_tz == "America/Chicago"
    end

    test "returns correct count when multiple checkins are updated" do
      place = place_fixture(%{coordinates: @denver_coords})
      utc_checkin_fixture(place)
      utc_checkin_fixture(place)
      utc_checkin_fixture(place)

      assert {:ok, 3} = Entries.backfill_timezone({39.7392, -104.9903}, "America/Denver")
    end

    test "accepts a %Place{} struct as source" do
      place = place_fixture(%{coordinates: @denver_coords})
      checkin = utc_checkin_fixture(place)

      assert {:ok, 1} = Entries.backfill_timezone(place, "America/Denver")

      updated = Repo.get!(Entry, checkin.id)
      assert updated.starts_tz == "America/Denver"
    end

    test "respects custom radius option" do
      near_place = place_fixture(%{coordinates: @denver_coords})
      # ~40km away
      far_place = place_fixture(%{coordinates: @boulder_coords})

      utc_checkin_fixture(near_place)
      utc_checkin_fixture(far_place)

      # 50km radius should include both
      assert {:ok, 2} =
               Entries.backfill_timezone({39.7392, -104.9903}, "America/Denver", radius: 50_000)
    end

    test "returns {:ok, 0} when no matching checkins exist" do
      assert {:ok, 0} = Entries.backfill_timezone({39.7392, -104.9903}, "America/Denver")
    end
  end

  describe "create_reply/5" do
    setup do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, comment} =
        create_comment(scope, checkin, %{"content" => "Top-level", "published_tz" => "UTC"})

      %{scope: scope, checkin: checkin, comment: comment}
    end

    test "creates a reply with in_reply_to_uri pointing to the parent comment", %{
      scope: scope,
      checkin: checkin,
      comment: comment
    } do
      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      assert {:ok, %Entry{} = reply} =
               Entries.create_reply(
                 scope,
                 comment,
                 %{"content" => "A reply", "published_tz" => "UTC"},
                 uri_fn,
                 uri_fn
               )

      assert reply.type == :note
      assert reply.in_reply_to_uri == comment.uri
      assert reply.context == checkin.context
      assert reply.author_uri == scope.person.uri
      assert reply.content == "A reply"
    end

    test "preserves the checkin context URI from the parent comment", %{
      scope: scope,
      checkin: checkin,
      comment: comment
    } do
      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, reply} =
        Entries.create_reply(
          scope,
          comment,
          %{"content" => "Reply", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      assert reply.context == checkin.context
    end

    test "enforces comment_max_length for :user role", %{scope: scope, comment: comment} do
      uri_fn = fn id -> "https://example.com/notes/#{id}" end
      long_content = String.duplicate("a", 2001)

      assert {:error, changeset} =
               Entries.create_reply(
                 scope,
                 comment,
                 %{"content" => long_content, "published_tz" => "UTC"},
                 uri_fn,
                 uri_fn
               )

      assert %{content: [_ | _]} = errors_on(changeset)
    end

    test "preloads author on success", %{scope: scope, comment: comment} do
      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, reply} =
        Entries.create_reply(
          scope,
          comment,
          %{"content" => "Reply", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      assert %Revix.People.Person{} = reply.author
    end

    test "broadcasts :comment_created on the context topic", %{
      scope: scope,
      checkin: checkin,
      comment: comment
    } do
      uri_fn = fn id -> "https://example.com/notes/#{id}" end
      Entries.subscribe_to_context(checkin.context)

      {:ok, reply} =
        Entries.create_reply(
          scope,
          comment,
          %{"content" => "Reply", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      assert_receive {:comment_created, received}
      assert received.id == reply.id
    end

    test "uses in_reply_to_uri as context fallback when parent context is nil", %{
      scope: scope,
      checkin: checkin
    } do
      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      # Simulate a remote comment with nil context (e.g., arrived before Fix 3)
      {:ok, remote_comment} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/nil-parent",
          url: "https://remote.example.com/notes/nil-parent",
          author_uri: "https://remote.example.com/users/alice",
          content: "Remote with nil context",
          in_reply_to_uri: checkin.uri,
          context: nil,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      {:ok, reply} =
        Entries.create_reply(
          scope,
          remote_comment,
          %{"content" => "Local reply to nil-context remote", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      # context falls back to parent's in_reply_to_uri, which is checkin.uri
      assert reply.context == checkin.uri
    end

    test "broadcasts reply to checkin context topic when parent context was nil", %{
      scope: scope,
      checkin: checkin
    } do
      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, remote_comment} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/nil-parent2",
          url: "https://remote.example.com/notes/nil-parent2",
          author_uri: "https://remote.example.com/users/alice",
          content: "Remote with nil context",
          in_reply_to_uri: checkin.uri,
          context: nil,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      Entries.subscribe_to_context(checkin.uri)

      {:ok, reply} =
        Entries.create_reply(
          scope,
          remote_comment,
          %{"content" => "Reply", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      assert_receive {:comment_created, received}
      assert received.id == reply.id
    end

    test "owner can create a reply with no max-length constraint applied", %{comment: comment} do
      uri_fn = fn id -> "https://example.com/notes/#{id}" end
      owner_person = People.set_person_role(person_fixture(), :owner) |> elem(1)
      owner_scope = Scope.for_person(owner_person)

      assert {:ok, reply} =
               Entries.create_reply(
                 owner_scope,
                 comment,
                 %{"content" => "owner reply", "published_tz" => "UTC"},
                 uri_fn,
                 uri_fn
               )

      assert reply.content == "owner reply"
    end
  end

  describe "get_comment_tree/1" do
    setup do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      %{scope: scope, checkin: checkin}
    end

    test "returns empty list when no comments exist", %{checkin: checkin} do
      assert [] = Entries.get_comment_tree(checkin)
    end

    test "returns top-level comments with empty reply lists", %{scope: scope, checkin: checkin} do
      {:ok, c1} = create_comment(scope, checkin, %{"content" => "First", "published_tz" => "UTC"})

      {:ok, c2} =
        create_comment(scope, checkin, %{"content" => "Second", "published_tz" => "UTC"})

      tree = Entries.get_comment_tree(checkin)
      assert length(tree) == 2

      ids = Enum.map(tree, fn {c, _} -> c.id end)
      assert c1.id in ids
      assert c2.id in ids

      Enum.each(tree, fn {_comment, replies} -> assert replies == [] end)
    end

    test "nests replies under their parent comment", %{scope: scope, checkin: checkin} do
      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, comment} =
        create_comment(scope, checkin, %{"content" => "Top", "published_tz" => "UTC"})

      {:ok, reply} =
        Entries.create_reply(
          scope,
          comment,
          %{"content" => "Reply", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      tree = Entries.get_comment_tree(checkin)
      assert [{top, replies}] = tree |> Enum.filter(fn {c, _} -> c.id == comment.id end)
      assert top.id == comment.id
      assert length(replies) == 1
      assert hd(replies).id == reply.id
    end

    test "does not include replies as top-level comments", %{scope: scope, checkin: checkin} do
      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, comment} =
        create_comment(scope, checkin, %{"content" => "Top", "published_tz" => "UTC"})

      {:ok, _reply} =
        Entries.create_reply(
          scope,
          comment,
          %{"content" => "Reply", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      tree = Entries.get_comment_tree(checkin)
      top_level_ids = Enum.map(tree, fn {c, _} -> c.id end)
      refute _reply.id in top_level_ids
    end

    test "preloads author on all entries", %{scope: scope, checkin: checkin} do
      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, comment} =
        create_comment(scope, checkin, %{"content" => "Top", "published_tz" => "UTC"})

      {:ok, _reply} =
        Entries.create_reply(
          scope,
          comment,
          %{"content" => "Reply", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      tree = Entries.get_comment_tree(checkin)
      [{comment_loaded, replies}] = tree

      assert %Revix.People.Person{} = comment_loaded.author
      assert %Revix.People.Person{} = hd(replies).author
    end

    test "preloads in_reply_to with author on replies", %{scope: scope, checkin: checkin} do
      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, comment} =
        create_comment(scope, checkin, %{"content" => "Top", "published_tz" => "UTC"})

      {:ok, _reply} =
        Entries.create_reply(
          scope,
          comment,
          %{"content" => "Reply", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      tree = Entries.get_comment_tree(checkin)
      [{_comment_loaded, replies}] = tree
      reply = hd(replies)

      assert %Revix.Entries.Entry{} = reply.in_reply_to
      assert reply.in_reply_to.id == comment.id
      assert %Revix.People.Person{} = reply.in_reply_to.author
    end

    test "orders top-level comments oldest first", %{scope: scope, checkin: checkin} do
      t1 = ~U[2024-01-01 10:00:00Z]
      t2 = ~U[2024-01-01 11:00:00Z]

      {:ok, first} =
        create_comment(scope, checkin, %{"content" => "First", "published_tz" => "UTC"})

      {:ok, second} =
        create_comment(scope, checkin, %{"content" => "Second", "published_tz" => "UTC"})

      Revix.Repo.update!(Ecto.Changeset.change(first, published_at_utc: t1))
      Revix.Repo.update!(Ecto.Changeset.change(second, published_at_utc: t2))

      [{c1, _}, {c2, _}] = Entries.get_comment_tree(checkin)
      assert c1.id == first.id
      assert c2.id == second.id
    end

    test "includes remote top-level comments", %{checkin: checkin} do
      {:ok, _} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/1",
          url: "https://remote.example.com/notes/1",
          author_uri: "https://remote.example.com/users/alice",
          content: "Remote hello",
          in_reply_to_uri: checkin.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      tree = Entries.get_comment_tree(checkin)
      assert length(tree) == 1
      [{comment, []}] = tree
      assert comment.origin == :remote
      assert comment.author_uri == "https://remote.example.com/users/alice"
    end

    test "nests remote reply under its local parent", %{scope: scope, checkin: checkin} do
      {:ok, parent} =
        create_comment(scope, checkin, %{"content" => "Local top", "published_tz" => "UTC"})

      {:ok, _} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/2",
          url: "https://remote.example.com/notes/2",
          author_uri: "https://remote.example.com/users/bob",
          content: "Remote reply",
          in_reply_to_uri: parent.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 11:00:00Z]
        })

      tree = Entries.get_comment_tree(checkin)
      [{loaded_parent, replies}] = Enum.filter(tree, fn {c, _} -> c.id == parent.id end)
      assert loaded_parent.id == parent.id
      assert length(replies) == 1
      assert hd(replies).origin == :remote
    end

    test "author association is nil for remote comments with no local Person", %{checkin: checkin} do
      {:ok, _} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/3",
          url: "https://remote.example.com/notes/3",
          author_uri: "https://remote.example.com/users/carol",
          content: "No local person",
          in_reply_to_uri: checkin.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 12:00:00Z]
        })

      [{comment, []}] = Entries.get_comment_tree(checkin)
      assert is_nil(comment.author)
      assert comment.author_uri == "https://remote.example.com/users/carol"
    end

    test "includes remote comment with nil context when in_reply_to_uri matches checkin", %{
      checkin: checkin
    } do
      {:ok, _} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/nil-ctx",
          url: "https://remote.example.com/notes/nil-ctx",
          author_uri: "https://remote.example.com/users/alice",
          content: "Nil context comment",
          in_reply_to_uri: checkin.uri,
          context: nil,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      tree = Entries.get_comment_tree(checkin)
      assert length(tree) == 1
      [{comment, []}] = tree
      assert comment.content == "Nil context comment"
    end

    test "includes remote comment with foreign context when in_reply_to_uri matches checkin", %{
      checkin: checkin
    } do
      {:ok, _} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/foreign-ctx",
          url: "https://remote.example.com/notes/foreign-ctx",
          author_uri: "https://remote.example.com/users/alice",
          content: "Foreign context comment",
          in_reply_to_uri: checkin.uri,
          context: "https://mastodon.social/contexts/abc",
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      tree = Entries.get_comment_tree(checkin)
      assert length(tree) == 1
      [{comment, []}] = tree
      assert comment.content == "Foreign context comment"
    end

    test "nests remote reply-to-remote-reply correctly", %{checkin: checkin} do
      {:ok, remote_parent} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/rp1",
          url: "https://remote.example.com/notes/rp1",
          author_uri: "https://remote.example.com/users/alice",
          content: "Remote top-level",
          in_reply_to_uri: checkin.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      {:ok, _} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/rp2",
          url: "https://remote.example.com/notes/rp2",
          author_uri: "https://remote.example.com/users/bob",
          content: "Remote reply to remote",
          in_reply_to_uri: remote_parent.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 11:00:00Z]
        })

      tree = Entries.get_comment_tree(checkin)
      [{parent, replies}] = tree
      assert parent.id == remote_parent.id
      assert length(replies) == 1
      assert hd(replies).content == "Remote reply to remote"
    end

    test "flattens 3-level chain: local comment → remote reply → remote reply-to-reply", %{
      scope: scope,
      checkin: checkin
    } do
      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, local_comment} =
        create_comment(scope, checkin, %{"content" => "Local top", "published_tz" => "UTC"})

      {:ok, remote_reply} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/d1",
          url: "https://remote.example.com/notes/d1",
          author_uri: "https://remote.example.com/users/alice",
          content: "Remote reply",
          in_reply_to_uri: local_comment.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 11:00:00Z]
        })

      {:ok, deep_reply} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/d2",
          url: "https://remote.example.com/notes/d2",
          author_uri: "https://remote.example.com/users/bob",
          content: "Remote reply to reply",
          in_reply_to_uri: remote_reply.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 12:00:00Z]
        })

      tree = Entries.get_comment_tree(checkin)
      [{top, replies}] = tree
      assert top.id == local_comment.id
      reply_ids = Enum.map(replies, & &1.id)
      assert remote_reply.id in reply_ids
      assert deep_reply.id in reply_ids

      # local comment is the only top-level entry
      assert length(tree) == 1
      # both level-2 and level-3 are flattened into replies
      assert length(replies) == 2

      _ = uri_fn
    end

    test "flattens 4-level chain and terminates correctly", %{checkin: checkin} do
      {:ok, n1} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/f1",
          url: "https://remote.example.com/notes/f1",
          author_uri: "https://remote.example.com/users/alice",
          content: "Level 1",
          in_reply_to_uri: checkin.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      {:ok, n2} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/f2",
          url: "https://remote.example.com/notes/f2",
          author_uri: "https://remote.example.com/users/bob",
          content: "Level 2",
          in_reply_to_uri: n1.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 11:00:00Z]
        })

      {:ok, n3} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/f3",
          url: "https://remote.example.com/notes/f3",
          author_uri: "https://remote.example.com/users/alice",
          content: "Level 3",
          in_reply_to_uri: n2.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 12:00:00Z]
        })

      {:ok, n4} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/f4",
          url: "https://remote.example.com/notes/f4",
          author_uri: "https://remote.example.com/users/bob",
          content: "Level 4",
          in_reply_to_uri: n3.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 13:00:00Z]
        })

      tree = Entries.get_comment_tree(checkin)
      assert length(tree) == 1
      [{top, replies}] = tree
      assert top.id == n1.id
      reply_ids = Enum.map(replies, & &1.id)
      assert n2.id in reply_ids
      assert n3.id in reply_ids
      assert n4.id in reply_ids
      assert length(replies) == 3
    end

    test "interleaves each direct reply's sub-replies immediately after it", %{
      checkin: checkin
    } do
      # A (top) has direct replies B (10:00) and C (11:00).
      # B has sub-reply D; C has sub-reply E.
      # Expected order: [B, D, C, E] — not [B, C, D, E].
      {:ok, a} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/interleave-a",
          url: "https://remote.example.com/notes/interleave-a",
          author_uri: "https://remote.example.com/users/alice",
          content: "A (top)",
          in_reply_to_uri: checkin.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 09:00:00Z]
        })

      {:ok, b} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/interleave-b",
          url: "https://remote.example.com/notes/interleave-b",
          author_uri: "https://remote.example.com/users/alice",
          content: "B",
          in_reply_to_uri: a.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      {:ok, c} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/interleave-c",
          url: "https://remote.example.com/notes/interleave-c",
          author_uri: "https://remote.example.com/users/bob",
          content: "C",
          in_reply_to_uri: a.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 11:00:00Z]
        })

      {:ok, d} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/interleave-d",
          url: "https://remote.example.com/notes/interleave-d",
          author_uri: "https://remote.example.com/users/alice",
          content: "D (reply to B)",
          in_reply_to_uri: b.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 12:00:00Z]
        })

      {:ok, e} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/interleave-e",
          url: "https://remote.example.com/notes/interleave-e",
          author_uri: "https://remote.example.com/users/bob",
          content: "E (reply to C)",
          in_reply_to_uri: c.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 13:00:00Z]
        })

      [{_top, replies}] = Entries.get_comment_tree(checkin)
      reply_ids = Enum.map(replies, & &1.id)
      assert reply_ids == [b.id, d.id, c.id, e.id]
    end

    test "orders multiple sub-replies of the same parent chronologically", %{checkin: checkin} do
      # Top comment A has one direct reply B; B has two sub-replies D (10:00) and E (11:00).
      # Expected order: [B, D, E].
      {:ok, a} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/multi-sub-a",
          url: "https://remote.example.com/notes/multi-sub-a",
          author_uri: "https://remote.example.com/users/alice",
          content: "A (top)",
          in_reply_to_uri: checkin.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 08:00:00Z]
        })

      {:ok, b} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/multi-sub-b",
          url: "https://remote.example.com/notes/multi-sub-b",
          author_uri: "https://remote.example.com/users/alice",
          content: "B",
          in_reply_to_uri: a.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 09:00:00Z]
        })

      {:ok, d} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/multi-sub-d",
          url: "https://remote.example.com/notes/multi-sub-d",
          author_uri: "https://remote.example.com/users/bob",
          content: "D (first reply to B)",
          in_reply_to_uri: b.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      {:ok, e} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/multi-sub-e",
          url: "https://remote.example.com/notes/multi-sub-e",
          author_uri: "https://remote.example.com/users/alice",
          content: "E (second reply to B)",
          in_reply_to_uri: b.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 11:00:00Z]
        })

      [{_top, replies}] = Entries.get_comment_tree(checkin)
      reply_ids = Enum.map(replies, & &1.id)
      assert reply_ids == [b.id, d.id, e.id]
    end

    test "places childless direct reply before sibling with sub-replies", %{checkin: checkin} do
      # Top comment A; direct replies B (10:00, no children) and C (11:00) with sub-reply D.
      # Expected order: [B, C, D].
      {:ok, a} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/childless-a",
          url: "https://remote.example.com/notes/childless-a",
          author_uri: "https://remote.example.com/users/alice",
          content: "A (top)",
          in_reply_to_uri: checkin.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 09:00:00Z]
        })

      {:ok, b} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/childless-b",
          url: "https://remote.example.com/notes/childless-b",
          author_uri: "https://remote.example.com/users/alice",
          content: "B (no children)",
          in_reply_to_uri: a.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      {:ok, c} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/childless-c",
          url: "https://remote.example.com/notes/childless-c",
          author_uri: "https://remote.example.com/users/bob",
          content: "C (has child)",
          in_reply_to_uri: a.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 11:00:00Z]
        })

      {:ok, d} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/childless-d",
          url: "https://remote.example.com/notes/childless-d",
          author_uri: "https://remote.example.com/users/alice",
          content: "D (reply to C)",
          in_reply_to_uri: c.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 12:00:00Z]
        })

      [{_top, replies}] = Entries.get_comment_tree(checkin)
      reply_ids = Enum.map(replies, & &1.id)
      assert reply_ids == [b.id, c.id, d.id]
    end

    test "preserves depth-first order for a linear 4-level chain", %{checkin: checkin} do
      {:ok, n1} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/linear-1",
          url: "https://remote.example.com/notes/linear-1",
          author_uri: "https://remote.example.com/users/alice",
          content: "Level 1",
          in_reply_to_uri: checkin.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 10:00:00Z]
        })

      {:ok, n2} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/linear-2",
          url: "https://remote.example.com/notes/linear-2",
          author_uri: "https://remote.example.com/users/bob",
          content: "Level 2",
          in_reply_to_uri: n1.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 11:00:00Z]
        })

      {:ok, n3} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/linear-3",
          url: "https://remote.example.com/notes/linear-3",
          author_uri: "https://remote.example.com/users/alice",
          content: "Level 3",
          in_reply_to_uri: n2.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 12:00:00Z]
        })

      {:ok, n4} =
        Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/linear-4",
          url: "https://remote.example.com/notes/linear-4",
          author_uri: "https://remote.example.com/users/bob",
          content: "Level 4",
          in_reply_to_uri: n3.uri,
          context: checkin.context,
          published_at_utc: ~U[2024-01-01 13:00:00Z]
        })

      [{_top, replies}] = Entries.get_comment_tree(checkin)
      reply_ids = Enum.map(replies, & &1.id)
      assert reply_ids == [n2.id, n3.id, n4.id]
    end
  end

  describe "create_comment/5 PubSub broadcast" do
    setup do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      %{scope: scope, checkin: checkin}
    end

    test "broadcasts :comment_created on context topic", %{scope: scope, checkin: checkin} do
      Entries.subscribe_to_context(checkin.context)

      {:ok, comment} =
        create_comment(scope, checkin, %{"content" => "Hello", "published_tz" => "UTC"})

      assert_receive {:comment_created, received}
      assert received.id == comment.id
    end
  end

  describe "update_comment/2 PubSub broadcast" do
    setup do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, comment} =
        create_comment(scope, checkin, %{"content" => "Original", "published_tz" => "UTC"})

      %{checkin: checkin, comment: comment}
    end

    test "broadcasts :comment_updated on context topic", %{checkin: checkin, comment: comment} do
      Entries.subscribe_to_context(checkin.context)

      {:ok, updated} = Entries.update_comment(comment, %{"content" => "Updated"})

      assert_receive {:comment_updated, received}
      assert received.id == updated.id
    end
  end

  describe "delete_comment/1 PubSub broadcast" do
    setup do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})

      {:ok, comment} =
        create_comment(scope, checkin, %{"content" => "To delete", "published_tz" => "UTC"})

      %{checkin: checkin, comment: comment}
    end

    test "broadcasts :comment_deleted on context topic", %{checkin: checkin, comment: comment} do
      Entries.subscribe_to_context(checkin.context)

      {:ok, deleted} = Entries.delete_comment(comment)

      assert_receive {:comment_deleted, comment_id}
      assert comment_id == deleted.id
    end
  end

  # ── Posts ────────────────────────────────────────────────────────────────────

  defp post_uri_fn(id), do: "https://example.com/posts/#{id}"

  defp post_url_fn(%{id: id, published_at_local: nil}), do: "https://example.com/posts/#{id}"

  defp post_url_fn(%{id: id, published_at_local: local, name: name}) do
    slug = Slug.slugify(name || "") |> then(fn s -> if s in [nil, ""], do: id, else: s end)
    year = Calendar.strftime(local, "%Y")
    month = Calendar.strftime(local, "%m")
    day = Calendar.strftime(local, "%d")
    "https://example.com/posts/#{id}/#{year}/#{month}/#{day}/#{slug}"
  end

  defp post_url_fn(%{id: id}), do: "https://example.com/posts/#{id}"

  describe "get_recent_posts/1" do
    test "returns local posts ordered most recently published first" do
      old = post_fixture(%{published_at_utc: ~U[2026-01-01 10:00:00Z]})
      new = post_fixture(%{published_at_utc: ~U[2026-01-15 10:00:00Z]})

      assert [first, second] = Entries.get_recent_posts()
      assert first.id == new.id
      assert second.id == old.id
    end

    test "excludes remote posts" do
      post_fixture(%{origin: :remote})
      assert [] = Entries.get_recent_posts()
    end

    test "excludes non-post entry types" do
      checkin_fixture()
      assert [] = Entries.get_recent_posts()
    end

    test "returns empty list when no posts exist" do
      assert [] = Entries.get_recent_posts()
    end

    test "respects the limit parameter" do
      for _ <- 1..5, do: post_fixture()
      assert length(Entries.get_recent_posts(3)) == 3
    end
  end

  describe "get_local_post/1" do
    test "returns a post by id" do
      post = post_fixture()
      assert {:ok, found} = Entries.get_local_post(post.id)
      assert found.id == post.id
    end

    test "returns :not_found for unknown id" do
      assert {:error, :not_found} = Entries.get_local_post("11111111111")
    end

    test "returns :not_found for a checkin id" do
      checkin = checkin_fixture()
      assert {:error, :not_found} = Entries.get_local_post(checkin.id)
    end

    test "preloads author" do
      post = post_fixture()
      assert {:ok, found} = Entries.get_local_post(post.id)
      assert found.author != nil
    end
  end

  describe "create_local_post/4" do
    test "creates a post with required fields" do
      scope = person_scope_fixture()

      attrs = %{"published_tz" => "America/New_York", "content" => "Hello world"}

      assert {:ok, post} =
               Entries.create_local_post(scope, attrs, &post_uri_fn/1, &post_url_fn/1)

      assert post.type == :post
      assert post.origin == :local
      assert post.author_uri == scope.person.uri
      assert post.content == "Hello world"
      assert post.published_tz == "America/New_York"
      assert post.published_at_utc != nil
    end

    test "url includes YYYY/MM/DD and slug when published" do
      scope = person_scope_fixture()
      attrs = %{"published_tz" => "UTC", "name" => "Hello World"}

      assert {:ok, post} =
               Entries.create_local_post(scope, attrs, &post_uri_fn/1, &post_url_fn/1)

      year = Calendar.strftime(post.published_at_local, "%Y")
      month = Calendar.strftime(post.published_at_local, "%m")
      day = Calendar.strftime(post.published_at_local, "%d")

      assert post.url =~ "/posts/#{post.id}/#{year}/#{month}/#{day}/hello-world"
    end

    test "url uses id as slug when name is nil" do
      scope = person_scope_fixture()
      attrs = %{"published_tz" => "UTC"}

      assert {:ok, post} =
               Entries.create_local_post(scope, attrs, &post_uri_fn/1, &post_url_fn/1)

      year = Calendar.strftime(post.published_at_local, "%Y")
      month = Calendar.strftime(post.published_at_local, "%m")
      day = Calendar.strftime(post.published_at_local, "%d")

      assert post.url =~ "/posts/#{post.id}/#{year}/#{month}/#{day}/#{post.id}"
    end

    test "creates a post with an optional name" do
      scope = person_scope_fixture()
      attrs = %{"published_tz" => "UTC", "name" => "My Post Title"}

      assert {:ok, post} =
               Entries.create_local_post(scope, attrs, &post_uri_fn/1, &post_url_fn/1)

      assert post.name == "My Post Title"
    end

    test "converts content to HTML" do
      scope = person_scope_fixture()
      attrs = %{"published_tz" => "UTC", "content" => "**bold**"}

      assert {:ok, post} =
               Entries.create_local_post(scope, attrs, &post_uri_fn/1, &post_url_fn/1)

      assert post.content_html =~ "<strong>"
    end

    test "returns error when timezone is missing" do
      scope = person_scope_fixture()
      attrs = %{"content" => "No timezone"}

      assert {:error, changeset} =
               Entries.create_local_post(scope, attrs, &post_uri_fn/1, &post_url_fn/1)

      assert %{published_tz: [_ | _]} = errors_on(changeset)
    end

    test "returns error for invalid timezone" do
      scope = person_scope_fixture()
      attrs = %{"published_tz" => "Not/ATimezone"}

      assert {:error, changeset} =
               Entries.create_local_post(scope, attrs, &post_uri_fn/1, &post_url_fn/1)

      assert %{published_tz: [_ | _]} = errors_on(changeset)
    end
  end

  describe "get_local_posts_for_place/1" do
    test "returns posts associated with the place" do
      place = place_fixture()
      post = post_fixture()
      Revix.EntryPlaces.add_place(post.uri, place.uri)

      results = Entries.get_local_posts_for_place(place)
      assert length(results) == 1
      assert hd(results).id == post.id
    end

    test "returns empty list when no posts are associated" do
      place = place_fixture()
      assert [] = Entries.get_local_posts_for_place(place)
    end

    test "does not return posts associated with a different place" do
      place_a = place_fixture()
      place_b = place_fixture()
      post = post_fixture()
      Revix.EntryPlaces.add_place(post.uri, place_a.uri)

      assert [] = Entries.get_local_posts_for_place(place_b)
    end

    test "does not return checkins associated with the place" do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      _ = checkin

      assert [] = Entries.get_local_posts_for_place(place)
    end

    test "orders posts by published_at_utc descending" do
      place = place_fixture()

      older =
        post_fixture(%{
          published_at_utc: ~U[2026-01-01 00:00:00Z],
          published_at_local: ~N[2026-01-01 00:00:00],
          published_tz: "UTC"
        })

      newer =
        post_fixture(%{
          published_at_utc: ~U[2026-06-01 00:00:00Z],
          published_at_local: ~N[2026-06-01 00:00:00],
          published_tz: "UTC"
        })

      Revix.EntryPlaces.add_place(older.uri, place.uri)
      Revix.EntryPlaces.add_place(newer.uri, place.uri)

      [first, second] = Entries.get_local_posts_for_place(place)
      assert first.id == newer.id
      assert second.id == older.id
    end
  end

  describe "create_local_post_with_companions/5" do
    test "creates post and companions atomically" do
      scope = person_scope_fixture()
      companion = person_fixture()
      attrs = %{"published_tz" => "UTC"}

      assert {:ok, post} =
               Entries.create_local_post_with_companions(
                 scope,
                 attrs,
                 &post_uri_fn/1,
                 &post_url_fn/1,
                 [companion.uri]
               )

      assert Revix.EntryPeople.companion_of?(companion.uri, post.uri)
    end

    test "rolls back if companion insert fails" do
      scope = person_scope_fixture()
      attrs = %{"published_tz" => "BAD/ZONE"}

      assert {:error, _} =
               Entries.create_local_post_with_companions(
                 scope,
                 attrs,
                 &post_uri_fn/1,
                 &post_url_fn/1,
                 []
               )

      assert [] = Entries.get_recent_posts()
    end
  end

  describe "create_local_post_with_companions/6 — with place_uris" do
    test "creates post with places atomically" do
      scope = person_scope_fixture()
      place = place_fixture()
      attrs = %{"published_tz" => "UTC"}

      assert {:ok, post} =
               Entries.create_local_post_with_companions(
                 scope,
                 attrs,
                 &post_uri_fn/1,
                 &post_url_fn/1,
                 [],
                 [place.uri]
               )

      assert Revix.EntryPlaces.place_of?(place.uri, post.uri)
    end

    test "creates post with both companions and places" do
      scope = person_scope_fixture()
      companion = person_fixture()
      place = place_fixture()
      attrs = %{"published_tz" => "UTC"}

      assert {:ok, post} =
               Entries.create_local_post_with_companions(
                 scope,
                 attrs,
                 &post_uri_fn/1,
                 &post_url_fn/1,
                 [companion.uri],
                 [place.uri]
               )

      assert Revix.EntryPeople.companion_of?(companion.uri, post.uri)
      assert Revix.EntryPlaces.place_of?(place.uri, post.uri)
    end

    test "defaults to empty place_uris when omitted" do
      scope = person_scope_fixture()
      place = place_fixture()
      attrs = %{"published_tz" => "UTC"}

      assert {:ok, post} =
               Entries.create_local_post_with_companions(
                 scope,
                 attrs,
                 &post_uri_fn/1,
                 &post_url_fn/1,
                 []
               )

      refute Revix.EntryPlaces.place_of?(place.uri, post.uri)
    end
  end

  describe "update_local_post/4" do
    test "updates content" do
      post = post_fixture()

      assert {:ok, updated} =
               Entries.update_local_post(
                 post,
                 %{"content" => "New content"},
                 :user,
                 &post_url_fn/1
               )

      assert updated.content == "New content"
    end

    test "updates name" do
      post = post_fixture()

      assert {:ok, updated} =
               Entries.update_local_post(post, %{"name" => "New Title"}, :user, &post_url_fn/1)

      assert updated.name == "New Title"
    end

    test "name change updates url slug" do
      post =
        post_fixture(%{
          name: "Old Title",
          published_at_local: ~N[2026-03-15 10:00:00]
        })

      assert {:ok, updated} =
               Entries.update_local_post(post, %{"name" => "New Title"}, :user, &post_url_fn/1)

      assert updated.url =~ "/posts/#{post.id}/2026/03/15/new-title"
    end

    test "content-only change preserves the date and slug in url" do
      post = post_fixture(%{published_at_local: ~N[2026-03-15 10:00:00], name: "Same Title"})

      assert {:ok, first} =
               Entries.update_local_post(post, %{"content" => "First"}, :user, &post_url_fn/1)

      assert {:ok, second} =
               Entries.update_local_post(first, %{"content" => "Second"}, :user, &post_url_fn/1)

      assert second.url =~ "/posts/#{post.id}/2026/03/15/same-title"
      assert second.url == first.url
    end

    test "owner can update published_tz" do
      scope = person_scope_fixture()

      {:ok, post} =
        Entries.create_local_post(
          scope,
          %{"published_tz" => "UTC"},
          &post_uri_fn/1,
          &post_url_fn/1
        )

      People.set_person_role(scope.person, :owner)

      assert {:ok, updated} =
               Entries.update_local_post(
                 post,
                 %{"published_tz" => "America/Denver"},
                 :owner,
                 &post_url_fn/1
               )

      assert updated.published_tz == "America/Denver"
    end

    test "owner timezone change shifts date segment when date crosses midnight" do
      scope = person_scope_fixture()

      {:ok, post} =
        Entries.create_local_post(
          scope,
          %{"published_tz" => "UTC", "name" => "Midnight Post"},
          &post_uri_fn/1,
          &post_url_fn/1
        )

      People.set_person_role(scope.person, :owner)

      assert {:ok, updated} =
               Entries.update_local_post(
                 post,
                 %{"published_tz" => "America/Denver"},
                 :owner,
                 &post_url_fn/1
               )

      year = Calendar.strftime(updated.published_at_local, "%Y")
      month = Calendar.strftime(updated.published_at_local, "%m")
      day = Calendar.strftime(updated.published_at_local, "%d")

      assert updated.url =~ "/posts/#{post.id}/#{year}/#{month}/#{day}/midnight-post"
    end

    test "non-owner cannot update published_tz" do
      scope = person_scope_fixture()

      {:ok, post} =
        Entries.create_local_post(
          scope,
          %{"published_tz" => "UTC"},
          &post_uri_fn/1,
          &post_url_fn/1
        )

      {:ok, _} =
        Entries.update_local_post(
          post,
          %{"published_tz" => "America/Denver"},
          :user,
          &post_url_fn/1
        )

      {:ok, reloaded} = Entries.get_local_post(post.id)
      assert reloaded.published_tz == "UTC"
    end

    test "owner timezone change preserves published_at_utc" do
      scope = person_scope_fixture()

      {:ok, post} =
        Entries.create_local_post(
          scope,
          %{"published_tz" => "UTC"},
          &post_uri_fn/1,
          &post_url_fn/1
        )

      original_utc = post.published_at_utc
      People.set_person_role(scope.person, :owner)

      assert {:ok, updated} =
               Entries.update_local_post(
                 post,
                 %{"published_tz" => "America/Denver"},
                 :owner,
                 &post_url_fn/1
               )

      assert updated.published_at_utc == original_utc
      assert updated.published_tz == "America/Denver"

      expected_local =
        DateTime.shift_zone!(original_utc, "America/Denver") |> DateTime.to_naive()

      assert updated.published_at_local == expected_local
    end

    test "owner content update preserves published_at_utc" do
      scope = person_scope_fixture()

      {:ok, post} =
        Entries.create_local_post(
          scope,
          %{"published_tz" => "UTC"},
          &post_uri_fn/1,
          &post_url_fn/1
        )

      original_utc = post.published_at_utc
      People.set_person_role(scope.person, :owner)

      assert {:ok, updated} =
               Entries.update_local_post(
                 post,
                 %{"content" => "Updated content"},
                 :owner,
                 &post_url_fn/1
               )

      assert updated.published_at_utc == original_utc
    end
  end

  describe "change_post/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = Entries.change_post(:owner)
    end

    test "returns changeset without timezone validation (draft mode)" do
      cs = Entries.change_post(:owner, %{"published_tz" => "Bad/Zone"})
      assert %Ecto.Changeset{} = cs
    end
  end

  describe "get_recent_posts_for_person/2" do
    test "returns posts for the given person only" do
      scope_a = person_scope_fixture()
      scope_b = person_scope_fixture()
      post_fixture(%{author_uri: scope_a.person.uri})
      post_fixture(%{author_uri: scope_b.person.uri})

      results = Entries.get_recent_posts_for_person(scope_a.person)
      assert length(results) == 1
      assert hd(results).author_uri == scope_a.person.uri
    end

    test "respects the limit option" do
      scope = person_scope_fixture()
      for _ <- 1..5, do: post_fixture(%{author_uri: scope.person.uri})
      assert length(Entries.get_recent_posts_for_person(scope.person, limit: 2)) == 2
    end
  end

  describe "update_inbound_note/2" do
    @remote_note_uri "https://remote.example.com/notes/abc"
    @remote_actor_uri "https://remote.example.com/users/alice"

    defp note_attrs(uri \\ @remote_note_uri) do
      %{
        uri: uri,
        url: uri,
        author_uri: @remote_actor_uri,
        content: "<p>Hello</p>",
        published_at_utc: ~U[2026-05-14 10:00:00Z]
      }
    end

    test "updates an existing remote entry" do
      {:ok, existing} = Entries.create_inbound_note(note_attrs())

      updated_attrs = Map.put(note_attrs(), :content, "<p>Updated</p>")
      assert {:ok, updated} = Entries.update_inbound_note(@remote_note_uri, updated_attrs)
      assert updated.id == existing.id
      assert updated.content == "<p>Updated</p>"
    end

    test "creates the entry when not found (upsert path)" do
      assert {:ok, created} = Entries.update_inbound_note(@remote_note_uri, note_attrs())
      assert created.uri == @remote_note_uri
      assert created.origin == :remote
    end

    test "returns {:error, :not_remote} when entry has local origin" do
      checkin = checkin_fixture()

      assert {:error, :not_remote} =
               Entries.update_inbound_note(checkin.uri, note_attrs(checkin.uri))
    end
  end

  describe "delete_inbound_note/2" do
    @del_note_uri "https://remote.example.com/notes/del"
    @del_actor_uri "https://remote.example.com/users/alice"

    defp insert_remote_note do
      {:ok, entry} =
        Entries.create_inbound_note(%{
          uri: @del_note_uri,
          url: @del_note_uri,
          author_uri: @del_actor_uri,
          content: "<p>Hi</p>",
          published_at_utc: ~U[2026-05-14 10:00:00Z]
        })

      entry
    end

    test "hard-deletes a remote entry when actor matches" do
      insert_remote_note()
      assert {:ok, _} = Entries.delete_inbound_note(@del_note_uri, @del_actor_uri)
      assert is_nil(Repo.get_by(Entry, uri: @del_note_uri))
    end

    test "returns :ok when entry not found (idempotent)" do
      assert :ok = Entries.delete_inbound_note(@del_note_uri, @del_actor_uri)
    end

    test "returns :ok when actor does not match entry author_uri" do
      insert_remote_note()

      assert :ok =
               Entries.delete_inbound_note(
                 @del_note_uri,
                 "https://remote.example.com/users/mallory"
               )

      assert Repo.get_by!(Entry, uri: @del_note_uri).origin == :remote
    end

    test "returns :ok for a local-origin entry" do
      checkin = checkin_fixture()
      assert :ok = Entries.delete_inbound_note(checkin.uri, @del_actor_uri)
      assert Repo.get_by!(Entry, uri: checkin.uri).origin == :local
    end
  end

  describe "outbound delivery enqueueing" do
    test "create_local_checkin enqueues DeliverEntryWorker with Create" do
      scope = person_scope_fixture()
      place = place_fixture()

      {:ok, entry} =
        Entries.create_local_checkin(
          scope,
          place,
          %{"starts_at_local" => NaiveDateTime.utc_now(:second), "starts_tz" => "UTC"},
          &checkin_uri/1,
          &checkin_url/2
        )

      assert_enqueued(
        worker: Revix.Workers.DeliverEntryWorker,
        args: %{"entry_id" => entry.id, "activity_type" => "Create"}
      )
    end

    test "create_local_post enqueues DeliverEntryWorker with Create" do
      scope = person_scope_fixture()

      {:ok, entry} =
        Entries.create_local_post(
          scope,
          %{"content" => "Hello!", "published_tz" => "UTC"},
          &post_uri_fn/1,
          &post_url_fn/1
        )

      assert_enqueued(
        worker: Revix.Workers.DeliverEntryWorker,
        args: %{"entry_id" => entry.id, "activity_type" => "Create"}
      )
    end

    test "create_comment enqueues DeliverEntryWorker with Create" do
      scope = person_scope_fixture()
      checkin = checkin_fixture()

      {:ok, entry} =
        create_comment(scope, checkin, %{"content" => "A comment.", "published_tz" => "UTC"})

      assert_enqueued(
        worker: Revix.Workers.DeliverEntryWorker,
        args: %{"entry_id" => entry.id, "activity_type" => "Create"}
      )
    end

    test "update_local_checkin enqueues DeliverEntryWorker with Update" do
      scope = person_scope_fixture()
      place = place_fixture()

      {:ok, entry} =
        Entries.create_local_checkin(
          scope,
          place,
          %{"starts_at_local" => NaiveDateTime.utc_now(:second), "starts_tz" => "UTC"},
          &checkin_uri/1,
          &checkin_url/2
        )

      {:ok, updated} = Entries.update_local_checkin(entry, %{"content" => "Updated"})

      assert_enqueued(
        worker: Revix.Workers.DeliverEntryWorker,
        args: %{"entry_id" => updated.id, "activity_type" => "Update"}
      )
    end

    test "update_comment enqueues DeliverEntryWorker with Update" do
      scope = person_scope_fixture()
      checkin = checkin_fixture()

      {:ok, comment} =
        create_comment(scope, checkin, %{"content" => "Original", "published_tz" => "UTC"})

      {:ok, updated} = Entries.update_comment(comment, %{"content" => "Edited"})

      assert_enqueued(
        worker: Revix.Workers.DeliverEntryWorker,
        args: %{"entry_id" => updated.id, "activity_type" => "Update"}
      )
    end

    test "delete_comment enqueues DeliverEntryWorker with Delete" do
      scope = person_scope_fixture()
      checkin = checkin_fixture()

      {:ok, comment} =
        create_comment(scope, checkin, %{"content" => "To delete", "published_tz" => "UTC"})

      {:ok, _} = Entries.delete_comment(comment)

      assert_enqueued(
        worker: Revix.Workers.DeliverEntryWorker,
        args: %{"entry_id" => comment.id, "activity_type" => "Delete"}
      )
    end
  end

  # ── get_recent_comments_for_feed/2 ───────────────────────────────────────

  describe "get_recent_comments_for_feed/2 with include_replies option" do
    test "returns both comments and replies when include_replies: true" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = comment_fixture(scope, checkin)

      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, reply} =
        Entries.create_reply(
          scope,
          comment,
          %{"content" => "A reply", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      ids =
        Entries.get_recent_comments_for_feed(50, include_replies: true) |> Enum.map(& &1.id)

      assert comment.id in ids
      assert reply.id in ids
    end

    test "excludes replies when include_replies: false" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = comment_fixture(scope, checkin)

      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, reply} =
        Entries.create_reply(
          scope,
          comment,
          %{"content" => "A reply", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      ids =
        Entries.get_recent_comments_for_feed(50, include_replies: false) |> Enum.map(& &1.id)

      assert comment.id in ids
      refute reply.id in ids
    end
  end

  # ── get_recent_comments_for_person_feed/2 ────────────────────────────────

  describe "get_recent_comments_for_person_feed/2 with include_replies: true" do
    test "includes replies authored by the person" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = comment_fixture(scope, checkin)

      uri_fn = fn id -> "https://example.com/notes/#{id}" end

      {:ok, reply} =
        Entries.create_reply(
          scope,
          comment,
          %{"content" => "A reply", "published_tz" => "UTC"},
          uri_fn,
          uri_fn
        )

      ids =
        Entries.get_recent_comments_for_person_feed(scope.person,
          include_replies: true,
          limit: 50
        )
        |> Enum.map(& &1.id)

      assert comment.id in ids
      assert reply.id in ids
    end
  end

  # ── get_comment_for_feed/1 ────────────────────────────────────────────────

  describe "get_comment_for_feed/1" do
    test "returns {:ok, comment} with preloads for a valid note id" do
      scope = person_scope_fixture()
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      comment = comment_fixture(scope, checkin)

      assert {:ok, found} = Entries.get_comment_for_feed(comment.id)
      assert found.id == comment.id
      assert %Revix.Entries.Entry{} = found.in_reply_to
    end

    test "returns {:error, :not_found} for a nonexistent id" do
      nonexistent_id = Revix.Ecto.Base58Id.autogenerate()
      assert {:error, :not_found} = Entries.get_comment_for_feed(nonexistent_id)
    end

    test "returns {:error, :not_found} when id belongs to a checkin (not a note)" do
      place = place_fixture()
      checkin = checkin_fixture(%{place_uri: place.uri})
      assert {:error, :not_found} = Entries.get_comment_for_feed(checkin.id)
    end
  end
end
