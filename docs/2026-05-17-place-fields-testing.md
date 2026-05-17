# Place Fields — Manual Testing Checklist

**Date:** 2026-05-17
**Branch:** next/8
**Scope:** Situation fields (country, city, secondary) on places; canonical URL enrichment for places and checkins; URL sync on edit.

---

## Setup

- Have an **owner-role** account and a separate **non-owner** account available.
- Have at least one existing place. If none, create one via `/checkins/new`.
- Run `make migrate-db` to apply the `add_situation_to_places` migration.

---

## Location Details section on the edit form

Sign in as an **owner** and navigate to `/places/:id/edit`.

- [ ] A "Location Details" section is present between "Place Details" and "OpenStreetMap"
- [ ] The section contains three inputs: Country, City, and State / Province
- [ ] A hint is visible explaining that country is required if city or secondary are set
- [ ] All three fields are empty for a place that has none of these values set

---

## Validation — inline errors

- [ ] Enter `usa` in the Country field and tab away — inline error appears: "must be 2 characters"
- [ ] Enter `U1` in the Country field — inline error appears: "must be two lowercase letters"
- [ ] Enter `scottsdale` in the City field with Country left blank — inline error appears: "requires country to be set"
- [ ] Enter `az` in the State / Province field with City left blank — inline error appears: "requires country and city to be set"
- [ ] Enter `US` in the Country field — field normalises to `us` on save (uppercase is accepted and lowercased)
- [ ] Enter `Scottsdale` in the City field — field normalises to `scottsdale` on save
- [ ] Enter `New Mexico` in the State / Province field — field normalises to `new-mexico` on save

---

## Saving situation fields

### Country only

- [ ] Set Country to `us`, leave City and State / Province blank, click **Save Changes** — redirected to `/places/:id/us/:slug`
- [ ] Navigate to the place show page — the canonical URL in the browser address bar is `/places/:id/us/:slug`
- [ ] Navigate back to `/places/:id/edit` — the Country field is pre-filled with `us`

### Country + city

- [ ] Set Country to `us` and City to `scottsdale`, click **Save Changes** — redirected to `/places/:id/us/scottsdale/:slug`

### Country + city + secondary

- [ ] Set Country to `us`, City to `scottsdale`, and State / Province to `az`, click **Save Changes** — redirected to `/places/:id/us/az/scottsdale/:slug`

### Clearing situation fields

- [ ] Edit a place that has Country + City set; clear both fields and click **Save Changes** — redirected to the bare-slug URL `/places/:id/:slug`

---

## Canonical URL redirects — places

These redirects apply for HTML requests only. For each, navigate directly to the URL and confirm the browser redirects.

- [ ] Visit `/places/:id` for a place with Country set — redirected to `/places/:id/us/:slug`
- [ ] Visit `/places/:id/:slug` for a place with Country set — redirected to `/places/:id/us/:slug`
- [ ] Visit `/places/:id/wrong-country/:slug` for a place with Country `us` — redirected to `/places/:id/us/:slug`
- [ ] Visit `/places/:id` for a place with no situation fields — redirected to `/places/:id/:slug`

---

## Canonical URL redirects — checkins

- [ ] Navigate to a checkin for a place with Country `us` and City `scottsdale`
- [ ] The browser URL is `/checkins/:id/us/scottsdale/:slug`
- [ ] Visit `/checkins/:id` directly — redirected to `/checkins/:id/us/scottsdale/:slug`
- [ ] Visit `/checkins/:id/:slug` directly — redirected to `/checkins/:id/us/scottsdale/:slug`

---

## Checkin URL sync on place edit

This verifies that a place edit which changes the canonical URL also updates existing checkin URLs.

- [ ] Find a place that has one or more checkins. Note the current checkin show page URLs (e.g., `/checkins/:id/:slug`).
- [ ] Edit the place and add Country `fr`. Click **Save Changes**.
- [ ] Navigate to any of the checkins for that place — the URL is now `/checkins/:id/fr/:slug`; the old URL redirects to the new one.
- [ ] Edit the place again and change the name (which changes the slug). Click **Save Changes**.
- [ ] The checkin URLs now reflect the new slug.

---

## Checkin URL not updated on non-URL edits

- [ ] Edit a place with situation fields set; change only the coordinates. Click **Save Changes**.
- [ ] Navigate to a checkin for that place — the URL is unchanged (situation fields did not change, so no checkin update occurred).

---

## Non-owner and unauthenticated access

- [ ] Sign in as a **non-owner** and navigate to `/places/:id/edit` — redirected with "not authorized" flash; the Location Details section is never visible.
- [ ] Visit `/places/:id/edit` while not signed in — redirected to `/people/signin`.

---

## Format responses are unaffected

- [ ] Visit `/places/:id?_format=geo` for a place with situation fields — GeoJSON response is returned without redirect.
- [ ] Visit `/places/:id?_format=activity` for a place with situation fields — Activity Streams response is returned. The `url` field in the response reflects the canonical URL with situation segments; the `id` (ActivityPub URI) is the bare `/places/:id` URI, unchanged.

---

## Regression: existing place and checkin flows

- [ ] Create a new place via `/checkins/new` — no situation fields are set; the canonical URL is the bare-slug form.
- [ ] The checkin created alongside the new place has the bare-slug URL.
- [ ] The place show page, checkin show page, nearby places, and Atom feed all render correctly for places with no situation fields.
- [ ] The place edit form's existing Name, Coordinates, and OpenStreetMap sections are unaffected.

---

## Automated tests

```
make tests
```

Should report **0 failures**.
