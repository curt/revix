# ActivityPub Follows — 2026-05-14

**Branch:** topic/follows  
**Scope:** Outbound and inbound ActivityPub `Follow`, `Accept`, and `Undo Follow` activities; `/following` LiveView management page; `followers` and `following` ActivityPub collection endpoints.

---

## Summary

Adds full ActivityPub follow support: local users can follow remote actors by URI, remote actors can follow local users, and both directions support unfollow/undo. Inbound follows are auto-accepted by default — an `Accept{Follow}` activity is delivered immediately by an Oban worker. Auto-accept can be disabled via the `AUTO_ACCEPT_FOLLOWS` environment variable, in which case pending follows queue up and the person accepts them manually from the `/following` page.

The `follows` table stores both local (outbound) and remote (inbound) follows with a shared soft-delete pattern via `unfollowed_at` (nil = active). `accepted_at` tracks whether an inbound follow has been accepted; local outbound follows leave this nil — the local actor is the initiator, so acceptance is implied.

Six new Oban workers handle activity delivery and inbound processing on the `:federation` queue at `max_attempts: 1`, consistent with the Ping/Pong and inbound Likes workers. The `InboxController` dispatches `Follow` and `Undo{Follow}` to the appropriate workers; clause ordering is significant — the typed `Undo{Follow}` clause must precede the generic `Undo` catch-all.

The `followers` and `following` ActivityPub collection endpoints (`GET /people/:id/followers` and `/people/:id/following`), previously stubs, now return real data.

The `tag:` URI scheme used for inbound likes without an `"id"` field was extracted into a shared `Revix.ActivityPub.TagUri` module and reused here for both local outbound follows and inbound follows without an `"id"`. The id embedded in the tag URI is reused as the database row's primary key, so no separate id generation is needed.

The full Elixir suite (1243 tests) and JS suite (35 tests) pass at 0 failures.

---

## New Files

### `lib/revix/activity_pub/tag_uri.ex`

Shared `tag:` URI generator extracted from `ProcessInboundLikeWorker`. Returns `{id, uri}` — the caller uses the embedded Base58 id directly as the database row's primary key.

```
tag:{authority},{date}:{type}:{id}
```

The authority is read from `REVIX_HOST` at runtime, defaulting to `"revix"`. Two calls always return different values (different Base58 ids).

**File:** [lib/revix/activity_pub/tag_uri.ex](lib/revix/activity_pub/tag_uri.ex)

---

### `lib/revix/follows/follow.ex`

Schema for the `follows` table. Uses `use Revix.Schema` (Base58 primary key, UTC timestamps). Fields:

| Field | Type | Notes |
|---|---|---|
| `uri` | `:string` | ActivityPub `id`; unique |
| `follower_uri` | `:string` | URI of the actor doing the following |
| `following_uri` | `:string` | URI of the actor being followed |
| `origin` | `Origin` | `:local` or `:remote` |
| `accepted_at` | `:utc_datetime` | Set when an inbound follow is accepted; nil for outbound |
| `unfollowed_at` | `:utc_datetime` | Set on soft-delete; nil = active |

Changesets:
- `create_changeset/2` — casts and validates required fields; enforces unique constraints on `uri` and `[follower_uri, following_uri]`
- `accept_changeset/1` — sets `accepted_at: DateTime.utc_now(:second)`
- `unfollow_changeset/1` — sets `unfollowed_at: DateTime.utc_now(:second)`
- `refollow_changeset/1` — clears both `accepted_at` and `unfollowed_at` (used when re-following after an unfollow)
- `active?/1` — pattern-matches on `unfollowed_at: nil`

**File:** [lib/revix/follows/follow.ex](lib/revix/follows/follow.ex)

---

### `lib/revix/follows.ex`

Public context API. All branching is expressed through private multi-clause functions; public functions are thin pipelines.

**Outbound (local person follows someone):**

- `follow(scope, target_uri)` — guards against self-follow; delegates to `do_follow/2` which dispatches via `insert_or_refollow/3` (three clauses: nil → insert, active → idempotent ok, previously-unfollowed → refollow). Enqueues `DeliverFollowWorker`.
- `unfollow(scope, following_uri)` — looks up active follow and delegates to `soft_delete_follow/1`. Enqueues `DeliverUndoFollowWorker`.

**Inbound (remote follows local):**

- `upsert_inbound_follow(%{uri, follower_uri, following_uri})` — same three-state upsert via `upsert_follow/5`. Reads `auto_accept` at runtime via `Application.get_env` (not compile-time). When accepting: sets `accepted_at` on insert/re-follow, enqueues `DeliverAcceptFollowWorker`, and broadcasts `:follows_updated`. When not accepting: broadcasts only.
- `accept_follow(follow_id)` — manual acceptance path used from the LiveView; sets `accepted_at`.
- `undo_inbound_follow(follow_uri)` — by URI string; soft-deletes and broadcasts.
- `undo_inbound_follow(follower_uri, following_uri)` — fallback by pair; same.

