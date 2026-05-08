# Checkin Datetime Window — Manual Testing Checklist

**Date:** 2026-05-07
**Branch:** topics/checkin-cleanup
**Scope:** Role-based datetime validation on new checkin creation; owner-only datetime editing on the edit page.

---

## Setup

- Have two accounts available: one with the default **user** role and one with the **owner** role.
- The current local time and timezone must be known to construct test datetimes accurately.
- The lookback window defaults to **24 hours**. All "too old" cases below use a datetime more than 24 hours in the past.

---

## New checkin — non-owner datetime restrictions

Sign in as a **non-owner** user.

- [ ] Load `/checkins/new` — the Date and Time field and Time Zone selector are visible (non-owners may still select a datetime within the window)
- [ ] Select a place, set the datetime to **now** (or any time in the past 24 hours), and submit — checkin is created successfully
- [ ] Set the datetime to **5 minutes from now** and submit — the form re-renders with a validation error: "must be in the past"; no checkin is created
- [ ] Set the datetime to **25 hours ago** and submit — the form re-renders with a validation error: "must be within the last 24 hours"; no checkin is created
- [ ] Set the datetime to exactly **23 hours and 55 minutes ago** and submit — checkin is created successfully (inside the window)

---

## New checkin — non-UTC timezone correctness

Sign in as a **non-owner** user.

- [ ] Set the Time Zone selector to a non-UTC zone (e.g., `America/New_York`, UTC-4 or UTC-5 depending on DST)
- [ ] Enter a local time that is **23 hours ago in that timezone** — the UTC equivalent is also within the window — submit succeeds
- [ ] Enter a local time that is **25 hours ago in that timezone** — submit shows "must be within the last 24 hours"
- [ ] Enter a local time that is **1 hour from now in that timezone** — submit shows "must be in the past"

---

## New checkin — owner has no datetime restrictions

Sign in as an **owner**.

- [ ] Set the datetime to **3 hours from now** and submit — checkin is created successfully
- [ ] Set the datetime to a date **over a year in the past** (e.g., 2024-01-01) and submit — checkin is created successfully
- [ ] All timezone options are available and any timezone can be combined with any datetime

---

## Edit checkin — non-owner cannot see or change datetime

Sign in as a **non-owner** user, then create or navigate to a checkin you authored.

- [ ] Load the edit page for your checkin — the **Date and Time** section is **not visible**; no `datetime-local` or timezone select input appears anywhere on the page
- [ ] Update the content and submit — the checkin is saved; the original `starts_at` is unchanged (verify on the show page or in the checkin header)

---

## Edit checkin — owner can see and update datetime

Sign in as an **owner**.

- [ ] Load the edit page for any checkin — a **Date and Time** section is visible with a `datetime-local` input and a **Time Zone** select
- [ ] Change the datetime to a value several hours earlier and submit — the show page reflects the updated time
- [ ] Change the timezone to a different IANA zone and submit — the updated timezone is shown correctly on the show page
- [ ] Enter an invalid or empty datetime and submit — the form re-renders with a validation error; no change is persisted
- [ ] Enter a valid datetime with a non-UTC timezone — the UTC equivalent is stored correctly (verify the time displayed accounts for the offset)

---

## Edit checkin — datetime param injection by non-owner

This verifies the server-side guard, not just the UI.

- [ ] As a non-owner author, open the edit page in browser DevTools
- [ ] Manually add hidden `starts_at_local` and `starts_tz` inputs to the form (or use the network console to POST injected params with a future datetime)
- [ ] Submit — the checkin content is updated if changed, but `starts_at` is **unchanged** (the injected params are silently ignored)

---

## Regression: existing checkin flows

- [ ] Non-owner creates a checkin with a recent datetime and selects an existing DB place — checkin is created and shown correctly
- [ ] Non-owner creates a checkin with a recent datetime and selects an OSM place — place is created and checkin is saved correctly
- [ ] Owner creates a checkin with a future datetime — checkin is saved; the future time is displayed on the show page
- [ ] Companion and image flows on the edit page are unaffected for both roles

---

## Automated tests

```
make tests
```

Should report **0 failures**.
