defmodule Revix.Ecto.CustomTypesTest do
  use ExUnit.Case, async: true

  alias Revix.Ecto.Direction
  alias Revix.Ecto.EntryPeopleType
  alias Revix.Ecto.EntryType
  alias Revix.Ecto.ImageVersion
  alias Revix.Ecto.Origin
  alias Revix.Ecto.OsmElementType
  alias Revix.Ecto.PingStatus
  alias Revix.Ecto.PingType

  # ── Direction ───────────────────────────────────────────────────────────────

  describe "Direction" do
    test "cast/1 accepts valid atoms" do
      assert Direction.cast(:inbound) == {:ok, :inbound}
      assert Direction.cast(:outbound) == {:ok, :outbound}
    end

    test "cast/1 rejects invalid values" do
      assert Direction.cast(:unknown) == :error
      assert Direction.cast("inbound") == :error
    end

    test "load/1 loads valid strings" do
      assert Direction.load("inbound") == {:ok, :inbound}
      assert Direction.load("outbound") == {:ok, :outbound}
    end

    test "load/1 rejects invalid strings" do
      assert Direction.load("other") == :error
      assert Direction.load(nil) == :error
    end

    test "dump/1 dumps valid atoms" do
      assert Direction.dump(:inbound) == {:ok, "inbound"}
      assert Direction.dump(:outbound) == {:ok, "outbound"}
    end

    test "dump/1 rejects invalid values" do
      assert Direction.dump(:unknown) == :error
    end

    test "values/0" do
      assert Direction.values() == [:inbound, :outbound]
    end
  end

  # ── EntryPeopleType ──────────────────────────────────────────────────────────

  describe "EntryPeopleType" do
    test "cast/1 accepts :companion" do
      assert EntryPeopleType.cast(:companion) == {:ok, :companion}
    end

    test "cast/1 rejects invalid values" do
      assert EntryPeopleType.cast(:other) == :error
    end

    test "load/1 loads \"companion\"" do
      assert EntryPeopleType.load("companion") == {:ok, :companion}
    end

    test "load/1 rejects invalid strings" do
      assert EntryPeopleType.load("other") == :error
      assert EntryPeopleType.load(nil) == :error
    end

    test "dump/1 dumps :companion" do
      assert EntryPeopleType.dump(:companion) == {:ok, "companion"}
    end

    test "dump/1 rejects invalid values" do
      assert EntryPeopleType.dump(:other) == :error
    end

    test "values/0" do
      assert EntryPeopleType.values() == [:companion]
    end
  end

  # ── EntryType ────────────────────────────────────────────────────────────────

  describe "EntryType" do
    test "cast/1 accepts all valid atoms" do
      assert EntryType.cast(:post) == {:ok, :post}
      assert EntryType.cast(:note) == {:ok, :note}
      assert EntryType.cast(:checkin) == {:ok, :checkin}
      assert EntryType.cast(:event) == {:ok, :event}
    end

    test "cast/1 rejects invalid values" do
      assert EntryType.cast(:other) == :error
      assert EntryType.cast("post") == :error
    end

    test "load/1 loads all valid strings" do
      assert EntryType.load("post") == {:ok, :post}
      assert EntryType.load("note") == {:ok, :note}
      assert EntryType.load("checkin") == {:ok, :checkin}
      assert EntryType.load("event") == {:ok, :event}
    end

    test "load/1 rejects invalid strings" do
      assert EntryType.load("other") == :error
      assert EntryType.load(nil) == :error
    end

    test "dump/1 dumps all valid atoms" do
      assert EntryType.dump(:post) == {:ok, "post"}
      assert EntryType.dump(:note) == {:ok, "note"}
      assert EntryType.dump(:checkin) == {:ok, "checkin"}
      assert EntryType.dump(:event) == {:ok, "event"}
    end

    test "dump/1 rejects invalid values" do
      assert EntryType.dump(:other) == :error
    end

    test "values/0" do
      assert EntryType.values() == [:post, :note, :checkin, :event]
    end
  end

  # ── ImageVersion ─────────────────────────────────────────────────────────────

  describe "ImageVersion" do
    test "cast/1 accepts valid atoms" do
      assert ImageVersion.cast(:large) == {:ok, :large}
      assert ImageVersion.cast(:medium) == {:ok, :medium}
    end

    test "cast/1 rejects invalid values" do
      assert ImageVersion.cast(:thumb) == :error
      assert ImageVersion.cast("large") == :error
    end

    test "load/1 loads valid strings" do
      assert ImageVersion.load("large") == {:ok, :large}
      assert ImageVersion.load("medium") == {:ok, :medium}
    end

    test "load/1 rejects invalid strings" do
      assert ImageVersion.load("thumb") == :error
      assert ImageVersion.load(nil) == :error
    end

    test "dump/1 dumps valid atoms" do
      assert ImageVersion.dump(:large) == {:ok, "large"}
      assert ImageVersion.dump(:medium) == {:ok, "medium"}
    end

    test "dump/1 rejects invalid values" do
      assert ImageVersion.dump(:thumb) == :error
    end

    test "values/0" do
      assert ImageVersion.values() == [:large, :medium]
    end
  end

  # ── Origin ───────────────────────────────────────────────────────────────────

  describe "Origin" do
    test "cast/1 accepts valid atoms" do
      assert Origin.cast(:local) == {:ok, :local}
      assert Origin.cast(:remote) == {:ok, :remote}
    end

    test "cast/1 rejects invalid values" do
      assert Origin.cast(:unknown) == :error
      assert Origin.cast("local") == :error
    end

    test "load/1 loads valid strings" do
      assert Origin.load("local") == {:ok, :local}
      assert Origin.load("remote") == {:ok, :remote}
    end

    test "load/1 rejects invalid strings" do
      assert Origin.load("other") == :error
      assert Origin.load(nil) == :error
    end

    test "dump/1 dumps valid atoms" do
      assert Origin.dump(:local) == {:ok, "local"}
      assert Origin.dump(:remote) == {:ok, "remote"}
    end

    test "dump/1 rejects invalid values" do
      assert Origin.dump(:unknown) == :error
    end

    test "values/0" do
      assert Origin.values() == [:local, :remote]
    end
  end

  # ── OsmElementType ───────────────────────────────────────────────────────────

  describe "OsmElementType" do
    test "cast/1 accepts valid atoms" do
      assert OsmElementType.cast(:node) == {:ok, :node}
      assert OsmElementType.cast(:way) == {:ok, :way}
      assert OsmElementType.cast(:relation) == {:ok, :relation}
    end

    test "cast/1 accepts valid strings (binary cast path)" do
      assert OsmElementType.cast("node") == {:ok, :node}
      assert OsmElementType.cast("way") == {:ok, :way}
      assert OsmElementType.cast("relation") == {:ok, :relation}
    end

    test "cast/1 rejects invalid atom" do
      assert OsmElementType.cast(:other) == :error
    end

    test "cast/1 rejects unknown binary string" do
      assert OsmElementType.cast("unknown_osm_element") == :error
    end

    test "load/1 loads valid strings" do
      assert OsmElementType.load("node") == {:ok, :node}
      assert OsmElementType.load("way") == {:ok, :way}
      assert OsmElementType.load("relation") == {:ok, :relation}
    end

    test "load/1 rejects invalid strings" do
      assert OsmElementType.load("other") == :error
      assert OsmElementType.load(nil) == :error
    end

    test "dump/1 dumps valid atoms" do
      assert OsmElementType.dump(:node) == {:ok, "node"}
      assert OsmElementType.dump(:way) == {:ok, "way"}
      assert OsmElementType.dump(:relation) == {:ok, "relation"}
    end

    test "dump/1 rejects invalid values" do
      assert OsmElementType.dump(:other) == :error
    end

    test "values/0" do
      assert OsmElementType.values() == [:node, :way, :relation]
    end
  end

  # ── PingStatus ───────────────────────────────────────────────────────────────

  describe "PingStatus" do
    test "cast/1 accepts valid atoms" do
      assert PingStatus.cast(:pending) == {:ok, :pending}
      assert PingStatus.cast(:delivered) == {:ok, :delivered}
      assert PingStatus.cast(:failed) == {:ok, :failed}
    end

    test "cast/1 rejects invalid values" do
      assert PingStatus.cast(:unknown) == :error
      assert PingStatus.cast("pending") == :error
    end

    test "load/1 loads valid strings" do
      assert PingStatus.load("pending") == {:ok, :pending}
      assert PingStatus.load("delivered") == {:ok, :delivered}
      assert PingStatus.load("failed") == {:ok, :failed}
    end

    test "load/1 rejects invalid strings" do
      assert PingStatus.load("other") == :error
      assert PingStatus.load(nil) == :error
    end

    test "dump/1 dumps valid atoms" do
      assert PingStatus.dump(:pending) == {:ok, "pending"}
      assert PingStatus.dump(:delivered) == {:ok, "delivered"}
      assert PingStatus.dump(:failed) == {:ok, "failed"}
    end

    test "dump/1 rejects invalid values" do
      assert PingStatus.dump(:unknown) == :error
    end

    test "values/0" do
      assert PingStatus.values() == [:pending, :delivered, :failed]
    end
  end

  # ── PingType ─────────────────────────────────────────────────────────────────

  describe "PingType" do
    test "cast/1 accepts valid atoms" do
      assert PingType.cast(:ping) == {:ok, :ping}
      assert PingType.cast(:pong) == {:ok, :pong}
    end

    test "cast/1 rejects invalid values" do
      assert PingType.cast(:unknown) == :error
      assert PingType.cast("ping") == :error
    end

    test "load/1 loads valid strings" do
      assert PingType.load("ping") == {:ok, :ping}
      assert PingType.load("pong") == {:ok, :pong}
    end

    test "load/1 rejects invalid strings" do
      assert PingType.load("other") == :error
      assert PingType.load(nil) == :error
    end

    test "dump/1 dumps valid atoms" do
      assert PingType.dump(:ping) == {:ok, "ping"}
      assert PingType.dump(:pong) == {:ok, "pong"}
    end

    test "dump/1 rejects invalid values" do
      assert PingType.dump(:unknown) == :error
    end

    test "values/0" do
      assert PingType.values() == [:ping, :pong]
    end
  end
end
