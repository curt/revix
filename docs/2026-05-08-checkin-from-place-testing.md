# Checkin from Place — Manual Testing Checklist

**Date:** 2026-05-08
**Branch:** topics/checkin-cleanup
**Scope:** New checkin-creation flow at `/places/:id/checkins/new` — no place-search UI.

---

## Setup

- Have an **owner-role** account and a separate **non-owner** account available.
- Create or navigate to an existing place (e.g., via `/places`).
- Note the place ID from the URL for constructing the test path.

---

## Place show page link

- [ ] Sign in as an **owner** and navigate to any place show page — a "Check in here" link with a map-pin icon appears directly below the place name
- [ ] Click "Check in here" — navigated to `/places/:id/checkins/new` with the place name in the header
- [ ] Sign in as a **non-owner** and navigate to the same place show page — no "Check in here" link is visible
- [ ] Visit the place show page while **not signed in** — no "Check in here" link is visible

---

## Authentication & Authorization

- [ ] Navigate to `/places/:id/checkins/new` while **not signed in** — redirected to `/people/signin`
- [ ] Sign in as a **non-owner** and navigate to `/places/:id/checkins/new` — redirected to `/checkins/new` with the flash error "not authorized"
- [ ] Navigate to `/places/11111111111/checkins/new` as an **owner** (a valid-format ID that does not exist) — redirected to `/places` with "Place not found" flash

---

## Owner mount

Sign in as an **owner** and navigate to `/places/:id/checkins/new` for a real place.

- [ ] The page header reads "New Checkin at {place name}"
- [ ] No "Locate me" button is visible
- [ ] No "Nearby Places" heading is visible
- [ ] No Place Name, Latitude, or Longitude inputs are visible
- [ ] A Content textarea, Date and Time input, and Time Zone selector are present
- [ ] A Companions section is present
- [ ] A Photos section is present
- [ ] The Date and Time field is pre-filled with the current local time (set by the JS hook on mount)
- [ ] The Time Zone selector is pre-set to the browser's local timezone

---

## Creating a checkin

- [ ] Fill in optional content, adjust the datetime if desired, and click **Create Checkin** — checkin is created and you are redirected to the checkin show page
- [ ] The show page displays the correct place name, datetime, and any content entered
- [ ] Leave the Date and Time field blank and submit — form re-renders with "can't be blank" validation error; no checkin is created
- [ ] Enter a future datetime and submit — checkin is created (owner has no window restriction)
- [ ] Enter a datetime years in the past and submit — checkin is created

---

## Companions

- [ ] Type a partial name into the companion search box — matching suggestions appear
- [ ] Click a suggestion — it appears as a chip below the search box
- [ ] Click the × on a chip — it is removed
- [ ] Add a companion and create the checkin — navigate to the show page and confirm the companion is listed

---

## Photos

- [ ] Attach a photo using the file picker — a pending upload card appears with the filename
- [ ] Click the × on the pending upload card — the card is removed and the file is no longer queued
- [ ] Add a photo, fill in an optional caption, and create the checkin — the photo and caption appear on the show page

---

## Regression: existing /checkins/new flow

- [ ] `/checkins/new` is unaffected — place search, locate, manual entry, and all other behaviors work as before

---

## Browser console checks

- [ ] No JavaScript errors in the browser console during any of the above flows
- [ ] No server-side errors or crashes in the application log

---

## Automated tests

```
make tests
```

Should report **0 failures**.
