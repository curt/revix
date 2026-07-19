# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. See also `AGENTS.md` in the repo root, which contains general Phoenix/Elixir/Ecto/HTML guidelines that apply to this project — read both files before making changes.

## Running Commands

- **Run tests:** `make tests` (injects env vars from `.env` via the Makefile)
- **Run server:** `make serve` (starts `iex -S mix phx.server`)
- **Migrate database:** `make migrate-db`
- **Rollback migration:** `make rollback-db`
- **Create database:** `make create-db`
- **Precommit checks:** `make precommit` (compile --warnings-as-errors, deps.unlock --unused, format, test)
- **Coverage report:** `make coverage` (runs `MIX_ENV=test mix coveralls.html`, outputs to `cover/excoveralls.html`)
- **JS tests:** `cd assets && npm test` (vitest with jsdom)

Do NOT run `mix test` or `mix precommit` directly — use `make tests` / `make precommit` so that the `.env` file is loaded.

## Git Remotes, Branching, and Commits

- Two remotes: `origin` (`curt/revix-dev`, default branch `dev`) and `public` (`curt/revix`, default branch `main`) — confirm which remote/base a branch tracks (`git branch -vv`, `gh repo view --json nameWithOwner,defaultBranchRef`) before opening a PR; do not assume `dev`.
- Commit messages follow Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`) without a scope — see `git log` for examples.

## Code Coverage

Coverage is tracked with **ExCoveralls** and reported to coveralls.io via CI. The target is **90% overall** with no coverable module below **50%**.

- `coveralls.json` at the repo root configures which files are excluded (boilerplate, maintenance modules)
- `lib/revix_web/maintenance/` is excluded from coverage
- When adding a new module, write tests that bring it to ≥90% covered before merging
- When extending an existing module, ensure the overall module coverage does not drop below 50%
- CI runs `mix coveralls.github` and reports to coveralls.io using `COVERALLS_REPO_TOKEN`
- When adding a substantial new feature, update `README.md` to reflect it — keep the same writing style and stay within a ~20% word-count increase per change

### Using coverage output to find untested edge cases

After implementing new code, run `make coverage` and check the per-module percentages for changed files. A drop signals uncovered new lines. Open `cover/excoveralls.html` for per-line detail.

Distinguish pre-existing uncovered lines (already missing before your change) from newly uncovered lines (introduced by the current change). Only newly uncovered lines need attention.

For each newly uncovered line, determine: **dead code** (remove it) or **untested edge case** (add a test). Multi-clause functions commonly leave guard clauses uncovered — the most common patterns:
- `nil` guard at the top of a recursive helper (e.g. `defp walk_to_checkin(nil), do: {:error, :not_found}`)
- `other -> other` or `_ -> default` catch-all branches
- `{:error, _}` branches in `case` or `with` expressions

These are not dead code — they are real behaviors that the happy-path tests never exercise. Add a targeted test for each: construct a minimal fixture that hits the branch (e.g. a note with `in_reply_to_uri: nil`, or a URI that does not exist in the DB) and assert the expected result.

## Testing Philosophy

New code must be written in a testable way and be covered by comprehensive unit tests.

- **Testability first:** Design modules so that collaborators can be injected or swapped in tests. Do not hardcode references to `RevixWeb.Endpoint`, `CanonicalRoutes`, or other web-layer modules inside domain context functions — pass them as callback arguments (`uri_fn`, `url_fn`) instead.
- **HTTP stubs via Req.Test:** Inject the Req plug through `Application.get_env(:revix, :some_req_plug)` (see `Revix.Overpass` as the canonical example). Register `{Req.Test, :name}` in `config/test.exs` so HTTP calls are stubable without network access. See the Req.Test Mocking section for the full pattern.
- **Domain layer must not couple to web layer:** Modules under `lib/revix/` must not call `RevixWeb.*` modules directly. Use injected callbacks or application-config plugs.
- **Coverage targets apply to all new code:** Every new module must reach ≥90% coverage before merging. See the Code Coverage section above for full thresholds and CI details.

## Project Structure

**Phoenix 1.8** app with `phx.gen.auth`-generated authentication. Designed for ActivityPub federation (URI-based references, WebFinger, Atom feeds, per-person RSA keypairs).

Domain contexts under `lib/revix/`:
- **Entries** — checkins and notes (comments); core domain aggregate
- **Places** — locations with PostGIS geometry; hybrid local DB + Overpass API search
- **People** — users with magic-link auth, avatar upload, RSA keys
- **Likes** — soft-delete via `unliked_at` field (nil = active)
- **EntryPeople** — join table for companions (`:companion` type, hard delete)
- **Media** — image uploads via Waffle + S3; orphan cleanup when last entry detaches
- **Overpass** — HTTP wrapper for OSM Overpass API with Req.Test mocking support

Web layer under `lib/revix_web/`:
- Controllers for HTML, GeoJSON (`:geo`), and ActivityPub (`:activity`) formats
- Three LiveViews: `CheckinNewLive` (multi-step: place search → companions → images), `CheckinEditLive`, and `CheckinFromPlaceLive` (place-first creation, owner-only)
- JSON APIs for likes and companions use the `:browser` pipeline (not `:api`)
- `FeedController` renders Atom 1.0 activity feeds
- `WebfingerController` and `NodeInfoController` for federation discovery

## Key Conventions

**Custom IDs:** 11-character Base58 strings (`lib/revix/ecto/base58_id.ex`), not UUIDs.

**Migrations:** Use `:text` for string columns, `:char` with `size: 11` for ID primary/foreign keys. No FK constraints (federation compatibility).

**Custom Ecto types** in `lib/revix/ecto/` — follow the `Origin` pattern (atom ↔ string cast/load/dump) when adding new enum-like types. Existing types: `Origin`, `EntryType`, `Role`, `OsmElementType`, `EntryPeopleType`.

**Three-tier datetimes:** User-facing datetimes (e.g. `starts_at`, `published_at`, `ends_at`) are stored as three fields — `*_utc` (DateTime), `*_local` (NaiveDateTime), `*_tz` (IANA string). Browser provides timezone via `Intl.DateTimeFormat().resolvedOptions().timeZone`. Internal-only datetimes (e.g. `inserted_at`, `updated_at`, token timestamps) are UTC only.

**URI-based references:** `author_uri`, `place_uri`, `entry_uri`, `in_reply_to_uri` store canonical URLs instead of FK columns — supports federation without foreign key constraints.

**Elixir style — pattern-matched private functions over branching:** Prefer breaking `case`/`if`/`unless` branches out into private multi-clause functions rather than nesting them inline. For example, a three-way `case` on a DB lookup result becomes three `defp do_thing/n` clauses matching `nil`, `%Struct{field: nil}`, and `%Struct{}`. This keeps public functions as a thin pipeline and makes each branch independently readable. The `with` anti-pattern of `else {:error, reason} -> {:error, reason}` (a no-op passthrough) should be removed — `with` already propagates non-matching values automatically.

## Oban Workers

Daily cron workers live in `lib/revix/workers/` and are registered in the `crontab` list in `config/config.exs`.

**Remote-person activity check (`PurgeInactiveRemotePeopleWorker`):** When a new activity type is introduced that a remote person can participate in (e.g. follows, reposts), add a `defp` check and a reference in `activity_checks/0` in `lib/revix/people.ex`. Each check is a one-liner that returns a boolean via `Repo.exists?`. The current checks are `authored_entry?`, `has_like?`, `is_entry_person?`, and `is_ping_actor?`. Add a corresponding test case in `test/revix/workers/purge_inactive_remote_people_worker_test.exs`.

## Authentication & Authorization

- Session-based auth with magic link as primary login method
- `Scope` struct carries `person` and `role` fields; access person as `@current_scope.person`
- Roles: `:user` (default), `:owner` — managed via `Revix.People.set_person_role/2`
- Authorization plugs in `RevixWeb.PersonAuth`: `require_authenticated_person`, `require_sudo_mode`, `require_role`
- Entry-level auth: compare `entry.author_uri` against `scope.person.uri`

## Phoenix 1.8 Patterns

- LiveView templates begin with `<Layouts.app flash={@flash} current_scope={@current_scope}>` (`Layouts` is aliased in `revix_web.ex`)

## LiveView Test Sandbox / Postgrex Disconnect Errors

`[error] Postgrex.Protocol disconnected: client #PID<...> exited` in tests means the LiveView process was killed (by sandbox cleanup) while it still held a DB connection — typically mid-`handle_info` after a PubSub broadcast.

