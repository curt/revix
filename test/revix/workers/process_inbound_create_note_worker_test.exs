defmodule Revix.Workers.ProcessInboundCreateNoteWorkerTest do
  use Revix.DataCase, async: false

  alias Revix.Workers.ProcessInboundCreateNoteWorker
  alias Revix.Entries
  alias Revix.Entries.Entry
  alias Revix.EntryPlaces
  alias Revix.Follows
  alias Revix.Media
  alias Revix.Places
  alias Revix.Repo

  import Revix.PeopleFixtures
  import Revix.EntriesFixtures

  @jpeg_binary File.read!("test/support/fixtures/test.jpg")

  @actor_uri "https://remote.example.com/users/alice"
  @note_uri "https://remote.example.com/users/alice/notes/abc123"

  defp base_note(in_reply_to_uri, opts \\ []) do
    context = Keyword.get(opts, :context, in_reply_to_uri)

    %{
      "id" => @note_uri,
      "type" => "Note",
      "actor" => @actor_uri,
      "content" => "<p>Hello!</p>",
      "inReplyTo" => in_reply_to_uri,
      "context" => context,
      "published" => "2026-05-12T10:00:00Z"
    }
  end

  defp base_activity(note) do
    %{
      "type" => "Create",
      "id" => "#{@actor_uri}/activities/1",
      "actor" => @actor_uri,
      "object" => note
    }
  end

  defp perform(activity, person_id) do
    perform_job(ProcessInboundCreateNoteWorker, %{
      "activity" => activity,
      "person_id" => person_id
    })
  end

  describe "perform/1" do
    test "silently ignores a note whose context and inReplyTo don't resolve to any local entry" do
      person = person_fixture()
      note = base_note("https://remote.example.com/checkins/xyz")
      activity = base_activity(note)

      assert :ok = perform(activity, person.id)
      assert Repo.get_by(Entry, uri: @note_uri) == nil
    end

    test "silently ignores a note whose context resolves to a remote entry" do
      person = person_fixture()
      remote_checkin = checkin_fixture(%{origin: :remote})
      note = base_note(remote_checkin.uri)
      activity = base_activity(note)

      assert :ok = perform(activity, person.id)
      assert Repo.get_by(Entry, uri: @note_uri) == nil
    end

    test "persists when context is a local checkin URI" do
      person = person_fixture()
      checkin = checkin_fixture()
      note = base_note(checkin.uri)
      activity = base_activity(note)

      assert :ok = perform(activity, person.id)

      saved = Repo.get_by!(Entry, uri: @note_uri)
      assert saved.type == :note
      assert saved.origin == :remote
      assert saved.author_uri == @actor_uri
      assert saved.in_reply_to_uri == checkin.uri
      assert saved.context == checkin.uri
      assert saved.published_at_utc == ~U[2026-05-12 10:00:00Z]
    end

    test "persists when only inReplyTo resolves to a local entry (no context field)" do
      person = person_fixture()
      checkin = checkin_fixture()

      note =
        base_note(checkin.uri)
        |> Map.delete("context")

      activity = base_activity(note)

      assert :ok = perform(activity, person.id)
      assert Repo.get_by!(Entry, uri: @note_uri).origin == :remote
    end

    test "is idempotent — second call with same note URI returns :ok without duplicate" do
      person = person_fixture()
      checkin = checkin_fixture()
      note = base_note(checkin.uri)
      activity = base_activity(note)

      assert :ok = perform(activity, person.id)
      assert :ok = perform(activity, person.id)

      assert Repo.aggregate(from(e in Entry, where: e.uri == ^@note_uri), :count) == 1
    end

    test "broadcasts {:comment_created, note} on the context topic when saved" do
      person = person_fixture()
      checkin = checkin_fixture()
      note = base_note(checkin.uri)
      activity = base_activity(note)

      Entries.subscribe_to_context(checkin.uri)

      assert :ok = perform(activity, person.id)

      assert_received {:comment_created, received_note}
      assert received_note.uri == @note_uri
    end

    test "does not broadcast when the note is silently ignored" do
      person = person_fixture()
      note = base_note("https://remote.example.com/checkins/foreign")
      activity = base_activity(note)

      Entries.subscribe_to_context("https://remote.example.com/checkins/foreign")

      assert :ok = perform(activity, person.id)

      refute_received {:comment_created, _}
    end

    test "returns error when object is missing" do
      person = person_fixture()

      activity = %{
        "type" => "Create",
        "id" => "#{@actor_uri}/activities/1",
        "actor" => @actor_uri
      }

      assert {:error, :invalid_activity} = perform(activity, person.id)
    end

    test "returns error when object is not a map" do
      person = person_fixture()

      activity = %{
        "type" => "Create",
        "id" => "#{@actor_uri}/activities/1",
        "actor" => @actor_uri,
        "object" => @note_uri
      }

      assert {:error, :invalid_activity} = perform(activity, person.id)
    end

    test "returns error when object has no id" do
      person = person_fixture()

      note =
        base_note("https://remote.example.com/checkins/xyz")
        |> Map.delete("id")

      activity = base_activity(note)

      assert {:error, :invalid_activity} = perform(activity, person.id)
    end

    test "persists when actor is followed by a local user (no local context)" do
      follower = person_fixture()
      scope = person_scope_fixture(follower)

      note = %{
        "id" => @note_uri,
        "type" => "Note",
        "content" => "<p>Hello from someone you follow!</p>",
        "published" => "2026-05-14T10:00:00Z"
      }

      activity = %{
        "type" => "Create",
        "id" => "#{@actor_uri}/activities/99",
        "actor" => @actor_uri,
        "object" => note
      }

      {:ok, _} = Follows.follow(scope, @actor_uri)

      assert :ok = perform(activity, follower.id)
      assert Repo.get_by!(Entry, uri: @note_uri).origin == :remote
    end

    test "Article type is accepted the same as Note" do
      person = person_fixture()
      checkin = checkin_fixture()

      note =
        base_note(checkin.uri)
        |> Map.put("type", "Article")

      activity =
        base_activity(note)
        |> Map.put("object", note)

      assert :ok = perform(activity, person.id)
      assert Repo.get_by!(Entry, uri: @note_uri).origin == :remote
    end
  end

  describe "attachment import" do
    test "downloads and attaches a single Document attachment" do
      person = person_fixture()
      checkin = checkin_fixture()

      Req.Test.stub(:inbound_attachment, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "image/jpeg")
        |> Plug.Conn.send_resp(200, @jpeg_binary)
      end)

      note =
        base_note(checkin.uri)
        |> Map.put("attachment", %{
          "type" => "Document",
          "mediaType" => "image/jpeg",
          "url" => "https://remote.example.com/media/photo.jpg"
        })

      assert :ok = perform(base_activity(note), person.id)

      entry = Repo.get_by!(Entry, uri: @note_uri)
      images = Media.get_images_for_entry(entry.id)
      assert length(images) == 1
      assert hd(images).content_type == "image/jpeg"
    end

    test "downloads and attaches an array of Document attachments" do
      person = person_fixture()
      checkin = checkin_fixture()

      Req.Test.stub(:inbound_attachment, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "image/jpeg")
        |> Plug.Conn.send_resp(200, @jpeg_binary)
      end)

      note =
        base_note(checkin.uri)
        |> Map.put("attachment", [
          %{
            "type" => "Document",
            "mediaType" => "image/jpeg",
            "url" => "https://remote.example.com/media/a.jpg"
          },
          %{
            "type" => "Document",
            "mediaType" => "image/jpeg",
            "url" => "https://remote.example.com/media/b.jpg"
          }
        ])

      assert :ok = perform(base_activity(note), person.id)

      entry = Repo.get_by!(Entry, uri: @note_uri)
      assert length(Media.get_images_for_entry(entry.id)) == 2
    end

    test "stores alt and caption from attachment name/summary fields" do
      person = person_fixture()
      checkin = checkin_fixture()

      Req.Test.stub(:inbound_attachment, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "image/jpeg")
        |> Plug.Conn.send_resp(200, @jpeg_binary)
      end)

      note =
        base_note(checkin.uri)
        |> Map.put("attachment", %{
          "type" => "Document",
          "mediaType" => "image/jpeg",
          "url" => "https://remote.example.com/media/photo.jpg",
          "name" => "A nice photo",
          "summary" => "<p>alt text</p>"
        })

      assert :ok = perform(base_activity(note), person.id)

      entry = Repo.get_by!(Entry, uri: @note_uri)
      [image] = Media.get_images_for_entry(entry.id)
      assert image.alt == "A nice photo"
      assert image.caption == "<p>alt text</p>"
    end

    test "silently skips attachment whose body fails magic byte check" do
      person = person_fixture()
      checkin = checkin_fixture()

      Req.Test.stub(:inbound_attachment, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "image/jpeg")
        |> Plug.Conn.send_resp(200, "not an image")
      end)

      note =
        base_note(checkin.uri)
        |> Map.put("attachment", %{
          "type" => "Document",
          "mediaType" => "image/jpeg",
          "url" => "https://remote.example.com/media/fake.jpg"
        })

      assert :ok = perform(base_activity(note), person.id)

      entry = Repo.get_by!(Entry, uri: @note_uri)
      assert [] = Media.get_images_for_entry(entry.id)
    end

    test "silently skips attachment on non-200 response" do
      person = person_fixture()
      checkin = checkin_fixture()

      Req.Test.stub(:inbound_attachment, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      note =
        base_note(checkin.uri)
        |> Map.put("attachment", %{
          "type" => "Document",
          "mediaType" => "image/jpeg",
          "url" => "https://remote.example.com/media/gone.jpg"
        })

      assert :ok = perform(base_activity(note), person.id)

      entry = Repo.get_by!(Entry, uri: @note_uri)
      assert [] = Media.get_images_for_entry(entry.id)
    end

    test "silently skips attachment on transport error" do
      person = person_fixture()
      checkin = checkin_fixture()

      Req.Test.stub(:inbound_attachment, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      note =
        base_note(checkin.uri)
        |> Map.put("attachment", %{
          "type" => "Document",
          "mediaType" => "image/jpeg",
          "url" => "https://remote.example.com/media/timeout.jpg"
        })

      assert :ok = perform(base_activity(note), person.id)

      entry = Repo.get_by!(Entry, uri: @note_uri)
      assert [] = Media.get_images_for_entry(entry.id)
    end

    test "silently skips non-Document attachment types" do
      person = person_fixture()
      checkin = checkin_fixture()

      note =
        base_note(checkin.uri)
        |> Map.put("attachment", %{
          "type" => "Video",
          "mediaType" => "video/mp4",
          "url" => "https://remote.example.com/media/video.mp4"
        })

      assert :ok = perform(base_activity(note), person.id)

      entry = Repo.get_by!(Entry, uri: @note_uri)
      assert [] = Media.get_images_for_entry(entry.id)
    end
  end

  describe "location import" do
    test "saves entry as :checkin when exactly one location with coordinates + startTime" do
      person = person_fixture()
      checkin = checkin_fixture()

      note =
        base_note(checkin.uri)
        |> Map.put("location", %{
          "type" => "Place",
          "id" => "https://remote.example.com/places/1",
          "name" => "Remote Cafe",
          "latitude" => 40.0,
          "longitude" => -105.0
        })
        |> Map.put("startTime", "2026-05-14T18:00:00Z")

      assert :ok = perform(base_activity(note), person.id)

      saved = Repo.get_by!(Entry, uri: @note_uri)
      assert saved.type == :checkin
      assert saved.starts_at_utc == ~U[2026-05-14 18:00:00Z]
      assert is_binary(saved.place_uri)

      place = Repo.get_by!(Revix.Places.Place, uri: saved.place_uri)
      assert place.name == "Remote Cafe"
      assert place.origin == :remote
    end

    test "creates a remote Place record for the checkin location" do
      person = person_fixture()
      checkin = checkin_fixture()

      note =
        base_note(checkin.uri)
        |> Map.put("location", %{
          "type" => "Place",
          "id" => "https://remote.example.com/places/2",
          "name" => "Remote Bar",
          "latitude" => 41.0,
          "longitude" => -106.0
        })
        |> Map.put("startTime", "2026-05-14T19:00:00Z")

      assert :ok = perform(base_activity(note), person.id)

      assert {:ok, place} =
               Places.upsert_remote_place(%{
                 uri: "https://remote.example.com/places/2",
                 name: "Remote Bar",
                 latitude: 41.0,
                 longitude: -106.0
               })

      assert place.origin == :remote
    end

    test "saves entry as :note when location has no coordinates" do
      person = person_fixture()
      checkin = checkin_fixture()

      note =
        base_note(checkin.uri)
        |> Map.put("location", %{
          "type" => "Place",
          "id" => "https://remote.example.com/places/nocoords",
          "name" => "No Coords Place"
        })
        |> Map.put("startTime", "2026-05-14T18:00:00Z")

      assert :ok = perform(base_activity(note), person.id)

      saved = Repo.get_by!(Entry, uri: @note_uri)
      assert saved.type == :note
      assert is_nil(saved.place_uri)
    end

    test "saves entry as :note when startTime is absent even with one location" do
      person = person_fixture()
      checkin = checkin_fixture()

      note =
        base_note(checkin.uri)
        |> Map.put("location", %{
          "type" => "Place",
          "id" => "https://remote.example.com/places/3",
          "name" => "Somewhere",
          "latitude" => 40.0,
          "longitude" => -105.0
        })

      assert :ok = perform(base_activity(note), person.id)

      saved = Repo.get_by!(Entry, uri: @note_uri)
      assert saved.type == :note
    end

    test "saves entry as :note when two locations are present; both linked via EntryPlaces" do
      person = person_fixture()
      checkin = checkin_fixture()

      note =
        base_note(checkin.uri)
        |> Map.put("location", [
          %{
            "type" => "Place",
            "id" => "https://remote.example.com/places/4",
            "name" => "Place A",
            "latitude" => 40.0,
            "longitude" => -105.0
          },
          %{
            "type" => "Place",
            "id" => "https://remote.example.com/places/5",
            "name" => "Place B",
            "latitude" => 41.0,
            "longitude" => -106.0
          }
        ])
        |> Map.put("startTime", "2026-05-14T18:00:00Z")

      assert :ok = perform(base_activity(note), person.id)

      saved = Repo.get_by!(Entry, uri: @note_uri)
      assert saved.type == :note

      entry_places = EntryPlaces.get_places_for_entry(saved.uri)
      assert length(entry_places) == 2
    end

    test "array-form single location with startTime is still treated as checkin" do
      person = person_fixture()
      checkin = checkin_fixture()

      note =
        base_note(checkin.uri)
        |> Map.put("location", [
          %{
            "type" => "Place",
            "id" => "https://remote.example.com/places/6",
            "name" => "Single in Array",
            "latitude" => 42.0,
            "longitude" => -107.0
          }
        ])
        |> Map.put("startTime", "2026-05-14T20:00:00Z")

      assert :ok = perform(base_activity(note), person.id)

      saved = Repo.get_by!(Entry, uri: @note_uri)
      assert saved.type == :checkin
    end

    test "entry with one coordinate-less location and startTime gets no EntryPlace row" do
      person = person_fixture()
      checkin = checkin_fixture()

      note =
        base_note(checkin.uri)
        |> Map.put("location", %{
          "type" => "Place",
          "id" => "https://remote.example.com/places/nocoords2",
          "name" => "No Coords"
        })
        |> Map.put("startTime", "2026-05-14T18:00:00Z")

      assert :ok = perform(base_activity(note), person.id)

      saved = Repo.get_by!(Entry, uri: @note_uri)
      assert [] = EntryPlaces.get_places_for_entry(saved.uri)
    end
  end
end
