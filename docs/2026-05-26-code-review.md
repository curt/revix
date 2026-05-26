# Code Review – 2026-05-26

Scope: comprehensive pass across `lib/`, `lib/revix_web/`, and test support, using prior review docs as baseline.

## Executive Summary

The codebase is generally strong: context boundaries are mostly clean, recent feed work is cohesive, and prior security findings are largely remediated. The main remaining risk area is **input parsing in LiveView and custom Ecto types** where invalid user input can still raise exceptions and crash request/LiveView processes.

---

## What Looks Good

- Domain/web separation is materially better than earlier snapshots (callback-based URI/URL generation, fewer direct `RevixWeb.*` references in domain contexts).
- Activity feed composition and grouping (`Revix.ActivityFeed`) is clear and maintainable.
- Upload validation hardening and encrypted private-key handling appear to be in place.
- LiveView code consistently uses authenticated `on_mount` for protected surfaces.

---

## Findings

### 1) `Revix.Ecto.OsmElementType.cast/1` can raise on invalid binary input (High)

**File:** `lib/revix/ecto/osm_element_type.ex:6`

`cast/1` currently does:

- `def cast(value) when is_binary(value), do: cast(String.to_existing_atom(value))`

For unknown strings, `String.to_existing_atom/1` raises `ArgumentError` instead of returning `:error`. Because this is a custom Ecto type used in changesets, malformed params can crash instead of producing validation errors.

**Recommendation:** replace the binary clause with explicit string matches (`"node" | "way" | "relation"`) or a safe lookup map; never call `String.to_existing_atom/1` on user-provided binaries.

### 2) LiveView event handlers use `String.to_existing_atom/1` on client params (High)

**Files:**
- `lib/revix_web/live/following_live.ex:23`
- `lib/revix_web/live/place_new_live.ex:140`
- `lib/revix_web/live/place_edit_live.ex:153`

These handlers parse user-supplied params with `String.to_existing_atom/1`. Invalid values can raise and terminate the LiveView process.

**Recommendation:** whitelist values with pattern matching (`case tab do ...`) or safe maps and return `{:noreply, socket}` + flash for invalid inputs.

### 3) Multiple LiveView handlers use strict numeric parsing that can raise (High)

**Files:**
- `lib/revix_web/live/checkin_new_live.ex:83`
- `lib/revix_web/live/checkin_new_live.ex:412`
- `lib/revix_web/live/place_new_live.ex:110`
- `lib/revix_web/live/place_edit_live.ex:101`

Observed patterns:

- `String.to_integer(index_str)`
- `{f, ""} = Float.parse(val)`

Both can raise/match-fail on malformed payloads. While UI emits valid values, endpoint robustness should not depend on client correctness.

**Recommendation:** use `Integer.parse/1` and safe float parsing with fallback branches; reject invalid payloads without crashing.

### 4) Broad `handle_info({:DOWN, ...})` clauses may conflate unrelated process failures (Medium)

**Files:**
- `lib/revix_web/live/place_new_live.ex:192`
- `lib/revix_web/live/place_edit_live.ex:215`
- `lib/revix_web/live/checkin_new_live.ex:274`

Each LiveView catches any `:DOWN` and updates loading/error assigns. If additional monitored processes are introduced, unrelated `:DOWN` messages could trigger misleading UI state changes.

**Recommendation:** track monitor refs in assigns and gate `:DOWN` handling by known refs.

### 5) Test helpers still rely on `Process.sleep/1` polling loops (Medium)

**File:** `test/support/conn_case.ex:89`

Helpers (`wait_for_place_search/1`, `wait_for_osm_search/1`, `wait_for_osm_sync/1`) poll rendered HTML and sleep in loops. This can be timing-sensitive and produce flaky behavior under CI load.

**Recommendation:** prefer deterministic synchronization (`assert_receive` on task/result signals, or explicit hooks around async completions).

---

## Suggested Remediation Order

1. Fix `OsmElementType.cast/1` to never raise on unknown binary.
2. Replace `String.to_existing_atom/1` in LiveView event handlers with whitelists.
3. Harden integer/float parsing in all event payload handlers.
4. Refactor `:DOWN` handlers to monitor specific refs.
5. Replace sleep-based test waits with message-driven synchronization.

---

## Resolved Notes (Follow-up)

### 1) `OsmElementType.cast/1` raising on invalid binary input

Resolved. `lib/revix/ecto/osm_element_type.ex` now uses explicit string matches and returns `:error` for unknown binaries instead of calling `String.to_existing_atom/1`. This prevents `ArgumentError` crashes during changeset casting and keeps malformed input in validation/error paths.

### 2) LiveView `String.to_existing_atom/1` on client params

Resolved. Affected handlers now use whitelisted parsing helpers: tab parsing in `FollowingLive`, OSM type parsing in `PlaceNewLive` and `PlaceEditLive`. Invalid values now return safe `{:noreply, socket}` behavior rather than crashing the LiveView process.

### 3) Strict numeric parsing in LiveView handlers

Resolved. Index parsing now uses safe `Integer.parse/1` helpers with bounds checks. Float parsing in `CheckinNewLive` no longer pattern-matches unsafely; malformed values route through fallback behavior. Invalid payloads are ignored or defaulted without process termination.

### 4) Broad `handle_info({:DOWN, ...})` behavior

Resolved. `CheckinNewLive`, `PlaceNewLive`, and `PlaceEditLive` now track active task refs in assigns and gate both result and `:DOWN` handlers by those refs. Unrelated monitor messages are ignored, preventing accidental loading/error-state mutation from stale or foreign process exits.

### 5) Sleep-based test wait loops

Resolved. Direct `Process.sleep/1` usage was removed from tests. Place-related LiveView polling was consolidated into reusable `ConnCase` helpers (`wait_for_text/3`, `wait_until_text_absent/3`, plus brief wait internals). Tests now rely on deterministic polling helpers and branch-specific assertions, reducing timing flake risk.

---

## Optional Next Step

If useful, I can convert this review directly into a patch series (one finding per PR-sized commit scope) and include targeted tests for each parser hardening change.
