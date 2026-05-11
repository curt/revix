# ActivityPub Inbound Likes — 2026-05-11

**Branch:** topics/inbound-likes  
**Scope:** Inbound ActivityPub `Like` and `Undo Like` activities; `like_uri` column on the `likes` table; federation workers for both activity types.

---

## Summary

Extends the ActivityPub inbox to accept `Like` and `Undo Like` activities from remote actors, mapping them to the existing `likes` table with `origin: :remote`. Previously, only `Ping` and `Pong` were handled; unknown types were silently discarded.

The `likes` table gains a `like_uri` column — the canonical ActivityPub `id` of each like object. This is required to process `Undo Like` activities that reference the original `Like` by URI rather than by re-sending the full object. A migration backfills existing local likes using a `{base_url}/likes/{id}` pattern, where the base URL is derived at migration time from each row's `author_uri`. Going forward, local likes are assigned a URI by the caller via a `uri_fn` argument to `like_entry`; remote likes take the `id` from the inbound activity.

Two new Oban workers process the inbound activities. The `InboxController` dispatches `Like` to `ProcessInboundLikeWorker` and any `Undo` to `ProcessInboundUndoLikeWorker`; both are enqueued on the `:federation` queue at `max_attempts: 1`, consistent with the Ping/Pong workers.

The full Elixir suite (932 tests) and JS suite (35 tests) pass at 0 failures.

---

## New Files

### `lib/revix/workers/process_inbound_like_worker.ex`

Processes a `Like` activity received at the inbox.

1. Extracts `actor_uri` and `object_uri` from the activity. Returns `{:error, :invalid_activity}` if `object_uri` is missing or not a string.
2. Resolves `like_uri` from `activity["id"]`. If absent or not a string, generates a fallback `tag:` URI via `generate_like_uri/0` (RFC 4151; authority from `REVIX_HOST` env var, defaulting to `"revix"`).
3. Calls `Likes.create_inbound_like/1`. Unique constraint errors on `[:author_uri, :object_uri]` or `:like_uri` are treated as `:ok` (idempotent delivery).

**File:** [lib/revix/workers/process_inbound_like_worker.ex](lib/revix/workers/process_inbound_like_worker.ex)

---

### `lib/revix/workers/process_inbound_undo_like_worker.ex`

Processes an `Undo Like` activity received at the inbox.

Resolves the target like by inspecting `activity["object"]`:

| Shape | Resolution |
|---|---|
| String (a URI) | `Likes.undo_inbound_like/1` — lookup by `like_uri` |
| Map with `"id"` | `Likes.undo_inbound_like/1` — lookup by `like_uri` |
| Map without `"id"`, with `"actor"` + `"object"` | `Likes.undo_inbound_like/2` — fallback lookup by `author_uri` + `object_uri` |
| Anything else | `:ok` — silently discarded |

`{:error, :not_found}` is treated as `:ok` (idempotent). The actor guard (`^actor_uri` pin in the map pattern) prevents a remote actor from undoing another actor's like.

**File:** [lib/revix/workers/process_inbound_undo_like_worker.ex](lib/revix/workers/process_inbound_undo_like_worker.ex)

---

## Modified Files

### `priv/repo/migrations/20260511120000_add_like_uri_to_likes.exs`

Three-phase migration:

1. Adds `like_uri :text, null: true`.
2. Backfills local likes using Repo calls (not raw SQL) so the base URL can be computed from each row's `author_uri` without access to the Endpoint. Parses `scheme + host + non-default port` from `author_uri`; appends `/likes/{id}`.
3. Adds `NOT NULL` constraint via `modify`, then creates a unique index on `like_uri`.

Uses `def up`/`def down` (not `def change`) because `modify` with `null: false` is not reversible.

**File:** [priv/repo/migrations/20260511120000_add_like_uri_to_likes.exs](priv/repo/migrations/20260511120000_add_like_uri_to_likes.exs)

---

### `lib/revix/likes/like.ex`

Added `field :like_uri, :string` to the schema. Added `:like_uri` to `create_changeset/2` cast and validate_required, plus `unique_constraint(:like_uri)`. The `unlike_changeset/1` and `re_like_changeset/2` changesets are unchanged — `like_uri` is set at creation and never updated.

**File:** [lib/revix/likes/like.ex](lib/revix/likes/like.ex)

---

### `lib/revix/likes.ex`

**`like_entry/4` and `like_entry/5`** — `uri_fn` (a 1-arity function) is now required as the fourth argument. The private `do_like_entry/4` pre-generates the `id` via `Base58Id.autogenerate/0`, calls `uri_fn.(id)` to obtain `like_uri`, and sets both on the `%Like{}` struct before inserting. For re-likes, the `like_uri` is unchanged (stable identifier). The 5-arity variant adds `context_uri` for PubSub broadcast, as before.

**`create_inbound_like/1`** — remote path; no `Scope` required. Accepts `%{author_uri, object_uri, like_uri}`. Sets `origin: :remote`, `published_tz: "UTC"`, and both `published_at_*` fields to the current UTC time. Calls `Like.create_changeset/2` and `Repo.insert/1`.