**Two fixes, both required for `live_isolated` tests:**

1. **Explicit sandbox allow + LV shutdown in `on_exit`** — register an `on_exit` callback that monitors and kills the LV process before the sandbox tears down. Because `on_exit` runs LIFO, register it *after* `live_isolated` returns so it fires before the sandbox's own cleanup:

```elixir
defp mount_comment_section(conn, checkin, person_token \\ nil) do
  session = %{"checkin_uri" => checkin.uri, "person_token" => person_token}
  {:ok, lv, html} = live_isolated(conn, RevixWeb.CommentSectionLive, session: session)
  Ecto.Adapters.SQL.Sandbox.allow(Revix.Repo, self(), lv.pid)
  pid = lv.pid

  on_exit(fn ->
    ref = Process.monitor(pid)
    Process.exit(pid, :shutdown)
    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      500 -> :ok
    end
  end)

  {:ok, lv, html}
end
```

2. **`render(lv)` after events that trigger PubSub** — `render_submit`/`render_click` return before the LV's `handle_info` for the broadcast finishes its DB queries. Call `render(lv)` immediately after to flush the mailbox before the test ends:

```elixir
lv |> form(...) |> render_submit()
render(lv)   # flush pending handle_info DB work
assert ...
```

Apply this to any test that (a) triggers a create/update/delete/like event and (b) queries the DB directly afterward, or simply ends without another `render` call.

