# LiveView Checkin Forms — Manual Testing Checklist

**Date:** 2026-02-27
**Branch:** topics/liveview-checkin
**Scope:** New checkin and edit checkin LiveView forms — photos, companions, validation debounce

---

## Setup

- Sign in as an owner-role account (needed to create places)
- Have at least one place in the database, or be prepared to create one manually

---

## New Checkin Form (`/checkins/new`)

### Place selection

- [ ] "Locate me" button triggers geolocation; loading spinner appears while OSM results load
- [ ] DB and OSM results appear; selecting one highlights it
- [ ] "Enter manually..." appears (owner only) and shows name/lat/lon fields when clicked
- [ ] Submitting with no place selected shows a flash error

### Checkin details

- [ ] Typing in the Content textarea does **not** fire validate on every keystroke — wait ~300ms after stopping before the server responds
- [ ] Date/time and timezone fields validate on change (after debounce)

### Companions

- [ ] Typing in the companion search box shows matching people (debounced)
- [ ] Selecting a person from the dropdown adds a chip
- [ ] Clicking × on a chip removes it
- [ ] The current user does not appear in search results

### Photos

- [ ] File picker accepts jpg, jpeg, gif, png, webp; rejects other types
- [ ] After selecting files, each appears as a card with thumbnail, filename, and progress bar
- [ ] Caption and alt text inputs are present on each card
- [ ] Typing in a caption or alt field does **not** trigger form-level validate
- [ ] Cards can be dragged to reorder
- [ ] Clicking × cancels an upload and removes the card
- [ ] Submitting creates the checkin and redirects to the show page
- [ ] Uploaded photos appear on the show page in the correct order
- [ ] Captions and alt text saved correctly (check image metadata)

---

## Edit Checkin Form (`/checkins/:id/edit`)

### Authorization

- [ ] Visiting another user's checkin edit URL redirects with an error flash
- [ ] Visiting a nonexistent checkin ID redirects to `/checkins`

### Content

- [ ] Existing content is pre-filled
- [ ] Typing does **not** fire validate on every keystroke — waits ~300ms
- [ ] Updating content and saving redirects to the show page with updated content

### Companions

- [ ] Existing companions appear as chips on page load
- [ ] Searching and adding a companion immediately creates the DB record (no submit required)
- [ ] Removing a companion chip immediately deletes the DB record
- [ ] The current user does not appear in search results

### Photos — existing images

- [ ] Existing photos appear as cards with thumbnail, caption, and alt text pre-filled
- [ ] Typing in a caption or alt field does **not** trigger form-level validate
- [ ] Caption/alt changes are saved when the form is submitted
- [ ] Clicking the trash icon on an existing photo opens a confirmation dialog ("Remove photo?")
- [ ] Clicking Cancel in the dialog closes it without deleting the image
- [ ] Clicking Remove in the dialog deletes the image immediately (no submit required)
- [ ] Existing photo cards can be dragged to reorder; order is saved on submit

### Photos — new uploads

- [ ] File picker adds new upload cards above or interleaved with existing photos
- [ ] New upload cards show thumbnail, progress, caption, and alt fields
- [ ] New uploads can be dragged to reorder relative to existing photos
- [ ] Cancelling a pending upload removes only that card
- [ ] On submit, new photos are saved in the correct position relative to existing ones

### Mixed reorder (existing + new)

- [ ] Drag an existing photo below a pending upload — submit — verify order on show page
- [ ] Drag a pending upload above an existing photo — submit — verify order on show page

---

## Browser console checks

- [ ] No repeated `HANDLE EVENT "validate"` log lines while typing in caption/alt fields
- [ ] No `FunctionClauseError` or GenServer termination errors in the server log
- [ ] No JavaScript errors in the browser console during drag-and-drop

---

## Automated tests

```
make tests
cd assets && npm test
```

Both should report 0 failures.
