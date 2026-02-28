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

      attrs = %{
        "starts_at_local" => ~N[2026-02-16 10:30:00],
        "starts_tz" => "America/New_York",
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
      assert entry.starts_at_utc == ~U[2026-02-16 15:30:00Z]
      assert String.length(entry.id) == 11
      assert entry.uri =~ "/checkins/#{entry.id}"
      assert entry.url =~ "/checkins/#{entry.id}"
      assert entry.context == entry.uri
      assert %DateTime{} = entry.published_at_utc
      assert %NaiveDateTime{} = entry.published_at_local
      assert entry.published_tz == "America/New_York"
    end

    test "creates a checkin without content" do
      person = Revix.PeopleFixtures.person_fixture()
      scope = Revix.People.Scope.for_person(person)
      place = Revix.PlacesFixtures.place_fixture()

      attrs = %{
        "starts_at_local" => ~N[2026-02-16 10:30:00],
        "starts_tz" => "America/New_York"
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

  describe "change_checkin/1" do
    test "returns a changeset" do
      changeset = Entries.change_checkin()
      assert %Ecto.Changeset{} = changeset
    end

    test "pre-populates attrs when provided" do
      changeset = Entries.change_checkin(%{"content" => "hello"})
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
      assert comment.context == checkin.uri
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
end
