# Activity Feed Improvements

**Date:** 2026-05-19  
**Branch:** next/13

---

## Overview

The home page and person profile page activity feeds were rewritten from static controller-rendered HTML to real-time LiveViews. Likes and comments are now grouped by target object — multiple people liking or commenting on the same checkin collapse into a single row with an avatar group and the latest timestamp. Unauthenticated visitors no longer see replies or remote-origin likes. Author name links were removed from all activity types in favour of avatar-only subjects.

---

## Requirements

- **Unauthenticated users** do not see replies (notes whose parent is another note) or remote-origin likes.
- **Authenticated users** receive live feed updates via PubSub without a full page reload.
- **All users** see likes on the same checkin/post grouped into one row, and comments/replies on the same checkin/post grouped into one row.
- Each group shows an overlapping avatar group (up to 3, with a +N overflow bubble) and the timestamp of the latest activity in the group.
- Author names are not displayed in the feed — the linked avatars (with hover `title` text) provide the subject.
- The map on the home and person profile pages must not blank out when LiveView re-renders the feed.
- GeoJSON format for the home page is still supported.

---

## Architecture

### `lib/revix/activity_feed.ex` (new)

Central module that owns feed assembly and activity grouping.

| Function | Purpose |
|---|---|
| `build_feed_activities/2` | Assembles the home feed for a given scope and limit — checkins, posts, likes, comments, drafts — then groups and sorts |
| `build_person_activities/3` | Same for a single person's profile feed |
| `group_activities/1` | Partitions `{:like, _}` and `{:comment, _}` tuples, groups likes by `object_uri` and comments by root URI, merges back, sorts by timestamp desc |
| `comment_root_uri/1` | Walks the `in_reply_to` chain to find the URI of the root non-note entry (checkin or post) |
| `comment_root/1` | Same walk, returns the struct instead of the URI |

`comment_root_uri/1` deliberately walks the `in_reply_to` chain rather than using the `context` field. Federated threads frequently return with a different `context` URI than expected; the `in_reply_to` chain is authoritative.

**Grouped like struct:**
```
%{object, object_uri, authors, latest_at, latest_published_at_local, latest_published_tz, count}
```

**Grouped comment struct:**
```
%{root, root_uri, authors, latest_at, latest_published_at_local, latest_published_tz, latest_comment_id, count}
```

### `lib/revix/entries.ex`

New and modified functions:

| Function | Change |
|---|---|
| `get_recent_comments_for_feed/2` | New — like `get_recent_comments` but accepts `include_replies: bool`; filters at DB level via left-join |
| `get_recent_comments_for_person_feed/2` | New — same with author filter |
| `get_comment_for_feed/1` | New — fetches a single comment with deep preloads for LiveView re-fetch after broadcast |
| `subscribe_to_feed/0` | New — subscribes to the `"feed"` PubSub topic |
| `broadcast_feed/1` (private) | New — broadcasts to `"feed"` topic |
| `create_local_checkin/5` | Now broadcasts `{:checkin_created, checkin}` to `"feed"` after insert |
| `create_comment/5` | Now broadcasts `{:comment_created, comment}` to `"feed"` after insert |
| `create_reply/5` | Now broadcasts `{:comment_created, reply}` to `"feed"` after insert |
| `maybe_enqueue_post_delivery/2` | Broadcasts `{:post_created, post}` to `"feed"` in the `:publish` branch |
| `with_comment_preloads/1` (private) | Deepened to two levels: `in_reply_to: [:author, :place, in_reply_to: [:author, :place]]` — supports reply→comment→checkin chain walking |

`maybe_exclude_replies/2` performs the reply filter with a left-join on `Entry`:
```elixir
join(query, :left, [e], parent in Entry, on: parent.uri == e.in_reply_to_uri)
|> where([e, parent], is_nil(parent.id) or parent.type != :note)
```
This is done at the database level, not in Elixir, for efficiency.

### `lib/revix/likes.ex`

| Function | Change |
|---|---|
| `get_like_with_object/1` | New — fetches a like with preloads and object enrichment; used by LiveViews after broadcast |
| `do_like_entry/3` | Now broadcasts `{:like_created, like}` to `"feed"` via `tap_ok` |

### `lib/revix/workers/process_inbound_like_worker.ex`

After a successful `upsert_inbound_like`, also calls `broadcast_feed_like/1` which broadcasts `{:like_created, like}` on the `"feed"` topic, enabling the home feed LiveView to pick up remote likes for authenticated users.

### `lib/revix/workers/process_inbound_create_note_worker.ex`

