# Subscriber Email Notifications — 2026-08-30

**Scope:** Per-person notification cadence (`notification_schedule` column on `people`); a `notifications` table capturing events at emit time; five event classes (owner posts, followed-author posts, likes/comments in a conversation you are part of, and owner-only new-registration alerts); a per-cadence Oban cron worker that batches unsent rows into one plain-text + HTML digest email; a settings LiveView at `/settings/notifications`; a retention purge worker. Also a menu reorganization in the app layout.

---

## Summary

Every local person with a verified email (`origin: :local`, `confirmed_at` set) is a **subscriber**. There is no separate "subscriber" concept — the cadence lives directly on the `people` row as `notification_schedule` (`:hourly | :daily | :weekly | :none`, default `:daily`), editable at `/settings/notifications`.

Superficially modeled on Klaxon's "subscriptions" feature, but broader: Klaxon notifies only on new local posts and re-queries "posts since a per-subscriber watermark" at send time. Revix must notify on five event classes drawn from four tables, so instead of a watermark it uses **write-on-emit**: each event inserts a `Notification` row synchronously, and the digest worker batches the recipient's unsent rows.

**Event classes** (`Revix.Ecto.NotificationType`):

| Type | Trigger | Recipients |
|---|---|---|
| `owner_entry` | A local **owner** publishes a post or checkin | Every eligible subscriber except the author |
| `followed_entry` | Any local person publishes any entry | That author's local followers (except the author) |
| `reply` | A comment is created anywhere in a thread | Ancestor-chain authors + root-entry companions + anyone who liked an entry in the thread (except the note's author) |
| `like` | An entry is liked | The liked entry's author and every ancestor author (except the liker) |
| `registration` | A person completes email verification | All local owners (except the new person) |

A recipient never receives a notification for an event they initiated. A single post/checkin/like/comment appears at most once per digest — two emit layers enforce this: `notify_new_entry/1` removes owner-set recipients from the followed set, and `deliver_digests/3` collapses rows sharing a `subject_uri` to the highest-priority type before rendering.

**Delay before delivery** (comparable to Klaxon): a `Notification` row is written immediately, but it only ships when the cron worker for that cadence next runs, and only if the row is older than a configurable settling lag (`config :revix, :notifications, send_offset_minutes: 30`) — activity in the last 30 minutes before a run waits for the following run. This guards against clock skew and against notifying on something about to be edited or deleted.

The emit path is best-effort: `emit/1` catches changeset errors and exceptions, logs a warning, and returns `:ok`, so a notification failure can never break entry or like creation. In the digest worker, one subscriber's send failure (mailer error or a raise in body-building) is logged and skipped rather than aborting the batch and forcing Oban to re-send to everyone already delivered in that run.

Digests are plain text **and** HTML, grouped by type, with a per-run timestamp in the subject line (`"Revix activity — Aug 30, 2026 13:15 UTC"`) so each run threads as its own conversation in a mail client. An RFC 8058 `List-Unsubscribe` header points at the settings page when a URL is supplied.

---

## Data Model

### `Revix.Ecto.NotificationSchedule`

**File:** [lib/revix/ecto/notification_schedule.ex](lib/revix/ecto/notification_schedule.ex)

Custom `use Ecto.Type` following the `Origin` / `EntryType` pattern (atom ↔ string `cast` / `load` / `dump`, plus `values/0`). **Not `Ecto.Enum`.** Values: `:hourly`, `:daily`, `:weekly`, `:none`.

### `Revix.Ecto.NotificationType`

**File:** [lib/revix/ecto/notification_type.ex](lib/revix/ecto/notification_type.ex)

Same shape. Values: `:owner_entry`, `:followed_entry`, `:reply`, `:like`, `:registration`.

### `people.notification_schedule`

**File:** [priv/repo/migrations/20260829120000_add_notification_schedule_to_people.exs](priv/repo/migrations/20260829120000_add_notification_schedule_to_people.exs)

`add :notification_schedule, :text, null: false, default: "daily"` — backfills every existing row to `"daily"`. The `Person` schema gains the field (typed `Revix.Ecto.NotificationSchedule`, default `:daily`) and a `notification_changeset/2` that casts only `[:notification_schedule]` and validates inclusion, mirroring `Person.role_changeset/2`.

### `notifications` table

**File:** [priv/repo/migrations/20260829120100_create_notifications.exs](priv/repo/migrations/20260829120100_create_notifications.exs)

| Column | Notes |
|---|---|
| `id` | 11-char Base58 (`Revix.Schema`) |
| `recipient_uri` | `people.uri` of the subscriber to email |
| `type` | one of the five `NotificationType` values |
| `subject_uri` | the entry / liked-object / new-person URI the event is about |
| `actor_uri` | who did it (nullable) |
| `summary` | one-line description, **frozen at emit time** — the worker never re-loads or re-renders source records that may since have been edited or tombstoned |
| `url` | link included in the digest (nullable) |
| `sent_at` | `nil` = pending; stamped when included in a delivered digest |

Indexes: `[:recipient_uri, :sent_at]`, `[:inserted_at]`, and a **unique** `[:recipient_uri, :type, :subject_uri]` — makes emit idempotent (`on_conflict: :nothing`), so a re-like after an unlike or a re-run of a create hook does not produce a duplicate.

**File:** [lib/revix/notifications/notification.ex](lib/revix/notifications/notification.ex) — `create_changeset/2` requires `[:recipient_uri, :type, :subject_uri, :summary]` and declares the unique constraint by name.

---

## Context — `Revix.Notifications`

**File:** [lib/revix/notifications.ex](lib/revix/notifications.ex)

Pure domain module (no `RevixWeb.*` references — any URL it needs is passed in or already frozen on a row). Implements `Revix.Notifications.Behaviour`.

### Preferences

- `get_schedule/1` — reads the atom off the `%Person{}`.
- `set_schedule/2` — `Person.notification_changeset/2` → `Repo.update()`. Lives here rather than in `Revix.People` to keep the feature cohesive; `People` stays unaware of notifications.
- `schedule_options/0` — `[{"Hourly", :hourly}, …, {"Off", :none}]`, derived from `NotificationSchedule.values()` so the settings form stays in sync with the type.

### Emit

One low-level primitive plus four fan-out helpers (the behaviour callbacks):

- `emit/6` — inserts one row idempotently; `{:error, changeset}` and any raised exception are logged at `:warning` and swallowed (`:ok`).
- `notify_new_entry/1` — classes `owner_entry` + `followed_entry`. `new_entry_recipients/1` computes the owner set first, then removes those URIs from the followed set, so a subscriber who follows an owner gets exactly one row.
- `notify_like/1` — walks the thread ancestor chain from `like.object_uri`, notifies each distinct ancestor author (minus the liker). `subject_uri` is the **liked object**, not the Like activity, so a recipient gets one row per post regardless of how many people like it.
- `notify_reply/1` — recipients are ancestor-chain authors ∪ root-entry companions ∪ thread likers, minus the note's author.
- `notify_registration/1` — local owners, minus the new person.

**Recipient eligibility** (`eligible_recipient_uris/1`) is a single query: `origin == :local AND confirmed_at IS NOT NULL AND notification_schedule != :none`. Keeps emit to ≤2 queries per event regardless of recipient count.

**Ancestor walk** (`ancestor_chain/1`) — one recursive walk up `in_reply_to_uri` returning `[{uri, author_uri}, …]` from the given entry to the root. Authors, the root URI (for companions), and the full URI list (for thread likers via `Likes.liker_uris_for_objects/1`) are all derived from this one walk. Depth is capped (default 20, overridable via `config :revix, :notification_ancestor_depth_limit`); `nil` / missing-URI base cases return `[]`.

**Summaries** are built at emit time. For entries the summary composes up to three parts, each included only when present, joined with ` — ` after a `: ` prefix:

1. **Place name** — for a checkin at a named place (`Place` lookup by `place_uri`);
2. **Title** — the post's `name`;
3. **Body excerpt** — `Revix.Snippet.snippify(content, 140)`.

Examples: `"Curt published a post: My Trip — Rome was incredible for the food alone."`, `"Ada published a checkin: Blue Bottle Coffee — third time this week"`, `"Bo published a checkin"` (no text at all). Like/reply summaries read `"X liked a post in a conversation you're part of"` and `"X commented in a conversation you're part of"` — accurate for every recipient (author, ancestor author, companion, liker).

### Digest send

`deliver_digests(schedule, now \\ DateTime.utc_now(), deps \\ [])`:

1. Loads local confirmed subscribers on `schedule`.
2. Per subscriber: unsent rows with `inserted_at <= now - send_offset_minutes`, ascending.
3. Skips subscribers with nothing pending.
4. `dedupe_by_subject/1` — collapses rows sharing a `subject_uri` to the highest-priority type (`owner_entry` > `followed_entry` > `reply` > `like` > `registration`), preserving `inserted_at` order.
5. Builds the email via the notifier and delivers via the mailer. On success, stamps **every** pending row (including collapsed ones) so nothing resurfaces next run. On failure — or an exception anywhere in the per-subscriber body — logs a warning and moves on.
6. Returns `%{sent: n, skipped: m}`.

`deps` (all defaulted) inject the notifier, the mailer, `:settings_url`, `:site_title`, and `:send_offset_minutes` — used by the worker and by tests.

Send and stamp are not transactional (as in Klaxon): a delivery that succeeds but fails to stamp will, on the worker's next attempt, resend those rows. `max_attempts` on the worker is kept at 3.

### Maintenance

`purge_sent_older_than_hours/1` — deletes rows with `sent_at` older than the cutoff. Returns `{:ok, count}`.

---

## Notifier — `Revix.Notifications.DigestNotifier`

**File:** [lib/revix/notifications/digest_notifier.ex](lib/revix/notifications/digest_notifier.ex)

`build(subscriber, notifications, ctx)` returns a `%Swoosh.Email{}`. Follows the `Revix.People.PersonNotifier` structure but adds an HTML body and the unsubscribe header.

- **Subject:** `"<site title> activity — <run timestamp> UTC"` — the distinct timestamp per run gives each digest a unique `Subject` with no `In-Reply-To`, so mail clients thread each run separately.
- **Grouping:** both bodies group notifications by type in a fixed section order (`owner_entry`, `followed_entry`, `reply`, `like`, `registration`), one line per row using the frozen `summary` and `url`. HTML output escapes `summary` and `url` (`Phoenix.HTML.html_escape/1`) since they can contain remote display names and titles.
- **`List-Unsubscribe`:** added only when `ctx[:settings_url]` is present; footer links to the settings page or, absent a URL, references "your account settings".

---

## Workers

### `Revix.Workers.NotificationDigestWorker`

**File:** [lib/revix/workers/notification_digest_worker.ex](lib/revix/workers/notification_digest_worker.ex)

`queue: :mailers, max_attempts: 3`. Registered in the crontab once per cadence:

```
"5 * * * *"     -> hourly
"15 13 * * *"   -> daily   (13:15 UTC)
"25 13 * * 1"   -> weekly  (13:25 UTC Monday)
```

This worker is the **composition root**: it resolves `CanonicalRoutes.notification_settings_url/0` and the site title from `Revix.Sites`, then hands them to the pure context. The context itself never touches the web layer.

Logging: `Logger.metadata(notification_digest: schedule)` at the top, cleared in an `after` block so it does not bleed into the next job on a reused Oban process. A run that sent or deferred anything logs the `%{sent:, skipped:}` summary at `:info`; a fully quiet run logs at `:debug` so hourly cron on a low-traffic instance stays silent. An invalid or missing `schedule` arg returns `{:cancel, reason}`.

### `Revix.Workers.PurgeSentNotificationsWorker`

**File:** [lib/revix/workers/purge_sent_notifications_worker.ex](lib/revix/workers/purge_sent_notifications_worker.ex)

`queue: :federation`, cron `"6 0 * * *"`. Reads `config :revix, :notifications` `[:retention_hours]` (default 168) and calls `Notifications.purge_sent_older_than_hours/1`. Silent, matching the other `Purge*Worker` siblings.

---

## Wiring into existing contexts

All calls are fire-and-forget after a successful `{:ok, _}`, made through a swappable indirection (`defp notifications, do: Application.get_env(:revix, :notifications_impl, Revix.Notifications)`) so the triggering contexts' tests can assert the call without exercising the whole path.

| Trigger | File / function | Call |
|---|---|---|
| Checkin / post first publication | [lib/revix/entries.ex](lib/revix/entries.ex) — `enqueue_deliver_entry/2` (the single chokepoint every publish path hits: simple flows via `maybe_enqueue_create/3`, LiveView flows via the public `enqueue_delivery/2` after their transaction commits) | `notify_new_entry(entry)`, guarded to `type in [:post, :checkin]` and `"Create"` |
| Comment / reply created | `create_comment/5`, `create_reply/5` | `notify_reply(note)` |
| Inbound remote note | `create_inbound_note/1` | `notify_reply(note)` |
| Like created | [lib/revix/likes.ex](lib/revix/likes.ex) — `do_like_entry/3` | `notify_like(like)` |
| Inbound remote like | `upsert_inbound_like/1` | `notify_like(like)` |
| Registration confirmed | [lib/revix/people.ex](lib/revix/people.ex) — `login_person_by_magic_link/1`, the unconfirmed-person branch, after `update_person_and_delete_all_tokens/1` | `notify_registration(person)` via a pattern-matched `defp notify_registration/1` |

`Revix.Likes` also gained `liker_uris_for_objects/1` — a single `distinct` query for the author URIs of active likes across a set of object URIs, used by `notify_reply/1`.

---

## Settings UI

**Files:** [lib/revix_web/live/notification_settings_live.ex](lib/revix_web/live/notification_settings_live.ex), [lib/revix_web/live/notification_settings_live.html.heex](lib/revix_web/live/notification_settings_live.html.heex)

`RevixWeb.NotificationSettingsLive` at `live "/settings/notifications"` inside the `:authenticated` live session. Modeled on `SiteSettingsLive` but with **no owner check** — every authenticated person manages their own cadence. `mount/2` builds a form from `Person.notification_changeset/2`; `handle_event("save", …)` converts the submitted value with `String.to_existing_atom/1`, calls `Notifications.set_schedule/2`, updates `current_scope`, and re-renders. A `<.input type="select">` is populated from `Notifications.schedule_options/0`.

`CanonicalRoutes.notification_settings_url/0` added for the worker and notifier to share.

---

## Menu reorganization

**File:** [lib/revix_web/components/layouts.ex](lib/revix_web/components/layouts.ex)

The app dropdown was reordered while adding the Notifications entry:

- **Sign in / Sign out** is always last; **Credits** is always second-to-last.
- **Settings** is a submenu (a non-link `<span class="text-accent">` label matching the submenu link color) containing **Profile** (`/people/settings`), **Notifications** (`/settings/notifications`), and — for owners — **Site** (`/settings/site`).
- Primary content links reordered to **Posts → Checkins → Places**.

Resulting order — owner: Home, Posts, Checkins, Places, Following, Pings, Settings [Profile / Notifications / Site], Credits, Sign out.

---

## Configuration

**File:** [config/config.exs](config/config.exs)

```elixir
config :revix, :notifications, retention_hours: 168, send_offset_minutes: 30

config :revix, Oban,
  queues: [federation: 5, mailers: 10],   # new :mailers queue
  plugins: [
    {Oban.Plugins.Cron, crontab: [
      # ... existing purge workers ...
      {"6 0 * * *",    Revix.Workers.PurgeSentNotificationsWorker},
      {"5 * * * *",    Revix.Workers.NotificationDigestWorker, args: %{"schedule" => "hourly"}},
      {"15 13 * * *",  Revix.Workers.NotificationDigestWorker, args: %{"schedule" => "daily"}},
      {"25 13 * * 1",  Revix.Workers.NotificationDigestWorker, args: %{"schedule" => "weekly"}}
    ]}
  ]
```

Swoosh, Oban, and a production SES adapter were already configured; no new dependencies.

---

## Testing

Covered by [test/revix/notifications_test.exs](test/revix/notifications_test.exs) (context — recipient resolution per class, self-exclusion for every initiator type, dedup, idempotency, ancestor-walk guard clauses, no-raise behavior, summary composition, digest send with the settling offset / cadence match / already-sent / delivery failure / per-subscriber crash isolation, retention purge), [test/revix/notifications_wiring_test.exs](test/revix/notifications_wiring_test.exs) (Mox — each trigger fires the right callback on success and not on failure paths, including the LiveView companion-publish flows and inbound remote like / inbound remote reply-to-a-comment), [test/revix/workers/notification_digest_worker_test.exs](test/revix/workers/notification_digest_worker_test.exs) (worker + log level assertions + metadata cleanup), [test/revix_web/live/notification_settings_live_test.exs](test/revix_web/live/notification_settings_live_test.exs), and [test/revix/ecto/notification_schedule_test.exs](test/revix/ecto/notification_schedule_test.exs) / [test/revix/ecto/notification_type_test.exs](test/revix/ecto/notification_type_test.exs). Fixtures in [test/support/fixtures/notifications_fixtures.ex](test/support/fixtures/notifications_fixtures.ex); `Revix.NotificationsMock` in [test/support/mocks.ex](test/support/mocks.ex).

Incidental fix: two `async: true` tests in [test/revix_web/structured_data_test.exs](test/revix_web/structured_data_test.exs) mutated the global `:waffle, :asset_host` env and could race with `Revix.Uploaders.ImageTest`; they were moved into a dedicated `async: false` module.

All new modules are ≥95% covered; the full Elixir suite passes at 0 failures with overall coverage above the 90% target.
