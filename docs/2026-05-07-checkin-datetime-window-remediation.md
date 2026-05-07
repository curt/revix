# Checkin Datetime Window — 2026-05-07

**Branch:** topics/checkin-cleanup
**Scope:** New and edit checkin LiveViews — role-based datetime validation on creation; datetime editing restricted to owners on the edit page.

---

## Summary

A business rule was added to enforce that non-owner users can only create checkins with a datetime within a configurable lookback window (default 24 hours) and never in the future. Owners retain the ability to create or edit checkins with any datetime. Non-owners cannot edit the datetime or timezone of a checkin after it has been created. All changes are covered by new automated tests; the full suite (629 tests) passes at 0 failures.

---

## Changes

### 1 — Configurable lookback window

A new config key was added alongside the existing `comment_max_length` setting:

```elixir
config :revix, :entry, comment_max_length: 2000, checkin_lookback_hours: 24
```

**File:** [config/config.exs](config/config.exs)

---

### 2 — Window validation in the Entry changeset

`Entry.checkin_changeset/3` (formerly `/2`) now requires a `role` argument. A `validate_starts_at_window/2` step was added to the pipeline after `compute_starts_at_utc`. It operates on the computed UTC value so that all comparisons are timezone-aware:

- **`:owner`** — passes through unchanged.
- **`valid?: false`** — passes through unchanged (avoids redundant errors when an earlier step already failed).
- **Any other role** — validates that `starts_at_utc` is not in the future and not older than `checkin_lookback_hours`. Errors are attached to `starts_at_local` (the field the user filled in).

The role is passed explicitly with no default — `:owner` is the more permissive role and must not be assumed.

`Entry.update_checkin_changeset/3` (formerly `/2`) was extended with a `role` argument and a `cast_datetime_fields/3` private function:

- **`:owner`** — casts `starts_at_local` and `starts_tz`, validates the timezone, and recomputes `starts_at_utc`.
- **Any other role** — datetime fields are not cast; injected params are silently ignored.

**File:** [lib/revix/entries/entry.ex](lib/revix/entries/entry.ex)

---

### 3 — Role threaded through the Entries context

Functions in the `Entries` context that call the changed changesets were updated to accept and forward `role`:

- `change_checkin/2` (formerly `/1`) — role is now the first argument, attrs second.
- `change_checkin_for_update/2,3` — two-clause form: `(entry, role \\ :user)` for mount-time form initialization, and `(entry, attrs, role)` for validate-event re-rendering.
- `create_local_checkin/5` — passes `scope.role` to `Entry.checkin_changeset/3`.
- `update_local_checkin/3` (formerly `/2`) — passes `role` to `Entry.update_checkin_changeset/3`.

**File:** [lib/revix/entries.ex](lib/revix/entries.ex)

---

### 4 — New checkin LiveView passes role through

`CheckinNewLive` already exposed datetime fields to all users (non-owners may create checkins within the lookback window). The mount, `set_defaults`, and `validate` handlers were updated to pass `scope.role` to the relevant context functions. No template changes were needed — the datetime fields remain visible for all users on the new checkin form.

**File:** [lib/revix_web/live/checkin_new_live.ex](lib/revix_web/live/checkin_new_live.ex)

---

### 5 — Edit checkin LiveView: owner-only datetime section

`CheckinEditLive` was updated to:

- Assign `can_edit_datetime: scope.role == :owner` and `timezones: Tzdata.zone_list() |> Enum.sort()` on mount.
- Pass `scope.role` to `change_checkin_for_update` (mount and validate) and `update_local_checkin` (submit).

The edit template gained a `Date and Time` section gated on `:if={@can_edit_datetime}` containing a `datetime-local` input for `starts_at_local` and a `select` input for `starts_tz`. Non-owners see neither field and cannot affect datetime through injected params.

**Files:** [lib/revix_web/live/checkin_edit_live.ex](lib/revix_web/live/checkin_edit_live.ex), [lib/revix_web/live/checkin_edit_live.html.heex](lib/revix_web/live/checkin_edit_live.html.heex)

---

## Test Coverage Added

### Unit tests — `Entry` changeset ([test/revix/entries/entry_test.exs](test/revix/entries/entry_test.exs))

