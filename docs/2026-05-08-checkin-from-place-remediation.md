# Checkin from Place — 2026-05-08

**Branch:** topics/checkin-cleanup
**Scope:** New alternate checkin-creation flow starting from an existing place; no place-search UI. Owner-only for now, designed for easy extension to non-owners.

---

## Summary

A second checkin-creation path was added at `GET /places/:id/checkins/new`. When an owner navigates to a place they want to check in to, they can create the checkin directly without going through the full place-search flow. The form shows only the checkin details (content, datetime, timezone), companions, and photos. All checkin logic — datetime validation, image upload, companion persistence — is identical to the existing `CheckinNewLive` path.

A latent bug in the `PlaceSearch` JS hook was discovered and fixed: the `set_defaults` push (which pre-fills the datetime and timezone fields) was silently skipped on any form without a locate button due to an early return placed before the push. The hook was extracted to `assets/js/place_search.js` (following the `image_sort.js` pattern) and 14 JS unit tests were added.

The full Elixir suite (649 tests) and JS suite (51 tests) pass at 0 failures.

---

## New Files

### `lib/revix_web/live/checkin_from_place_live.ex`

LiveView module for the place-first checkin flow. Mount loads the place by ID from `params` and short-circuits with a redirect on two conditions:

- **Non-owner:** redirects to `/checkins/new` with an error flash. The role check is a single `if scope.role != :owner` guard, designed to be relaxed to a broader condition (e.g. `scope.role not in [:user, :owner]`) when the feature is opened to non-owners.
- **Place not found:** redirects to `/places` with an error flash.

On successful mount, the place is assigned and no place-search assigns (`place_results`, `place_mode`, `selected_place`, etc.) are initialised — they are not needed.

All event handlers are shared with `CheckinNewLive` via `CheckinHelpers` (`handle_cancel_upload`, `consume_uploads`, `search_companions`, `normalize_person`) or are straightforward copies of the same logic:

| Handler | Notes |
|---|---|
| `set_defaults` | Identical to `CheckinNewLive` — populates datetime from JS `PlaceSearch` hook on mount |
| `validate` | Identical — rebuilds checkin form changeset on change |
| `search_companions`, `add_companion`, `remove_companion` | Identical in-memory companion logic |
| `cancel_upload`, `update_caption`, `update_alt`, `reorder_images` | Identical upload management |
| `submit` | Simplified — no `resolve_place` step; calls `create_local_checkin_with_companions` directly with `socket.assigns.place` |

**File:** [lib/revix_web/live/checkin_from_place_live.ex](lib/revix_web/live/checkin_from_place_live.ex)

---

### `lib/revix_web/live/checkin_from_place_live.html.heex`

Template for the place-first checkin form. Structurally identical to `checkin_new_live.html.heex` with the place-search section removed:

- Header shows "New Checkin at {place.name}"
- Checkin Details section: content, `datetime-local`, timezone select
- Companions section (shared `CompanionsComponent`)
- Photos section (shared `PhotosComponent`, distinct `container_id`)
- The `<form>` element still carries `phx-hook="PlaceSearch"` to trigger the `set_defaults` push from the JS hook (pre-fills browser datetime and timezone on mount)

**File:** [lib/revix_web/live/checkin_from_place_live.html.heex](lib/revix_web/live/checkin_from_place_live.html.heex)

---

## Modified Files

### `lib/revix_web/controllers/place_html/show.html.heex`

A "Check in here" link was added immediately below the `<h1>` place name, in its own `<div class="my-2">`. It mirrors the style of the Edit link on the checkin show page: an inline anchor with a `hero-map-pin` icon followed by text. The link is conditional on `@current_scope && @current_scope.role == :owner` — non-owners and unauthenticated visitors do not see it.

```heex
<%= if @current_scope && @current_scope.role == :owner do %>
  <div class="my-2">
    <a href={~p"/places/#{@place.id}/checkins/new"} class="my-1 inline-block align-middle">
      <.icon name="hero-map-pin" class="w-5 h-5" /> Check in here
    </a>
  </div>
<% end %>
```

**File:** [lib/revix_web/controllers/place_html/show.html.heex](lib/revix_web/controllers/place_html/show.html.heex)

---

### `lib/revix_web/router.ex`

Added one live route inside the existing `:authenticated` live session:

```elixir
live "/places/:id/checkins/new", CheckinFromPlaceLive, :new
```

**File:** [lib/revix_web/router.ex](lib/revix_web/router.ex)

### `test/revix_web/controllers/place_controller_test.exs`

Three new tests added to the `GET /places/:id` describe block:

| Test | What is covered |
|---|---|
| `owner sees 'Check in here' link` | Link text and href present for owner-role session |
| `non-owner does not see 'Check in here' link` | Link absent for default-role session |
| `unauthenticated visitor does not see 'Check in here' link` | Link absent with no session |

