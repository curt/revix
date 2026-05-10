# Posts Feature

**Date:** 2026-05-10
**Branch:** topics/posts

---

## Overview

Posts are a first-class entry type alongside checkins. They are `Note` objects for ActivityPub purposes and share the same `entries` table (distinguished by `type: :post`). Unlike checkins, posts have no required place and no `starts_at` datetime — `published_at` is the only timestamp.

---

## Requirements

- Posts are `entries` with `type: :post`.
- Posts are `Note` objects for ActivityPub purposes.
- Posts can have likes and comments.
- Posts can have zero to many places (join table, not a single `place_uri`).
- Posts can have companions (mentions/tagged people).
- Posts can have image attachments.
- Creating a post is similar to a checkin but places are optional and not the first step.
- Posts are editable by their author.
- Posts appear as a top-level nav item above Checkins.
- New Post is a second-level nav item visible to owners only.
- Show URL: `/posts/:id/YYYY/MM/DD/:slug`; bare `/posts/:id` redirects to canonical dated-slug URL.
- Posts appear in the Atom feed as "Person posted: Title".
- Posts appear in the home page activity feed.
- Owner can edit the post's timezone after creation; non-owners cannot.

---

## Architecture

### Reused without modification

| Thing | Location |
|---|---|
| `Entry` schema | `lib/revix/entries/entry.ex` |
| `EntryType` `:post` value | `lib/revix/ecto/entry_type.ex` |
| `EntryHelpers` (upload helpers) | `lib/revix_web/live/entry_helpers.ex` |
| `EntryLikeLive` | `lib/revix_web/live/entry_like_live.ex` |
| `CommentSectionLive` | `lib/revix_web/live/comment_section_live.ex` |
| `CompanionsComponent` | `lib/revix_web/components/companions_component.ex` |
| `PhotosComponent` | `lib/revix_web/components/photos_component.ex` |
| `EntryPeople` context | `lib/revix/entry_people.ex` |
| `Media` context | `lib/revix/media.ex` |
| `Likes` context | `lib/revix/likes.ex` |

### New files

| File | Purpose |
|---|---|
| `lib/revix/entry_places/entry_place.ex` | Join table schema: `entry_uri` ↔ `place_uri` |
| `lib/revix/entry_places.ex` | Context: `add_place/2`, `remove_place/2`, `get_places_for_entry/1`, `place_of?/2` |
| `priv/repo/migrations/20260510120000_create_entry_places.exs` | `entry_places` table with unique index on `(entry_uri, place_uri)` |
| `lib/revix_web/live/post_new_live.ex` | Owner-only LiveView for creating posts |
| `lib/revix_web/live/post_new_live.html.heex` | New post form template |
| `lib/revix_web/live/post_edit_live.ex` | Author-only LiveView for editing posts |
| `lib/revix_web/live/post_edit_live.html.heex` | Edit post form template |
| `lib/revix_web/controllers/post_controller.ex` | `index` and `show` actions; GeoJSON format support |
| `lib/revix_web/controllers/post_html.ex` | HTML view module |
| `lib/revix_web/controllers/post_html/index.html.heex` | Post list template |
| `lib/revix_web/controllers/post_html/show.html.heex` | Post detail template with map, likes, comments |

### Modified files

