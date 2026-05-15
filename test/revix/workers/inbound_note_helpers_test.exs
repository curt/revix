defmodule Revix.Workers.InboundNoteHelpersTest do
  use Revix.DataCase, async: true

  alias Revix.Workers.InboundNoteHelpers

  import Revix.EntriesFixtures

  @actor_uri "https://remote.example.com/users/alice"

  describe "local_context?/1" do
    test "returns true when context is a local entry URI" do
      checkin = checkin_fixture()
      note = %{"context" => checkin.uri, "inReplyTo" => nil}
      assert InboundNoteHelpers.local_context?(note)
    end

    test "returns true when inReplyTo is a local entry URI (no context)" do
      checkin = checkin_fixture()
      note = %{"inReplyTo" => checkin.uri}
      assert InboundNoteHelpers.local_context?(note)
    end

    test "returns false when context is a remote entry" do
      _remote = checkin_fixture(%{origin: :remote})
      remote_checkin = checkin_fixture(%{origin: :remote})
      note = %{"context" => remote_checkin.uri, "inReplyTo" => nil}
      refute InboundNoteHelpers.local_context?(note)
    end

    test "returns false when context and inReplyTo are both unknown URIs" do
      note = %{"context" => "https://remote.example.com/unknown", "inReplyTo" => nil}
      refute InboundNoteHelpers.local_context?(note)
    end

    test "returns false when context and inReplyTo are both nil" do
      note = %{"context" => nil, "inReplyTo" => nil}
      refute InboundNoteHelpers.local_context?(note)
    end
  end

  describe "parse_datetime/1" do
    test "parses a valid ISO 8601 string" do
      assert %DateTime{year: 2026, month: 5, day: 14} =
               InboundNoteHelpers.parse_datetime("2026-05-14T10:00:00Z")
    end

    test "returns nil for nil input" do
      assert is_nil(InboundNoteHelpers.parse_datetime(nil))
    end

    test "returns nil for invalid string" do
      assert is_nil(InboundNoteHelpers.parse_datetime("not-a-date"))
    end
  end

  describe "extract_note_attrs/2" do
    test "maps all note fields to attrs map" do
      note = %{
        "id" => "https://remote.example.com/notes/1",
        "url" => "https://remote.example.com/notes/1",
        "content" => "<p>Hello</p>",
        "inReplyTo" => "https://example.com/checkins/abc",
        "context" => "https://example.com/checkins/abc",
        "published" => "2026-05-14T10:00:00Z"
      }

      attrs = InboundNoteHelpers.extract_note_attrs(note, @actor_uri)

      assert attrs.uri == "https://remote.example.com/notes/1"
      assert attrs.url == "https://remote.example.com/notes/1"
      assert attrs.author_uri == @actor_uri
      assert attrs.content == "<p>Hello</p>"
      assert attrs.in_reply_to_uri == "https://example.com/checkins/abc"
      assert attrs.context == "https://example.com/checkins/abc"
      assert %DateTime{} = attrs.published_at_utc
    end

    test "falls back to id for url when url field is absent" do
      note = %{"id" => "https://remote.example.com/notes/1"}
      attrs = InboundNoteHelpers.extract_note_attrs(note, @actor_uri)
      assert attrs.url == "https://remote.example.com/notes/1"
    end

    test "resolves context from inReplyTo when context is nil and inReplyTo is a local entry" do
      checkin = checkin_fixture()

      note = %{
        "id" => "https://remote.example.com/notes/ctx-nil",
        "inReplyTo" => checkin.uri,
        "context" => nil
      }

      attrs = InboundNoteHelpers.extract_note_attrs(note, @actor_uri)
      assert attrs.context == checkin.uri
    end

    test "resolves context from inReplyTo when context is a foreign URI" do
      checkin = checkin_fixture()

      note = %{
        "id" => "https://remote.example.com/notes/ctx-foreign",
        "inReplyTo" => checkin.uri,
        "context" => "https://mastodon.social/contexts/xyz"
      }

      attrs = InboundNoteHelpers.extract_note_attrs(note, @actor_uri)
      assert attrs.context == checkin.uri
    end

    test "resolves context through a chain: inReplyTo points to a remote note whose context is a local entry" do
      checkin = checkin_fixture()

      {:ok, remote_parent} =
        Revix.Entries.create_inbound_note(%{
          uri: "https://remote.example.com/notes/parent",
          url: "https://remote.example.com/notes/parent",
          author_uri: @actor_uri,
          content: "<p>parent</p>",
          in_reply_to_uri: checkin.uri,
          context: checkin.uri,
          published_at_utc: ~U[2026-05-14 10:00:00Z]
        })

      note = %{
        "id" => "https://remote.example.com/notes/child",
        "inReplyTo" => remote_parent.uri,
        "context" => "https://mastodon.social/contexts/xyz"
      }

      attrs = InboundNoteHelpers.extract_note_attrs(note, @actor_uri)
      assert attrs.context == checkin.uri
    end

    test "falls back to note context when inReplyTo is absent (followed-actor note)" do
      note = %{
        "id" => "https://remote.example.com/notes/standalone",
        "context" => "https://remote.example.com/contexts/abc"
      }

      attrs = InboundNoteHelpers.extract_note_attrs(note, @actor_uri)
      assert attrs.context == "https://remote.example.com/contexts/abc"
    end

    test "returns nil context when both inReplyTo and context are absent" do
      note = %{"id" => "https://remote.example.com/notes/standalone2"}
      attrs = InboundNoteHelpers.extract_note_attrs(note, @actor_uri)
      assert is_nil(attrs.context)
    end
  end

  describe "extract_locations/1" do
    test "returns empty list when location is absent" do
      assert [] = InboundNoteHelpers.extract_locations(%{})
    end

    test "returns empty list when location is nil" do
      assert [] = InboundNoteHelpers.extract_locations(%{"location" => nil})
    end

    test "wraps single map location in a list" do
      loc = %{"type" => "Place", "id" => "https://example.com/places/1", "name" => "Cafe"}
      assert [^loc] = InboundNoteHelpers.extract_locations(%{"location" => loc})
    end

    test "returns array of map locations unchanged" do
      loc1 = %{"type" => "Place", "id" => "https://example.com/places/1", "name" => "Cafe"}
      loc2 = %{"type" => "Place", "id" => "https://example.com/places/2", "name" => "Bar"}
      note = %{"location" => [loc1, loc2]}
      assert [^loc1, ^loc2] = InboundNoteHelpers.extract_locations(note)
    end

    test "filters out string-form location entries" do
      loc = %{"type" => "Place", "id" => "https://example.com/places/1", "name" => "Cafe"}
      note = %{"location" => ["https://example.com/places/0", loc]}
      assert [^loc] = InboundNoteHelpers.extract_locations(note)
    end

    test "returns empty list when all location entries are strings" do
      note = %{"location" => "https://example.com/places/1"}
      assert [] = InboundNoteHelpers.extract_locations(note)
    end
  end

  describe "checkin?/1" do
    test "returns true when there is exactly one location and a startTime" do
      note = %{
        "location" => %{"type" => "Place", "id" => "https://ex.com/p/1", "name" => "Cafe"},
        "startTime" => "2026-05-14T10:00:00Z"
      }

      assert InboundNoteHelpers.checkin?(note)
    end

    test "returns true for single-element array location with startTime" do
      note = %{
        "location" => [%{"type" => "Place", "id" => "https://ex.com/p/1", "name" => "Cafe"}],
        "startTime" => "2026-05-14T10:00:00Z"
      }

      assert InboundNoteHelpers.checkin?(note)
    end

    test "returns false when there are two locations" do
      note = %{
        "location" => [
          %{"type" => "Place", "id" => "https://ex.com/p/1", "name" => "A"},
          %{"type" => "Place", "id" => "https://ex.com/p/2", "name" => "B"}
        ],
        "startTime" => "2026-05-14T10:00:00Z"
      }

      refute InboundNoteHelpers.checkin?(note)
    end

    test "returns false when location is absent" do
      note = %{"startTime" => "2026-05-14T10:00:00Z"}
      refute InboundNoteHelpers.checkin?(note)
    end

    test "returns false when startTime is absent" do
      note = %{
        "location" => %{"type" => "Place", "id" => "https://ex.com/p/1", "name" => "Cafe"}
      }

      refute InboundNoteHelpers.checkin?(note)
    end
  end

  describe "extract_place_attrs/1" do
    test "extracts all fields from a full place object" do
      loc = %{
        "id" => "https://example.com/places/1",
        "type" => "Place",
        "name" => "Remote Cafe",
        "latitude" => 40.0,
        "longitude" => -105.0,
        "url" => "https://example.com/places/1/web",
        "altitude" => 1600.0
      }

      attrs = InboundNoteHelpers.extract_place_attrs(loc)
      assert attrs.uri == "https://example.com/places/1"
      assert attrs.name == "Remote Cafe"
      assert attrs.latitude == 40.0
      assert attrs.longitude == -105.0
      assert attrs.url == "https://example.com/places/1/web"
      assert attrs.altitude == 1600.0
    end

    test "falls back to id for url when url is absent" do
      loc = %{
        "id" => "https://example.com/places/2",
        "name" => "No URL",
        "latitude" => 40.0,
        "longitude" => -105.0
      }

      attrs = InboundNoteHelpers.extract_place_attrs(loc)
      assert attrs.url == "https://example.com/places/2"
    end

    test "returns nil when name is missing" do
      loc = %{"id" => "https://example.com/places/3", "latitude" => 40.0, "longitude" => -105.0}
      assert is_nil(InboundNoteHelpers.extract_place_attrs(loc))
    end

    test "returns nil when latitude is missing" do
      loc = %{"id" => "https://example.com/places/4", "name" => "No lat", "longitude" => -105.0}
      assert is_nil(InboundNoteHelpers.extract_place_attrs(loc))
    end

    test "returns nil when longitude is missing" do
      loc = %{"id" => "https://example.com/places/5", "name" => "No lon", "latitude" => 40.0}
      assert is_nil(InboundNoteHelpers.extract_place_attrs(loc))
    end

    test "returns nil for nil input" do
      assert is_nil(InboundNoteHelpers.extract_place_attrs(nil))
    end
  end

  describe "extract_attachments/1" do
    test "returns empty list when attachment is absent" do
      assert [] = InboundNoteHelpers.extract_attachments(%{})
    end

    test "returns empty list when attachment is nil" do
      assert [] = InboundNoteHelpers.extract_attachments(%{"attachment" => nil})
    end

    test "wraps single Document attachment in a list" do
      att = %{
        "type" => "Document",
        "mediaType" => "image/jpeg",
        "url" => "https://ex.com/img.jpg"
      }

      assert [^att] = InboundNoteHelpers.extract_attachments(%{"attachment" => att})
    end

    test "accepts Image type as well as Document" do
      att = %{"type" => "Image", "mediaType" => "image/png", "url" => "https://ex.com/img.png"}
      assert [^att] = InboundNoteHelpers.extract_attachments(%{"attachment" => att})
    end

    test "returns array of valid attachments" do
      a1 = %{"type" => "Document", "mediaType" => "image/jpeg", "url" => "https://ex.com/a.jpg"}
      a2 = %{"type" => "Document", "mediaType" => "image/png", "url" => "https://ex.com/b.png"}
      note = %{"attachment" => [a1, a2]}
      assert [^a1, ^a2] = InboundNoteHelpers.extract_attachments(note)
    end

    test "filters out attachments with unsupported type" do
      att = %{"type" => "Video", "mediaType" => "video/mp4", "url" => "https://ex.com/v.mp4"}
      assert [] = InboundNoteHelpers.extract_attachments(%{"attachment" => att})
    end

    test "filters out attachments missing a url" do
      att = %{"type" => "Document", "mediaType" => "image/jpeg"}
      assert [] = InboundNoteHelpers.extract_attachments(%{"attachment" => att})
    end
  end
end
