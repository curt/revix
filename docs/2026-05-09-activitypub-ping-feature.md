# ActivityPub Ping — 2026-05-09

**Branch:** topics/activitypub-ping
**Scope:** Inbound and outbound ActivityPub Ping/Pong over HTTP Signatures; owner-only send UI; Oban background delivery; daily purge.

---

## Summary

Adds the first fully federated ActivityPub feature: Ping and Pong activities as described in `docs/ping.txt`. An owner can send a Ping to any remote actor URI; the remote server delivers a Pong to the local inbox; both are stored in a new `pings` table and displayed in a live-updating `/pings` page.

Two new dependencies handle the heavy lifting: **Oban** (background job processing) and **http_signatures** (HTTP Signature signing and verification). All outbound activities are signed with the sender's RSA private key; all inbound activities are verified against the sender's public key, which is fetched and cached in the `people` table with a configurable staleness window.

The inbox is general-purpose — it accepts any well-formed activity, dispatches known types to typed Oban workers, and silently discards unknown types. Ping and Pong handling enforces the owner-only constraint inside the worker (not at the HTTP layer), keeping the door open for future activity types that any person can receive.

The full Elixir suite (732 tests) and JS suite (51 tests) pass at 0 failures.

---

## New Files

### `lib/revix/pings/ping.ex`

Schema for the `pings` table. Uses the standard `Revix.Schema` base (Base58 primary key, UTC timestamps). Fields:

| Field | Type | Notes |
|---|---|---|
| `uri` | `:string` | ActivityPub `id` of the Ping or Pong activity; unique |
| `type` | `PingType` | `:ping` or `:pong` |
| `direction` | `Direction` | `:inbound` or `:outbound` |
| `actor_uri` | `:string` | Who sent the activity |
| `target_uri` | `:string` | Who received the activity |
| `object_uri` | `:string` | Nullable; the Ping URI that a Pong references |
| `status` | `PingStatus` | `:pending`, `:delivered`, or `:failed` |
| `error` | `:string` | Nullable; failure reason stored on `:failed` |

**File:** [lib/revix/pings/ping.ex](lib/revix/pings/ping.ex)

---

### `lib/revix/pings.ex`

Context module. Public functions:

| Function | Returns | Notes |
|---|---|---|
| `create_outbound_ping/3` | `{:ok, ping}` | `actor_uri, target_uri, ping_uri` |
| `create_inbound_ping/1` | `{:ok, ping}` | attrs map; status `:pending` |
| `create_outbound_pong/4` | `{:ok, ping}` | Adds `object_uri` linking to original Ping |
| `create_inbound_pong/1` | `{:ok, ping}` | attrs map; status `:delivered` immediately |
| `mark_delivered/1` | `{:ok, ping}` | Updates status |
| `mark_failed/2` | `{:ok, ping}` | Updates status and stores error string |
| `get_ping!/1` | `%Ping{}` | Raises on missing; used by workers |
| `get_ping_by_uri!/1` | `%Ping{}` | Raises on missing; used by self-ping/pong collision recovery |
| `list_recent/1` | `[%Ping{}]` | Ordered by `inserted_at desc`; default limit 50 |
| `purge_older_than/1` | `{:ok, count}` | Deletes all pings with `inserted_at` before `days` ago |
| `send_ping/3` | `{:ok, ping} \| {:error, :unauthorized}` | Owner check; inserts outbound Ping; enqueues `DeliverPingWorker` |

**File:** [lib/revix/pings.ex](lib/revix/pings.ex)

---

### `lib/revix/federation.ex`

Outbound HTTP delivery. Three public functions:

**`fetch_actor/1`** — GETs a remote actor document with `Accept: application/activity+json`. Returns `{:ok, map}` or `{:error, {:http_error, status} | reason}`. Retries are disabled (`retry: false`).

**`resolve_inbox/1`** — calls `fetch_actor/1` and extracts `actor["inbox"]`. Returns `{:ok, url}` or `{:error, :no_inbox | reason}`.

**`deliver/3`** — takes an activity map, an inbox URL, and a local `%Person{}`. Encodes the activity as JSON, builds a `Digest` header (SHA-256 of the body), constructs the signing string over `(request-target)`, `host`, `date`, `digest`, and `content-type`, signs with the person's RSA private key via `HTTPSignatures.sign/3`, and POSTs to the inbox with all headers. Returns `:ok` on 2xx or `{:error, reason}`.

