# Draft Posts Feature

**Date:** 2026-05-18
**Branch:** next/11

---

## Overview

Posts can now be saved as drafts. A draft is a post where all three `published_at_*` fields (`published_at_utc`, `published_at_local`, `published_tz`) are `NULL`. Publishing is a one-way, confirmed action — there is no unpublishing.

Draft posts are private to their author: they do not appear in the public post index, the Atom feed, ActivityPub outbox, or any other public-facing surface. The author sees their drafts in the post index (above published posts, with a "Draft" badge), in their own home feed (with the verb "drafted"), and on their own profile activity feed.

---

## Requirements

- When creating a post, the author can choose **Save as Draft** or **Publish…**.
- Saving as draft creates the post with all three `published_at_*` fields set to `NULL`.
- Publishing requires clicking **Publish…**, then confirming in a modal ("Once published, this cannot be undone.").
- When editing an **unpublished** post, the same two-button layout is shown: **Save as Draft** and **Publish…**.
- When editing an **already-published** post, only **Save Changes** is shown — no publish flow.
- Draft posts are visible only to their author.
- Draft posts are never federated and never appear in the Atom feed, site index, or any other syndication.
- For the author only: drafts appear in the post index before published posts, sorted by `updated_at desc`, with a visual "Draft" badge.
- For the author only: drafts appear in home and user activity feeds sorted by `updated_at`, with the verb "drafted" instead of "posted".
- The post show page displays "drafted" instead of "posted" for unpublished posts.
- Unpublishing is out of scope.

---

## Architecture

### No migration required

The existing `published_complete` CHECK constraint on the `entries` table already allows all three `published_at_*` fields to be simultaneously `NULL`. No schema change was needed.

### `lib/revix/entries/entry.ex`

Three changeset functions cover the post lifecycle:

| Function | Purpose |
|---|---|
| `draft_post_changeset/3` | Create or update a draft — casts `content`, `name`; sets `context`; does not touch `published_at_*` |
| `publish_post_changeset/3` | Publish a new post — casts `content`, `name`, `published_tz`; validates and sets all three `published_at_*` fields; sets `context` |
| `publish_draft_post_changeset/3` | Publish an existing draft — same as above but does not overwrite the existing `context` (set at draft creation) |

`update_post_changeset/3` (for editing already-published posts) is unchanged.

`rezone_published_at/1` (called when an owner changes the timezone on a published post) now guards against `nil` `published_at_utc` so that editing a draft as an owner with a timezone in the form params does not crash.

### `lib/revix/entries.ex`

New and updated functions:

| Function | Change |
|---|---|
| `change_post/2` | Now uses `draft_post_changeset` — no timezone validation required for live form feedback |
| `change_post_for_draft_update/2` | New — produces a draft changeset for the validate event when editing an unpublished post |
| `update_draft_post/2` | New — updates content/name on a draft without touching `published_at_*` and without enqueuing federation delivery |
| `create_local_post/4` | Now accepts `opts \\ []` with `mode: :draft \| :publish`; delegates to the appropriate changeset |
| `create_local_post_with_companions/5,6` | Extended to accept `opts \\ []` and thread `mode` through to `create_local_post` |
| `publish_local_post/4` | New — publishes an existing draft using `publish_draft_post_changeset`; enqueues a `"Create"` delivery (the post's first public activity) |
| `get_draft_posts_for_person/2` | New — returns a person's own draft posts ordered by `updated_at desc` |
| `published_posts/1` (private) | New query scope — filters to entries where `published_at_utc IS NOT NULL`; applied to `get_recent_posts/1`, `get_recent_posts_for_person/2`, `get_local_posts_for_place/1` |
| `draft_posts/1` (private) | New query scope — filters to entries where `published_at_utc IS NULL` |

`get_local_post/1` intentionally has **no** published filter — the author must be able to load their own draft for editing.

### `lib/revix_web/controllers/post_controller.ex`

- `index/2` fetches the author's drafts and passes them to the template as `draft_posts`. Anonymous visitors and non-authors receive an empty list.
- `show_by_format/4` has a new clause matching `%{published_at_utc: nil}` posts: renders to the author, returns `{:error, :not_found}` for everyone else.

### `lib/revix_web/controllers/post_html/index.html.heex`

A "Drafts" section is rendered above the published list when `@draft_posts != []`. Each draft shows its title (or "Untitled Draft"), a warning-coloured "Draft" badge, and an "Updated" date.

### `lib/revix_web/controllers/post_html/show.html.heex`

The verb "posted" is replaced with `if @post.published_at_utc, do: "posted", else: "drafted"` — no longer duplicated inside the `if @post.author` block.

### `lib/revix_web/controllers/page_controller.ex`

The home feed includes the author's own draft posts tagged `{:draft, post}`, sorted by `updated_at`. The sort key lambda gains an `|| item.updated_at` fallback to handle nil `published_at_utc` on drafts without crashing.

### `lib/revix_web/controllers/person_controller.ex`

`person_activities/2` now receives the `current_scope` and includes the author's drafts when viewing your own profile, tagged `{:draft, post}` with the same sort key fallback.

### `lib/revix_web/components/activity_components.ex`

A new `{:draft, post}` case in `activity_feed/1` renders a `draft_activity/1` component — displays the author avatar, "drafted" verb, post link, "Draft" badge, and updated date.

### `lib/revix_web/structured_data.ex`

`post_json_ld/1` gains a guard clause: `def post_json_ld(%Entry{published_at_utc: nil}), do: nil`. Draft show pages do not emit JSON-LD structured data.

### `lib/revix_web/live/post_new_live.ex` and `.html.heex`

- Two submit buttons with `name="action"`: `value="draft"` (secondary style) and `value="publish"` (warning style).
- `submit` with `action=publish` assigns `show_publish_modal: true` and stashes params.
- `submit` with `action=draft` calls `do_create_post/3` with `mode: :draft`.
- `confirm_publish` calls `do_create_post/3` with `mode: :publish`.
- `cancel_publish` clears the modal and stashed params.
- Flash on draft save: "Draft saved." Flash on publish: "Post published."
- A `<dialog>` confirmation modal is rendered outside the form when `@show_publish_modal` is true.

### `lib/revix_web/live/post_edit_live.ex` and `.html.heex`

- Mount assigns `post_published: not is_nil(post.published_at_utc)`.
- `can_edit_datetime` is now true for owners **or** any author editing an unpublished draft (timezone is needed for the publish action).
- A `set_timezone` handler populates the timezone form field from the browser on mount — needed because drafts have no stored timezone yet. It is a no-op for published posts.
- The validate event dispatches to `build_validate_form/2`: published posts use `change_post_for_update`; draft posts use `change_post_for_draft_update`.
- The submit event dispatches to `do_save_post/2`: draft posts use `update_draft_post/2` (ignores `published_tz`, no delivery enqueue); published posts use `update_local_post/4`.
- `submit` with `action=publish` shows the confirmation modal.
- `confirm_publish` calls `run_image_side_effects/1` then `Entries.publish_local_post/4`, redirects to the canonical dated-slug URL.
- `cancel_publish` clears the modal without persisting.
- Flash on draft save: "Draft saved." Flash on publish: "Post published." Flash on published-post update: "Post saved." (unchanged).
- The template renders a two-button layout when `!@post_published`, and a single **Save Changes** button when `@post_published`.

---

## Data Flow

### Creating a draft

1. Owner navigates to `/posts/new`.
2. JS `Timezone` hook fires `set_timezone` — form pre-fills timezone.
3. Owner fills in content; clicks **Save as Draft**.
4. `create_local_post_with_companions` called with `mode: :draft`; `draft_post_changeset` runs; no `published_at_*` fields set; no Oban job enqueued.
5. Redirect to `/posts/:id` (short form — no date in URL for unpublished posts).
6. Flash: "Draft saved."

### Publishing a new post

1–3. Same as above.
4. Owner clicks **Publish…** — modal appears.
5. Owner clicks **Publish** in modal.
6. `create_local_post_with_companions` called with `mode: :publish`; `publish_post_changeset` runs; all three `published_at_*` fields set; Oban job enqueued with type `"Create"`.
7. Redirect to `/posts/:id/YYYY/MM/DD/:slug`.
8. Flash: "Post published."

### Editing and saving a draft

1. Author navigates to `/posts/:id/edit`.
2. `set_timezone` hook fires — if no timezone is stored on the draft, the form's timezone field is pre-filled from the browser.
3. Author updates content; clicks **Save as Draft**.
4. `update_draft_post` called — only `content` and `name` updated; `published_at_*` remain `NULL`; no Oban job.
5. Redirect to `/posts/:id`. Flash: "Draft saved."

### Publishing an existing draft

1–2. Same as above.
3. Author clicks **Publish…** — modal appears.
4. Author clicks **Publish** in modal.
5. `publish_local_post` called — `publish_draft_post_changeset` runs; all three `published_at_*` fields set; Oban job enqueued with type `"Create"`.
6. Redirect to `/posts/:id/YYYY/MM/DD/:slug`. Flash: "Post published."

---

## Key Design Decisions

### All-or-nothing `published_at_*` fields

The pre-existing `published_complete` CHECK constraint enforces that the three temporal fields are either all `NULL` or all non-`NULL`. Draft state = all `NULL`. Published state = all non-`NULL`. There is no intermediate state.

### Separate changeset paths for draft vs. published updates

`update_post_changeset` (used for editing published posts) casts and validates `published_tz` for owners, which calls `rezone_published_at`. Calling it on a draft (with `published_at_utc: nil`) would crash. The fix is twofold: `do_save_post` uses `update_draft_post` → `draft_post_changeset` for unpublished posts (which never touches `published_tz`), and `rezone_published_at` also guards against `nil` `published_at_utc` as a defensive measure.

### `get_local_post/1` has no published filter

Every other public-facing post query applies `published_posts()`. `get_local_post/1` intentionally does not — the author must be able to load their own draft at `/posts/:id/edit`.

### `publish_local_post` enqueues `"Create"`, not `"Update"`

A draft's first publish is its first public activity. The delivery type is `"Create"` so followers receive an `Activity{type: "Create"}` as they would for any new post — not an update notification for something they have never seen.

### Timezone pre-fill on the edit form

The `Timezone` JS hook fires `set_timezone` on mount. On the new post form this was already handled. On the edit form it was previously ignored (no handler). For drafts, the form needs a timezone value so the author can publish — the handler now updates the form when the draft's `published_tz` is `nil`. For published posts the handler is a no-op (two-clause private function).

---

## What Was Not Changed

- `update_post_changeset/3` — unchanged; still used for editing published posts.
- `get_local_post/1` — no published filter (intentional; see above).
- `Entry.create_changeset` family for checkins — unaffected.
- ActivityPub outbox — drafts are excluded automatically because no Oban job is enqueued on draft save and `get_recent_posts` filters to published only.
- Atom feed — already queries `get_recent_posts`; inherits the `published_posts()` filter with no additional change.
- GeoJSON format — draft show page rendering to author is unchanged; the `?_format=geo` path does not reach the nil guard clause.

---

## Test Coverage

- `test/revix/entries/entry_test.exs` — `draft_post_changeset/3`, `publish_post_changeset/3`, `publish_draft_post_changeset/3`, `update_post_changeset/3` (`rezone_published_at` branches including nil UTC guard and invalid-timezone guard)
- `test/support/fixtures/entries_fixtures.ex` — `draft_post_fixture/1`
- `test/revix_web/live/post_new_live_test.exs` — save as draft (nil published_at, no Oban job), publish flow (modal, cancel, confirm, missing timezone error)
- `test/revix_web/live/post_edit_live_test.exs` — `set_timezone` event (draft with no stored timezone, published post no-op), save as draft (content updated, published_at remains nil, owner with timezone in params does not crash), publish flow (modal, cancel, confirm, enqueues Create job, missing timezone error), published post shows Save Changes only
- `test/revix_web/controllers/post_controller_test.exs` — anonymous sees no drafts in index, author sees own drafts with badge, other person sees no drafts; draft show 404 to anonymous and other person, renders to author
