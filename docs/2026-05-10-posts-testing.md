# Posts — Manual Testing Checklist

**Date:** 2026-05-10
**Branch:** topics/posts
**Scope:** Posts as a first-class entry type — creation, editing, show page, place/companion/photo management, feed, and place show integration.

---

## Setup

- Have an **owner-role** account and a separate **non-owner** account available.
- Have at least one existing **place** in the database (create via `/checkins/new` if needed).
- Run `make migrate-db` to apply the `entry_places` migration before testing.

---

## Navigation

- [ ] Sign in as an **owner** — "Posts" appears in the top nav above "Checkins"
- [ ] "New Post" appears as a sub-item under "Posts" in the nav
- [ ] Sign in as a **non-owner** — "Posts" appears in the nav, but no "New Post" sub-item
- [ ] Visit the site while **not signed in** — "Posts" appears in the nav, but no "New Post" sub-item

---

## Posts index — `/posts`

- [ ] Navigate to `/posts` — page renders with a "Posts" heading
- [ ] Create a post; return to `/posts` — the post appears in the list with its title and published date
- [ ] A post with no title shows "Post" as the list item text
- [ ] A post with at least one like shows a heart icon and count next to it in the list
- [ ] A post with zero likes shows no heart icon

---

## Authentication & Authorization — new post

- [ ] Navigate to `/posts/new` while **not signed in** — redirected to `/people/signin`
- [ ] Sign in as a **non-owner** and navigate to `/posts/new` — redirected to `/posts` with a flash error
- [ ] Sign in as an **owner** and navigate to `/posts/new` — form renders with "New Post" heading

---

## New post form — owner mount

Sign in as an **owner** and navigate to `/posts/new`.

- [ ] A "Title (optional)" text field is present
- [ ] A "Content" textarea is present
- [ ] A "Time Zone" selector is present and **pre-set to the browser's local timezone** (set automatically by the JS hook on mount)
- [ ] A "Places (optional)" section with a search input is present
- [ ] A "Companions" section with a search input is present
- [ ] A "Photos" section with a file picker is present
- [ ] A "Create Post" button is present

---

## Creating a post

- [ ] Fill in a title and content, confirm the timezone is correct, and click **Create Post** — redirected to the post show page at `/posts/:id/YYYY/MM/DD/:slug`
- [ ] The show page displays the title, content, author avatar, and published datetime
- [ ] Leave the Time Zone blank (clear the select) and submit — form re-renders with a validation error; no post is created
- [ ] Submit with only a timezone (no title, no content) — post is created (content is optional)
- [ ] Submit with a title but no content — post is created; show page renders the title with no content block

---

## Canonical URL redirect

- [ ] Visit `/posts/:id` — redirected to `/posts/:id/YYYY/MM/DD/:slug`
- [ ] Visit `/posts/:id/2000/01/01/wrong-slug` — redirected to the correct canonical URL
- [ ] Visit `/posts/:id/2000/01/01/correct-slug` with the wrong date — redirected to the correct canonical URL

---

## Edit post — authentication & authorization

- [ ] Visit `/posts/:id/edit` while **not signed in** — redirected to `/people/signin`
- [ ] Sign in as a **non-owner** who is not the author and navigate to `/posts/:id/edit` — redirected to the post show page with a flash error
- [ ] Sign in as the **author** (non-owner) and navigate to `/posts/:id/edit` — edit form renders
- [ ] Navigate to `/posts/11111111111/edit` as any authenticated user — redirected to `/posts`

---

## Edit post form — author (non-owner) mount

Sign in as a **non-owner author** and navigate to `/posts/:id/edit`.

- [ ] "Edit Post" heading is present
- [ ] The Title and Content fields are pre-filled with the post's current values
- [ ] **No Time Zone field is visible**
- [ ] A Places section shows any places already linked to the post
- [ ] A Companions section shows any companions already tagged
- [ ] A Photos section shows any existing attached images and a file picker for new uploads

---

## Edit post form — owner mount

Sign in as the **owner** (who is also the author) and navigate to `/posts/:id/edit`.

- [ ] All of the above fields are present
- [ ] A **Time Zone selector is visible** and pre-filled with the post's current timezone

---

## Editing content

- [ ] Change the title and click **Save Changes** — redirected to the show page with the updated title; the URL slug has updated to match the new title
- [ ] Change the content and click **Save Changes** — show page reflects the new content
- [ ] Clear the title and save — show page renders with no title heading

---

## Owner: editing timezone

Sign in as an **owner** on the edit page.

- [ ] Change the Time Zone to a different value and click **Save Changes** — show page reflects the new timezone abbreviation in the published time
- [ ] As a **non-owner author**, manually craft a POST submission with a `published_tz` field — the timezone is **not** changed (field is ignored for non-owners)

---

## Places — new post form