Outbound HTTP calls use `Req` with a configurable `federation_req_plug` (set to `{Req.Test, :federation}` in test) so they can be stubbed without changing production code.

**File:** [lib/revix/federation.ex](lib/revix/federation.ex)

---

### `lib/revix/federation/signature_verifier.ex`

Implements the `HTTPSignatures.Adapter` behaviour. Called by `HTTPSignatures.validate_conn/1` during inbox request verification.

**`fetch_public_key/1`** — extracts the `keyId` from the `Signature` header, strips the `#key` fragment to get the actor URI, and calls `fetch_or_refresh_person/2` with `force_refresh: false`. If the person is found locally and their `updated_at` is within the staleness window, returns the cached key. Otherwise re-fetches.

**`refetch_public_key/1`** — same flow but with `force_refresh: true`. Called automatically by `HTTPSignatures` when the first key fails validation.

**`fetch_or_refresh_person/2`** — looks up the actor URI in `people` via `People.get_person_by_uri/1`. If not found, stale (older than `key_refresh_hours`, default 24), or force-refreshed, calls `Federation.fetch_actor/1` and upserts via `People.upsert_remote_person/1`.

Public keys are decoded from PEM via `X509.PublicKey.from_pem/1` and returned as `:public_key`-compatible tuples.

**File:** [lib/revix/federation/signature_verifier.ex](lib/revix/federation/signature_verifier.ex)

---

### `lib/revix/workers/deliver_ping_worker.ex`

Delivers an outbound Ping. `max_attempts: 1` — no retry on failure per spec.

1. Loads the `%Ping{}` by id.
2. Looks up the local actor via `People.get_local_person_by_uri/1`.
3. Resolves the target's inbox via `Federation.resolve_inbox/1`.
4. Builds the Ping activity JSON (`type: "Ping"`, `id`, `actor`, `to`).
5. Delivers via `Federation.deliver/3`.
6. On success: `Pings.mark_delivered/1`; broadcasts `:pings_updated` on PubSub topic `"pings"`.
7. On failure: `Pings.mark_failed/2` with the error; broadcasts; returns `:discard`.

**File:** [lib/revix/workers/deliver_ping_worker.ex](lib/revix/workers/deliver_ping_worker.ex)

---

### `lib/revix/workers/deliver_pong_worker.ex`

Delivers an outbound Pong. Identical flow to `DeliverPingWorker`. Builds the Pong activity JSON (`type: "Pong"`, `id`, `actor`, `to`, `object` — the original Ping URI).

**File:** [lib/revix/workers/deliver_pong_worker.ex](lib/revix/workers/deliver_pong_worker.ex)

---

### `lib/revix/workers/process_inbound_ping_worker.ex`

Processes a Ping received at the inbox.

1. Loads the local person by id; if `role != :owner`, silently returns `:ok` (discards).
2. Stores the inbound Ping via `Pings.create_inbound_ping/1`. If the URI already exists (self-ping: the outbound record was inserted when the Ping was sent), the unique constraint error is caught and the existing record is reused via `Pings.get_ping_by_uri!/1` — no duplicate row is created.
3. Generates a Pong URI (`person.uri/pong/:id`), creates an outbound Pong via `Pings.create_outbound_pong/4`, and enqueues `DeliverPongWorker`.

**File:** [lib/revix/workers/process_inbound_ping_worker.ex](lib/revix/workers/process_inbound_ping_worker.ex)

---

### `lib/revix/workers/process_inbound_pong_worker.ex`

Processes a Pong received at the inbox.

1. Loads the local person by id; if `role != :owner`, silently returns `:ok`.
2. Stores the inbound Pong via `Pings.create_inbound_pong/1` (sets `object_uri` from `activity["object"]`). If the URI already exists (self-pong), the unique constraint error is caught and the existing outbound Pong is marked delivered via `Pings.mark_delivered/1` instead.
3. Broadcasts `:pings_updated` so the `/pings` LiveView refreshes.

**File:** [lib/revix/workers/process_inbound_pong_worker.ex](lib/revix/workers/process_inbound_pong_worker.ex)

---

### `lib/revix/workers/purge_pings_worker.ex`

Daily Oban cron job (runs at midnight UTC). Calls `Pings.purge_older_than/1` with `Application.get_env(:revix, :pings)[:retention_days]` (default 7).

**File:** [lib/revix/workers/purge_pings_worker.ex](lib/revix/workers/purge_pings_worker.ex)

---

### `lib/revix_web/controllers/inbox_controller.ex`

