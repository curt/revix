defmodule Revix.Repo.Migrations.CreateEntries do
  use Ecto.Migration

  def change do
    create table(:entries, primary_key: false) do
      add :id, :char, primary_key: true, null: false, size: 11
      add :uri, :text, null: false
      add :url, :text, null: false

      add :type, :string, null: false
      add :name, :text
      add :content, :text
      add :content_html, :text
      add :summary, :text
      add :summary_html, :text
      add :context, :text
      add :origin, :string, null: false

      # Published - UTC, local wall-clock, and timezone
      add :published_at_utc, :utc_datetime
      add :published_at_local, :naive_datetime
      add :published_tz, :string

      # Starts - UTC, local wall-clock, and timezone
      add :starts_at_utc, :utc_datetime
      add :starts_at_local, :naive_datetime
      add :starts_tz, :string

      # Ends - UTC, local wall-clock, and timezone
      add :ends_at_utc, :utc_datetime
      add :ends_at_local, :naive_datetime
      add :ends_tz, :string

      # URI-based references (no foreign key constraints)
      add :author_uri, :text, null: false
      add :in_reply_to_uri, :text
      add :place_uri, :text

      timestamps(type: :utc_datetime)
    end

    # URI is unique alternate key
    create unique_index(:entries, [:uri])

    # Index URI references for lookups
    create index(:entries, [:author_uri])
    create index(:entries, [:in_reply_to_uri])
    create index(:entries, [:place_uri])
    create index(:entries, [:type])
    create index(:entries, [:published_at_utc])
    create index(:entries, [:starts_at_utc])

    # Type-specific constraints
    create constraint(:entries, :checkin_requires_place,
             check: "type NOT IN ('checkin', 'event') OR place_uri IS NOT NULL"
           )

    create constraint(:entries, :temporal_entry_requires_starts_at,
             check:
               "type NOT IN ('checkin', 'event') OR (starts_at_utc IS NOT NULL AND starts_at_local IS NOT NULL AND starts_tz IS NOT NULL)"
           )

    # Ensure temporal fields are all-or-nothing (either all NULL or all present)
    create constraint(:entries, :published_complete,
             check:
               "(published_at_utc IS NULL AND published_at_local IS NULL AND published_tz IS NULL) OR (published_at_utc IS NOT NULL AND published_at_local IS NOT NULL AND published_tz IS NOT NULL)"
           )

    create constraint(:entries, :starts_complete,
             check:
               "(starts_at_utc IS NULL AND starts_at_local IS NULL AND starts_tz IS NULL) OR (starts_at_utc IS NOT NULL AND starts_at_local IS NOT NULL AND starts_tz IS NOT NULL)"
           )

    create constraint(:entries, :ends_complete,
             check:
               "(ends_at_utc IS NULL AND ends_at_local IS NULL AND ends_tz IS NULL) OR (ends_at_utc IS NOT NULL AND ends_at_local IS NOT NULL AND ends_tz IS NOT NULL)"
           )
  end
end
