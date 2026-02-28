# Code Review – 2026-02-27

Scope: full codebase review covering domain contexts, web layer, and tests.
Focus areas: DRY/SOLID/SRP, idiomatic Elixir, test coverage, comment hygiene, style consistency, and security.

---

## Summary

The codebase is in good shape overall. Contexts are well-separated, query helpers are composed cleanly, and test coverage is thorough for most contexts. The issues below are real but mostly modest — there are no architectural problems, just a handful of recurring patterns worth tidying.

---

## 1. DRY Violations

### 1a. `consume_uploads/3,4` duplicated across LiveViews

`CheckinNewLive` and `CheckinEditLive` both contain a nearly-identical `consume_uploads` private function (~40 lines each) that builds a `position_map`, calls `consume_uploaded_entries`, creates `Plug.Upload`, calls `Media.create_image`, attaches the image, and writes caption/alt metadata. The only difference is an optional `start_position` offset in the edit flow.

**Files:** [lib/revix_web/live/checkin_new_live.ex:316-371](lib/revix_web/live/checkin_new_live.ex#L316-L371), [lib/revix_web/live/checkin_edit_live.ex:281-337](lib/revix_web/live/checkin_edit_live.ex#L281-L337)

The logic belongs in a shared module (e.g., `RevixWeb.Live.UploadHelpers`) or, since it requires the socket, as a `use`-able concern.

### 1b. `search_companions` handler duplicated across LiveViews

Both `CheckinNewLive` and `CheckinEditLive` have identical `handle_event("search_companions", ...)` implementations (12 lines each), including the `People.search_people` call, the `Enum.map` to a normalized shape, and the `CanonicalRoutes.avatar_url` call.

**Files:** [lib/revix_web/live/checkin_new_live.ex:101-119](lib/revix_web/live/checkin_new_live.ex#L101-L119), [lib/revix_web/live/checkin_edit_live.ex:61-79](lib/revix_web/live/checkin_edit_live.ex#L61-L79)

### 1c. `normalize_companion/1` only in `CheckinEditLive`; `CheckinNewLive` inlines the same map

`CheckinEditLive` defines a `normalize_companion/1` private function. `CheckinNewLive` inlines the exact same `%{uri, display_name, username, avatar_url}` map construction in `handle_event("search_companions")`. The definition should be shared.

**Files:** [lib/revix_web/live/checkin_edit_live.ex:345-354](lib/revix_web/live/checkin_edit_live.ex#L345-L354), [lib/revix_web/live/checkin_new_live.ex:107-113](lib/revix_web/live/checkin_new_live.ex#L107-L113)

### 1d. `maybe_limit/2` defined in both `Entries` and `Likes`

The identical two-clause function appears in both context modules.

**Files:** [lib/revix/entries.ex:286-288](lib/revix/entries.ex#L286-L288), [lib/revix/likes.ex:175-176](lib/revix/likes.ex#L175-L176)

Could live in a shared `Revix.Query` helper module, or simply be accepted as intentional co-location (it is truly trivial).

### 1e. `*_ok_or_not_found` helpers repeated in every context

`entry_ok_or_not_found/1`, `place_ok_or_not_found/1`, and `person_ok_or_not_found/1` are each defined inline in their respective context modules, all doing the same two-clause pattern match. This is a good candidate for a single `Revix.Context.ok_or_not_found/1` helper.

### 1f. `comment_max_length` logic duplicated

The logic for deriving `comment_max_length` from `scope.role` and `Application.get_env` is repeated verbatim in `Entries.create_comment/3` and `CheckinController.show_by_format/7`.

**Files:** [lib/revix/entries.ex:135-139](lib/revix/entries.ex#L135-L139), [lib/revix_web/controllers/checkin_controller.ex:82-85](lib/revix_web/controllers/checkin_controller.ex#L82-L85)

### 1g. `update_caption` and `update_alt` handlers in `CheckinEditLive` have identical structure

The two handlers differ only in which key (`caption` vs `alt`) they update, and which map (`image_captions` vs `upload_captions`) they dispatch to. They could be merged into a single `handle_event("update_photo_meta", ...)` with a `field` parameter, or extracted into a shared private helper.

**Files:** [lib/revix_web/live/checkin_edit_live.ex:149-208](lib/revix_web/live/checkin_edit_live.ex#L149-L208)

---

## 2. SRP / Responsibility Concerns

### 2a. `CheckinNewLive` is very large

At ~377 lines, the module handles: geolocation, place search, place creation, companion search, companion management, image uploads, caption/alt editing, image reordering, and checkin submission. It mixes UI interaction concerns with non-trivial business logic (e.g., `resolve_place/4`, position_map computation).

The `resolve_place/4` private function is the cleanest candidate to move to the `Places` context (it only calls `Places` functions and performs no socket work). The `consume_uploads` logic similarly has no socket dependency except for `consume_uploaded_entries`, so it could be extracted.

### 2b. `Entries.create_comment/3` builds its own URL

`create_comment/3` hardcodes `base_url = RevixWeb.Endpoint.url()` and composes the note URI/URL from it.

**File:** [lib/revix/entries.ex:133-134](lib/revix/entries.ex#L133-L134)

This is the only place in a domain context where `RevixWeb.Endpoint` is referenced directly. All other entry/place creation functions correctly accept `uri_fn` and `url_fn` callbacks to avoid the domain knowing about the web layer. `create_comment` should follow the same pattern.

### 2c. `Person.maybe_generate_required_fields/3` calls `RevixWeb.CanonicalRoutes`

The `Person` schema calls `RevixWeb.CanonicalRoutes.person_uri/1` and `RevixWeb.CanonicalRoutes.person_url/2` when generating IDs for new registrations.

**File:** [lib/revix/people/person.ex:84-85](lib/revix/people/person.ex#L84-L85)

The comment `# FIXME: Heinous kludges follow!` acknowledges this. Like `create_comment`, `register_person` should accept uri/url callbacks, or the URI generation should be pushed to the caller. This is the more invasive issue because it's in the schema layer.

### 2d. `Media.remove_image_from_entry/2` is doing too much

The function performs a delete, then conditionally checks orphan status, then conditionally fetches the image and deletes it. This is imperative, multi-step logic with side effects scattered through `if` branches. It would be cleaner split into `detach_image/2` (removes the join record) and a separate `maybe_delete_orphaned_image/1`, called explicitly by the context or a transaction.

**File:** [lib/revix/media.ex:61-90](lib/revix/media.ex#L61-L90)

---

## 3. Security Concerns

### 3a. File type validation relies solely on extension

`Revix.Uploaders.Image.validate/1` (and by implication `Avatar`) checks only the file extension:

```elixir
file_extension = file.file_name |> Path.extname() |> String.downcase()
Enum.member?(~w(.jpg .jpeg .gif .png .webp), file_extension)
```

**File:** [lib/revix/uploaders/image.ex:7-13](lib/revix/uploaders/image.ex#L7-L13)

Extension-only validation is bypassable: an attacker can rename `malicious.exe` to `malicious.jpg`. The file's actual content (magic bytes / MIME sniffing) is never checked. ImageMagick's `convert` transform will fail for non-images, which provides a partial mitigation, but the `:original` version is stored without any transformation (`transform(:original, _) -> :noaction`), meaning the raw uploaded file — which could be non-image content — is persisted to S3 as-is. Recommend adding MIME type detection on the raw bytes (e.g. with `ExImageInfo` or `:magic` bindings) before accepting uploads.

### 3b. OSM result data is used without validation before DB insert

When a user selects an OSM search result, `resolve_place(:selected, %{source: :osm})` constructs attrs directly from the result map and passes them to `Places.create_local_place`. The `name`, `lat`, `lon`, `osm_type`, and `osm_id` values come from an HTTP response via `Revix.Overpass`. While the changeset does validate numeric ranges for lat/lon and the OSM ID goes through an Ecto cast, `name` is a free-text field with no length limit enforced in the changeset.

**File:** [lib/revix_web/live/checkin_new_live.ex:277-293](lib/revix_web/live/checkin_new_live.ex#L277-L293)

An attacker who can influence the Overpass response (or who intercepts it) could insert arbitrarily long place names. `Place.create_changeset` should add `validate_length(:name, max: N)`.

### 3c. `redirect_if_person_is_authenticated` checks `current_scope` truthiness, not `scope.person`

```elixir
def redirect_if_person_is_authenticated(conn, _opts) do
  if conn.assigns.current_scope do   # ← always truthy; nil scope is replaced with Scope.for_person(nil)
```

**File:** [lib/revix_web/person_auth.ex:188](lib/revix_web/person_auth.ex#L188)

`fetch_current_scope_for_person` assigns `Scope.for_person(nil)` (a non-nil struct) for unauthenticated visitors. So `conn.assigns.current_scope` is **never** `nil` in practice, meaning this check always redirects — even unauthenticated users are redirected away from the registration page. In practice the registration page seems reachable, so either `Scope.for_person(nil)` is falsy (worth verifying) or this branch is never hit. Either way, the condition should explicitly be `conn.assigns.current_scope && conn.assigns.current_scope.person` to be consistent with `require_authenticated_person` and to make the intent unambiguous.

### 3d. `search_nearby_places/3` calls Overpass synchronously in the same request

**File:** [lib/revix/places.ex:88-99](lib/revix/places.ex#L88-L99)

The synchronous `search_nearby_places/3` function (which is separate from the LiveView's async `search_nearby_osm` path) blocks for up to 30 seconds waiting for Overpass. If Overpass is slow or down, any caller of this function will hang for the full timeout. The LiveView correctly uses `Task.async` to avoid this, but `search_nearby_places/3` is still a public API that a future caller could invoke synchronously. A clearer API would remove `search_nearby_places/3` entirely and only expose `search_nearby_db` + `search_nearby_osm` (already public) plus `merge_place_results` — which is exactly how the LiveView uses them. The synchronous combined version is an invitation to re-introduce the slow blocking call.

### 3e. `Person.private_key` stored unencrypted in the database

**File:** [lib/revix/people/person.ex:18](lib/revix/people/person.ex#L18)

The RSA private key for federation signing is stored as plaintext in the `people` table. The field is marked `redact: true` (so it won't appear in logs), but the PEM is in the DB. If the database is breached, all private keys are exposed. Consider encrypting at rest using a database-level encrypted column or an application-level encryption library (e.g., `cloak_ecto`).

### 3f. `NoteController` passes raw `params["note"]` to `update_comment`

```elixir
case Entries.update_comment(note, params["note"] || %{})
```

**File:** [lib/revix_web/controllers/note_controller.ex:59](lib/revix_web/controllers/note_controller.ex#L59)

`params["note"]` is untrusted user input, but `update_comment_changeset` only casts `:content`, so only `:content` can be set — this is not directly exploitable today. However, passing the raw params map (which could contain arbitrary keys) instead of extracting only needed keys is a habit that creates risk if the changeset is later broadened. Prefer `Map.take(params["note"] || %{}, ["content"])`.

### 3g. `like_response` and `companions_response` perform extra DB queries after write

Both controller helpers call `get_active_likes_for_entry` and `get_companions_for_entry` after a write to build the JSON response. This means a like/unlike or companion add/remove triggers at minimum 2 DB queries. Not a security issue, but worth noting as a performance concern; the counts and lists could be derived from the write result instead.

---

## 4. Idiomatic Elixir

### 4a. `if/else` instead of pattern matching in changeset private functions

Several changeset helpers use `if changeset.valid?` guards followed by nested `if field do` checks. Idiomatic Ecto changeset pipelines use `validate_change`, `prepare_changes`, or early-return via `changeset.valid?` checked once at the top.

Example in `compute_starts_at_utc/1`:
```elixir
# Current
defp compute_starts_at_utc(changeset) do
  if changeset.valid? do
    local = get_field(changeset, :starts_at_local)
    tz = get_field(changeset, :starts_tz)
    if local && tz do
      ...
    else
      changeset
    end
  else
    changeset
  end
end
```

This can be written as:
```elixir
defp compute_starts_at_utc(%{valid?: false} = changeset), do: changeset
defp compute_starts_at_utc(changeset) do
  case {get_field(changeset, :starts_at_local), get_field(changeset, :starts_tz)} do
    {local, tz} when not is_nil(local) and not is_nil(tz) ->
      put_change(changeset, :starts_at_utc, ...)
    _ ->
      changeset
  end
end
```

The same pattern applies to `set_published_at/1`, `set_comment_published_at/1`, `set_context/1`, and `set_comment_context/1`.

**File:** [lib/revix/entries/entry.ex:120-205](lib/revix/entries/entry.ex#L120-L205)

### 4b. `set_published_at/1` and `set_comment_published_at/1` are near-identical

Both compute `now_utc`, shift to local, and call `put_change` for the same three fields. They differ only in which timezone field they read (`:starts_tz` vs `:published_tz`). A single private `set_published_at(changeset, tz_field)` with a field-name parameter would eliminate the duplication.

**File:** [lib/revix/entries/entry.ex:140-195](lib/revix/entries/entry.ex#L140-L195)

### 4c. `Enum.member?` instead of `in` in validators

Both `Uploaders.Image.validate/1` and `Entry.validate_timezone/2` use `Enum.member?/2`. Idiomatic Elixir uses the `in` operator:

```elixir
# Current
case Enum.member?(~w(.jpg .jpeg ...), file_extension) do
  true -> :ok
  false -> {:error, ...}
end

# Idiomatic
if file_extension in ~w(.jpg .jpeg ...), do: :ok, else: {:error, ...}
```

**Files:** [lib/revix/uploaders/image.ex:10](lib/revix/uploaders/image.ex#L10), [lib/revix/entries/entry.ex:99](lib/revix/entries/entry.ex#L99)

### 4d. `backfill_fields/2` uses mutable-style sequential rebinding

`backfill_fields/2` builds a map by conditionally `Map.put`-ing into it across three sequential `if` expressions that rebind `fields`. This reads imperatively. A cleaner Elixir approach would be `Enum.reduce` over the optional fields or a single pipeline:

```elixir
defp backfill_fields(entry, timezone) do
  %{starts_tz: timezone, published_tz: timezone}
  |> maybe_put_local(entry, :starts_at_utc, :starts_at_local, timezone)
  |> maybe_put_local(entry, :published_at_utc, :published_at_local, timezone)
  |> maybe_put_ends(entry, timezone)
end
```

**File:** [lib/revix/entries.ex:259-283](lib/revix/entries.ex#L259-L283)

### 4e. `backfill_timezone/3` uses `unless` with the positive branch in `else`

```elixir
unless timezone in Tzdata.zone_list() do
  {:error, :invalid_timezone}
else
  ...long body...
end
```

`unless/else` with a non-trivial `else` body is an anti-pattern — the intent reads as "if not valid, error; else do the real work." Prefer a guard clause / early return:

```elixir
if timezone not in Tzdata.zone_list() do
  {:error, :invalid_timezone}
else
  ...
end
```

or, better, a two-clause function with a pattern-matched guard.

**File:** [lib/revix/entries.ex:228-252](lib/revix/entries.ex#L228-L252)

### 4f. `add_companion/3` uses `cond` where two-clause pattern matching is more idiomatic

The `cond` in `add_companion` has three branches: self-companion check, auth check, then the real work. Because both guard conditions are pure attribute comparisons, they could be expressed as two-clause functions with guards, keeping `cond` for cases where runtime conditions genuinely differ in nature.

**File:** [lib/revix/entry_people.ex:20-45](lib/revix/entry_people.ex#L20-L45)

### 4g. `to_float/1` in `CheckinNewLive` re-implements `String.to_float`

The helper exists to handle integer, float, or string inputs for coordinates from the browser. The binary branch delegates directly to `String.to_float/1` which raises on bad input. A safer pattern uses `Float.parse/1` with a fallback, or the type coercion can be left to the changeset.

**File:** [lib/revix_web/live/checkin_new_live.ex:374-376](lib/revix_web/live/checkin_new_live.ex#L374-L376)

---

## 5. Test Coverage

### 5a. Well-covered

The following have thorough, well-structured tests:
- `Revix.Entries` — extensive, including edge cases for backfill, preloads, role-based limits
- `Revix.Likes` — all CRUD paths, idempotency, self-like prohibition, object enrichment
- `Revix.Places` — all CRUD, geospatial queries, OSM deduplication
- `Revix.Media` — create, get, attach, remove, orphan cleanup
- `RevixWeb.PersonAuth` — session lifecycle, token reissue
- `RevixWeb.Live.CheckinNewLive` / `CheckinEditLive` — per the testing document

### 5b. No tests for `Revix.EntryPeople` context

The `Revix.EntryPeopleTest` file exists but only tests add/remove companion operations. Missing:
- `get_companions_for_entry/1` — ordering, preloads
- `companion_of?/2` — true, false, nil person_uri
- `count_companions_by_entry_uris/1` — empty list early-return, multi-entry counts

**File:** [test/revix/entry_people_test.exs](test/revix/entry_people_test.exs)

### 5c. No tests for `Revix.Overpass`

`test/revix/overpass_test.exs` exists (confirmed in the Glob). No review of its coverage was possible as it was not read, but the Req.Test mocking pattern is documented in memory as working. Confirm `parse_elements/3` edge cases are covered: missing `name`, unsupported element `type`, missing coordinates, `way`/`relation` with `center` key.

### 5d. No tests for `RevixWeb.Controller.Helpers` (ActivityPub serialization)

The `to_person_activity/1`, `to_place_activity/1`, and `to_checkin_activity/1` functions in `controller_helpers.ex` (the ActivityPub/GeoJSON helpers) have no unit tests. These are pure transformation functions that are easy and valuable to test in isolation, especially given the federation use case.

**File:** [lib/revix_web/controller_helpers.ex](lib/revix_web/controller_helpers.ex)

### 5e. `NoteController` is missing authorization tests

`note_controller_test.exs` presumably exists. Confirm it tests that `update` and `delete` return 403/redirect when called by a non-author. Authorization logic lives in `authorize_edit/2` which is inline and not shared — verify it's covered.

### 5f. Tests using `Process.sleep` for second-precision ordering

Several tests use `Process.sleep(1100)` to ensure `published_at_utc` timestamps differ (since it has second-precision). This is fragile in slow CI environments and makes the test suite slow. A better pattern is to insert fixtures with explicit `published_at_utc` overrides so ordering is deterministic without sleeping.

**Files:** [test/revix/entries_test.exs:612](test/revix/entries_test.exs#L612), [test/revix/entries_test.exs:774](test/revix/entries_test.exs#L774), [test/revix/likes_test.exs:79](test/revix/likes_test.exs#L79)

---

## 6. Comment Hygiene

### 6a. Inline comments explaining what code does (not why)

Several comments describe the mechanics of the code rather than intent:

- `# Delete the image itself if it has no remaining entry associations` — the code immediately below makes this obvious ([lib/revix/media.ex:72](lib/revix/media.ex#L72))
- `# Re-order existing images per drag order (if user reordered them)` — same ([lib/revix_web/live/checkin_edit_live.ex:242](lib/revix_web/live/checkin_edit_live.ex#L242))
- `# New uploads are appended after all existing images` — obvious from `next_position = length(checkin.entry_images)` ([lib/revix_web/live/checkin_edit_live.ex:263](lib/revix_web/live/checkin_edit_live.ex#L263))
- `# Helper to determine if this is a reply` / `# Helper for top-level entries` — function names `reply?/1` and `top_level?/1` are self-documenting ([lib/revix/entries/entry.ex:170-175](lib/revix/entries/entry.ex#L170-L175))

### 6b. `# FIXME` in production schema code

The `# FIXME: Heinous kludges follow!` comment in `Person.maybe_generate_required_fields/3` ([lib/revix/people/person.ex:83](lib/revix/people/person.ex#L83)) is a live marker for the web-layer reference issue called out in §2c. It should become a tracked issue rather than a comment, and the underlying problem fixed.

### 6c. Dead commented-out scope in `router.ex`

```elixir
# Other scopes may use custom stacks.
# scope "/api", RevixWeb do
#   pipe_through :api
# end
```

**File:** [lib/revix_web/router.ex:29-32](lib/revix_web/router.ex#L29-L32)

This is Phoenix boilerplate that should be removed — the app already has API-style routes under `:browser`.

---

## 7. Style Inconsistencies

### 7a. Inconsistent return shape between context functions

Some context functions return `{:ok, list}` unconditionally (e.g., `get_recent_checkins`, `get_local_checkins`, `get_places_for_person`), while others return raw values (e.g., `get_recent_comments/1` returns a bare list, not `{:ok, list}`; `get_local_place_by_osm` returns `nil` or a struct). This inconsistency forces callers to remember which shape each function returns.

A consistent convention would be: functions that can fail or return not-found use `{:ok, _} | {:error, _}`; list-returning functions return bare lists (since an empty list is a valid success state, not an error).

**Affected:** `get_recent_comments/1` → bare list; `get_recent_checkins/1` → `{:ok, list}`; `get_local_place_by_osm/2` → struct or nil (no `{:ok}`).

### 7b. `Map.merge` used to set defaults for opts instead of `Keyword` pattern

`get_recent_checkins_for_person/2` and `get_recent_likes_for_person/2` accept `opts \\ %{}` as a map, then do `%{limit: 50} |> Map.merge(opts)`. The rest of the codebase uses `Keyword.get(opts, :key, default)` with keyword lists. Pick one convention.

**Files:** [lib/revix/entries.ex:30-31](lib/revix/entries.ex#L30-L31), [lib/revix/likes.ex:154](lib/revix/likes.ex#L154)

### 7c. `@impl true` not used consistently in LiveViews

`CheckinNewLive` has `@impl true` on `mount` and `handle_info` but not on all `handle_event` clauses. `CheckinEditLive` has it only on `mount`. `@impl true` should appear before all callbacks (`mount`, `handle_event`, `handle_info`, `render`) to get compile-time verification that the callbacks exist on the behaviour.

### 7d. `checkin_path/1` called without module alias in `NoteController`

`NoteController` calls `checkin_path(checkin)` without a visible `alias` or `import` of `CanonicalRoutes`.

**File:** [lib/revix_web/controllers/note_controller.ex:13](lib/revix_web/controllers/note_controller.ex#L13)

This presumably works because `RevixWeb.Router.Helpers` or a `use RevixWeb, :controller` import brings it in — but it's worth confirming the exact resolution to avoid future confusion.

---

## Prioritised Action Items

| Priority | Issue |
|----------|-------|
| High | §3a — Validate file content (magic bytes), not just extension; `:original` stores untransformed uploads |
| High | §3e — RSA private key stored in plaintext; consider at-rest encryption |
| High | §2b / §2c — `create_comment` and `Person` schema reference `RevixWeb` directly; pass callbacks instead |
| Medium | §3c — `redirect_if_person_is_authenticated` checks scope truthiness rather than `scope.person` |
| Medium | §1a / §1b — Extract shared `consume_uploads` and companion search logic from both LiveViews |
| Medium | §3b — Add `validate_length(:name)` to `Place.create_changeset` |
| Medium | §5d — Add unit tests for ActivityPub/GeoJSON serialization helpers |
| Medium | §5f — Replace `Process.sleep` in tests with explicit `published_at_utc` fixture overrides |
| Low | §4a / §4b — Refactor changeset helpers to use pattern-matched clauses instead of nested `if` |
| Low | §7a — Standardise context return shapes (bare list vs `{:ok, list}`) |
| Low | §6c — Remove dead commented-out router scope |
| Low | §3f — Pass only extracted keys to `update_comment` instead of raw params map |
