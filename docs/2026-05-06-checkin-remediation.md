# Checkin Place-Search Remediation – 2026-05-06

**Branch:** topics/checkin-cleanup
**Scope:** New checkin LiveView — place search UX, input persistence, result limits, and template DRY cleanup.

---

## Summary

Six UX deficiencies were identified in `CheckinNewLive` and remediated in this session. One DRY violation in the template was resolved as a side effect. All changes are covered by new automated tests; the full suite (606 tests) passes at 0 failures.

---

## Deficiencies and Remediation

### 1 — Owner manual entry blocked without "Locate me"

**Deficiency:** When an owner loaded the new checkin page and entered place details manually without first clicking "Locate me," submitting the form showed "Please select a place" even though the fields were filled in. The manual-entry fields were visible before any locate, but `place_mode` remained `:none`, causing `resolve_place/4` to return `{:error, :no_place_selected}`.

**Remediation:** Added a fourth `resolve_place/4` clause that matches `place_mode == :none` with non-empty `manual_params`, delegating to the existing `:manual` clause. The `:manual` clause already enforces the owner-role guard, so no additional authorization logic was needed. No template change required.

**File:** [lib/revix_web/live/checkin_new_live.ex](lib/revix_web/live/checkin_new_live.ex)

---

### 2 — Geolocation lat/lon not pre-populated in manual entry fields

**Deficiency:** After clicking "Locate me," the discovered coordinates were not pre-filled into the latitude/longitude inputs. An owner wanting to enter a place manually after locating had to look up or re-type the coordinates.

**Remediation:** In `handle_event("locate")`, after calling `search_nearby_db`, the `place_changeset` is now updated with the discovered lat/lon — but only when both fields are currently empty in the changeset. "Both or neither" is maintained by always setting both together or neither.

**File:** [lib/revix_web/live/checkin_new_live.ex](lib/revix_web/live/checkin_new_live.ex)

---

### 3 — Input values lost when the browser loses focus

**Deficiency:** If an owner opened another app to look up coordinates, pasted the values into the lat/lon fields, then switched away and back, the pasted values were wiped on the next LiveView re-render. Values were read from `place_changeset.changes` at render time. The `validate` handler only updated the changeset when `place_mode == :manual`; values entered before OSM results arrived (while `place_mode` was still `:none`) were never stored server-side and were cleared on the next patch.

**Remediation:** The `validate` handler now always rebuilds `place_changeset` from `place_manual` params whenever they are present in the event payload, regardless of `place_mode`. Inline validation errors are still only shown when `place_mode == :manual`. The handler's pattern was also relaxed from `%{"checkin" => ...}` to a plain `params` match with `params["checkin"] || %{}`, making it tolerant of events that include only `place_manual` fields.

**File:** [lib/revix_web/live/checkin_new_live.ex](lib/revix_web/live/checkin_new_live.ex)

---

### 4 — Place selection lost when OSM results arrived after selection

**Deficiency:** If a user selected a place from DB results before the async OSM task completed, the `handle_info` callback unconditionally overwrote `place_results`. The `selected_place` assign was preserved, but it was possible for the merged list to no longer contain the selected entry (e.g., if a second locate fired at a new location), leaving the UI in an inconsistent state.

**Remediation:** `handle_info` now checks whether the currently-selected place still appears in the merged result list. If it does, the selection is preserved as-is. If it no longer appears (e.g., after a second locate at a different location), `place_mode` is reset to `:none`, `selected_place` is cleared, and `place_list_open` is re-opened.

**File:** [lib/revix_web/live/checkin_new_live.ex](lib/revix_web/live/checkin_new_live.ex)

---

### 5 — Unbounded place results list in dense areas

**Deficiency:** In densely populated areas, the merged DB+OSM results list could contain dozens or hundreds of entries, making the UI unwieldy. There was no cap on either the database query or the merged result set.

**Remediation:** A configurable limit was introduced in `config/config.exs` as `config :revix, :places, nearby_result_limit: 20`. The `merge_place_results/2` function in `lib/revix/places.ex` now applies `Enum.take(limit)` after merging and sorting, so only the nearest N places are returned. The limit applies to the combined DB+OSM set after deduplication.

**Files:** [lib/revix/places.ex](lib/revix/places.ex), [config/config.exs](config/config.exs)

---

### 6 — No way to collapse or re-expand the place list after selecting

**Deficiency:** The place results list remained fully expanded after a place was selected, cluttering the form. There was no affordance to collapse it or re-expand it.

**Remediation:** A `place_list_open` boolean assign (default `true`) was added to the LiveView. `select_place` now sets it to `false`, collapsing the list on selection. A chevron icon button (`hero-chevron-down` / `hero-chevron-right`) next to the "Nearby Places" heading toggles `place_list_open` via a new `toggle_place_list` event. The list body is wrapped in `:if={@place_list_open}`. The heading row and toggle button remain visible whenever results exist, allowing re-expansion to change selection.

**Files:** [lib/revix_web/live/checkin_new_live.ex](lib/revix_web/live/checkin_new_live.ex), [lib/revix_web/live/checkin_new_live.html.heex](lib/revix_web/live/checkin_new_live.html.heex)

---

## DRY Improvement

The template previously contained two nearly identical manual-place-entry blocks — one shown when `place_results == []` and a second shown when `place_mode == :manual` with results present. These were extracted into a private `manual_place_fields/1` function component (with an `attr :changeset` declaration), rendered once with the combined condition `:if={@can_create_place and (@place_results == [] or @place_mode == :manual)}`.

**Files:** [lib/revix_web/live/checkin_new_live.ex](lib/revix_web/live/checkin_new_live.ex), [lib/revix_web/live/checkin_new_live.html.heex](lib/revix_web/live/checkin_new_live.html.heex)

---

## Test Coverage Added

New tests were added to [`test/revix_web/live/checkin_new_live_test.exs`](test/revix_web/live/checkin_new_live_test.exs):

| Describe block | What is covered |
|---|---|
| `owner manual entry without locate` | Owner submits with manual params and no locate; non-owner cannot bypass the restriction via direct event injection |
| `lat/lon pre-population from geolocation` | Locate pre-populates both fields when empty; does not overwrite if either field already has a value |
| `place changeset persisted across re-renders` | Manual lat/lon values survive OSM results arriving via `handle_info` |
| `place selection preserved on late OSM results` | Selection preserved when place still in merged list; cleared and reset when it is no longer present |
| `nearby result limit` | `merge_place_results/2` returns at most `nearby_result_limit` entries regardless of input size |
| `place list collapse and expand` | `select_place` collapses list; `toggle_place_list` re-expands; toggle also collapses an open list |

Total suite after changes: **606 tests, 0 failures**.
