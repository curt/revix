defmodule Revix.Entries.EntryTest do
  use Revix.DataCase

  alias Revix.Entries.Entry

  describe "checkin_changeset/2" do
    test "valid changeset with required fields" do
      changeset =
        Entry.checkin_changeset(%Entry{}, %{
          starts_at_local: ~N[2026-02-16 10:30:00],
          starts_tz: "America/New_York"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :starts_at_utc) == ~U[2026-02-16 15:30:00Z]
      assert %DateTime{} = Ecto.Changeset.get_field(changeset, :published_at_utc)
      assert %NaiveDateTime{} = Ecto.Changeset.get_field(changeset, :published_at_local)
      assert Ecto.Changeset.get_field(changeset, :published_tz) == "America/New_York"
    end

    test "sets context to uri when uri is present" do
      changeset =
        Entry.checkin_changeset(
          %Entry{uri: "http://example.com/c/abc"},
          %{
            starts_at_local: ~N[2026-02-16 10:30:00],
            starts_tz: "America/New_York"
          }
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :context) == "http://example.com/c/abc"
    end

    test "valid changeset with content converted to HTML" do
      changeset =
        Entry.checkin_changeset(%Entry{}, %{
          starts_at_local: ~N[2026-02-16 10:30:00],
          starts_tz: "America/New_York",
          content: "**bold** text"
        })

      assert changeset.valid?
      html = Ecto.Changeset.get_field(changeset, :content_html)
      assert html =~ "<strong>bold</strong>"
    end

    test "requires starts_at_local" do
      changeset =
        Entry.checkin_changeset(%Entry{}, %{
          starts_tz: "America/New_York"
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).starts_at_local
    end

    test "requires starts_tz" do
      changeset =
        Entry.checkin_changeset(%Entry{}, %{
          starts_at_local: ~N[2026-02-16 10:30:00]
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).starts_tz
    end

    test "validates timezone is a real IANA timezone" do
      changeset =
        Entry.checkin_changeset(%Entry{}, %{
          starts_at_local: ~N[2026-02-16 10:30:00],
          starts_tz: "Not/A_Timezone"
        })

      refute changeset.valid?
      assert "is not a valid timezone" in errors_on(changeset).starts_tz
    end

    test "computes UTC from local time and timezone" do
      changeset =
        Entry.checkin_changeset(%Entry{}, %{
          starts_at_local: ~N[2026-07-15 10:30:00],
          starts_tz: "America/New_York"
        })

      assert changeset.valid?
      # EDT is UTC-4 in summer
      assert Ecto.Changeset.get_field(changeset, :starts_at_utc) == ~U[2026-07-15 14:30:00Z]
    end

    test "does not set content_html when content is nil" do
      changeset =
        Entry.checkin_changeset(%Entry{}, %{
          starts_at_local: ~N[2026-02-16 10:30:00],
          starts_tz: "America/New_York"
        })

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :content_html)
    end

    test "does not cast programmatic fields" do
      changeset =
        Entry.checkin_changeset(%Entry{}, %{
          starts_at_local: ~N[2026-02-16 10:30:00],
          starts_tz: "America/New_York",
          id: "injected",
          type: :note,
          origin: :remote,
          author_uri: "injected",
          place_uri: "injected"
        })

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :id)
      refute Ecto.Changeset.get_change(changeset, :type)
      refute Ecto.Changeset.get_change(changeset, :origin)
      refute Ecto.Changeset.get_change(changeset, :author_uri)
      refute Ecto.Changeset.get_change(changeset, :place_uri)
    end
  end

  describe "update_checkin_changeset/2" do
    test "valid changeset with content change" do
      changeset =
        Entry.update_checkin_changeset(%Entry{content: "old"}, %{
          content: "new content"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :content) == "new content"
    end

    test "converts content to HTML" do
      changeset =
        Entry.update_checkin_changeset(%Entry{}, %{
          content: "**bold** text"
        })

      assert changeset.valid?
      html = Ecto.Changeset.get_field(changeset, :content_html)
      assert html =~ "<strong>bold</strong>"
    end

    test "does not set content_html when content is nil" do
      changeset = Entry.update_checkin_changeset(%Entry{}, %{})

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :content_html)
    end

    test "does not cast programmatic fields" do
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
  end
end
