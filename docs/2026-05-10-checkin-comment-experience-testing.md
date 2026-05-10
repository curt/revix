# Checkin Comment Experience — Manual Testing Checklist

**Date:** 2026-05-10  
**Branch:** topics/comment-replies.  
**Scope:** Live threaded comments, replies, comment likes, checkin like LiveView, activity feed links, `/notes/:id` redirect fix.

---

## Setup

- Have at least **two authenticated accounts** available (Person A and Person B).
- Have one account that is the **author of a checkin** and one that is not.
- Start the server: `make serve`.
- Navigate to a checkin show page that has a place with a slug (e.g. `http://localhost:4000/checkins/{id}/{slug}`).

---

## Unauthenticated view

- [ ] Visit the checkin show page while **not signed in** — the comment section renders with no form
- [ ] If comments exist, a horizontal stack of commenter avatars appears below the like section
- [ ] No "Add a comment" textarea is visible
- [ ] The like section renders liker avatars (if any) but no Like button

---

## Comment like section (CheckinLikeLive)

### Unauthenticated
- [ ] Liker avatars display correctly; no Like button visible

### Authenticated — non-author
- [ ] A **Like** button is visible with a heart icon
- [ ] Click **Like** — button changes to **Unlike**, the heart becomes solid, and the liker avatar stack updates to include your avatar, all without a page reload
- [ ] Click **Unlike** — button reverts to **Like**, your avatar is removed from the stack
- [ ] Open the same checkin in a second browser tab and like it — in the **first tab**, the liker avatar stack updates in real time without a refresh

### Authenticated — checkin author
- [ ] Visit your own checkin show page — the Like button is **disabled** (authors cannot like their own checkin)

---

## Submitting a comment

- [ ] Sign in as Person A and visit a checkin show page
- [ ] A **"Add a comment…"** textarea appears below the thread
- [ ] Type a comment and click **Comment** — the comment appears in the thread immediately without a page reload
- [ ] The comment shows Person A's avatar, display name, and timestamp
- [ ] Open the same checkin in a second browser tab (as Person B) — Person A's new comment appears in real time

---

## Threaded replies

- [ ] Click **Reply** on an existing top-level comment — an inline reply textarea appears
- [ ] Type a reply and click **Reply** — the reply appears indented under the parent comment
- [ ] Click **Cancel** before submitting — the reply form disappears
- [ ] Click **Reply** on a reply (second level) — a reply-to-reply form appears
- [ ] Submit the reply-to-reply — it appears indented under its parent; visual indent is capped at two levels even if the chain is deeper
- [ ] Open the same checkin in a second browser tab — each reply appears in real time

---

## Liking a comment

- [ ] Sign in as Person B and visit a checkin with a comment by Person A
- [ ] A **Like** button appears below the comment text
- [ ] Click **Like** — the button changes to **Unlike**, the heart becomes solid, and Person B's avatar appears next to the button (up to 3 avatars shown)
- [ ] Click **Unlike** — reverts to **Like**, avatar removed
- [ ] Sign in as Person A (the comment author) and visit the same checkin — Person A cannot like their own comment (the Like button is absent or disabled for their own comments)

---

## Editing a comment

- [ ] Sign in as Person A and visit a checkin with your own comment
- [ ] A pencil (edit) icon button appears on your comment
- [ ] Click it — an edit textarea pre-filled with the current content appears
- [ ] Change the text and click **Save** — the updated text replaces the old content
- [ ] Click edit, change text, then click **Cancel** — the original text is restored
- [ ] Sign in as Person B — the edit button is **absent** on Person A's comments

---

## Deleting a comment

- [ ] Sign in as Person A and visit a checkin with your own comment
- [ ] A trash icon button appears on your comment
- [ ] Click it and confirm the dialog — the comment is removed from the thread without a page reload
- [ ] Sign in as Person B — the delete button is **absent** on Person A's comments

---

## `/notes/:id` redirect

### Direct comment
- [ ] Find a comment's note ID (visible in the DOM as `id="comment-{id}"`)
- [ ] Visit `http://localhost:4000/notes/{id}` — redirected to the checkin show page with `#comment-{id}` in the URL
- [ ] The browser scrolls to (or highlights) the comment

### Reply
- [ ] Find a reply's note ID
- [ ] Visit `http://localhost:4000/notes/{reply_id}` — redirected to the **original checkin** (not a `/notes/` URL), with `#comment-{reply_id}` anchor

### Reply-to-reply
- [ ] Find a reply-to-reply's note ID
- [ ] Visit `http://localhost:4000/notes/{reply_to_reply_id}` — redirected to the **original checkin** (not to the parent note or any intermediate note), with `#comment-{reply_to_reply_id}` anchor
- [ ] Confirm the anchor element exists on the page (the reply div has `id="comment-{reply_to_reply_id}"`)

---

## Activity feed

### Home page (`/`)
- [ ] After adding a **top-level comment**, an item appears in the home page activity feed reading "**[Name] commented on [Place Name]**" with a link to the checkin
- [ ] After adding a **reply to a comment**, an item appears reading "**[Name] replied to [a comment](link)**" where the link resolves to the correct checkin with the reply anchor
- [ ] After **liking a checkin**, an item appears reading "**[Name] ♥ liked [Place Name]**" with a link to the checkin
- [ ] After **liking a comment**, an item appears reading "**[Name] ♥ liked [a comment](link)**" where the link resolves to the correct checkin with the comment anchor

### Person show page (`/@{username}` or `/people/{id}`)
- [ ] The same four activity types appear correctly on the person's own activity page

---

## Real-time updates (PubSub)

- [ ] Open the same checkin in two browser tabs
- [ ] In tab 1: submit a comment — it appears in tab 2 without a refresh
- [ ] In tab 1: like a comment — the Like button state and avatar update in tab 2
- [ ] In tab 1: delete a comment — it disappears in tab 2
- [ ] In tab 1: edit a comment — the updated text appears in tab 2
- [ ] Like the checkin in tab 1 — the liker avatar stack updates in tab 2

---

## Browser console checks

- [ ] No JavaScript errors in the browser console during any of the above flows
- [ ] No server-side errors or crashes in the application log

---

## Automated tests

```
make tests
```

Should report **0 failures** (779 Elixir tests, 35 JS tests).