**File:** [test/revix_web/controllers/place_controller_test.exs](test/revix_web/controllers/place_controller_test.exs)

---

## PlaceSearch Hook Extraction and Bug Fix

### Bug: `set_defaults` not firing on the place-first form

`CheckinFromPlaceLive` uses `phx-hook="PlaceSearch"` on its form element to pre-fill the datetime and timezone fields on mount. When the new page was first tested, the fields were blank — the `set_defaults` event was never pushed.

**Root cause:** The original inline hook in `app.js` looked up `#locate-btn` and returned early (`if (!locateBtn) return`) *before* calling `pushEvent("set_defaults", ...)`. Since `CheckinFromPlaceLive` has no locate button, the early return silently prevented the push from ever running.

**Fix:** The `set_defaults` push was moved to the top of `mounted()`, before the locate-button lookup. The hook was also extracted to its own module to make the fix testable and to follow the same pattern already established by `image_sort.js`.

### Extraction: `assets/js/place_search.js`

The hook was moved from an inline object in `app.js` to a factory function exported from `assets/js/place_search.js`:

```javascript
export function createPlaceSearchHook() {
  return {
    mounted() {
      // set_defaults push comes first — must not be gated on locate button
      this.pushEvent("set_defaults", { local_datetime: ..., timezone: ... })
      const locateBtn = this.el.querySelector("#locate-btn")
      if (!locateBtn) return
      // locate button wiring...
    },
    updated() { ... }
  }
}
```

`app.js` now imports and uses this factory:

```javascript
import { createPlaceSearchHook } from "./place_search.js"
Hooks.PlaceSearch = createPlaceSearchHook()
```

**Files:** [assets/js/place_search.js](assets/js/place_search.js), [assets/js/app.js](assets/js/app.js)

### JS unit tests: `assets/js/place_search.test.js`

14 tests across 4 describe blocks, run with vitest + jsdom. The test helper instantiates the hook directly without a LiveView:

```javascript
function mountHook(el) {
  const hook = createPlaceSearchHook()
  hook.el = el
  hook.pushEvent = vi.fn()
  hook.mounted()
  return hook
}
```

Key patterns used:
- `vi.spyOn(Intl, "DateTimeFormat").mockImplementation(...)` with `vi.restoreAllMocks()` in `afterEach` — required because `Intl.DateTimeFormat` is a constructor; direct assignment breaks `new` calls
- `new Date(2026, 4, 8, 14, 5, 0)` for fixed-time tests (local-time constructor, not ISO-Z string) — avoids the result shifting by the test runner's UTC offset
- `vi.useFakeTimers()` before `vi.setSystemTime()`, then `vi.useRealTimers()` after assertions

**File:** [assets/js/place_search.test.js](assets/js/place_search.test.js)

---

## What Was Not Changed

- `CheckinHelpers` — no new functions needed; all helpers were already general enough to reuse.
- `Entries` context — `create_local_checkin_with_companions/6` is called unchanged.
- `CheckinNewLive` — unaffected; both flows coexist independently.
- `CanonicalRoutes` — no helper added; callers use `~p"/places/#{place.id}/checkins/new"` directly. A `checkin_from_place_path/1` helper can be added when there are multiple callers.

---

## Extending to Non-Owners

To open the flow to non-owners, change the mount guard in `CheckinFromPlaceLive`:

```elixir
# Current (owner only):
if scope.role != :owner do

# Future (all authenticated users):
# Remove the guard entirely, or keep it for a specific restricted role.
```

Non-owners would be subject to the same `validate_starts_at_window` rule as in `CheckinNewLive` — no changeset changes are needed since `Entry.checkin_changeset/3` already enforces the window based on the role passed from `scope.role`.

---

## Test Coverage

New test file: [`test/revix_web/live/checkin_from_place_live_test.exs`](test/revix_web/live/checkin_from_place_live_test.exs)

| Describe block | Tests |
|---|---|
| `unauthenticated access` | Redirects to `/people/signin` when not logged in |
| `authorization` | Non-owner redirected to `/checkins/new` with error flash; nonexistent place redirected to `/places` |
| `authenticated mount as owner` | Place name in header; no place search UI; checkin details form present; companions and photos sections present |
| `create checkin from place` | Successful creation and redirect; validation error shown without creating; owner future datetime accepted; owner ancient datetime accepted |
| `companion management` | Search returns suggestions; add shows chip; remove clears chip; companions persisted on submit |
| `file upload` | `cancel_upload` removes pending entry |

Total Elixir suite after changes: **649 tests, 0 failures**.

JS tests (`cd assets && npm test`): **51 tests, 14 new** (all in `place_search.test.js`).
