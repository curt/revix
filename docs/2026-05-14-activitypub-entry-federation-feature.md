# ActivityPub Entry Federation — 2026-05-14

**Branch:** topic/follows  
**Scope:** Inbound `Create{Note/Article}`, `Update{Note/Article}`, and `Delete` activities; outbound fan-out of local entry create/update/delete to followers; broader inbound acceptance when the actor is followed by any local user.

---

## Summary

Extends entry federation in three directions:

**Broader inbound acceptance.** Inbound `Create{Note/Article}` was previously only accepted when the note's `context` or `inReplyTo` resolved to a local entry. It now also accepts if the actor is followed by any local user — a single JOIN query (`followed_by_any_local?/1`) on the `follows` + `people` tables, no N+1.

**Inbound Update as upsert.** A new `ProcessInboundUpdateNoteWorker` handles `Update{Note/Article}`. The same two-path acceptance check applies. If the entry already exists with `origin: :remote`, its content is updated and a `{:comment_updated, entry}` broadcast is sent. If the entry is not found, it is created (upsert path) and `{:comment_created, entry}` is broadcast. If the entry exists with `origin: :local`, the update is silently ignored — a remote actor cannot overwrite a local entry.

**Inbound Delete.** `ProcessInboundDeleteNoteWorker` handles `Delete` activities. The object is extracted from either a plain URI string or a Tombstone map with an `"id"` field. Authorization requires three conditions: a valid HTTP Signature (enforced by `InboxController`), the activity's `actor` matching the entry's `author_uri` (enforced by a pin match in `delete_inbound_note/2`), and the entry having `origin: :remote`. On success, the row is hard-deleted and `{:comment_deleted, entry_id}` is broadcast on the context topic. Not-found is idempotent (`:ok`). Authorization mismatches and local-origin entries are silently ignored.

**Outbound fan-out.** Every local entry create, update, and delete now enqueues a `DeliverEntryWorker` job with the entry ID and activity type (`"Create"`, `"Update"`, or `"Delete"`). The worker looks up the entry and its local author, fetches all accepted active followers, resolves each follower's inbox URL, and delivers the signed activity. Fan-out delivery is best-effort — failures for individual followers are silently ignored and the job returns `:ok`. All entries (checkins, posts, comments, replies) are serialized as `"type": "Note"` for maximum AP interoperability.

**DRY helpers.** `local_context?/1` and `parse_datetime/1` were private to `ProcessInboundCreateNoteWorker`. Since `ProcessInboundUpdateNoteWorker` needs the same logic, these were extracted to `Revix.Workers.InboundNoteHelpers` along with a new `extract_note_attrs/2` convenience function. Both workers now delegate to this shared module.

The full Elixir suite (1292 tests) and JS suite (35 tests) pass at 0 failures.

---

## New Files

### `lib/revix/workers/inbound_note_helpers.ex`

Shared helpers for inbound Note/Article workers. Three public functions:

- `local_context?(note)` — checks `note["context"]` and `note["inReplyTo"]` against `Entries.get_entry_by_uri/1`; returns `true` if either resolves to an entry with `origin: :local`. Checks both fields so notes that omit `context` are handled correctly.
- `extract_note_attrs(note, actor_uri)` — maps AP JSON keys to the attrs map expected by `Entries.create_inbound_note/1` and `Entry.inbound_note_changeset/2`. Falls back to `note["id"]` for `url` when the `"url"` field is absent.
- `parse_datetime(str_or_nil)` — parses ISO 8601 strings via `DateTime.from_iso8601/1`; returns `nil` for `nil` input or unparseable strings.

**File:** [lib/revix/workers/inbound_note_helpers.ex](lib/revix/workers/inbound_note_helpers.ex)

---

### `lib/revix/workers/process_inbound_update_note_worker.ex`

Oban worker on `:federation` queue, `max_attempts: 1`. Pattern-matched `perform/1` clauses:

- Main clause: extracts `note` (must be a map) and `actor_uri` from the activity; validates `note["id"]` is a binary. Falls through to `{:error, :invalid_activity}` via `with` if validation fails.
- Catch-all clause: `{:error, :invalid_activity}` for structurally invalid jobs.

Acceptance check: `InboundNoteHelpers.local_context?(note) or Follows.followed_by_any_local?(actor_uri)`. If neither is true, returns `:ok` (silently ignored).

