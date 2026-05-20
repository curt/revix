# Activity Feed Improvements — Manual Testing Checklist

**Date:** 2026-05-20  
**Branch:** next/13  
**Scope:** LiveView home and person feeds, activity grouping, reply/remote-like visibility, live updates, map stability.

---

## Setup

- Have an **authenticated** account and a separate **second** account available.
- No migration is required.
- Start the server: `make serve`.

---

## Home page — unauthenticated

Sign out completely and navigate to `/`.

- [ ] The page loads and shows a feed of checkins and activity
- [ ] At least one checkin row is visible showing "checked into [place name]" with a timestamp
- [ ] No author name link is present — only an avatar (or blank space if the author is unresolvable)
- [ ] The map renders and shows place markers; it does not go blank after the initial load

### Likes — unauthenticated

- [ ] Local likes (authored by local users) are visible in the feed with a heart icon and "liked [place name]"
- [ ] Multiple local likes on the same checkin appear as a **single grouped row** with an avatar group, not separate rows
- [ ] Remote likes (authored by federated users) are **not** visible

### Comments — unauthenticated

- [ ] Comments on checkins are visible with "commented on [place name]"
- [ ] Multiple comments on the same checkin appear as a **single grouped row** with an avatar group
- [ ] **Replies** (comments on comments) are **not** visible as separate feed rows
- [ ] A comment and a reply to that comment on the same checkin appear as a single grouped row (not two rows)

---

## Home page — authenticated

Sign in and navigate to `/`.

- [ ] The page loads and shows the same feed visible to unauthenticated users

### Likes — authenticated

- [ ] Remote likes (federated users) are **visible** in the feed with a heart icon
- [ ] Remote and local likes on the same checkin are grouped into a single row

### Comments — authenticated

- [ ] Replies are visible and grouped with their parent comment under the same checkin row
- [ ] A comment and a reply to that comment appear as a single "commented on [place name]" row with both authors in the avatar group

---

## Home page — live updates

Sign in and navigate to `/`. Keep the tab open.

### New checkin appears live

In a second browser tab or via IEx, create a new checkin. Return to the first tab.

- [ ] The new checkin appears at the top of the feed **without a page reload**
- [ ] The map does **not** go blank when the new checkin appears

### New like appears live

Create a new like on an existing checkin (via the heart button on a checkin page). Return to the home feed tab.

- [ ] The liked checkin appears in the feed (or its existing group updates) **without a page reload**

### New comment appears live

Post a comment on an existing checkin. Return to the home feed tab.

- [ ] The comment appears in the feed **without a page reload**
- [ ] If a comment group for that checkin already exists, the new comment merges into it (no duplicate row)

### Remote like — unauthenticated does not update

Sign out. Open the home page. Trigger an inbound remote like (via federation test or IEx `Likes.upsert_inbound_like/1`).

- [ ] The feed does **not** update with the remote like

---

## Home page GeoJSON

- [ ] `GET /home.geo` returns a JSON response with `"type": "FeatureCollection"`
- [ ] The response includes local places as features with `name` and `url` properties
- [ ] `GET /?_format=geo` returns the LiveView HTML, not GeoJSON (format negotiation no longer applies at `/`)

---

## Person profile page — unauthenticated

Navigate to `/@username` (or `/people/:id`) for a user who has checkins, likes, and comments.

- [ ] The page renders with the person's display name as the heading
- [ ] Only that person's own activities appear — other people's checkins are not shown
- [ ] The map renders correctly and does not go blank
- [ ] No author name links are visible — only avatars

### Replies — unauthenticated

- [ ] If the person has replied to a comment, the reply is **not** visible as a separate "replied to" row
- [ ] The reply is merged into the same "commented on [place]" group as the original comment

---

## Person profile page — authenticated (viewing own profile)

Sign in and navigate to your own profile page (`/@yourusername`).

- [ ] Replies you have made are visible and grouped with the parent comment under the same checkin

### Live updates on own profile

- [ ] Create a new checkin — it appears at the top of your profile feed without a reload
- [ ] Like a checkin — the like appears in your feed without a reload
- [ ] Post a comment — it appears (or merges) in your feed without a reload

---

## Person profile page — authenticated (viewing another profile)

Sign in and navigate to a different user's profile page.

- [ ] Only that person's activities appear
- [ ] Your own activities are not shown
- [ ] Creating a new checkin under your own account does **not** cause the other person's profile to update

---

## Avatar groups

Find a checkin or post with multiple likes or comments from different users.

- [ ] Up to 3 avatars are shown overlapping (negative space effect)
- [ ] If there are more than 3 participants, a `+N` overflow bubble appears after the third avatar
- [ ] Each avatar links to the respective person's profile and has a `title` tooltip with their display name

---

## Activity timestamps

- [ ] Each activity row shows a date (`YYYY-MM-DD`) and local time with timezone abbreviation
- [ ] For grouped rows (like_group, comment_group), the timestamp shown is the **latest** activity in the group, not the earliest
- [ ] After a live update adds to a group, the timestamp updates to reflect the newer activity

---

## Map stability

- [ ] Navigate to `/` — map renders correctly
- [ ] Trigger a live update (create checkin, like, or comment) — map remains visible and interactive; it does **not** flash blank
- [ ] Navigate to `/@username` — map renders correctly
- [ ] Trigger a live update on that page — map remains stable

---

## Regression checks

- [ ] Checkin show page loads and displays comments correctly
- [ ] Liking/unliking a checkin via the heart button on the show page still works
- [ ] Posting a comment on a checkin still works
- [ ] Person GeoJSON (`/@username?_format=geo`) still returns a GeoJSON FeatureCollection
- [ ] Person ActivityPub format (`/people/:id?_format=activity`) still returns the actor JSON
- [ ] `/people/:id` redirects to `/@username` when the person has a username
- [ ] `/people/:nonexistent-id` returns a 404
- [ ] Draft posts still appear in the authenticated user's own feed with the "drafted" verb and "Draft" badge
- [ ] Draft posts do **not** appear in the unauthenticated feed or another user's feed
- [ ] The Atom feed at `/feed.atom` is unaffected
- [ ] Checkin creation, editing, and place search flows are unaffected

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
