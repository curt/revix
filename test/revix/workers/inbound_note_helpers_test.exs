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
  end
end