`broadcast_note/1` extended to broadcast on `"feed"` in addition to `"context:#{context_uri}"`:
```elixir
defp broadcast_note(%Entry{context: context_uri} = note) when is_binary(context_uri) do
  Phoenix.PubSub.broadcast(Revix.PubSub, "context:#{context_uri}", {:comment_created, note})
  Phoenix.PubSub.broadcast(Revix.PubSub, "feed", {:comment_created, note})
end
```

### `lib/revix_web/live/person_auth.ex`

Added `:load_current_scope` `on_mount` clause for public LiveViews: always continues, assigns `current_scope` (nil for unauthenticated visitors). The `:require_authenticated_person` clause is unchanged.

### `lib/revix_web/live/home_feed_live.ex` (new)

LiveView for the home page. Mounts with `on_mount {RevixWeb.Live.PersonAuth, :load_current_scope}` and subscribes to the `"feed"` topic when connected.

`handle_info` clauses:

| Message | Behaviour |
|---|---|
| `{:checkin_created, checkin}` | Re-fetches full checkin, prepends to feed |
| `{:post_created, post}` | Re-fetches full post, prepends to feed |
| `{:like_created, like}` | Checks `show_like?` (remote likes hidden for unauthenticated); re-fetches with object; merges into existing `like_group` or prepends new group |
| `{:comment_created, comment}` | Checks `show_comment?` (replies hidden for unauthenticated); re-fetches with deep preloads; merges into existing `comment_group` or prepends new group |

All broadcast payloads carry only `:author` preloaded (or none for inbound workers). The LiveView always re-fetches the full struct from the DB before using it — the broadcast is a signal, not a payload.

`merge_like/2` and `merge_comment/2` find the existing group in the activity list by `object_uri` / `root_uri`, update it in place (deduplicating authors with `Enum.uniq_by/2`; `count` is recomputed as `length(deduped)` to stay in sync after deduplication), then re-run `group_activities` + `Enum.take` to maintain sort order.

`show_comment?` defaults to hidden (`false`) for unauthenticated users when the parent is not preloaded, avoiding spurious DB round-trips for replies.

### `lib/revix_web/live/home_feed_live.html.heex` (new)

Same structure as the previous `home.html.heex` controller template, with `<.map geo_url="/home.geo" />`.

### `lib/revix_web/live/person_feed_live.ex` (new)

LiveView for person profile pages. Mounted via `live_render` from `PersonController` with `session: %{"person_id" => person.id}`.

Same `handle_info` / `merge_*` pattern as `HomeFeedLive`, with an additional filter: events are only processed when `author_uri == socket.assigns.person.uri` (checkins, posts, comments, likes all authored by the profile subject).

### `lib/revix_web/live/person_feed_live.html.heex` (new)

Renders the person's display name as the page header and `<.map />` using the default `?geo` URL.

### `lib/revix_web/components/activity_components.ex`

- `activity_feed/1` gains `{:like_group, group}` and `{:comment_group, group}` cases.
- `like_group_activity/1` — avatar group + heart icon + "liked [place name or 'a checkin']" + timestamp.
- `comment_group_activity/1` — avatar group + "commented on [place name or 'a checkin']" + timestamp.
- `avatar_group/1` — renders up to 3 overlapping avatars (negative space via `-space-x-2`) with a +N bubble for overflow.
- `activity_author/1` — **removed**. Author name links were removed from all activity types (`checkin`, `post`, `draft`, `like`, `comment`). The linked avatar with its `title` attribute provides the subject.

### `lib/revix_web/components/core_components.ex`

`map/1` component updated:
- Added `phx-update="ignore"` and `id="map"` to prevent LiveView from patching the element — this preserves the Leaflet instance across feed re-renders.
- Added `geo_url` attr (default `"?geo"`); rendered as `data-geo-url` for JS to read.

### `assets/js/app.js`

Map initialisation now reads `mapElement.dataset.geoUrl || "?geo"` instead of the hardcoded `"?geo"` string, so the home page map can use `/home.geo` while person pages continue using `?geo`.

### `lib/revix_web/router.ex`

```elixir
live_session :public,
  on_mount: [{RevixWeb.Live.PersonAuth, :load_current_scope}] do
  live "/", HomeFeedLive, :index
end

get "/home.geo", PageController, :home
```

GeoJSON for the home page moved from `GET /` (format-negotiated) to `GET /home.geo`. This avoids a routing conflict — `live "/"` intercepts all HTML and WebSocket requests to `/`, so `?_format=geo` format negotiation no longer works there.

### `lib/revix_web/controllers/page_controller.ex`

