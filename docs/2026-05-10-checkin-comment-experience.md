# Checkin Comment Experience — 2026-05-10

**Branch:** topics/comment-replies  
**Scope:** Live threaded comments with replies and likes on checkin show pages; activity feed improvements; `/notes/:id` redirect bug fix.

---

## Summary

Replaces the static server-rendered comment section on checkin show pages with an embedded Phoenix LiveView (`CommentSectionLive`). Authenticated users get a fully interactive experience — submit comments, reply to any depth, like/unlike comments, edit and delete their own comments, and receive real-time updates from other users via PubSub — without a page reload. Unauthenticated users see a static stack of commenter avatars.

The checkin like section (`#like-section`) is similarly converted to an embedded LiveView (`CheckinLikeLive`), replacing the previous JavaScript/JSON-API approach. This eliminates `like.js` entirely.

A bug in `NoteController` is fixed: visiting `/notes/:id` for a reply-to-reply now always redirects to the original checkin, regardless of how deep the reply chain is, by using the `context` field on the entry rather than walking `in_reply_to`.

The activity feed is updated to distinguish "commented on" from "replied to a comment" and "liked a checkin" from "liked a comment", with correct links for all cases.

The full Elixir suite (779 tests) and JS suite (35 tests) pass at 0 failures.

---

## Architecture: Embedded LiveViews

Phoenix `live_render/3` embeds a LiveView inside a controller-rendered page. The checkin show page stays a static controller action; two LiveViews are embedded inside it:

- **`CommentSectionLive`** — full comment thread with real-time updates.
- **`CheckinLikeLive`** — live like button and liker avatar stack.

Both receive their session data (`checkin_uri`, `person_token`, `checkin_author_uri`) via the `session:` option and derive `current_scope` from the person token. Both subscribe to the same PubSub topic (`"context:#{checkin_uri}"`) when connected.

---

## New Files

### `lib/revix_web/live/comment_section_live.ex`

Embedded LiveView for the comment thread.

**Session keys:** `checkin_uri`, `person_token`.

**Assigns:**

| Assign | Purpose |
|---|---|
| `checkin_uri` | Root checkin URI; used for PubSub topic and queries |
| `current_scope` | Derived from person token; `nil` for unauthenticated |
| `comment_tree` | `[{comment, [reply, ...]}]` from `Entries.get_comment_tree/1` |
| `liked_uris` | `MapSet` of comment URIs liked by the current person |
| `like_counts` | `%{comment_uri => count}` for display |
| `liker_map` | `%{comment_uri => [like, ...]}` for avatar display |
| `reply_to_id` | Comment ID currently being replied to, or `nil` |
| `editing_id` | Comment ID currently being edited, or `nil` |
| `timezone` | IANA timezone string injected from the browser via `phx-hook="Timezone"` |

**Events handled:** `submit_comment`, `submit_reply`, `like_comment`, `unlike_comment`, `reply_to`, `cancel_reply`, `edit_comment`, `cancel_edit`, `update_comment`, `delete_comment`, `set_timezone`.

**PubSub messages handled:** `{:comment_created, comment}`, `{:comment_updated, comment}`, `{:comment_deleted, comment_id}`, `{:entry_liked, object_uri, liker_uri}`, `{:entry_unliked, object_uri, liker_uri}`.

