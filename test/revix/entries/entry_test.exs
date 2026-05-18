defmodule Revix.Entries.EntryTest do
  use Revix.DataCase

  alias Revix.Entries.Entry

  describe "checkin_changeset/3" do
    test "valid changeset with required fields" do
      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{
            starts_at_local: ~N[2026-02-16 10:30:00],
            starts_tz: "America/New_York"
          },
          :owner
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :starts_at_utc) == ~U[2026-02-16 15:30:00Z]
      assert %DateTime{} = Ecto.Changeset.get_field(changeset, :published_at_utc)
      assert %NaiveDateTime{} = Ecto.Changeset.get_field(changeset, :published_at_local)
      assert Ecto.Changeset.get_field(changeset, :published_tz) == "America/New_York"
    end

    test "sets context to a tag URI" do
      changeset =
        Entry.checkin_changeset(
          %Entry{uri: "http://example.com/c/abc"},
          %{
            starts_at_local: ~N[2026-02-16 10:30:00],
            starts_tz: "America/New_York"
          },
          :owner
        )

      assert changeset.valid?
      assert String.starts_with?(Ecto.Changeset.get_field(changeset, :context), "tag:")
    end

    test "valid changeset with content converted to HTML" do
      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{
            starts_at_local: ~N[2026-02-16 10:30:00],
            starts_tz: "America/New_York",
            content: "**bold** text"
          },
          :owner
        )

      assert changeset.valid?
      html = Ecto.Changeset.get_field(changeset, :content_html)
      assert html =~ "<strong>bold</strong>"
    end

    test "requires starts_at_local" do
      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{
            starts_tz: "America/New_York"
          },
          :owner
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).starts_at_local
    end

    test "requires starts_tz" do
      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{
            starts_at_local: ~N[2026-02-16 10:30:00]
          },
          :owner
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).starts_tz
    end

    test "validates timezone is a real IANA timezone" do
      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{
            starts_at_local: ~N[2026-02-16 10:30:00],
            starts_tz: "Not/A_Timezone"
          },
          :owner
        )

      refute changeset.valid?
      assert "is not a valid timezone" in errors_on(changeset).starts_tz
    end

    test "computes UTC from local time and timezone" do
      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{
            starts_at_local: ~N[2026-07-15 10:30:00],
            starts_tz: "America/New_York"
          },
          :owner
        )

      assert changeset.valid?
      # EDT is UTC-4 in summer
      assert Ecto.Changeset.get_field(changeset, :starts_at_utc) == ~U[2026-07-15 14:30:00Z]
    end

    test "does not set content_html when content is nil" do
      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{
            starts_at_local: ~N[2026-02-16 10:30:00],
            starts_tz: "America/New_York"
          },
          :owner
        )

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :content_html)
    end

    test "does not cast programmatic fields" do
      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{
            starts_at_local: ~N[2026-02-16 10:30:00],
            starts_tz: "America/New_York",
            id: "injected",
            type: :note,
            origin: :remote,
            author_uri: "injected",
            place_uri: "injected"
          },
          :owner
        )

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :id)
      refute Ecto.Changeset.get_change(changeset, :type)
      refute Ecto.Changeset.get_change(changeset, :origin)
      refute Ecto.Changeset.get_change(changeset, :author_uri)
      refute Ecto.Changeset.get_change(changeset, :place_uri)
    end

    test "non-owner: rejects future datetime" do
      future = NaiveDateTime.add(NaiveDateTime.utc_now(), 60, :second)

      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{starts_at_local: future, starts_tz: "Etc/UTC"},
          :user
        )

      refute changeset.valid?
      assert "must be in the past" in errors_on(changeset).starts_at_local
    end

    test "non-owner: rejects datetime older than lookback window" do
      lookback = Application.get_env(:revix, :entry)[:checkin_lookback_hours] || 24
      too_old = NaiveDateTime.add(NaiveDateTime.utc_now(), -(lookback + 1), :hour)

      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{starts_at_local: too_old, starts_tz: "Etc/UTC"},
          :user
        )

      refute changeset.valid?
      assert "must be within the last #{lookback} hours" in errors_on(changeset).starts_at_local
    end

    test "non-owner: accepts datetime within the lookback window" do
      recent = NaiveDateTime.add(NaiveDateTime.utc_now(), -30, :minute)

      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{starts_at_local: recent, starts_tz: "Etc/UTC"},
          :user
        )

      assert changeset.valid?
    end

    test "non-owner: accepts datetime near but inside the lookback boundary" do
      # One minute inside the window to avoid a timing race between test setup and validation
      lookback = Application.get_env(:revix, :entry)[:checkin_lookback_hours] || 24

      near_boundary =
        NaiveDateTime.add(NaiveDateTime.utc_now(:second), -(lookback * 60 - 1), :minute)

      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{starts_at_local: near_boundary, starts_tz: "Etc/UTC"},
          :user
        )

      assert changeset.valid?
    end

    test "non-owner: rejects datetime just outside the lookback boundary" do
      lookback = Application.get_env(:revix, :entry)[:checkin_lookback_hours] || 24

      just_outside =
        NaiveDateTime.add(NaiveDateTime.utc_now(:second), -(lookback * 60 + 1), :minute)

      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{starts_at_local: just_outside, starts_tz: "Etc/UTC"},
          :user
        )

      refute changeset.valid?
      assert "must be within the last #{lookback} hours" in errors_on(changeset).starts_at_local
    end

    test "non-owner: window check uses UTC conversion, not raw local time" do
      # A datetime that appears to be 1 hour ago in local time but is actually
      # 1 hour ago in UTC when the timezone is UTC+0. Here we give a local time
      # that is 23 hours ago expressed as America/New_York (UTC-4 in winter),
      # so the actual UTC instant is 23 hours ago — within the 24h window.
      local_23h_ago_nyc = NaiveDateTime.add(NaiveDateTime.utc_now(:second), -23, :hour)

      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{starts_at_local: local_23h_ago_nyc, starts_tz: "America/New_York"},
          :user
        )

      # 23h ago local NYC = 23h ago UTC (shifted 4h, but still within 24h window)
      assert changeset.valid?
    end

    test "non-owner: invalid timezone short-circuits before window check" do
      # An invalid tz makes the changeset invalid before validate_starts_at_window runs;
      # the window error should not also appear.
      future = NaiveDateTime.add(NaiveDateTime.utc_now(), 60, :second)

      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{starts_at_local: future, starts_tz: "Not/Real"},
          :user
        )

      refute changeset.valid?
      assert "is not a valid timezone" in errors_on(changeset).starts_tz
      refute Map.has_key?(errors_on(changeset), :starts_at_local)
    end

    test "owner: accepts future datetime" do
      future = NaiveDateTime.add(NaiveDateTime.utc_now(), 3600, :second)

      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{starts_at_local: future, starts_tz: "Etc/UTC"},
          :owner
        )

      assert changeset.valid?
    end

    test "owner: accepts datetime older than lookback window" do
      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{starts_at_local: ~N[2020-01-01 00:00:00], starts_tz: "Etc/UTC"},
          :owner
        )

      assert changeset.valid?
    end

    test "owner: published_tz reflects the provided timezone" do
      changeset =
        Entry.checkin_changeset(
          %Entry{},
          %{starts_at_local: ~N[2026-06-01 09:00:00], starts_tz: "America/Chicago"},
          :owner
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :published_tz) == "America/Chicago"
    end
  end

  describe "update_checkin_changeset/3" do
    test "valid changeset with content change" do
      changeset =
        Entry.update_checkin_changeset(%Entry{content: "old"}, %{content: "new content"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :content) == "new content"
    end

    test "converts content to HTML" do
      changeset =
        Entry.update_checkin_changeset(%Entry{}, %{content: "**bold** text"})

      assert changeset.valid?
      html = Ecto.Changeset.get_field(changeset, :content_html)
      assert html =~ "<strong>bold</strong>"
    end

    test "does not set content_html when content is nil" do
      changeset = Entry.update_checkin_changeset(%Entry{}, %{})

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :content_html)
    end

    test "non-owner (default): does not cast datetime fields" do
      changeset =
        Entry.update_checkin_changeset(%Entry{}, %{
          id: "injected",
          type: :note,
          starts_at_local: ~N[2026-02-16 10:30:00],
          starts_tz: "America/New_York",
          author_uri: "injected"
        })

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :id)
      refute Ecto.Changeset.get_change(changeset, :type)
      refute Ecto.Changeset.get_change(changeset, :starts_at_local)
      refute Ecto.Changeset.get_change(changeset, :starts_tz)
      refute Ecto.Changeset.get_change(changeset, :author_uri)
    end

    test "owner: casts and computes UTC from updated datetime fields" do
      changeset =
        Entry.update_checkin_changeset(
          %Entry{},
          %{starts_at_local: ~N[2026-07-15 10:30:00], starts_tz: "America/New_York"},
          :owner
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :starts_at_local) == ~N[2026-07-15 10:30:00]
      assert Ecto.Changeset.get_change(changeset, :starts_tz) == "America/New_York"
      # EDT is UTC-4 in summer
      assert Ecto.Changeset.get_change(changeset, :starts_at_utc) == ~U[2026-07-15 14:30:00Z]
    end

    test "owner: rejects invalid timezone on update" do
      changeset =
        Entry.update_checkin_changeset(
          %Entry{},
          %{starts_at_local: ~N[2026-07-15 10:30:00], starts_tz: "Not/Real"},
          :owner
        )

      refute changeset.valid?
      assert "is not a valid timezone" in errors_on(changeset).starts_tz
    end

    test "owner: datetime fields are optional — content-only update still valid" do
      changeset =
        Entry.update_checkin_changeset(%Entry{}, %{content: "just text"}, :owner)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :content) == "just text"
      refute Ecto.Changeset.get_change(changeset, :starts_at_utc)
    end

    test "non-owner explicit: ignores datetime fields even when passed" do
      changeset =
        Entry.update_checkin_changeset(
          %Entry{},
          %{starts_at_local: ~N[2026-02-16 10:30:00], starts_tz: "America/New_York"},
          :user
        )

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :starts_at_local)
      refute Ecto.Changeset.get_change(changeset, :starts_tz)
      refute Ecto.Changeset.get_change(changeset, :starts_at_utc)
    end
  end

  describe "draft_post_changeset/3" do
    test "valid without published_tz" do
      changeset = Entry.draft_post_changeset(%Entry{}, %{"content" => "hello"}, :user)
      assert changeset.valid?
    end

    test "does not set published_at fields" do
      changeset = Entry.draft_post_changeset(%Entry{}, %{"content" => "hello"}, :user)
      refute Ecto.Changeset.get_change(changeset, :published_at_utc)
      refute Ecto.Changeset.get_change(changeset, :published_at_local)
      refute Ecto.Changeset.get_change(changeset, :published_tz)
    end

    test "sets context to a tag URI" do
      changeset = Entry.draft_post_changeset(%Entry{}, %{"content" => "hello"}, :user)
      context = Ecto.Changeset.get_change(changeset, :context)
      assert is_binary(context)
      assert String.starts_with?(context, "tag:")
    end

    test "converts content to HTML" do
      changeset = Entry.draft_post_changeset(%Entry{}, %{"content" => "**bold**"}, :user)
      assert Ecto.Changeset.get_change(changeset, :content_html) =~ "<strong>"
    end

    test "valid without content" do
      changeset = Entry.draft_post_changeset(%Entry{}, %{}, :user)
      assert changeset.valid?
    end
  end

  describe "publish_post_changeset/3" do
    test "requires published_tz" do
      changeset = Entry.publish_post_changeset(%Entry{}, %{"content" => "hello"}, :user)
      refute changeset.valid?
      assert errors_on(changeset)[:published_tz]
    end

    test "sets all three published fields" do
      changeset =
        Entry.publish_post_changeset(
          %Entry{},
          %{"content" => "hello", "published_tz" => "America/New_York"},
          :user
        )

      assert changeset.valid?
      assert %DateTime{} = Ecto.Changeset.get_field(changeset, :published_at_utc)
      assert %NaiveDateTime{} = Ecto.Changeset.get_field(changeset, :published_at_local)
      assert Ecto.Changeset.get_field(changeset, :published_tz) == "America/New_York"
    end

    test "rejects invalid timezone" do
      changeset =
        Entry.publish_post_changeset(
          %Entry{},
          %{"content" => "hello", "published_tz" => "Not/AZone"},
          :user
        )

      refute changeset.valid?
      assert errors_on(changeset)[:published_tz]
    end

    test "sets context" do
      changeset =
        Entry.publish_post_changeset(
          %Entry{},
          %{"content" => "hello", "published_tz" => "UTC"},
          :user
        )

      context = Ecto.Changeset.get_change(changeset, :context)
      assert is_binary(context)
      assert String.starts_with?(context, "tag:")
    end
  end

  describe "publish_draft_post_changeset/3" do
    test "requires published_tz" do
      changeset = Entry.publish_draft_post_changeset(%Entry{}, %{"content" => "hello"}, :user)
      refute changeset.valid?
      assert errors_on(changeset)[:published_tz]
    end

    test "sets all three published fields" do
      changeset =
        Entry.publish_draft_post_changeset(
          %Entry{},
          %{"content" => "hello", "published_tz" => "America/Chicago"},
          :user
        )

      assert changeset.valid?
      assert %DateTime{} = Ecto.Changeset.get_field(changeset, :published_at_utc)
      assert %NaiveDateTime{} = Ecto.Changeset.get_field(changeset, :published_at_local)
      assert Ecto.Changeset.get_field(changeset, :published_tz) == "America/Chicago"
    end

    test "does not overwrite existing context" do
      existing_context = "tag:example.com,2026:convo/abc123"
      entry = %Entry{context: existing_context}

      changeset =
        Entry.publish_draft_post_changeset(
          entry,
          %{"content" => "hello", "published_tz" => "UTC"},
          :user
        )

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :context)
      assert Ecto.Changeset.get_field(changeset, :context) == existing_context
    end
  end

  describe "update_post_changeset/3 — rezone_published_at branches" do
    test "no-op when published_tz is not changed by owner" do
      utc = ~U[2026-01-01 12:00:00Z]

      entry = %Entry{
        published_at_utc: utc,
        published_at_local: ~N[2026-01-01 12:00:00],
        published_tz: "UTC"
      }

      changeset = Entry.update_post_changeset(entry, %{"content" => "updated"}, :owner)

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :published_at_local)
    end

    test "does not crash when published_at_utc is nil (draft edited by owner with tz in params)" do
      entry = %Entry{published_at_utc: nil, published_at_local: nil, published_tz: nil}

      changeset =
        Entry.update_post_changeset(entry, %{"published_tz" => "America/Denver"}, :owner)

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :published_at_local)
    end

    test "rezones correctly when owner changes timezone on a published post" do
      utc = ~U[2026-06-15 20:00:00Z]

      entry = %Entry{
        published_at_utc: utc,
        published_at_local: ~N[2026-06-15 20:00:00],
        published_tz: "UTC"
      }

      changeset =
        Entry.update_post_changeset(entry, %{"published_tz" => "America/New_York"}, :owner)

      assert changeset.valid?
      local = Ecto.Changeset.get_change(changeset, :published_at_local)
      assert local == ~N[2026-06-15 16:00:00]
    end

    test "returns invalid changeset without crashing when timezone is invalid" do
      utc = ~U[2026-01-01 12:00:00Z]

      entry = %Entry{
        published_at_utc: utc,
        published_at_local: ~N[2026-01-01 12:00:00],
        published_tz: "UTC"
      }

      changeset = Entry.update_post_changeset(entry, %{"published_tz" => "Bad/Zone"}, :owner)

      refute changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :published_at_local)
    end
  end
end
