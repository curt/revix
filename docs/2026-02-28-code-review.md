# Code Review – 2026-02-28

Scope: follow-up review of the full codebase after mitigating findings from the 2026-02-27 review.
Focus: confirming closed issues, surfacing remaining open items, and identifying any new concerns.

---

## Summary

The codebase is in substantially better shape than the previous review. Ten of the thirteen actionable issues from 2026-02-27 have been closed. The domain layer now correctly keeps all web-layer references out of contexts and schemas. Security validations are tightened. Changeset helpers and auth plugs have been refactored to idiomatic pattern-matched clauses. Three issues remain open, and three new findings are documented below.

---

## What Was Fixed

The following issues from the 2026-02-27 review are confirmed resolved:

- **§2b** — `Entries.create_comment/5` now accepts `uri_fn`/`url_fn` callbacks; no longer calls `RevixWeb.Endpoint` directly.
- **§2c** — `Person.maybe_generate_required_fields/3` now receives `uri_fn`/`url_fn` callbacks via opts; the `FIXME` comment and direct `RevixWeb.CanonicalRoutes` references are both gone.
- **§2d** — `Media.remove_image_from_entry/2` has been split into `detach_image/2` and `maybe_delete_orphaned_image/2`, separating the two responsibilities.
- **§3a** — Both uploaders now validate magic bytes via the shared `Revix.Uploaders.Validation.validate_image/3` helper using `ExImageInfo`. The `:original` version is no longer accepted without content verification.
- **§3b** — `Place.create_changeset/2` now enforces `validate_length(:name, max: 200)`.
- **§3c** — `redirect_if_person_is_authenticated/2` replaced the `if scope` check with two pattern-matched clauses and an explicit `when not is_nil(person)` guard.
- **§3d** — `Places.search_nearby_places/3` (the synchronous combined wrapper) has been deleted. Callers use `search_nearby_db/3`, `search_nearby_osm/3`, and `merge_place_results/2` directly.
- **§4a/4b** — Changeset helpers in `entry.ex` have been refactored to pattern-matched guard clauses. `set_published_at/1` and `set_comment_published_at/1` now share `set_published_at_fields/2`, eliminating the near-duplication.
- **§4c** — `Enum.member?` replaced with the `in` operator throughout.
- **§6a/6b/6c** — All redundant and dead comments removed: the two "Helper to..." comments in `entry.ex`, the two inline comments in `checkin_edit_live.ex`, the `# FIXME: Heinous kludges follow!` marker, and the commented-out Phoenix `/api` scope block in `router.ex`.

---

## Remaining Open Issues

### §3e — `Person.private_key` stored unencrypted in the database

**File:** [lib/revix/people/person.ex:18](lib/revix/people/person.ex#L18)

The RSA private key for federation signing is stored as plaintext in the `people` table. The field is marked `redact: true`, which prevents it from appearing in logs and debug output, but the PEM is fully exposed if the database is compromised. Mitigating this requires application-level encryption (e.g., `cloak_ecto`) or a database-level encrypted column. This issue was explicitly deferred pending research; no change yet.

**Priority:** High

### §3f — `NoteController.update/2` passes raw params to `update_comment/2`

**File:** [lib/revix_web/controllers/note_controller.ex:59](lib/revix_web/controllers/note_controller.ex#L59)

```elixir
case Entries.update_comment(note, params["note"] || %{})
```

`params["note"]` is untrusted user input passed directly to the changeset. The `update_comment_changeset` only casts `:content`, so no other field can be written today — but passing the full params map is fragile habit. If the changeset is later broadened (e.g., to accept `:content_html` or a `published_at` override), existing callers silently become exploitable. Prefer `Map.take(params["note"] || %{}, ["content"])`.

**Priority:** Medium

### §7a — `get_local_places_near/2` returns `{:ok, list}` instead of a bare list

**File:** [lib/revix/places.ex:47](lib/revix/places.ex#L47)

```elixir
{:ok, places}
```

This function has no error path — it always returns a list (possibly empty). Per the project convention documented in CLAUDE.md, list-returning context functions that cannot fail should return bare lists. `get_local_places_near/2` is the only such function in the codebase that wraps its result in `{:ok, _}`. The `PlaceController.show/2` caller would need to be updated alongside it.

**Priority:** Low

---

## New Findings

### N1 — `set_context/1` and `set_comment_context/1` are near-identical

**File:** [lib/revix/entries/entry.ex:136-144](lib/revix/entries/entry.ex#L136-L144) and [lib/revix/entries/entry.ex:171-179](lib/revix/entries/entry.ex#L171-L179)

Both functions share the same `if field_value do put_change ... else changeset end` structure and differ only in which field they read:

```elixir
defp set_context(changeset) do
  uri = get_field(changeset, :uri)
  if uri do
    put_change(changeset, :context, uri)
  else
    changeset
  end
end

defp set_comment_context(changeset) do
  in_reply_to_uri = get_field(changeset, :in_reply_to_uri)
  if in_reply_to_uri do
    put_change(changeset, :context, in_reply_to_uri)
  else
    changeset
  end
end
```

A shared one-liner `defp set_context_from_field(changeset, field)` would eliminate the duplication, with `set_context/1` and `set_comment_context/1` delegating to it.

**Priority:** Low

### N2 — `maybe_limit/2` still duplicated in `Entries` and `Likes`

**Files:** [lib/revix/entries.ex:285-287](lib/revix/entries.ex#L285-L287), [lib/revix/likes.ex:172-173](lib/revix/likes.ex#L172-L173)

This was noted as §1d in the 2026-02-27 review. The identical two-clause private helper remains in both modules. Given how trivial the function is, intentional co-location is defensible — but if a third context ever needs it, a shared `Revix.Query` module becomes the right home.

**Priority:** Low

### N3 — `Process.sleep` in `checkin_new_live_test.exs` for async task settlement

**File:** [test/revix_web/live/checkin_new_live_test.exs](test/revix_web/live/checkin_new_live_test.exs) — lines 106, 155, 170, 191, 206

Five `Process.sleep(50)` calls are used to allow `Task.async` Overpass results to arrive before asserting on rendered HTML. This is distinct from the timestamp-ordering sleeps from §5f of the previous review (those are gone); these are waiting on genuine async task I/O. The 50 ms budget is timing-dependent and can produce flaky failures in slow CI or under load. The idiomatic replacement is `assert_receive` on the task result message or, if the Phoenix LiveView version supports it, `render_async/1`.

**Priority:** Low

---

## Prioritized Action Items

| Priority | Issue |
|----------|-------|
| High | §3e — RSA private key stored in plaintext; evaluate `cloak_ecto` for at-rest encryption |
| Medium | §3f — Pass `Map.take(params["note"] || %{}, ["content"])` to `update_comment/2` instead of raw params |
| Low | §7a — Change `get_local_places_near/2` to return bare list; update `PlaceController.show/2` caller |
| Low | N1 — Extract shared `set_context_from_field/2` helper in `entry.ex` |
| Low | N2 — Accept or extract `maybe_limit/2` duplication between `Entries` and `Likes` |
| Low | N3 — Replace `Process.sleep(50)` in LiveView tests with `assert_receive` or `render_async/1` |
