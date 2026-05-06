# Checkin Place Search — Manual Testing Checklist

**Date:** 2026-05-06
**Branch:** topics/checkin-cleanup
**Scope:** New checkin LiveView — place search UX changes from the 2026-05-06 remediation

---

## Setup

- Sign in as an **owner-role** account for all place-related tests (owners can create places)
- Have a second browser tab or app available to simulate losing focus
- A dense urban area is useful for the result-limit test; alternatively, seed the database with many nearby places

---

## Owner manual entry without "Locate me"

- [ ] Load `/checkins/new` as an owner — the Place Name, Latitude, and Longitude fields are visible immediately, before clicking "Locate me"
- [ ] Fill in all three fields, complete the checkin details, and submit — checkin is created successfully with no "Please select a place" flash
- [ ] Leave one of the three fields blank and submit — the form re-renders with a validation error on the missing field
- [ ] Log in as a non-owner — the manual entry fields are **not** visible before locate; submitting the form without selecting a place shows "Please select a place before submitting"

---

## Lat/lon pre-population from geolocation

- [ ] As an owner, click "Locate me" — after the browser grants permission, the Latitude and Longitude fields are automatically pre-filled with the discovered coordinates
- [ ] Verify that pre-filling happens for **both** fields together; neither appears empty while the other is filled
- [ ] Type a custom value into the Latitude field **before** clicking "Locate me," then click "Locate me" — the field retains your typed value and is **not** overwritten by the discovered coordinate
- [ ] Same for Longitude — typing first prevents overwrite

---

## Input values survive focus loss

- [ ] As an owner (before clicking "Locate me"), type a place name into the Place Name field
- [ ] Open another app or browser window so the checkin page loses focus, then return — the typed value is still present
- [ ] Paste coordinates into Latitude and Longitude, then switch away and back — values are retained
- [ ] Click "Locate me" so OSM results arrive while the manual fields are visible — any values you already typed are still present after the results load

---

## Place list collapse and expand

- [ ] Click "Locate me" and wait for results — the list of nearby places is expanded by default
- [ ] Click a place to select it — the list **collapses**; only the selected-place confirmation box ("✓ Selected: …") is visible
- [ ] A chevron button (▸) appears next to the "Nearby Places" heading — click it — the list **re-expands**
- [ ] With the list expanded, click a different place — it becomes selected and the list collapses again
- [ ] With the list open and no place selected, click the chevron (▾) — the list collapses; the heading and chevron remain visible

---

## Selection preserved when OSM results arrive late

- [ ] Click "Locate me" — the DB results appear immediately with the spinner still showing
- [ ] While the spinner is still visible, click a place — it becomes selected and the list collapses
- [ ] When the spinner disappears (OSM results merged), the selected-place confirmation is still shown and the same place is still selected
- [ ] Click "Locate me" a second time at a noticeably different location — after OSM results arrive, the previously-selected place from the first search is cleared and the form returns to the "no place selected" state

---

## Result limit in dense areas

- [ ] In a densely populated area (or with many seeded places), click "Locate me" — the list shows at most 20 entries regardless of how many are nearby
- [ ] The 20 results shown are the **nearest** ones, sorted by distance

---

## "Enter manually..." option after locate (owner)

- [ ] Click "Locate me" as an owner — the "Enter manually..." option appears at the bottom of the results list
- [ ] Click "Enter manually..." — the manual Place Name / Latitude / Longitude fields appear; the button is highlighted
- [ ] Fill in the fields and submit — a new place is created and the checkin is saved

---

## Non-owner restrictions

- [ ] As a non-owner, click "Locate me" — no "Enter manually..." option appears in the list
- [ ] Submitting with no place selected shows "Please select a place before submitting"

---

## Regression: existing place search behavior

- [ ] Selecting a DB place and submitting creates the checkin correctly
- [ ] Selecting an OSM place creates a new local place and saves the checkin
- [ ] If OSM fails (e.g., disconnect network before "Locate me"), DB results are still shown and the spinner goes away; no crash
- [ ] "No places found nearby" message appears when search completes with no results from either source
- [ ] The spinner is visible immediately after "Locate me" and disappears once OSM results (or error) arrive

---

## Browser console checks

- [ ] No `FunctionClauseError` or GenServer termination errors in the server log during any of the above flows
- [ ] No JavaScript errors in the browser console

---

## Automated tests

```
make tests
```

Should report **0 failures**.
