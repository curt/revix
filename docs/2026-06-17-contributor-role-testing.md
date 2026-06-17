# Contributor Role — Manual Testing Checklist

**Date:** 2026-06-17
**Scope:** New `:contributor` role; manual place creation during checkin with browser-locked coordinates; place standalone creation and editing remain owner-only.

---

## Setup

- Have an **owner-role** account, a **contributor-role** account, and a plain **user** account available.
- To promote a person to contributor, run in IEx (`make serve`):
  ```elixir
  person = Revix.People.get_person_by_email("user@example.com")
  Revix.People.set_person_role(person, :contributor)
  ```
- Run `make migrate-db` to apply the `add_contributor_role` migration before testing.
- Enable browser geolocation for the test domain, or use a browser that allows spoofing location (DevTools → Sensors → Geolocation override in Chrome). The tests below assume geolocation is available.

---

## Contributor: checkin creation with a new place

Sign in as a **contributor** and navigate to `/checkins/new`.

### Before locating

- [ ] The page loads without error
- [ ] "Enter manually…" is **not** visible (manual entry only appears in the place list after locate runs)
- [ ] The manual place form fields (Name, Latitude, Longitude) are visible because no place results exist yet

### After clicking "Locate me"

- [ ] Geolocation runs and nearby places are listed
- [ ] "Enter manually…" appears at the bottom of the place list
- [ ] Clicking "Enter manually…" selects it (highlighted) and the manual place form is shown

### Manual place form — field behaviour

- [ ] The **Place Name** field is empty and editable
- [ ] The **Latitude** field is pre-filled with the browser's latitude and is **not editable** (readonly)
- [ ] The **Longitude** field is pre-filled with the browser's longitude and is **not editable** (readonly)
- [ ] Attempting to click into the Latitude or Longitude fields does not allow typing

### Submitting with a new manual place

- [ ] Enter a place name (e.g., "Corner Café"), fill in checkin details, and click **Save as Draft**
- [ ] Draft is saved; redirected to the checkin edit page
- [ ] Navigate to `/places` — "Corner Café" is listed as a local place
- [ ] The place's coordinates match the browser-reported location

### Publishing

- [ ] Create another checkin with a new manual place, click **Publish…**, confirm — published checkin appears on the public feed
- [ ] The new place is in the database with the browser-provided coordinates

---

## Contributor: restrictions

### Standalone place creation blocked

- [ ] Navigate to `/places/new` as a contributor — redirected with "not authorized" flash
- [ ] The redirect target is `/places`

### Place editing blocked

- [ ] Navigate to `/places/:id/edit` as a contributor — redirected with "not authorized" flash

### CheckinFromPlaceLive blocked

- [ ] Navigate to a place show page; no "Check in here" button is visible for contributors (it is owner-only)
- [ ] Attempt to visit `/places/:id/checkin` directly as a contributor — redirected with an error

---

## User role: unchanged behaviour

Sign in as a plain **user** (no role change).

- [ ] Navigate to `/checkins/new` and click "Locate me" — "Enter manually…" does **not** appear in the place list
- [ ] Only existing nearby places (DB and OSM) are selectable
- [ ] Navigate to `/places/new` — redirected with "not authorized" flash
- [ ] Attempting to submit a checkin form with `place_manual` params included (e.g. via a modified request) returns an error — "You do not have permission to create places."

---

## Owner role: unchanged behaviour

Sign in as an **owner**.

- [ ] Navigate to `/checkins/new`, click "Locate me", click "Enter manually…" — the Place Name, Latitude, and Longitude fields are **all editable**
- [ ] Owner can type arbitrary coordinates (not locked to browser location)
- [ ] Navigate to `/places/new` — form loads normally; owner can create a standalone place
- [ ] Navigate to `/places/:id/edit` — form loads normally; owner can edit a place

---

## starts_at window enforcement

Contributors follow the same 24-hour window as regular users.

- [ ] Sign in as a **contributor**, create a checkin with a date more than 24 hours in the past — error: "must be within the last 24 hours"
- [ ] Sign in as a **contributor**, create a checkin with a date in the future — error: "must be in the past"
- [ ] Sign in as an **owner** and create a checkin with an older date — no window error

---

## Regression: existing checkin flows

- [ ] A **user** can still select an existing nearby OSM place during checkin creation — it is auto-created in the local database and the checkin is saved
- [ ] A **contributor** can also select an existing OSM place — same behaviour as a user
- [ ] A **contributor** can select an existing local (DB) place — checkin saved normally
- [ ] All companion, image upload, and draft/publish flows work for contributors exactly as they do for users

---

## Automated tests

```
make tests
```

Should report **0 failures**.
