# Contributor Role — 2026-06-17

**Scope:** A new `:contributor` role that sits between `:user` and `:owner`. Contributors may create a place when creating a new checkin, even if the place is not in OSM. They are constrained to the coordinates provided by the browser and cannot create or edit places outside the checkin flow.

---

## Overview

Previously, the app recognised two roles: `:user` (default) and `:owner`. When creating a checkin, a user can only attach a place already in OSM or in the local database; only owners can type a name and coordinates manually. The contributor role extends that privilege to trusted non-owner accounts while keeping standalone place creation and editing owner-only.

A contributor creating a checkin sees the same "Enter manually…" option as an owner. The latitude and longitude fields are rendered `readonly` — they are pre-filled from the browser's geolocation result and cannot be edited in the UI. Only the place name is free-text. Owners retain fully editable coordinates. No other behaviour changes: the 24-hour `starts_at` window, the 2000-character comment limit, ping federation, and CheckinFromPlaceLive remain owner-only.

---

## Architecture

### `priv/repo/migrations/20260615120000_add_contributor_role.exs`

Replaces the `valid_role` check constraint on the `people` table:

```
role IN ('user', 'owner')  →  role IN ('user', 'contributor', 'owner')
```

The `role` column is a plain `:text` field with no enum type; adding the new string to the constraint is the only schema change required.

### `lib/revix/ecto/role.ex`

Added `:contributor` to all four functions: `cast/1`, `load/1`, `dump/1`, and `values/0`. The atom `:contributor` maps to the database string `"contributor"`. `values/0` now returns `[:user, :contributor, :owner]`.

### `lib/revix_web/live/checkin_new_live.ex`

Three changes:

**`mount/3`** — the existing `can_create_place` assign is broadened and a new assign added:

```elixir
|> assign(:can_create_place, scope.role in [:owner, :contributor])
|> assign(:can_edit_place_coords, scope.role == :owner)
```

`can_create_place` controls whether the "Enter manually…" option and the manual place form are shown. `can_edit_place_coords` controls whether the latitude and longitude inputs are editable.

**`resolve_place/4` manual clause** — the role guard is widened from `:owner` only to `:owner` or `:contributor`:

```elixir
if scope.role in [:owner, :contributor] do
  Places.create_local_place(manual_params, ...)
else
  {:error, :unauthorized}
end
```

**`manual_place_fields/1` component** — a new required `can_edit_coords` boolean attr is added. Both the latitude and longitude `<.input>` elements receive `readonly={not @can_edit_coords}`. The `readonly` HTML attribute does not prevent form submission, so the browser-supplied coordinates flow through to `Places.create_local_place/3` unchanged regardless of role.

The coordinate constraint is UI-only and is appropriate for trusted accounts; contributors are expected not to spoof geolocation.

### `lib/revix_web/live/checkin_new_live.html.heex`

The `<.manual_place_fields>` call gains `can_edit_coords={@can_edit_place_coords}` to thread the new assign into the component.

---

## Test Coverage

### `test/revix/ecto/role_test.exs`

`:contributor` added to the `cast/1`, `load/1`, and `dump/1` describe blocks. The `values/0` assertion updated to `[:user, :contributor, :owner]`. A `cast/1` rejection test confirms that the string `"contributor"` is rejected (atoms only).

### `test/revix_web/live/checkin_new_live_test.exs`

A new `describe "contributor role"` block (4 tests, `async: false`):

| Test | What is covered |
|---|---|
| sees manual place entry option after locate | "Enter manually…" appears in the place list after a `locate` event with at least one nearby DB result |
| can switch to manual place mode | `select_manual` event is accepted; `place_mode` becomes `:manual` |
| can create checkin with manual place | Full end-to-end: submit with name + browser coordinates → checkin and place created in DB; uses a UTC-relative `starts_at` within the 24-hour window |
| lat/lon fields are rendered readonly | HTML for the manual place form contains `readonly` on both lat and lon inputs after `select_manual` |

---

## What Was Not Changed

- `Place.create_changeset/2` — unchanged; place creation logic is unaffected.
- `PlaceNewLive` — mount guard remains `scope.role != :owner`; contributors are redirected with an unauthorised flash.
- `PlaceEditLive` / `PlaceMergeLive` — unchanged; remain owner-only.
- `CheckinFromPlaceLive` — unchanged; remains owner-only.
- Entry changeset functions — all non-`:owner` roles (including `:contributor`) continue to hit the `_role` catch-all clauses: the 24-hour `starts_at` window and post datetime restrictions apply to contributors exactly as they do to regular users.
- `comment_max_length/1` — `:contributor` receives the default 2000-character limit (only `:owner` pattern receives `nil`).
- Ping / federation — `:contributor` does not satisfy the `scope.person.role == :owner` guard in `Pings.send_ping/3`.
- `Revix.People.set_person_role/2` — no changes; promoting a person to `:contributor` works as before via IEx: `Revix.People.set_person_role(person, :contributor)`.