**`undo_inbound_like/1`** — looks up an active like by `like_uri`; returns `{:error, :not_found}` or soft-deletes via `Like.unlike_changeset/1`.

**`undo_inbound_like/2`** — fallback; looks up by `author_uri` + `object_uri` via the existing private `get_active_like/2`; same return contract.

**File:** [lib/revix/likes.ex](lib/revix/likes.ex)

---

### `lib/revix_web/canonical_routes.ex`

Added:

```elixir
def like_path(id), do: "/likes/#{id}"
def like_uri(id), do: Phoenix.VerifiedRoutes.unverified_url(RevixWeb.Endpoint, like_path(id))
```

Used by web-layer callers to build the `uri_fn` passed to `like_entry`. Not a verified route (no matching router entry) — consistent with other non-routed URI helpers in this module.

**File:** [lib/revix_web/canonical_routes.ex](lib/revix_web/canonical_routes.ex)

---

### `lib/revix_web/controllers/inbox_controller.ex`

Added two `enqueue_activity/2` clauses before the catch-all:

- `%{"type" => "Like"}` → `ProcessInboundLikeWorker`
- `%{"type" => "Undo"}` → `ProcessInboundUndoLikeWorker`

The `Undo` clause enqueues unconditionally; the worker inspects the nested object type and silently discards non-Like undos.

**File:** [lib/revix_web/controllers/inbox_controller.ex](lib/revix_web/controllers/inbox_controller.ex)

---

### `lib/revix_web/controllers/like_controller.ex`

Builds `uri_fn = &RevixWeb.CanonicalRoutes.like_uri/1` and passes it as the fourth argument to `like_entry/4`.

**File:** [lib/revix_web/controllers/like_controller.ex](lib/revix_web/controllers/like_controller.ex)

---

### `lib/revix_web/live/entry_like_live.ex` and `lib/revix_web/live/comment_section_live.ex`

Both LiveViews build `uri_fn = &RevixWeb.CanonicalRoutes.like_uri/1` and pass it before `context_uri` in the `like_entry/5` call.

**Files:** [lib/revix_web/live/entry_like_live.ex](lib/revix_web/live/entry_like_live.ex), [lib/revix_web/live/comment_section_live.ex](lib/revix_web/live/comment_section_live.ex)

---

## Fallback `like_uri` Generation

When a remote `Like` activity arrives without an `"id"` field, `generate_like_uri/0` in `ProcessInboundLikeWorker` produces a `tag:` URI following RFC 4151:

```
tag:{authority},{date}:like:{Base58Id}
```

The authority is read from the `REVIX_HOST` environment variable at runtime, defaulting to `"revix"`. This produces a globally unique, non-dereferenceable identifier that is suitable for the `like_uri` column. Using the remote actor's URI as a base (the previous approach) was incorrect because we do not control that namespace.

---

## Test Coverage

### `test/revix/workers/process_inbound_like_worker_test.exs`

5 tests (`async: false`):

| Test | Scenario |
|---|---|
| Creates a remote Like record | Sets `origin: :remote`, `like_uri` from activity `"id"`, `published_tz: "UTC"` |
| Generates `like_uri` when activity has no `"id"` | Fallback URI starts with `"tag:"` |
| Idempotent on duplicate `[:author_uri, :object_uri]` | Second identical activity returns `:ok`; one row in DB |
| Idempotent on duplicate `like_uri` | Same `"id"` with different actor/object returns `:ok` |
| Returns `{:error, :invalid_activity}` when `"object"` missing or non-binary | Guards against malformed activities |

### `test/revix/workers/process_inbound_undo_like_worker_test.exs`

5 tests (`async: false`):

| Test | Scenario |
|---|---|
| Soft-deletes when `"object"` is a plain URI string | Sets `unliked_at`; verifies via `Repo.get_by!` |
| Soft-deletes when `"object"` is a full Like map with `"id"` | Same outcome via `undo_inbound_like/1` |
| Soft-deletes when `"object"` map has no `"id"` | Fallback to `undo_inbound_like/2` by actor + object |
| Returns `:ok` when no matching active like exists | Idempotent; no crash |
| Returns `:ok` when like was already unliked | `undo_inbound_like/1` sees nil; returns `:ok` |

### `test/revix_web/controllers/inbox_controller_test.exs`

Two tests added to the existing `"POST /people/:id/inbox"` describe block:

| Test | Scenario |
|---|---|
| `returns 202 for valid signed Like activity` | Full signature round-trip; 202 returned |
| `returns 202 for valid signed Undo Like activity` | Full signature round-trip with nested Like object |

---

## What Was Not Changed

- Outbound Like delivery — there is no outbound `Like` activity worker; local likes are not federated.
- `LikeController` response shape — the JSON response to the browser is unchanged.
- `unlike_entry/3` (broadcast variant) — signature unchanged.
- Existing Ping/Pong, checkin, media, and companion flows — unaffected.
- JavaScript — no new hooks or assets.