Handles `POST /people/:id/inbox`. Uses the `:federation` pipeline (accepts `application/activity+json`). Steps:

1. **Person lookup** — `safe_get_local_person/1` wraps `People.get_local_person/1` to catch `Ecto.Query.CastError` on malformed IDs and return `{:error, :not_found}`. Returns 404 on not found.
2. **Signature verification** — injects `{"(request-target)", "post /people/:id/inbox"}` into `req_headers` (the pseudo-header is not present in real requests and is needed to reconstruct the signing string), then calls `HTTPSignatures.validate_conn/1`. Returns 401 on failure.
3. **Activity validation** — requires `type`, `actor`, and `id` fields to be present and binary. Returns 400 on failure.
4. **202 Accepted** — returned immediately (non-blocking).
5. **Enqueue** — dispatches by `type`: `"Ping"` → `ProcessInboundPingWorker`, `"Pong"` → `ProcessInboundPongWorker`, anything else is silently accepted and not queued.

**File:** [lib/revix_web/controllers/inbox_controller.ex](lib/revix_web/controllers/inbox_controller.ex)

---

### `lib/revix_web/raw_body_reader.ex`

Thin wrapper around `Plug.Conn.read_body/2` that accumulates the raw request body into `conn.assigns[:raw_body]`. Configured as `body_reader` on `Plug.Parsers` in `endpoint.ex` so the raw bytes are available for Digest header verification after the body has been parsed by the JSON decoder.

**File:** [lib/revix_web/raw_body_reader.ex](lib/revix_web/raw_body_reader.ex)

---

### `lib/revix_web/live/pings_live.ex`

Owner-only LiveView at `GET /pings`. Mount redirects non-owners to `/` with a flash error. Subscribes to PubSub topic `"pings"` when connected.

Assigns:

| Assign | Purpose |
|---|---|
| `pings` | Recent `%Ping{}` list from `Pings.list_recent/0` |
| `people` | `%{uri => %Person{}}` map built by `People.get_people_by_uris/1` over all actor/target URIs in `pings`; refreshed alongside `pings` |
| `target_uri` | Current value of the target actor URI input |
| `sending` | Reserved; not currently used to gate UI |

Events:

| Handler | Notes |
|---|---|
| `send_ping` | Trims `target_uri`; calls `Pings.send_ping/3` with a URI factory for `person.uri/ping/:id`; reloads the list and people map; sets flash |
| `update_target` | Keeps `target_uri` in sync with the text input |

`handle_info(:pings_updated, ...)` reloads both `pings` and `people` whenever a worker broadcasts a status change.

Private helpers: `person_link/1` renders an avatar and linked display name (falling back to the raw URI if the person is not yet in the DB); `format_age/1` renders a human-readable age string (just now / Nm ago / Nh ago / Nd ago); `status_class/1` returns a Tailwind text color class per status.

**File:** [lib/revix_web/live/pings_live.ex](lib/revix_web/live/pings_live.ex)

---

### `lib/revix_web/live/pings_live.html.heex`

Single-page layout:

- A form with a text input for the target actor URI and a "Send Ping" button (`phx-disable-with="Sending…"`).
- A table with columns: Direction, Type, Actor, Target, Status (with inline error if present), Age.
- A "No pings yet." row when the list is empty.

Actor and Target cells render via `person_link/1`: a small circular avatar followed by the person's display name (or username, or ID as fallback) as a link to their `url`. The full URI appears as a `title` tooltip. If the person is not yet in the local `people` table, the raw URI is shown in monospace as a fallback.

**File:** [lib/revix_web/live/pings_live.html.heex](lib/revix_web/live/pings_live.html.heex)

---

### `test/support/federation_fixtures.ex`

Static RSA key pair (2048-bit, generated once and embedded as PEM literals) for deterministic signature tests. Functions:

| Function | Returns |
|---|---|
| `private_key_pem/0` | PEM string of the test private key |
| `public_key_pem/0` | PEM string of the test public key |
| `private_key/0` | Decoded private key tuple |
| `public_key/0` | Decoded public key tuple |
| `remote_actor_uri/0` | `"https://remote.example.com/users/alice"` |
| `remote_inbox_url/0` | `"https://remote.example.com/users/alice/inbox"` |
| `remote_actor_map/1` | Full ActivityPub actor JSON map including `publicKey` |
| `sign_headers/3` | Calls `HTTPSignatures.sign/3` with test key |
| `signed_conn/2` | Adds `date`, `digest`, and `signature` headers to a test conn |