Delegates to `update_and_normalize/2` which calls `Entries.update_inbound_note/2` and maps outcomes:
- `{:ok, _}` → `:ok`
- `{:error, :not_remote}` → `:ok` (local-origin entry; suppress)
- `{:error, reason}` → `{:error, reason}` (Ecto changeset failure — propagated)

**File:** [lib/revix/workers/process_inbound_update_note_worker.ex](lib/revix/workers/process_inbound_update_note_worker.ex)

---

### `lib/revix/workers/process_inbound_delete_note_worker.ex`

Oban worker on `:federation` queue, `max_attempts: 1`.

Extracts the object URI via private `extract_object_uri/1`:

| Object shape | Result |
|---|---|
| Binary string | The string itself |
| Map with binary `"id"` | The `"id"` value |
| Anything else (nil, map without `"id"`, etc.) | `nil` → `{:error, :invalid_activity}` |

Once a URI and `actor_uri` are confirmed as binaries, delegates to `Entries.delete_inbound_note(uri, actor_uri)`, normalizing all non-error results to `:ok`.

**File:** [lib/revix/workers/process_inbound_delete_note_worker.ex](lib/revix/workers/process_inbound_delete_note_worker.ex)

---

### `lib/revix/workers/deliver_entry_worker.ex`

Oban worker on `:federation` queue, `max_attempts: 1`. Args: `%{"entry_id" => id, "activity_type" => type}`.

Steps:
1. Load the entry via `Repo.get!/2`
2. Resolve the local actor via `People.get_local_person_by_uri/1` — if not found (e.g., entry deleted between enqueue and execution), returns `:ok` gracefully via `with`
3. Build the outbound activity via `build_activity/2`
4. Fetch accepted active followers via `Follows.get_followers_for_person/1`
5. For each follower, resolve inbox URL via `Federation.resolve_inbox/1` and deliver via `Federation.deliver/3`

Activity shapes:

| Type | Object |
|---|---|
| `"Create"` | Nested Note object with `attributedTo`, `content`, `inReplyTo`, `context`, `published` |
| `"Update"` | Same as Create |
| `"Delete"` | Plain URI string (`entry.uri`) — standard AP Delete shape |

Nil values are stripped from the Note object (`Map.reject`). `published` is omitted when `published_at_utc` is nil. All entries use `"type": "Note"` regardless of their internal type (checkin, post, comment, reply).

**File:** [lib/revix/workers/deliver_entry_worker.ex](lib/revix/workers/deliver_entry_worker.ex)

---

## Modified Files

### `lib/revix/workers/process_inbound_create_note_worker.ex`

- Replaced private `local_context?/1` and `parse_datetime/1` with `alias Revix.Workers.InboundNoteHelpers` and calls to the shared module
- Added `alias Revix.Follows`
- Changed the acceptance guard from `if local_context?(note)` to `if InboundNoteHelpers.local_context?(note) or Follows.followed_by_any_local?(actor_uri)`
- `persist_and_broadcast/2` now calls `InboundNoteHelpers.extract_note_attrs/2` instead of building the attrs inline

**File:** [lib/revix/workers/process_inbound_create_note_worker.ex](lib/revix/workers/process_inbound_create_note_worker.ex)

---

### `lib/revix/follows.ex`

Added `followed_by_any_local?/1`:

```elixir
def followed_by_any_local?(actor_uri) when is_binary(actor_uri) do
  Repo.exists?(
    from f in Follow,
      join: p in Revix.People.Person,
        on: p.uri == f.follower_uri and p.origin == :local,
      where: f.following_uri == ^actor_uri and is_nil(f.unfollowed_at)
  )
end
```

Single JOIN query — no N+1. Checks that the follower is a local person (`origin: :local`) and the follow is still active (`unfollowed_at IS NULL`). Does not require `accepted_at` — for inbound acceptance, the local user's intent to follow is sufficient.

**File:** [lib/revix/follows.ex](lib/revix/follows.ex)

---

### `lib/revix/entries.ex`

Four additions:

**`update_inbound_note/2`** — three-clause pattern via `case get_entry_by_uri(uri)`:

| Result | Action |
|---|---|
| `{:ok, %Entry{origin: :remote}}` | `Repo.update` + `tap_ok` broadcast `{:comment_updated, entry}` |
| `{:error, :not_found}` | `create_inbound_note(attrs)` + `tap_ok` broadcast `{:comment_created, entry}` |
| `{:ok, %Entry{origin: :local}}` | `{:error, :not_remote}` |

**`delete_inbound_note/2`** — pin-matches `author_uri` in the pattern head:

| Pattern | Action |
|---|---|
| `{:ok, %Entry{origin: :remote, author_uri: ^actor_uri}}` | `Repo.delete` + broadcast `{:comment_deleted, id}` |
| `{:error, :not_found}` | `:ok` |
| `_` (wrong actor, local origin) | `:ok` |

**`enqueue_deliver_entry/2`** (private) — creates and inserts a `DeliverEntryWorker` Oban job.

**`tap_ok/2`** (private) — applies `fun.(value)` when result is `{:ok, value}`, passes all other values through unchanged. Same pattern as `Follows` context.

**Wired outbound delivery** into eight existing functions:
- Create: `create_local_checkin`, `create_local_post`, `create_comment`, `create_reply`
- Update: `update_local_checkin`, `update_local_post`, `update_comment`
- Delete: `delete_comment`

**File:** [lib/revix/entries.ex](lib/revix/entries.ex)

---

### `lib/revix_web/controllers/inbox_controller.ex`

Added two `enqueue_activity/2` clauses before the existing `Create` clause:

```elixir
defp enqueue_activity(%{"type" => "Update", "object" => %{"type" => type}} = activity, person)
     when type in ["Note", "Article"] do
  ...ProcessInboundUpdateNoteWorker...
end

defp enqueue_activity(%{"type" => "Delete"} = activity, person) do
  ...ProcessInboundDeleteNoteWorker...
end
```

Clause ordering: `Update{Note/Article}` → `Delete` → existing `Create{Note/Article}` → catch-all. The `Delete` clause has no object type guard — Delete activities commonly carry plain URI strings or Tombstone maps, not typed Note maps.

**File:** [lib/revix_web/controllers/inbox_controller.ex](lib/revix_web/controllers/inbox_controller.ex)

---

## Data Flow

### Inbound Create / Update acceptance

```
Remote POST → InboxController (202)
  → ProcessInboundCreateNoteWorker or ProcessInboundUpdateNoteWorker
      ↓
  InboundNoteHelpers.local_context?(note)?
    context or inReplyTo → local entry (origin: :local)? → YES
  OR
  Follows.followed_by_any_local?(actor_uri)?
    JOIN follows + people WHERE origin: :local, unfollowed_at IS NULL → YES
      ↓ YES: Entries.create_inbound_note / update_inbound_note
          → Repo.insert / Repo.update
          → broadcast_context(context, {:comment_created/:comment_updated, entry})
      ↓ NO: :ok (silently ignored)
```

### Inbound Delete

```
Remote POST → InboxController (202)
  → ProcessInboundDeleteNoteWorker
      ↓
  extract_object_uri(activity["object"])
    binary string → uri
    map with "id"  → id
    other          → nil → {:error, :invalid_activity}
      ↓
  Entries.delete_inbound_note(uri, actor_uri)
    {:ok, %Entry{origin: :remote, author_uri: ^actor_uri}} →
        Repo.delete + broadcast {:comment_deleted, id} → :ok
    {:error, :not_found} → :ok
    _                    → :ok
```

### Outbound fan-out

```
Entries.create/update/delete_* → enqueue_deliver_entry(entry, "Create"/"Update"/"Delete")
  → DeliverEntryWorker.perform
      ↓
  Repo.get!(Entry, id)
  People.get_local_person_by_uri(author_uri)
  build_activity(type, entry)
  Follows.get_followers_for_person(author_uri)   ← accepted + active
      ↓ for each follower:
  Federation.resolve_inbox(follower_uri)
    {:ok, inbox_url} → Federation.deliver(activity, inbox_url, actor)
    _ → :ok
      ↓
  :ok
```

---

## What Was Not Changed

- Outbound `Like` delivery — local likes are still not federated outbound.
- Shared inbox support — fan-out delivers to per-actor inboxes only.
- Remote entries use hard delete (`Repo.delete`) — no soft-delete for remote-origin notes.
- Existing Ping/Pong, checkin UI, places, media, and companion flows — unaffected.
- JavaScript — no new hooks or assets.
