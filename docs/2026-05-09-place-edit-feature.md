# Place Edit — 2026-05-09

**Branch:** topics/place-edit-feature
**Scope:** Owners can edit a place's name, coordinates, and OpenStreetMap link; all users see an OSM badge on the place show page.

---

## Summary

A new `PlaceEditLive` at `GET /places/:id/edit` lets owners update a place's name, coordinates, and OSM reference. Three context functions were added to `Revix.Places`, and `Revix.Overpass` gained a `fetch_element/2` function for fetching a single OSM element by type and ID.

The edit form exposes two ways to set the OSM link: a "Search nearby" button that queries Overpass around the place's existing coordinates and a manual type/ID input. Search results contain only OSM entries — local DB places are excluded since the purpose is linking to an OSM entity, not finding an already-linked one. Selecting a nearby result pre-fills the OSM type and ID fields without auto-saving.

When an OSM type and ID are present in the form — whether from a saved link or from a newly selected nearby result — a "Sync from OSM" button appears. Clicking it fetches the OSM element and populates the name, latitude, and longitude fields without saving, so the owner can review before clicking Save. This allows the new link and the updated name and coordinates to be committed in a single transaction.

When a place already has a saved OSM link, the "Search nearby" button, the nearby results list, and the OSM type/ID inputs are hidden — they are only revealed after clicking "Unlink". The "Sync from OSM" button remains visible while the place is linked. An "Unlink" button clears the reference from the database. A public OSM badge was added to the place show page — visible to all users — linking to `openstreetmap.org`.

The full Elixir suite (698 tests) passes at 0 failures.

---

## New Files

### `lib/revix_web/live/place_edit_live.ex`

LiveView module. Mount checks `scope.role == :owner` and redirects with a flash error if not; loads the place by ID and redirects to `/places` if not found. The form is pre-populated by `Places.change_place_for_edit/1`, which seeds a changeset from the place's stored name, lat/lon, and OSM fields.

Assigns:

| Assign | Purpose |
|---|---|
| `place` | The place being edited (reloaded after unlink) |
| `form` | Bound to the edit changeset |
| `osm_form_type` | Current OSM type string from the form (tracks `validate`, `select_osm_result`, `unlink_osm`) |
| `osm_form_id` | Current OSM ID string from the form (same) |
| `osm_results` | Results from nearby OSM search |
| `osm_searched` | Whether a search has been run |
| `osm_loading` | True while the async nearby-search Task is running |
| `osm_list_open` | Controls collapse of the result list |
| `osm_sync_loading` | True while the async `fetch_element` Task is running |
| `osm_sync_error` | Inline error message after a failed sync |

`osm_form_type` and `osm_form_id` are the source of truth for what the Sync button operates on. They are set from the saved place on mount, updated on every `validate` event and on `select_osm_result`, and cleared on `unlink_osm`. This allows the Sync button to work both when the place already has a saved link and when the owner has just selected a nearby result but not yet saved.

Event handlers:

| Handler | Notes |
|---|---|
| `validate` | Rebuilds changeset with `action: :validate`; updates `osm_form_type` and `osm_form_id` from params |
| `save` | Calls `Places.update_local_place/2`; on success redirects to the place show path |
| `search_nearby` | Reads lat/lon from `place.coordinates`; spawns `Task.async` calling `Places.search_nearby_osm/3` (OSM only, no DB results) |
| `select_osm_result` | Merges selected result's `osm_type`/`osm_id` into current form params, rebuilds form; updates `osm_form_type`/`osm_form_id`; closes the list |
| `toggle_osm_list` | Collapses/expands the search result list |
| `unlink_osm` | Calls `Places.unlink_place_osm/1`; reloads the place and resets all OSM assigns |
| `sync_osm` | Reads `osm_form_type`/`osm_form_id` assigns; parses and validates them; spawns `Task.async` calling `Overpass.fetch_element/2`; sets `osm_sync_loading: true` |

`handle_info` clauses follow the `Task.async` pattern: each result tuple is tagged (`{:osm_results, ...}` vs `{:osm_sync, ...}`) to distinguish the two Tasks; a single `:DOWN` clause handles crashes from either and clears both loading flags.

**File:** [lib/revix_web/live/place_edit_live.ex](lib/revix_web/live/place_edit_live.ex)

---

### `lib/revix_web/live/place_edit_live.html.heex`

Two-section form:

**Place Details** — name (text), latitude and longitude (number, `step="any"`) in a two-column layout.

**OpenStreetMap** — structured in layers:

1. When `@place.osm_type && @place.osm_id`: a summary row shows the OSM type/ID as an external link and an "Unlink" button.
2. When `@osm_form_type` and `@osm_form_id` are non-empty: a "Sync from OSM" button (with spinner while `@osm_sync_loading`) and any `@osm_sync_error` inline below it.
3. When the place has no saved OSM link (`@place.osm_type` or `@place.osm_id` is nil): a "Search nearby" button, the async result list (collapsible, OSM badge on each entry), the OSM type select, and the OSM ID number input.

The search/input block is deliberately hidden while a link is saved — those controls are only needed when establishing a new link. Unlinking restores them.

**File:** [lib/revix_web/live/place_edit_live.html.heex](lib/revix_web/live/place_edit_live.html.heex)

---

### `test/revix_web/live/place_edit_live_test.exs`