**File:** [test/support/federation_fixtures.ex](test/support/federation_fixtures.ex)

---

## Modified Files

### `mix.exs`

Added two dependencies:

```elixir
{:oban, "~> 2.22"},
{:http_signatures, "~> 0.1"},
```

**File:** [mix.exs](mix.exs)

---

### `lib/revix/people/person.ex`

Added `remote_changeset/2` for inserting or updating remote actors fetched via federation. Sets `origin: :remote` and generates two synthetic values to satisfy NOT NULL constraints:

- **email** — `sha256(uri)` encoded as lowercase hex, appended with `@example.invalid`. The domain is guaranteed non-deliverable (RFC 2606); the hash provides uniqueness without collision risk.
- **url** — falls back to `uri` when the actor document does not include a `url` field.

These synthetic values are never used for authentication — magic-link login queries by real email addresses only, and remote persons have no `hashed_password`.

**File:** [lib/revix/people/person.ex](lib/revix/people/person.ex)

---

### `lib/revix/people.ex`

Added three functions:

**`get_person_by_uri/1`** — like `get_local_person_by_uri/1` but without the `origin: :local` constraint. Used by `SignatureVerifier` to look up cached remote actors.

**`get_people_by_uris/1`** — bulk-loads all persons matching a list of URIs and returns a `%{uri => %Person{}}` map. Used by `PingsLive` to populate the actor/target display without N+1 queries.

**`upsert_remote_person/1`** — inserts a new remote person or updates `display_name`, `username`, `public_key`, `url`, and `updated_at` on URI conflict. Used by `SignatureVerifier` when re-fetching a stale or unknown actor.

**File:** [lib/revix/people.ex](lib/revix/people.ex)

---

### `lib/revix_web/endpoint.ex`

Added `body_reader: {RevixWeb.RawBodyReader, :read_body, []}` to `Plug.Parsers` so the raw request body is cached before JSON parsing consumes it.

**File:** [lib/revix_web/endpoint.ex](lib/revix_web/endpoint.ex)

---

### `lib/revix_web/router.ex`

Added a `:federation` pipeline (accepts `application/activity+json` and `application/json`, no session or CSRF):

```elixir
pipeline :federation do
  plug Plug.RewriteOn, [:x_forwarded_host, :x_forwarded_port, :x_forwarded_proto]
  plug :accepts, ["activity", "json"]
end
```

Added two routes:

```elixir
# Inside :authenticated live_session
live "/pings", PingsLive, :index

# Under :federation pipeline (no auth)
post "/people/:id/inbox", InboxController, :create
```

**File:** [lib/revix_web/router.ex](lib/revix_web/router.ex)

---

### `lib/revix/application.ex`

Added Oban to the supervision tree, before `RevixWeb.Endpoint`:

```elixir
{Oban, Application.fetch_env!(:revix, Oban)}
```

**File:** [lib/revix/application.ex](lib/revix/application.ex)

---

### `config/config.exs`

Added:

```elixir
config :revix, :federation, key_refresh_hours: 24
config :revix, :pings, retention_days: 7

config :revix, Oban,
  engine: Oban.Engines.Basic,
  repo: Revix.Repo,
  queues: [federation: 5],
  plugins: [
    {Oban.Plugins.Cron, crontab: [{"0 0 * * *", Revix.Workers.PurgePingsWorker}]}
  ]

config :http_signatures, adapter: Revix.Federation.SignatureVerifier
```

**File:** [config/config.exs](config/config.exs)

---

### `config/test.exs`

Added:

```elixir
config :revix, :federation_req_plug, {Req.Test, :federation}
config :revix, Oban, testing: :manual
```

Oban manual mode enqueues jobs normally but never executes them automatically. Worker logic is tested directly via `Oban.Testing.perform_job/2` (injected into all `DataCase` tests via `use Oban.Testing, repo: Revix.Repo`), which runs the worker in the test process and avoids spawning processes that would lose sandbox access. Tests that trigger federation HTTP calls stub `:federation` with `Req.Test` and are marked `async: false`.

**File:** [config/test.exs](config/test.exs)

---

## New Ecto Types

Three new types in `lib/revix/ecto/`, all following the `Origin` pattern (atom ↔ string cast/load/dump, `values/0`):

| Module | Values |
|---|---|
| `Revix.Ecto.PingType` | `:ping`, `:pong` |
| `Revix.Ecto.PingStatus` | `:pending`, `:delivered`, `:failed` |
| `Revix.Ecto.Direction` | `:inbound`, `:outbound` |

