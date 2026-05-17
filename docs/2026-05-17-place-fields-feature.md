# Place Fields — 2026-05-17

**Branch:** next/8
**Scope:** Three new geographic situation fields on `Place` — country, city, secondary — produce richer canonical URLs for places and their checkins. Owners can set these fields on the place edit form.

---

## Overview

Places previously produced canonical URLs of the form `/places/:id/:slug`. This feature adds optional `country`, `city`, and `secondary` fields that, when populated, extend the canonical URL with location context:

| Fields populated | Example place URL |
|---|---|
| none | `/places/aaaaaaaaaaa/jimbos-grill` |
| country | `/places/aaaaaaaaaaa/us/jimbos-grill` |
| country + city | `/places/aaaaaaaaaaa/us/scottsdale/jimbos-grill` |
| country + city + secondary | `/places/aaaaaaaaaaa/us/az/scottsdale/jimbos-grill` |

Checkin URLs follow the same pattern, inheriting the place's situation fields:

| Fields populated | Example checkin URL |
|---|---|
| none | `/checkins/bbbbbbbbbbb/jimbos-grill` |
| country | `/checkins/bbbbbbbbbbb/us/jimbos-grill` |
| country + city | `/checkins/bbbbbbbbbbb/us/scottsdale/jimbos-grill` |
| country + city + secondary | `/checkins/bbbbbbbbbbb/us/az/scottsdale/jimbos-grill` |

The ID-only and ID+slug routes continue to exist. The controller redirects any request that doesn't match the canonical path to the correct URL.

---

## Field Definitions

**`country`** — Two lowercase letters (ISO 3166-1 alpha-2). Validated to exactly 2 characters and `[a-z]{2}`. Input is downcased before validation and storage.

**`city`** — Slugified string (lowercase, hyphens only). Requires `country` to be present. Input is run through `Slug.slugify/1` before storage.

**`secondary`** — Slugified string. Represents a subdivision such as a US state or Canadian province. Requires both `country` and `city` to be present. Input is slugified before storage.

All three fields are nullable. Database-level `CHECK` constraints mirror the changeset dependency rules:

| Constraint | Rule |
|---|---|
| `country_length_2` | `country IS NULL OR char_length(country) = 2` |
| `city_requires_country` | `city IS NULL OR country IS NOT NULL` |
| `secondary_requires_city` | `secondary IS NULL OR (country IS NOT NULL AND city IS NOT NULL)` |

---

## Architecture

### `priv/repo/migrations/20260517011359_add_situation_to_places.exs`

Adds three `:text` columns and the three CHECK constraints to the `places` table.

### `lib/revix/places/place.ex`

Three new fields added to the schema: `country`, `city`, `secondary`.

A new `update_situation_changeset/2` is responsible for all situation-field logic. It is intentionally separate from `create_changeset/2` because the situation fields are owner-only and irrelevant to creation or OSM sync. The changeset:

1. Casts the three fields.
2. Normalizes: `country` → `String.downcase/1`; `city` and `secondary` → `Slug.slugify/1`. Empty strings are converted to `nil`.
3. Validates: `country` must match `~r/^[a-z]{2}$/`; dependency rules enforce city requires country and secondary requires both.
4. Declares `check_constraint` for `city_requires_country` and `secondary_requires_city` so DB violations surface as field-level changeset errors rather than raw exceptions.

### `lib/revix/places.ex`

`change_place_for_edit/1` — updated to include `country`, `city`, and `secondary` in the attrs map so the edit form pre-populates the current values. It now pipes through both `Place.create_changeset/2` and `Place.update_situation_changeset/2`.

`update_local_place/4` — signature extended from `2` to `4` arguments (`place, attrs, url_fn, checkin_url_fn`). The two callbacks are 1-arity functions that accept pseudo-structs and return absolute URLs; passing them in keeps the domain layer decoupled from `RevixWeb`. After building and validating the merged changeset, the function:

1. Resolves the new `slug`, `country`, `city`, and `secondary` via `Ecto.Changeset.get_field/2`.
2. Builds a place pseudo-struct and calls `url_fn` to compute the new canonical place URL; puts it into the changeset.
3. Compares the new URL against the existing `place.url` to determine whether checkin URLs need updating.
4. Wraps the place update and any checkin updates in a single `Repo.transaction`.
5. If `url_changed`, fetches local checkin IDs for this place and updates each entry's `url` and `updated_at` (set to `updated_place.updated_at`) via `Repo.update_all`. Checkin `updated_at` is set explicitly because `Repo.update_all` bypasses Ecto's automatic timestamp handling.
6. If `url_changed` is false (e.g., only coordinates or OSM fields changed), the checkin loop is skipped entirely.

### `lib/revix_web/canonical_routes.ex`

`place_path/1` and `checkin_path/1` were rewritten to read the situation fields and dispatch to an internal 5-arity `place_path/5` / `checkin_path/5` that selects the appropriate `~p` route:

```
place_path(id, country, secondary, city, slug)
```

Pattern-matched clauses cover all four combinations (all present → 3-segment; country+city; country only; none). The `%{id:, slug:}` struct clause was replaced with a single `is_map_key(place, :slug)` check that reads situation fields via `Map.get` with implicit `nil` defaults — this ensures maps without the new keys (e.g., in tests) still work correctly.

`place_url/2` and `checkin_url/2` (2-arity convenience forms used by fixtures) now delegate to the 5-arity path helpers with `nil` situation fields.

### `lib/revix_web/router.ex`

Six new show routes added to the `:robots_index` scope (three for places, three for checkins):

```elixir
get "/places/:id/:country/:slug", PlaceController, :show
get "/places/:id/:country/:city/:slug", PlaceController, :show
get "/places/:id/:country/:secondary/:city/:slug", PlaceController, :show

get "/checkins/:id/:country/:slug", CheckinController, :show
get "/checkins/:id/:country/:city/:slug", CheckinController, :show
get "/checkins/:id/:country/:secondary/:city/:slug", CheckinController, :show
```

The existing `/places/:id` and `/places/:id/:slug` routes remain unchanged.

### `lib/revix_web/controllers/place_controller.ex` and `checkin_controller.ex`

The redirect guard previously matched `when place.slug != slug` — a pattern-match guard comparing a single param. This approach doesn't generalise to the multiple possible URL shapes. The redirect clause was replaced with an `if` check in the function body:

```elixir
if CanonicalRoutes.place_path(place) != conn.request_path do
  redirect(conn, to: CanonicalRoutes.place_path(place))
else
  # render
end
```

`conn.request_path` is always the actual path string regardless of which route pattern matched, making this a single comparison that handles all six route shapes uniformly.

### `lib/revix_web/live/place_edit_live.ex`

- `handle_event("validate", ...)` now pipes through both `create_changeset` and `update_situation_changeset` so inline validation errors for the situation fields appear immediately.
- `handle_event("save", ...)` passes `&CanonicalRoutes.place_url/1` and `&CanonicalRoutes.checkin_url/1` as callbacks to `update_local_place/4`.
- `form_params/1` extended with `"country"`, `"city"`, and `"secondary"` keys so the current form values are preserved during OSM sync operations.

### `lib/revix_web/live/place_edit_live.html.heex`

A new "Location Details" section added between "Place Details" and "OpenStreetMap". Contains three inputs: Country (2-char, placeholder "us"), City (placeholder "scottsdale"), and State / Province (placeholder "az"). An explanatory hint notes that country is required for the other two.

---

## What Was Not Changed

- `Place.create_changeset/2` — unchanged; situation fields are not part of place creation.
- `create_local_place/3` — unchanged; newly created places have no situation fields.
- `lib/revix_web/maintenance/routes.ex` — this module has its own direct-SQL batch logic for rebuilding canonical routes and does not call `update_local_place`.
- Checkin creation — checkin `url` is set from `place.slug` at creation time; situation fields are not yet populated for new places.
- ActivityPub / federation — `place_uri` and `checkin_uri` are always the bare ID path and are unaffected by situation fields.