## LiveView + Task.async Pattern

Place and geolocation lookups use `Task.async` for non-blocking work:
- Task results arrive via `handle_info({ref, result}, socket) when is_reference(ref)`
- Always call `Process.demonitor(ref, [:flush])` after receiving the result
- Task crashes arrive via `handle_info({:DOWN, ref, :process, pid, reason}, socket)`
- Keep all `handle_event` clauses grouped together (not interleaved with `handle_info`)

## Req.Test Mocking (HTTP Stubs)

For Overpass and any other HTTP stubs in tests:
```elixir
# config/test.exs
config :revix, :overpass_req_plug, {Req.Test, :overpass}

# In the module under test
plug = Application.get_env(:revix, :overpass_req_plug)
opts = Keyword.put(opts, :plug, plug)

# In tests
Req.Test.stub(:overpass, fn conn -> Req.Test.json(conn, %{...}) end)

# For LiveView tests (Task spawned by LiveView process)
Req.Test.allow(:overpass, self(), view.pid)
```
- Simulate transport errors with `Req.Test.transport_error(conn, :timeout)` — never raise in stubs
- Tests using Req stubs must be `async: false`; do not call `set_req_test_to_shared()`

## Context Conventions

- List-returning context functions return bare lists; functions that can fail return `{:ok, _} | {:error, atom}`. Do NOT wrap unconditional list returns in `{:ok, list}` — that pattern is inconsistently used and should not be expanded.
- Opts params use `Keyword.get(opts, :key, default)` with keyword lists, not `%{} |> Map.merge(opts)` maps.
- New contexts needing "ok or not found" wrapping should use a private two-clause `*_ok_or_not_found/1` helper (see `Entries`, `Places`, `People`).

## Encryption at Rest (cloak_ecto)

`Person.private_key` is encrypted with AES-256-GCM via `cloak_ecto`. The field type is `Revix.Ecto.EncryptedBinary` (`lib/revix/ecto/encrypted_binary.ex`), backed by `Revix.Vault` (`lib/revix/vault.ex`).