---

## Database Migrations

Two migrations added under `priv/repo/migrations/`:

**`20260509120000_add_oban_jobs.exs`** — runs `Oban.Migrations.up(version: 14)`, which creates the `oban_jobs` and `oban_peers` tables with all supporting indexes, triggers, and enum types.

**`20260509120001_create_pings.exs`** — creates the `pings` table with unique index on `uri` and standard indexes on `actor_uri`, `target_uri`, `object_uri`, and `inserted_at`.

---

## Test Coverage

### `test/revix/pings_test.exs`

14 tests (`async: false`; stubbed `:federation`):

| Describe block | Tests |
|---|---|
| `create_outbound_ping/3` | Fields set correctly; status `:pending` |
| `create_inbound_ping/1` | Direction `:inbound`; status `:pending` |
| `create_outbound_pong/4` | Type `:pong`; `object_uri` set |
| `create_inbound_pong/1` | Status `:delivered` immediately |
| `mark_delivered/1` | Status updated |
| `mark_failed/2` | Status and error stored |
| `list_recent/1` | Ordered desc; limit respected |
| `purge_older_than/1` | Deletes old rows; spares recent rows |
| `send_ping/3` | Owner creates ping and enqueues worker; non-owner returns `:unauthorized` |

### `test/revix/federation_test.exs`

8 tests (`async: false`; stubbed `:federation`):

| Describe block | Tests |
|---|---|
| `fetch_actor/1` | 200 returns map; non-200 returns `{:error, {:http_error, status}}`; transport error returns `{:error, _}` |
| `resolve_inbox/1` | Extracts inbox URL; returns `{:error, :no_inbox}` when field absent |
| `deliver/3` | Posts signed activity to inbox and returns `:ok` |

### `test/revix/workers/`

Three worker test files. All use `perform_job/2` from `Oban.Testing` (available in every `DataCase` via `use Oban.Testing, repo: Revix.Repo`) rather than `Oban.insert/1`, so workers run in the test process and never orphan sandbox connections.

| File | Tests |
|---|---|
| `process_inbound_ping_worker_test.exs` | Stores inbound ping and enqueues pong for owner; self-ping reuses existing outbound ping and still enqueues pong; silently drops for non-owner |
| `process_inbound_pong_worker_test.exs` | Stores inbound pong for owner; self-pong marks existing outbound pong as delivered rather than inserting a duplicate; silently drops for non-owner |
| `purge_pings_worker_test.exs` | Deletes old pings; leaves recent ones |

### `test/revix_web/controllers/inbox_controller_test.exs`

5 tests (`async: false`). Uses `Plug.Test.conn/3` with a raw binary body and direct `RevixWeb.Endpoint.call/2` dispatch to ensure the request body bytes exactly match the `Digest` header computed during signing:

| Test | Scenario |
|---|---|
| 404 for unknown person | Malformed or non-existent ID |
| 400 for malformed activity | Missing required fields |
| 202 for valid signed Ping to owner | Full round-trip: pre-seeded public key, correct signature |
| 202 for valid signed Pong | Same, with Pong type |
| 202 for unknown activity type | `"Follow"` accepted and discarded silently |

### `test/revix_web/live/pings_live_test.exs`

5 tests (`async: false`; stubbed `:federation`):

| Test | Scenario |
|---|---|
| Redirects non-owner to home | `{:error, {:redirect, %{to: "/"}}}` |
| Renders ping table for owner | Page heading and send button visible |
| Shows "No pings yet" when empty | Empty state row |
| Owner can send a ping | Form submit triggers `send_ping` |
| Redirects unauthenticated user | To `/people/signin` |

---

### `lib/revix_web/components/layouts.ex`

Added a "Pings" navigation menu item between Settings and Sign out. The item is only rendered when `@current_scope.person.role == :owner`.

**File:** [lib/revix_web/components/layouts.ex](lib/revix_web/components/layouts.ex)

---

## What Was Not Changed

- Existing ActivityPub serialization helpers (`to_person_activity`, `to_checkin_activity`, `to_place_activity`) — unaffected.
- `WebfingerController`, `NodeInfoController` — unaffected.
- Existing person inbox/outbox/followers/following URLs advertised in `to_person_activity` — the inbox is now live; outbox, followers, and following remain stub URLs.
- JavaScript — no new hooks or assets.
- Existing checkin, like, entry-people, and media flows — unaffected.
