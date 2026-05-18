# Draft Posts — Manual Testing Checklist

**Date:** 2026-05-18
**Branch:** next/11
**Scope:** Draft/publish distinction for posts — two-button form UI, confirmation modal, draft visibility rules, activity feeds, show page verb.

---

## Setup

- Have an **owner-role** account and a separate **non-owner** account (author role) available.
- No migration is required — the existing schema already supports `NULL` `published_at_*` fields.

---

## New post form — button layout

Sign in as an **owner** and navigate to `/posts/new`.

- [ ] A **Save as Draft** button (secondary/gray style) is present
- [ ] A **Publish…** button (warning/amber style) is present
- [ ] No "Create Post" button is visible
- [ ] The Time Zone selector is pre-filled with the browser's local timezone

---

## Creating a draft

Sign in as an **owner** and navigate to `/posts/new`.

- [ ] Fill in a title and content; click **Save as Draft** — redirected to `/posts/:id` (short URL, no date segment)
- [ ] Flash message reads "Draft saved."
- [ ] Navigate to the post show page — the word "drafted" appears where "posted" would appear for a published post
- [ ] Navigate to `/posts` — the post appears in a "Drafts" section above the published list, with a "Draft" badge and an "Updated" date
- [ ] Sign out and navigate to `/posts` — the draft does **not** appear
- [ ] Sign out and navigate to `/posts/:id` directly — page returns a 404-equivalent error (not rendered)
- [ ] Sign in as the **non-owner** account and navigate to `/posts/:id` — 404-equivalent error

---

## Publish flow from new post form

Sign in as an **owner** and navigate to `/posts/new`.

- [ ] Fill in a title and content; click **Publish…** — a confirmation modal appears with the text "Once published, this cannot be undone."
- [ ] Click **Cancel** in the modal — the modal closes; no post is created
- [ ] Click **Publish…** again to reopen the modal; click **Publish** — redirected to `/posts/:id/YYYY/MM/DD/:slug` (canonical dated URL)
- [ ] Flash message reads "Post published."
- [ ] The post appears on `/posts` in the published list (not the Drafts section)
- [ ] Sign out; navigate to `/posts/:id` directly — the post renders correctly (not a 404)

---

## Missing timezone — publish validation

Sign in as an **owner** and navigate to `/posts/new`.

- [ ] Clear the Time Zone selector so it is blank
- [ ] Click **Publish…** and then **Publish** in the modal — the modal closes and the form re-renders with a validation error on the timezone field; no post is created

---

## Edit form — unpublished post button layout

Navigate to `/posts/:id/edit` for a draft post (created above).

- [ ] **Save as Draft** and **Publish…** buttons are visible
- [ ] **Save Changes** button is **not** visible
- [ ] The Time Zone selector is visible (even for a non-owner author)
- [ ] The Time Zone selector is pre-filled with the browser's local timezone (populated by the JS hook on mount, since the draft has no stored timezone)

---

## Editing and saving a draft

- [ ] Change the content and click **Save as Draft** — redirected to `/posts/:id`; flash reads "Draft saved."
- [ ] Navigate back to `/posts/:id/edit` — the updated content is present
- [ ] The post's `published_at` fields remain unset (the show page still shows "drafted" and the URL has no date segment)

---

## Publishing an existing draft via the edit form

Navigate to `/posts/:id/edit` for a draft post.

- [ ] Set or confirm the Time Zone; click **Publish…** — confirmation modal appears
- [ ] Click **Cancel** — modal closes; post remains a draft
- [ ] Click **Publish…** again; click **Publish** in the modal — redirected to `/posts/:id/YYYY/MM/DD/:slug`
- [ ] Flash message reads "Post published."
- [ ] Navigate to `/posts` — the post has moved from the "Drafts" section to the published list
- [ ] The post show page now displays "posted" (not "drafted")
- [ ] The **Save Changes** button appears on subsequent visits to `/posts/:id/edit` (no **Publish…** button)

---

## Missing timezone — publish validation on edit form

Navigate to `/posts/:id/edit` for a draft post.

- [ ] Clear the Time Zone selector; click **Publish…**, then **Publish** in the modal — modal closes, form re-renders with a timezone validation error; post remains unpublished

---

## Edit form — published post button layout

Navigate to `/posts/:id/edit` for a **published** post.

- [ ] A **Save Changes** button (primary/blue style) is visible
- [ ] **Save as Draft** and **Publish…** buttons are **not** visible
- [ ] Non-owners do **not** see a Time Zone selector
- [ ] Owners see the Time Zone selector pre-filled with the post's stored timezone

---

## Show page verb

- [ ] Visit a **draft** post's show page as the author — the metadata line reads "drafted" (not "posted")
- [ ] Visit a **published** post's show page — the metadata line reads "posted"

---

## Draft visibility — post index `/posts`

Sign in as the **owner** (author of the draft).

- [ ] The "Drafts" section appears above the published list
- [ ] Each draft shows its title (or "Untitled Draft"), a warning-coloured "Draft" badge, and an "Updated" date
- [ ] Clicking a draft in the list navigates to its show page at `/posts/:id`

Sign out.

- [ ] The "Drafts" section is **not** visible; published posts are still listed normally

Sign in as the **non-owner** account.

- [ ] The "Drafts" section is **not** visible

---

## Draft visibility — home page activity feed

Sign in as the **owner** (author of the draft).

- [ ] The draft appears in the home activity feed with the verb "drafted" and a "Draft" badge
- [ ] The activity is sorted by `updated_at` among other activities

Sign out.

- [ ] The "drafted" activity entry is **not** present

Sign in as the **non-owner** account.

- [ ] The "drafted" activity entry is **not** present

---

## Draft visibility — person profile activity feed

Navigate to the owner's public profile page (e.g. `/@username`).

As the **owner** (viewing your own profile):

- [ ] The draft appears in the activity feed with the "drafted" verb

As an **anonymous** visitor or the **non-owner** account:

- [ ] The draft does **not** appear in the profile activity feed

---

## Draft show page — direct access

- [ ] While **not signed in**, navigate to `/posts/:id` for a draft — 404-equivalent error
- [ ] While signed in as the **non-owner** account, navigate to `/posts/:id` — 404-equivalent error
- [ ] While signed in as the **author** (owner), navigate to `/posts/:id` — post renders; "drafted" verb is present; no structured data (no JSON-LD script tag)

---

## Atom feed

- [ ] After creating a draft, fetch `/feed.atom` — the draft does **not** appear in the feed
- [ ] After publishing a post, fetch `/feed.atom` — the post appears as it would for any other post

---

## Regression checks

- [ ] Creating a new post via **Publish…** → **Publish** produces a canonical dated URL and works identically to the previous single-button flow
- [ ] Existing published posts on `/posts/:id/edit` show only **Save Changes** — no regression
- [ ] Owner can still change timezone on a published post via the edit form
- [ ] Checkin and place flows are unaffected
- [ ] The Atom feed, ActivityPub outbox, and GeoJSON format for published posts are unaffected
- [ ] Likes and comments on published posts continue to work correctly

---

## Browser console checks

- [ ] No JavaScript errors during any of the above flows
- [ ] No server-side errors or crashes in the application log (`make serve` output)

---

## Automated tests

```
make tests
```

Should report **0 failures**.