| File | Change |
|---|---|
| `lib/revix/entries/entry.ex` | Added `has_many :entry_places`; added `post_changeset/3`, `update_post_changeset/3` |
| `lib/revix/entries.ex` | Added `create_local_post_with_companions/6`, `get_local_post/1`, `get_recent_posts/1`, `get_local_posts_for_place/1`, `update_local_post/3`, `change_post/2`, `change_post_for_update/2,3` |
| `lib/revix/places.ex` | Added `search_local_places/1` |
| `lib/revix_web/canonical_routes.ex` | Added `post_path/1`, `post_url/1`, `post_uri/1`; fixed `Slug.slugify/1` nil guard |
| `lib/revix_web/router.ex` | Added post routes (public index/show + authenticated new/edit) |
| `lib/revix_web/components/layouts.ex` | Added Posts nav item with New Post sub-item for owners |
| `lib/revix_web/controllers/feed_controller.ex` | Added posts to Atom feed activity list |
| `lib/revix_web/controllers/feed_atom.ex` | Added `{:post, _}` clauses for all `feed_entry_*` functions |
| `lib/revix_web/controllers/feed_atom/index.atom.eex` | Updated subtitle to include posts |
| `lib/revix_web/controllers/place_controller.ex` | Fetches and passes `posts` to place show template |
| `lib/revix_web/controllers/place_html/show.html.heex` | Renders posts section above checkins |
| `lib/revix_web/controllers/page_controller.ex` | Includes posts in home page activity feed |

---

## Key Design Decisions

### Places as a join table

Posts have zero-to-many places, so a single `place_uri` column on `Entry` is insufficient. A new `entry_places` join table (mirroring `entry_people`) stores `(entry_uri, place_uri)` pairs with a unique constraint. Checkins continue to use the existing `place_uri` column unchanged.

On the **new post** form, places are held in memory and written atomically with the post on submit (same pattern as companions). On the **edit** form, `add_place` and `remove_place` write to the database immediately (same pattern as companion management on the edit page).

### Timezone handling

On the new post form the `Timezone` JS hook fires `set_timezone` on mount, pre-filling the Time Zone selector with the browser's local timezone — the same mechanism used by the checkin form.

On the edit form, only owners can see and change the Time Zone field (`can_edit_datetime` assign). Non-owners cannot inject a timezone change even via a crafted form submission, because `update_post_changeset` only casts `:published_tz` when `role == :owner`.

### Slug fallback

`Slug.slugify/1` returns `nil` (not `""`) when given an empty string. `CanonicalRoutes.post_path/1` guards against both `nil` and `""` before falling back to the post ID as the slug.

### GeoJSON format

`PostController.show/2` supports `?_format=geo`, returning a `FeatureCollection` of the post's associated places — consumed by the Leaflet map on the show page. The canonical URL redirect is skipped for non-HTML format requests.

---

## Data Flow

### Creating a post

1. Owner navigates to `/posts/new`
2. JS `Timezone` hook fires `set_timezone` → form pre-fills timezone
3. Owner fills title (optional), content, selects places, companions, attaches photos
4. `submit` handler calls `Entries.create_local_post_with_companions/6` in a single transaction: creates post, inserts `EntryPlace` rows, inserts `EntryPerson` rows
5. `consume_uploads` saves image files and attaches them to the new post
6. Redirect to `/posts/:id/YYYY/MM/DD/:slug`

### Editing a post

1. Author (or owner) navigates to `/posts/:id/edit`
2. Form pre-filled from existing post; companion chips and place chips loaded from DB
3. Adding/removing a companion or place writes to DB immediately (no submit required)
4. `submit` handler calls `Entries.update_local_post/3`; new image uploads consumed; redirect to show

---

## Test Coverage

- `test/revix/entry_places_test.exs` — full coverage of `EntryPlaces` context
- `test/revix/entries_test.exs` — post changesets, `create_local_post_with_companions/6` with places, `get_local_posts_for_place/1`
- `test/revix/places_test.exs` — `search_local_places/1`
- `test/revix_web/controllers/post_controller_test.exs` — index, show, canonical redirect, GeoJSON
- `test/revix_web/controllers/place_controller_test.exs` — posts section on place show
- `test/revix_web/controllers/feed_controller_test.exs` — post entries in Atom feed
- `test/revix_web/live/post_new_live_test.exs` — auth, mount, timezone, companions, places, file upload, submit
- `test/revix_web/live/post_edit_live_test.exs` — auth, mount, content update, companions, images, timezone owner-only, places