`checkin_changeset/3` (describe block updated from `/2`):

| Test | What is covered |
|---|---|
| `non-owner: rejects future datetime` | Any datetime after now produces "must be in the past" on `starts_at_local` |
| `non-owner: rejects datetime older than lookback window` | Datetime more than `checkin_lookback_hours` in the past is rejected |
| `non-owner: accepts datetime within the lookback window` | 30-minute-ago datetime is valid |
| `non-owner: accepts datetime near but inside the lookback boundary` | 1-minute buffer inside the boundary passes; avoids clock-race flakiness |
| `non-owner: rejects datetime just outside the lookback boundary` | 1-minute outside the boundary is rejected |
| `non-owner: window check uses UTC conversion, not raw local time` | A non-UTC timezone is used; validates that comparison operates on the converted UTC instant |
| `non-owner: invalid timezone short-circuits before window check` | Invalid tz makes changeset invalid before window validation; window error does not also appear |
| `owner: accepts future datetime` | Owner role bypasses window validation entirely |
| `owner: accepts datetime older than lookback window` | Owner can use an arbitrary past date |
| `owner: published_tz reflects the provided timezone` | Non-UTC timezone propagates correctly to `published_tz` |

`update_checkin_changeset/3` (describe block updated from `/2`):

| Test | What is covered |
|---|---|
| `non-owner (default): does not cast datetime fields` | Default role leaves `starts_at_local`, `starts_tz`, `starts_at_utc` unchanged |
| `non-owner explicit: ignores datetime fields even when passed` | Explicit `:user` role also leaves datetime fields unchanged |
| `owner: casts and computes UTC from updated datetime fields` | Owner-role update recomputes `starts_at_utc` from the new local + timezone, including DST-aware conversion |
| `owner: rejects invalid timezone on update` | Invalid timezone on owner update fails validation |
| `owner: datetime fields are optional — content-only update still valid` | Owner can submit just a content change without providing datetime fields |

### Context tests — ([test/revix/entries_test.exs](test/revix/entries_test.exs))

- `change_checkin/2` describe block renamed from `/1`; call sites updated to `Entries.change_checkin(:owner, ...)`.
- Two `create_local_checkin` tests updated from hardcoded 2026-02-16 dates (outside the non-owner window) to `NaiveDateTime.add(NaiveDateTime.utc_now(:second), -30, :minute)` with `Etc/UTC`, so they pass non-owner validation without requiring an owner scope.

### LiveView tests — new checkin ([test/revix_web/live/checkin_new_live_test.exs](test/revix_web/live/checkin_new_live_test.exs))

New `describe "datetime window rule — new checkin"` block (5 tests):

| Test | What is covered |
|---|---|
| `non-owner: rejects future datetime` | Submit with a future `starts_at_local` shows validation error; no checkin created |
| `non-owner: rejects datetime older than lookback window` | Submit with a too-old datetime shows validation error; no checkin created |
| `non-owner: accepts recent datetime` | Submit with a 30-minute-ago datetime succeeds and redirects |
| `owner: accepts future datetime` | Owner can create a checkin with a future datetime |
| `owner: accepts ancient datetime` | Owner can create a checkin with a datetime far in the past |

Two existing tests (`creates checkin with an existing DB place`, `companions are persisted atomically`) promoted to `:owner` role because their hardcoded datetimes fall outside the non-owner window; their purpose is testing place selection, not datetime.

### LiveView tests — edit checkin ([test/revix_web/live/checkin_edit_live_test.exs](test/revix_web/live/checkin_edit_live_test.exs))

New `describe "datetime editing on edit page"` block (4 tests):

| Test | What is covered |
|---|---|
| `non-owner does not see datetime fields on edit page` | `starts_at_local` and `starts_tz` inputs absent from rendered HTML |
| `owner sees datetime fields on edit page` | Both inputs present after `set_person_role(person, :owner)` |
| `owner can update the checkin datetime` | Owner submits new datetime; `starts_tz` is persisted correctly |
| `non-owner submit ignores datetime params even if injected` | Direct `render_submit` with injected datetime params; `starts_at_utc` is unchanged |

Total suite after changes: **629 tests, 0 failures**.