Stripped to a single `home/2` action that serves the GeoJSON feature collection at `/home.geo`. All HTML activity-building logic removed.

### `lib/revix_web/controllers/person_controller.ex`

The HTML rendering clause now delegates to `LiveView.Controller.live_render`:
```elixir
defp show_by_format(conn, person, _username, _format) do
  Phoenix.LiveView.Controller.live_render(conn, RevixWeb.PersonFeedLive,
    session: %{"person_id" => person.id}
  )
end
```
`person_activities/2` and `get_person_drafts/2` removed (replaced by `ActivityFeed.build_person_activities/3`).

---

## Key Design Decisions

### Walk `in_reply_to`, not `context`

Federated replies often arrive with a different `context` URI than the original thread's root. Grouping by `context` would scatter related comments into separate rows. Walking the `in_reply_to` chain is the only reliable way to find the shared checkin or post root. The two-level preload depth covers the common cases: comment→checkin (1 hop) and reply→comment→checkin (2 hops).

### Broadcast as signal, re-fetch for payload

`create_comment`, `create_reply`, `do_like_entry`, and the inbound workers broadcast structs with minimal preloads (at most `:author`). Both LiveViews re-fetch the full struct from the DB on receipt. This avoids broadcasting large, heavily preloaded structs over PubSub while guaranteeing the LiveView always has complete data.

### `count` tracks `length(authors)` in live updates

In `merge_like` and `merge_comment`, `count` is recomputed as `length(deduped_authors)` rather than incremented. This prevents drift if the same broadcast arrives twice (e.g. a worker retry) — the author list is deduplicated by `Enum.uniq_by/2` and `count` stays consistent with it. `count` is built accurately from `length(sorted)` in the initial `group_activities/1` pass.

### No author names in feed rows

Author names were removed from all activity components. The linked avatar with its `title` attribute (set to the person's display name or username) supplies the authorship information without cluttering the row text. This is consistent across single-person rows (`checkin`, `post`, `like`) and group rows (`like_group`, `comment_group`).

### GeoJSON at `/home.geo`

Phoenix's `live "/"` route intercepts all requests to `/` for HTML and WebSocket negotiation, making `?_format=geo` format negotiation unreliable. Moving the GeoJSON endpoint to a dedicated path is the cleanest resolution.

---

## What Was Not Changed

- `get_recent_comments/1` — unchanged; still used by non-feed surfaces.
- `get_recent_comments_for_person/2` — unchanged.
- Person GeoJSON (`?_format=geo` on `/@username`) — unaffected; served by `PersonController`.
- ActivityPub person format — unaffected.
- Checkin, post, note show pages — unaffected.
- Atom feed — unaffected.
- Comment section LiveView — unaffected.

---

## Test Coverage

- `test/revix/activity_feed_test.exs` (new) — `group_activities/1` (empty, single like, two likes same object, two likes different objects, `latest_at` ordering, single comment, two comments same checkin, two comments different checkins, comment `latest_at`, reply grouped under checkin root, mixed activities); `build_feed_activities/2` (unauthenticated includes local checkins, hides remote likes, authenticated includes remote likes, excludes replies for unauthenticated, includes and groups replies for authenticated, groups multiple likes, groups multiple comments); `build_person_activities/3` (only person's own activities, excludes replies for unauthenticated, includes and groups replies for matching scope, groups person's likes, groups person's comments)
- `test/revix_web/live/home_feed_live_test.exs` (new) — initial render (home page, empty feed, checkin with place and verb, author display name in avatar title, date and timezone, author profile link, checkin URL, no place fallback, unresolvable-author checkin still renders); like activity (verb and icon, place name, 'a checkin' fallback, grouping, remote like hidden for unauthenticated, remote like shown for authenticated, date and timezone); comment activity (verb, author name, place link, 'a checkin' fallback, replies hidden for unauthenticated, reply grouped with comment for authenticated, two comments grouped); live updates (prepend new checkin, remote like not prepended for unauthenticated, authenticated like updates group, authenticated second comment merges into group)
- `test/revix_web/live/person_feed_live_test.exs` (new) — basic rendering (renders page, redirects to @username, 404 for unknown id, display name in header); person activity (checkins, likes, comments, other people's activity hidden, likes on same object grouped, comments on same checkin grouped); reply visibility (hidden for unauthenticated, grouped with parent for authenticated own profile); ActivityPub and GeoJSON formats; live updates (new checkin by person, checkin by other person ignored, like updates feed, second comment merges into group)
- `test/revix_web/controllers/page_controller_test.exs` — stripped to GeoJSON tests at `/home.geo`