22 integration tests across 7 describe blocks. Uses `async: false` (required for `Req.Test` stubs). `Req.Test.allow` is called after `live/2` to permit the LiveView process (and its spawned Tasks via `$callers`) to see the stub.

| Describe block | Tests |
|---|---|
| `unauthenticated access` | Redirect to sign-in when not logged in |
| `authorization` | Non-owner redirected with flash error; nonexistent place redirected to `/places` |
| `authenticated mount as owner` | Form pre-populated with name, lat/lon, osm fields; sync/unlink buttons visible only when OSM link is set; search/type/ID inputs hidden when OSM link is set |
| `validate` | Inline errors for blank name and out-of-range latitude |
| `save` | Updates name and redirects; returns errors without redirecting; linking by manual OSM type+ID |
| `unlink_osm` | Clears DB fields; hides sync/unlink buttons; restores search/type/ID inputs |
| `search_nearby` | OSM results appear after Task completes; "No places found nearby" when OSM returns empty; selecting an OSM result pre-fills osm_type/osm_id; toggle collapses/expands list |
| `sync_osm` | Form fields updated on success; sync available after selecting a result (no prior saved link); inline error on not-found; inline error on HTTP error; spinner clears |
| `OSM badge on place show page` | Badge present when place has OSM link; absent otherwise |

**File:** [test/revix_web/live/place_edit_live_test.exs](test/revix_web/live/place_edit_live_test.exs)

---

## Modified Files

### `lib/revix/overpass.ex`

Added `fetch_element/2` and a private `parse_single_element/1` helper. `fetch_element/2` posts a targeted Overpass query for a single element by type and ID using `out center` (so coordinates of ways and relations are always in the `center` key, the same shape already handled by `element_coordinates/1`). It reads the same `overpass_req_plug` config key as `search_nearby/3` so it is mockable in tests without changes to the test infrastructure. Returns `{:ok, %{name, lat, lon}}` or `{:error, :not_found | {:http_error, status} | reason}`.

**File:** [lib/revix/overpass.ex](lib/revix/overpass.ex)

---

### `lib/revix/places.ex`

Three new context functions:

**`change_place_for_edit/1`** — builds a valid changeset seeded from the place's stored values. Extracts lat/lon from `place.coordinates.coordinates` (PostGIS stores `{lon, lat}`) so the virtual fields are populated and the form renders correctly.

**`update_local_place/2`** — passes the existing `%Place{}` struct to `Place.create_changeset/2` and calls `Repo.update/1`. The uncast fields (`id`, `uri`, `url`, `origin`) are preserved from the struct; the slug is regenerated from the new name.

**`unlink_place_osm/1`** — uses `Ecto.Changeset.change/2` instead of `create_changeset/2` to set both OSM fields to `nil` directly, bypassing the `OsmElementType` custom cast which cannot accept `nil` as a string.

**File:** [lib/revix/places.ex](lib/revix/places.ex)

---

### `lib/revix_web/router.ex`

Added one live route inside the existing `:authenticated` live session:

```elixir
live "/places/:id/edit", PlaceEditLive, :edit
```

**File:** [lib/revix_web/router.ex](lib/revix_web/router.ex)

---

### `lib/revix_web/controllers/place_html/show.html.heex`

Two additions:

An "Edit place" link with a `hero-pencil-square` icon, inside the existing owner-only block alongside the "Check in here" link.

An OSM badge rendered outside the owner block — visible to all users — linking to `https://www.openstreetmap.org/{type}/{id}`. The badge only renders when `@place.osm_type && @place.osm_id`.

**File:** [lib/revix_web/controllers/place_html/show.html.heex](lib/revix_web/controllers/place_html/show.html.heex)

---

## Test Coverage

### `test/revix/overpass_test.exs`

7 new tests in a separate `Revix.OverpassFetchTest` module (`async: false`):

| Test | What is covered |
|---|---|
| Node with lat/lon | Returns `{:ok, %{name, lat, lon}}` |
| Way with center | Returns center coordinates |
| Relation with center | Returns center coordinates |
| Empty elements list | Returns `{:error, :not_found}` |
| Element with no name | Returns `{:error, :not_found}` |
| Non-200 response | Returns `{:error, {:http_error, 429}}` |
| Transport error | Returns `{:error, reason}` via `Req.Test.transport_error/2` |

### `test/revix/places_test.exs`

12 new tests across three describe blocks:

| Describe block | Tests |
|---|---|
| `change_place_for_edit/1` | Pre-populates name; pre-populates lat/lon from coordinates; pre-populates osm fields; handles nil OSM fields |
| `update_local_place/2` | Updates name and regenerates slug; updates coordinates; updates OSM fields; preserves uri/url/origin; returns error changeset for blank name and out-of-range coordinates |
| `unlink_place_osm/1` | Sets both OSM fields to nil; succeeds when already nil |

### `test/support/conn_case.ex`

Added `wait_for_osm_search/1` and `wait_for_osm_sync/1` helpers alongside the existing `wait_for_place_search/1`, following the same poll-until-spinner-gone pattern.

---

## What Was Not Changed

- `Place.create_changeset/2` — no second changeset added; the existing one is safe for updates when passed a populated struct.
- `CheckinNewLive` / `CheckinFromPlaceLive` — unaffected.
- Database migrations — `osm_type` and `osm_id` columns already existed.
- JavaScript — no new hook; all interactions are server-driven via `phx-click` and `phx-submit`.
