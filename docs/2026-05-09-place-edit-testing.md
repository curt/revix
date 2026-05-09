# Place Edit — Manual Testing Checklist

**Date:** 2026-05-09
**Branch:** topics/place-edit-feature
**Scope:** Owner place editing at `/places/:id/edit` — name, coordinates, OSM link.

---

## Setup

- Have an **owner-role** account and a separate **non-owner** account available.
- Have at least one existing place (e.g., created via `/checkins/new`).
- Optionally note a valid OSM node ID from [openstreetmap.org](https://www.openstreetmap.org) for testing the OSM sync flow.

---

## Place show page links

- [ ] Sign in as an **owner** and navigate to any place show page — an "Edit place" link with a pencil icon appears alongside the "Check in here" link
- [ ] Click "Edit place" — navigated to `/places/:id/edit`
- [ ] Sign in as a **non-owner** — no "Edit place" link is visible on the place show page
- [ ] Visit the place show page while **not signed in** — no "Edit place" link is visible

---

## Authentication & Authorization

- [ ] Navigate to `/places/:id/edit` while **not signed in** — redirected to `/people/signin`
- [ ] Sign in as a **non-owner** and navigate to `/places/:id/edit` — redirected to the place show page with the flash error "not authorized"
- [ ] Navigate to `/places/11111111111/edit` as an **owner** (valid-format ID that does not exist) — redirected to `/places` with "Place not found" flash

---

## Owner mount — place with no OSM link

Sign in as an **owner** and navigate to `/places/:id/edit` for a place with no OSM link.

- [ ] The page header reads "Edit Place"
- [ ] The Name field is pre-filled with the place's current name
- [ ] The Latitude and Longitude fields are pre-filled with the place's current coordinates
- [ ] An OSM Type select and OSM ID number input are visible
- [ ] A "Search nearby" button is visible
- [ ] A "Save Changes" button is visible
- [ ] No "Sync from OSM" button is visible
- [ ] No "Unlink" button is visible

---

## Owner mount — place with a saved OSM link

Navigate to `/places/:id/edit` for a place that already has an OSM link.

- [ ] The OSM summary row is visible with the type/ID as a link to `openstreetmap.org` and an "Unlink" button
- [ ] A "Sync from OSM" button is visible
- [ ] No "Search nearby" button is visible
- [ ] No OSM Type select or OSM ID input is visible

---

## Editing name and coordinates

- [ ] Change the name to something new and click **Save Changes** — redirected to the place show page with the new name in the heading and (if the name changed) an updated slug in the URL
- [ ] Navigate back to `/places/:id/edit` — the Name field reflects the updated name
- [ ] Clear the name field and click **Save Changes** — form re-renders with "can't be blank" inline error; no save occurs
- [ ] Enter `91` in the Latitude field and tab away — inline validation error appears immediately; saving is blocked

---

## Linking a place to OSM manually

Starting from a place with no OSM link:

- [ ] Select "node" from the OSM Type select and enter a valid OSM node ID — a "Sync from OSM" button appears
- [ ] Click **Save Changes** — the place show page now shows an OSM badge linking to `openstreetmap.org/node/{id}`
- [ ] Navigate back to the edit page — the OSM summary row is visible; "Search nearby", OSM Type, and OSM ID inputs are hidden

---

## OSM badge on the show page

- [ ] Navigate to the place show page for a place with an OSM link — an "OSM" badge is visible (outside the owner block) linking to `openstreetmap.org`
- [ ] Sign out and revisit the same place show page — the OSM badge is still visible
- [ ] Navigate to a place with no OSM link — no OSM badge is visible

---

## Searching nearby to link an OSM object

Starting from a place with no OSM link:

- [ ] Click **Search nearby** — a spinner appears briefly, then a "Nearby Places" list appears with OSM results (each row has an "OSM" badge); no local database entries appear in the list
- [ ] Click the collapse toggle next to "Nearby Places" — the list collapses; click again — it expands
- [ ] Click an OSM result from the list — the OSM Type select and OSM ID field are updated with that result's values; a "Sync from OSM" button appears; the list closes
- [ ] Click **Save Changes** — the place is saved with the selected OSM link; the show page shows the OSM badge

---

## Syncing name and coordinates from OSM — from a saved link

Navigate to the edit page for a place that already has a saved OSM link.

- [ ] Click **Sync from OSM** — a spinner appears inside the button
- [ ] Once the sync completes, the Name, Latitude, and Longitude fields update to reflect the OSM element's current values; the spinner disappears
- [ ] The form has **not** been saved — click **Save Changes** to persist the synced values
- [ ] With an invalid OSM ID saved (e.g., set osm_id to `1` manually and save), click "Sync from OSM" — an inline error appears: "OSM element not found. Check the type and ID."

---

## Syncing name and coordinates from OSM — after selecting a nearby result

Starting from a place with no OSM link:

- [ ] Click **Search nearby** and select an OSM result from the list — the OSM Type and ID fields are filled and "Sync from OSM" appears
- [ ] Click **Sync from OSM** — name, latitude, and longitude fields update to the OSM element's values
- [ ] Click **Save Changes** — the place is saved with the new link, name, and coordinates in a single transaction; the show page reflects all updated values

---

## Unlinking from OSM

- [ ] On the edit page for a place with a saved OSM link, click **Unlink** — the OSM summary row disappears; "Search nearby", OSM Type, and OSM ID inputs reappear; "Sync from OSM" disappears
- [ ] Navigate to the place show page — the OSM badge is no longer visible

---

## Regression: place show page

- [ ] The "Check in here" link is still present and works for owners
- [ ] The existing checkin flows (`/checkins/new`, `/places/:id/checkins/new`) are unaffected

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