**Queries:**

- `get_followers_for_person/2` — accepted + active only; ordered desc inserted_at; optional `:limit`
- `get_following_for_person/2` — active (regardless of `accepted_at`); ordered desc; optional `:limit`
- `get_pending_followers_for_person/1` — `accepted_at IS NULL AND unfollowed_at IS NULL`
- `follower_of?/2` — requires accepted + active; returns boolean; handles nil follower
- `following?/2` — requires active only (pending outbound counts); handles nil follower
- `count_followers/1`, `count_following/1` — integer counts
- `subscribe_to_follows/1` — PubSub subscribe on `"follows:#{person_uri}"`

**File:** [lib/revix/follows.ex](lib/revix/follows.ex)

---

### `lib/revix/workers/deliver_follow_worker.ex`

Looks up the follow record, resolves the local actor by `follower_uri`, resolves the inbox for `following_uri`, and delivers:

```json
{"type": "Follow", "id": "{follow.uri}", "actor": "{follower_uri}", "object": "{following_uri}"}
```

**File:** [lib/revix/workers/deliver_follow_worker.ex](lib/revix/workers/deliver_follow_worker.ex)

---

### `lib/revix/workers/deliver_undo_follow_worker.ex`

Same lookup pattern; delivers:

```json
{"type": "Undo", "id": "{follow.uri}#undo", "actor": "{follower_uri}", "object": {"type": "Follow", "id": "{follow.uri}", ...}}
```

**File:** [lib/revix/workers/deliver_undo_follow_worker.ex](lib/revix/workers/deliver_undo_follow_worker.ex)

---

### `lib/revix/workers/deliver_accept_follow_worker.ex`

Looks up the follow record, resolves the local actor by `following_uri` (the person being followed signs the Accept), resolves the inbox for `follower_uri` (Accept is delivered back to the remote follower), and delivers:

```json
{"type": "Accept", "id": "{actor.uri}/accepts/{follow.id}", "actor": "{following_uri}", "object": {"type": "Follow", ...}}
```

**File:** [lib/revix/workers/deliver_accept_follow_worker.ex](lib/revix/workers/deliver_accept_follow_worker.ex)

---

### `lib/revix/workers/process_inbound_follow_worker.ex`

Validates that `activity["object"]` is a binary (returns `{:error, :invalid_activity}` otherwise — enforced via a guard on `perform/1` with a catch-all clause). Resolves the follow URI from `activity["id"]`, falling back to `TagUri.generate("follow")` when absent. Calls `Follows.upsert_inbound_follow/1`, which handles Accept delivery internally.

**File:** [lib/revix/workers/process_inbound_follow_worker.ex](lib/revix/workers/process_inbound_follow_worker.ex)

---

### `lib/revix/workers/process_inbound_undo_follow_worker.ex`

Dispatches via private `undo/2` multi-clause functions matching the three shapes of `activity["object"]`:

| Shape | Resolution |
|---|---|
| String (a URI) | `undo_inbound_follow(uri)` |
| Map with `"id"` | `undo_inbound_follow(follow_uri)` |
| Map with `"actor"` + `"object"` but no `"id"` | `undo_inbound_follow(actor_uri, following_uri)` |
| Anything else | `:ok` — silently discarded |

`{:error, :not_found}` is normalised to `:ok` (idempotent). The actor pin (`^actor_uri`) in the third clause prevents a remote actor from undoing another actor's follow.

**File:** [lib/revix/workers/process_inbound_undo_follow_worker.ex](lib/revix/workers/process_inbound_undo_follow_worker.ex)

---

### `lib/revix_web/live/following_live.ex` and `lib/revix_web/live/following_live.html.heex`

LiveView available to all authenticated users (no owner restriction). Subscribes to `"follows:#{person_uri}"` PubSub topic when connected; refreshes all lists on `:follows_updated`.

Events:

| Event | Action |
|---|---|
| `"follow"` | `Follows.follow(scope, uri)`; resets input; flash |
| `"unfollow"` | `Follows.unfollow(scope, following_uri)`; flash |
| `"accept"` | `Follows.accept_follow(follow_id)`; enqueues `DeliverAcceptFollowWorker`; flash |
| `"update_target"` | Updates `:target_uri` assign |
| `"switch_tab"` | Switches between `:following` and `:followers` tabs |

The template has two tabs: **Following** (list of outgoing follows with Unfollow buttons) and **Followers** (pending follows with Accept buttons at top, accepted followers below). People are bulk-loaded via `People.get_people_by_uris/1` and displayed with avatars and display names; unknown URIs fall back to monospace text.