- **Dev/prod key:** `CLOAK_KEY` env var (Base64-encoded 256-bit key); set in `.env` for dev, required in prod environment
- **Test key:** fixed cipher config in `config/test.exs` — tests never need `CLOAK_KEY` in the environment
- **Vault init guard:** `Revix.Vault.init/1` checks `Keyword.has_key?(config, :ciphers)` before reading `CLOAK_KEY`, so the static test config is used as-is without calling `System.fetch_env!`
- **`redact: true` is still required** — encryption protects data at rest (DB breach); `redact` prevents the decrypted plaintext from appearing in logs and crash reports. Both are needed.
- **Data migrations** that need encryption should call `Cloak.Ciphers.AES.GCM.encrypt/2` directly with the decoded key rather than starting the vault GenServer — avoids process name conflicts when the app supervisor is also running

## Security Patterns

- File upload validation must check **content (magic bytes)**, not just file extension — extension-only checks are bypassable. The `:original` Waffle version stores files untransformed.
- Pass `uri_fn`/`url_fn` callbacks into domain context functions instead of referencing `RevixWeb.Endpoint` or `CanonicalRoutes` directly from the domain layer.
- Never pass raw `params` maps to changesets — extract only the permitted keys first.
- `redirect_if_person_is_authenticated` uses two pattern-matched clauses with `when not is_nil(person)` — checking `scope.person`, not `scope`, because `Scope.for_person(nil)` produces a non-nil struct for unauthenticated visitors.

## JavaScript Testing

- Async event handlers (click with `await`) must have `.catch()` clauses to avoid unhandled promise rejections in vitest
- Use `vi.waitFor()` for async click side effects
- Count chips with `.children.length` (not `querySelectorAll`) to match server-rendered structure
- Use `btn.parentElement` (not `.closest()`) when removing server-rendered chip elements

### LiveView hook testing

Extract hooks to separate modules as factory functions (follow `place_search.js` / `image_sort.js`). This makes them importable and directly testable without a LiveView. Test a hook by constructing a minimal instance:

```javascript
function mountHook(el) {
  const hook = createMyHook()
  hook.el = el
  hook.pushEvent = vi.fn()
  hook.mounted()
  return hook
}
```

Then assert on `hook.pushEvent.mock.calls` and DOM state. Call `hook.updated()` directly to test the `updated()` lifecycle.

### Constructor mocking (e.g. `Intl.DateTimeFormat`)

Use `vi.spyOn` instead of direct assignment — direct assignment breaks `new` calls:

```javascript
// Correct
vi.spyOn(Intl, "DateTimeFormat").mockImplementation(() => ({
  resolvedOptions: () => ({ timeZone: "America/Denver" })
}))

// Wrong — breaks new Intl.DateTimeFormat()
Intl.DateTimeFormat = vi.fn(...)
```

Always call `vi.restoreAllMocks()` in `afterEach` when using spies.

### Fixed-time tests

Use the local-time `Date` constructor, not an ISO-Z string — an ISO-Z string shifts by the test runner's UTC offset:

```javascript
// Correct — 2:05 PM local regardless of test runner timezone
vi.useFakeTimers()
vi.setSystemTime(new Date(2026, 4, 8, 14, 5, 0)) // month is 0-indexed

// Wrong — renders as 7:05 AM if runner is UTC-7
vi.setSystemTime(new Date("2026-05-08T14:05:00Z"))
```

`vi.useFakeTimers()` must be called before `vi.setSystemTime()`.

### Early returns in hooks

An early return in `mounted()` silently skips all subsequent logic. Shared behavior (like `pushEvent("set_defaults", ...)`) must come before any conditional returns. Feature-specific wiring (like locate-button click handlers) should come after.

### JSDoc comments

Multi-line `/** ... */` JSDoc blocks are allowed on exported functions when the non-obvious behavior warrants it. Single-line `//` comments remain the default elsewhere.

## Typespecs

Do not add `@spec` typespecs to functions.