Private component `comment_row/1` renders a single comment: author avatar, display name, timestamp, content, and an action row with a Like/Unlike button (with up to 3 liker avatars), a Reply button, and (for the comment's own author) Edit and Delete buttons. When `editing_id` matches the comment, an inline textarea form replaces the content.

Private component `reply_form/1` renders the inline reply textarea form.

**File:** [lib/revix_web/live/comment_section_live.ex](lib/revix_web/live/comment_section_live.ex)

---

### `lib/revix_web/live/comment_section_live.html.heex`

Template for `CommentSectionLive`.

- Each top-level comment renders in a `div#comment-{id}` with a left border.
- Replies render indented below their parent in a `div#comment-{reply_id}`. Visual indent is capped at two levels; deeper replies exist in the database but render at the second indent level.
- Unauthenticated view: if there are any comments, renders a horizontal stack of unique commenter avatars (up to 8). No form.
- Authenticated view: comment form below the thread. Reply and edit forms appear inline.

**File:** [lib/revix_web/live/comment_section_live.html.heex](lib/revix_web/live/comment_section_live.html.heex)

---

### `lib/revix_web/live/checkin_like_live.ex`

Embedded LiveView for the checkin like button and liker avatars.

**Session keys:** `checkin_uri`, `checkin_author_uri`, `person_token`.

**Assigns:** `checkin_uri`, `checkin_author_uri`, `current_scope`, `likes`, `liked`, `can_like`, `timezone`.

**Events:** `like` (calls `Likes.like_entry/4` with context broadcast), `unlike` (calls `Likes.unlike_entry/3`), `set_timezone`.

**PubSub:** subscribes to `"context:#{checkin_uri}"` via `Entries.subscribe_to_context/1`. Handles `{:entry_liked, ^checkin_uri, _}` and `{:entry_unliked, ^checkin_uri, _}`; ignores all other messages (comment events on the same topic).

**File:** [lib/revix_web/live/checkin_like_live.ex](lib/revix_web/live/checkin_like_live.ex)

---

### `lib/revix_web/live/checkin_like_live.html.heex`

Renders the liker avatar stack unconditionally and, for authenticated non-authors, a Like/Unlike button styled with `btn btn-soft p-2` and a heart icon. Unauthenticated users see only the avatars.

**File:** [lib/revix_web/live/checkin_like_live.html.heex](lib/revix_web/live/checkin_like_live.html.heex)

---

### `test/revix_web/live/comment_section_live_test.exs`

23 tests covering: unauthenticated mount (static avatars, no form), authenticated mount (comment form, Comments heading), `submit_comment`, `submit_reply`, `like_comment`/`unlike_comment`, `edit_comment`/`update_comment`, `delete_comment`, authorization (cannot edit/delete others' comments), and real-time PubSub updates.

Uses `live_isolated/3` with explicit `Ecto.Adapters.SQL.Sandbox.allow/3` and an `on_exit` monitor+kill pattern to prevent Postgrex disconnect errors from PubSub-triggered `handle_info` DB queries racing with sandbox cleanup.

**File:** [test/revix_web/live/comment_section_live_test.exs](test/revix_web/live/comment_section_live_test.exs)

---

### `test/revix_web/live/checkin_like_live_test.exs`

14 tests covering: unauthenticated mount (avatars, no button), authenticated non-author (Like button), author (disabled button), `like` event, `unlike` event, and real-time PubSub updates.

**File:** [test/revix_web/live/checkin_like_live_test.exs](test/revix_web/live/checkin_like_live_test.exs)

---

## Modified Files

### `lib/revix/entries.ex`

Added:

**`create_reply/5`** — creates a reply to any comment or reply. Sets `in_reply_to_uri: parent.uri` and `context: parent.context` (always the root checkin URI, regardless of depth). Broadcasts `{:comment_created, reply}` on `"context:#{context_uri}"`.

**`get_comment_tree/1`** — fetches all notes for a checkin in one query (`where context == checkin_uri and type == :note and origin == :local`), then builds a `[{comment, [reply, ...]}]` tree in Elixir by grouping on `in_reply_to_uri`. Top-level entries are those whose `in_reply_to_uri == checkin_uri`. All entries have `:author` preloaded.

**`subscribe_to_context/1`** — `Phoenix.PubSub.subscribe(Revix.PubSub, "context:#{uri}")`.

**`get_comment/1`** — fetches a single note by ID; returns `{:ok, entry}` or `{:error, :not_found}`.

**`update_comment/2`** — updates a comment's content and broadcasts `{:comment_updated, updated}`.

**`delete_comment/1`** — deletes a comment and broadcasts `{:comment_deleted, comment.id}`.

**`comment_max_length/1`** — returns the configured character limit (or `nil` for owners).

PubSub broadcasts for create/update/delete use the private `broadcast_context/2` helper: `Phoenix.PubSub.broadcast(Revix.PubSub, "context:#{context_uri}", event)`.

**File:** [lib/revix/entries.ex](lib/revix/entries.ex)

---

### `lib/revix/likes.ex`

Added:

**`like_entry/4`** (with `context_uri`) — delegates to `like_entry/3` then broadcasts `{:entry_liked, object_uri, person_uri}` on `"context:#{context_uri}"`.

**`unlike_entry/3`** (with `context_uri`) — delegates to `unlike_entry/2` then broadcasts `{:entry_unliked, object_uri, person_uri}`.

**`get_active_likes_by_object_uris/1`** — batch-fetches all active likes for a list of URIs in one query; returns `%{object_uri => [like, ...]}` with `:author` preloaded. Used by `CommentSectionLive` to show liker avatars on comment like buttons without N+1 queries.

**File:** [lib/revix/likes.ex](lib/revix/likes.ex)

---

### `lib/revix_web/controllers/note_controller.ex`

**Bug fix — `show/2`:** Previously used `note.in_reply_to` (the immediate parent) as the checkin. For a reply-to-reply this is another note, not a checkin. Now uses `Entries.get_entry_by_uri(note.context)` to always resolve the root checkin regardless of reply depth.

**Bug fix — `create/2`:** The `:note` branch previously walked `parent.in_reply_to.in_reply_to` to find the checkin, which broke for deeper chains. Now uses a private `get_context_checkin/1` helper that resolves from `parent.context` for notes and returns the checkin directly for checkins.

Added private `get_context_checkin/1`:
- `%{type: :note, context: uri}` → `Entries.get_entry_by_uri(uri)`
- Checkin → `{:ok, checkin}`

**File:** [lib/revix_web/controllers/note_controller.ex](lib/revix_web/controllers/note_controller.ex)

---

### `lib/revix_web/controllers/checkin_controller.ex`

Removed `likes`, `liked`, and `can_like` assigns from `show_by_format/6` — these are now loaded by `CheckinLikeLive`. The `Likes` alias is retained for the index action (`count_active_likes_by_object_uris`).

**File:** [lib/revix_web/controllers/checkin_controller.ex](lib/revix_web/controllers/checkin_controller.ex)

---

### `lib/revix_web/controllers/checkin_html/show.html.heex`

Replaced the static `<div id="like-section">` block (button + JS-driven avatar list) with `live_render(@conn, RevixWeb.CheckinLikeLive, ...)`.

Replaced the static comments block with `live_render(@conn, RevixWeb.CommentSectionLive, ...)`.

**File:** [lib/revix_web/controllers/checkin_html/show.html.heex](lib/revix_web/controllers/checkin_html/show.html.heex)

---

### `lib/revix_web/components/activity_components.ex`

**`comment_activity/1`:** Inspects `in_reply_to.type` to distinguish two cases:
- `:checkin` → "commented on [place name]" with a link to `#{checkin.url}#comment-#{id}`.
- `:note` (or nil) → "replied to [a comment](note_url)" — links via the note's own URL, which redirects to the correct checkin anchor.

**`like_activity/1`:** Inspects `object.type`:
- `:note` → "liked [a comment](note_url)" — links via the note's own URL.
- `:checkin` → existing "liked [place name]" with a link to the checkin.

**File:** [lib/revix_web/components/activity_components.ex](lib/revix_web/components/activity_components.ex)

---

### `assets/js/like.js` and `assets/js/like.test.js`

Deleted. `CheckinLikeLive` replaces all functionality previously handled by `initLikeButtons()`. The import and `DOMContentLoaded` listener are removed from `assets/js/app.js`.

---

### `test/support/fixtures/entries_fixtures.ex`

Added `reply_fixture/3` — calls `Entries.create_reply/5` with a synthetic URI function.

**File:** [test/support/fixtures/entries_fixtures.ex](test/support/fixtures/entries_fixtures.ex)

---

### `test/revix_web/controllers/note_controller_test.exs`

Added tests for the `show/2` and `create/2` redirect fix:

- `GET /notes/:id` for a direct reply — redirects to the original checkin with correct anchor.
- `GET /notes/:id` for a reply-to-reply — redirects to the original checkin (not to a `/notes/` URL).
- `POST /notes` with a comment URI as `in_reply_to_uri` — redirects to the original checkin.
- `POST /notes` with a reply URI as `in_reply_to_uri` — redirects to the original checkin (not to a `/notes/` URL).

**File:** [test/revix_web/controllers/note_controller_test.exs](test/revix_web/controllers/note_controller_test.exs)

---

### `CLAUDE.md`

Added a **LiveView Test Sandbox / Postgrex Disconnect Errors** section documenting the two-part fix pattern: `on_exit` monitor+kill for the LiveView process and `render(lv)` after events that trigger PubSub broadcasts.

---

## Key Invariants

**`context` field:** Every note (comment or reply at any depth) has `context` set to the root checkin URI at creation time. `create_reply/5` copies `parent.context`, so the field propagates correctly regardless of chain depth. This is the single source of truth for "which checkin does this note belong to?"

**PubSub topic:** Both `Entries` (comment events) and `Likes` (like/unlike events) broadcast on `"context:#{checkin_uri}"`. Both embedded LiveViews subscribe to this same topic via `Entries.subscribe_to_context/1`. `CheckinLikeLive` filters to only the `checkin_uri` match-guarded clauses; `CommentSectionLive` handles all event types.

**Reply anchors:** All comment and reply `<div>` elements in `comment_section_live.html.heex` carry `id="comment-{id}"`. This is what the `/notes/:id` redirect points at.

---

## What Was Not Changed

- `NoteController.update/2` and `delete/2` — still return JSON; used as a fallback path (LiveView handles mutations for authenticated users).
- Router — no new routes added.
- `LikeController` — no changes; still handles JSON likes for the checkin index page (`count_active_likes_by_object_uris`).
- `FeedController`, `WebfingerController`, `NodeInfoController`, `InboxController` — unaffected.
- Existing checkin create/edit flows — unaffected.