**Files:** [lib/revix_web/live/following_live.ex](lib/revix_web/live/following_live.ex), [lib/revix_web/live/following_live.html.heex](lib/revix_web/live/following_live.html.heex)

---

## Modified Files

### `priv/repo/migrations/20260513120000_create_follows.exs`

Creates the `follows` table with a Base58 primary key (`:char`, size 11), `:text` columns, `:utc_datetime` for `accepted_at` and `unfollowed_at`, and standard UTC timestamps. Indexes:

- Unique on `uri`
- Unique on `[follower_uri, following_uri]`
- Non-unique on `follower_uri` and `following_uri` individually

No foreign key constraints (federation compatibility).

**File:** [priv/repo/migrations/20260513120000_create_follows.exs](priv/repo/migrations/20260513120000_create_follows.exs)

---

### `lib/revix/workers/process_inbound_like_worker.ex`

Replaced the private `generate_like_uri/0` helper with `elem(Revix.ActivityPub.TagUri.generate("like"), 1)`, now that the logic lives in the shared `TagUri` module.

**File:** [lib/revix/workers/process_inbound_like_worker.ex](lib/revix/workers/process_inbound_like_worker.ex)

---

### `lib/revix_web/controllers/inbox_controller.ex`

Added two `enqueue_activity/2` clauses before the existing `Undo` catch-all:

- `%{"type" => "Follow"}` → `ProcessInboundFollowWorker`
- `%{"type" => "Undo", "object" => %{"type" => "Follow"}}` → `ProcessInboundUndoFollowWorker`

Clause ordering is critical: the typed `Undo{Follow}` clause must precede the generic `Undo` clause (which handles `Undo{Like}` and string-URI undos).

**File:** [lib/revix_web/controllers/inbox_controller.ex](lib/revix_web/controllers/inbox_controller.ex)

---

### `lib/revix_web/controllers/person_collection_controller.ex`

Replaced stub `followers/2` and `following/2` actions with real queries. Both map follow records to URI strings and render them as `orderedItems` in an `OrderedCollection` response. The `liked` action remains a stub.

**File:** [lib/revix_web/controllers/person_collection_controller.ex](lib/revix_web/controllers/person_collection_controller.ex)

---

### `lib/revix/people.ex`

Added `alias Revix.Follows.Follow` and extended `activity_checks/0` with `&is_follow_actor?/1`:

```elixir
defp is_follow_actor?(uri) do
  Repo.exists?(from f in Follow, where: f.follower_uri == ^uri or f.following_uri == ^uri)
end
```

This prevents `PurgeInactiveRemotePeopleWorker` from deleting remote people who are followers or followees.

**File:** [lib/revix/people.ex](lib/revix/people.ex)

---

### `lib/revix_web/router.ex`

Added inside `live_session :authenticated`:

```elixir
live "/following", FollowingLive, :index
```

---

### `lib/revix_web/components/layouts.ex`

Added a "Following" nav link inside the `if @current_scope` block, visible to all authenticated users.

---

### `config/config.exs` and `config/runtime.exs`

Added default `auto_accept: true` in `config.exs`. Added runtime override in `runtime.exs` (prod block):

```elixir
config :revix, :follows,
  auto_accept: System.get_env("AUTO_ACCEPT_FOLLOWS", "true") == "true"
```

`auto_accept` is read at call-time via `Application.get_env`, not at compile-time, so the env var override works in releases without recompilation.

---

### `test/support/conn_case.ex`

Added `use Oban.Testing, repo: Revix.Repo` to the `using` block so `assert_enqueued` is available in LiveView and controller tests (not just `DataCase`).

---

## Auto-accept Flow

```
Remote actor POSTs Follow → InboxController (202) → ProcessInboundFollowWorker
  → upsert_inbound_follow (auto_accept: true)
    → sets accepted_at
    → enqueues DeliverAcceptFollowWorker
    → broadcasts :follows_updated
  → DeliverAcceptFollowWorker
    → resolves local actor (the person being followed)
    → resolves inbox for remote follower
    → delivers Accept{Follow} signed with local actor's private key
```

When `AUTO_ACCEPT_FOLLOWS=false`, the `DeliverAcceptFollowWorker` is not enqueued and `accepted_at` stays nil. The follow appears in the Pending section on the `/following` page. Clicking Accept calls `Follows.accept_follow/1` and then enqueues `DeliverAcceptFollowWorker` from the LiveView.

---

## What Was Not Changed

- Outbound `Like` delivery — local likes are still not federated outbound.
- Existing Ping/Pong, checkin, media, and companion flows — unaffected.
- JavaScript — no new hooks or assets.
- The `liked` ActivityPub collection endpoint — remains a stub.