- [ ] Type a partial place name into the "Search places…" input — matching local places appear as a dropdown list
- [ ] Type a blank or whitespace-only query — the dropdown is empty (no results)
- [ ] Click a place in the dropdown — a chip with the place name appears; the dropdown closes
- [ ] Click × on a chip — the place is removed from the list
- [ ] Add the same place twice (search again after adding) — only one chip appears (idempotent)
- [ ] Add a place and create the post — the show page displays the place name linked to the place show page

---

## Places — edit post form

- [ ] Search and add a place — the chip appears immediately and the database record is created (refresh the page to confirm it persists)
- [ ] Click × to remove a place — the chip disappears and the database record is deleted immediately
- [ ] Navigate to the edit page for a post that already has places — the chips are pre-populated on load
- [ ] Add the same place that is already linked — no duplicate chip appears

---

## Post show page — places and map

- [ ] A post with one place shows "at Place Name" below the author line, linked to the place show page
- [ ] A post with multiple places shows "at Place 1, Place 2" with each name linked
- [ ] A post with at least one place that has coordinates shows a **Leaflet map** below the author line
- [ ] The map marker links to the place show page
- [ ] A post with no places shows no "at …" text and no map

---

## Post show page — likes and comments

- [ ] The like button is present; clicking it increments the like count (sign in first)
- [ ] Clicking the like button again removes the like and decrements the count
- [ ] The comment section renders below the content; submitting a comment appends it in real time
- [ ] Comments show the commenter's avatar, name, and timestamp

---

## Companions — new post form

- [ ] Type a partial name into the companion search box — matching people appear as suggestions
- [ ] Click a suggestion — a chip with their name appears; the dropdown closes
- [ ] Click × on a chip — the person is removed
- [ ] Attempting to add yourself — no chip appears (self-add is blocked)
- [ ] Add a companion and create the post — the show page displays the companion's avatar in the "with" section

---

## Companions — edit post form

- [ ] Add a companion — chip appears immediately and the database record is created
- [ ] Remove a companion — chip disappears and the database record is deleted immediately
- [ ] Navigate to the edit page for a post with existing companions — chips are pre-populated

---

## Photos — new post form

- [ ] Attach a `.jpg` file — a pending upload card appears with the filename
- [ ] Click the × on the pending upload card — the card is removed
- [ ] Add a caption to a pending upload — the caption field is visible
- [ ] Create the post with a photo — the show page renders the image in an Attachments section
- [ ] The photo caption appears below the image as a figcaption

---

## Photos — edit post form

- [ ] Existing images are shown with their captions and a "Remove" option
- [ ] Click "Remove" on an existing image — a confirmation modal appears: "Remove photo?"
- [ ] Click **Cancel** in the modal — modal closes, image is still present
- [ ] Click **Confirm** in the modal — image is removed from the page and deleted from the database
- [ ] Upload a new image on the edit form and click **Save Changes** — image is attached and visible on the show page

---

## Edit link on show page

- [ ] Visit the post show page as the **author** — a pencil/Edit link is visible
- [ ] Click the Edit link — navigated to `/posts/:id/edit`
- [ ] Visit the show page as a **different authenticated user** — no Edit link is visible
- [ ] Visit the show page while **not signed in** — no Edit link is visible

---

## Place show page — posts section

- [ ] Navigate to a place show page for a place linked to at least one post — a "Posts" section appears **above** the "Checkins" section
- [ ] Each post in the list shows its title (or "Post") and published date, linked to the post show page
- [ ] Navigate to a place show page for a place with no linked posts — no "Posts" section is rendered

---

## Atom feed — `/feed.atom`

- [ ] After creating a post, fetch `/feed.atom` — the post appears as an `<entry>` with a title in the format "Author posted: Title"
- [ ] A post with no title appears with the title "Author posted: a post"
- [ ] The entry `<id>` matches the post's canonical URI
- [ ] The entry `<link>` points to the post show URL
- [ ] A post with content has a `<content type="html">` block with the rendered HTML
- [ ] The feed subtitle reads "Posts, check-ins, likes, and comments"

---

## Home page activity feed

- [ ] After creating a post, visit the home page — "Person posted: Title" (or "a post") appears in the activity feed
- [ ] The activity is sorted by published date among other activities (checkins, likes, comments)

---

## GeoJSON format

- [ ] Fetch `/posts/:id?_format=geo` for a post with places that have coordinates — response is a `FeatureCollection` with one feature per place
- [ ] Fetch `/posts/:id?_format=geo` for a post with no places — response is a `FeatureCollection` with an empty `features` array
- [ ] Fetch `/posts/:id/2000/01/01/wrong-slug?_format=geo` — returns GeoJSON without redirecting (canonical redirect is skipped for non-HTML formats)

---

## Regression checks

- [ ] `/checkins/new` and `/places/:id/checkins/new` are unaffected
- [ ] Checkin show pages still render likes, comments, companions, and maps correctly
- [ ] Place show pages still render the checkins section and "Check in here" / "Edit place" links for owners
- [ ] The Atom feed still includes checkins, likes, and comments alongside posts

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
