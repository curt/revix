# ActivityPub Update{Note} Conformance — 2026-05-29

**Branch:** next/16  
**Scope:** Five gaps in `Update{Note}` federation closed: `updated` field on outbound Note objects; dedicated `modified_at_utc` column; `published` and unique `id` on Update activity wrappers; inbound `note["updated"]` capture.

---

## Summary

When a local entry (checkin, post, or note) was edited, a `Update{Note}` activity was already delivered to followers via `DeliverEntryWorker`. However, the outbound shape had several spec non-conformances and the inbound path discarded update timestamps silently.

**Five gaps closed:**

1. **No `updated` field on Note objects.** Remote servers receiving an Update activity had no way to distinguish an edited Note from the original — both carried only `published`. The `updated` field is now emitted on any Note whose `modified_at_utc` is later than `published_at_utc`.

2. **No dedicated modification timestamp.** Ecto's auto-managed `updated_at` column is touched by any DB write and cannot reliably represent "content was intentionally edited at this time." A new `modified_at_utc` column records only deliberate content updates via the three update changesets.

3. **Update activity missing `published`.** The outbound `Update` wrapper had no `published` field while the `Create` wrapper did. Remote servers use `published` to determine when the update occurred. Update activities now carry `published` set to `modified_at_utc`.

4. **Update activity `id` was static.** `entry.uri <> "#update"` was the same string regardless of how many times an entry was edited. The AP spec requires unique activity IDs. The id is now `entry.uri <> "#update-" <> DateTime.to_iso8601(modified_at)`, unique per edit.

5. **Inbound `note["updated"]` was silently dropped.** `extract_note_attrs/2` extracted `note["published"]` but not `note["updated"]`. Remote update timestamps were discarded on ingest, so `modified_at_utc` on remote-origin entries was never populated. The field is now extracted and cast by `inbound_note_changeset`.

The full Elixir suite (1974 tests) passes at 0 failures. No JavaScript changes.

---

## New Files

### `priv/repo/migrations/20260529131051_add_modified_at_utc_to_entries.exs`

Adds `modified_at_utc :utc_datetime` (nullable) to the `entries` table and creates an index on the column. Single UTC column — not a three-tier datetime triple — because it is a system/federation timestamp, not a user-facing local-time display field.

**File:** [priv/repo/migrations/20260529131051_add_modified_at_utc_to_entries.exs](priv/repo/migrations/20260529131051_add_modified_at_utc_to_entries.exs)

---

## Modified Files

### `lib/revix/entries/entry.ex`

**Schema field:** `field :modified_at_utc, :utc_datetime` added after the `ends_at_*` trio.

**`set_modified_at/1` (new private helper):**
```elixir
defp set_modified_at(%{valid?: false} = changeset), do: changeset
defp set_modified_at(changeset), do: put_change(changeset, :modified_at_utc, DateTime.utc_now(:second))
```
Follows the same guard pattern as `set_post_published_at/1` — does nothing on an invalid changeset. Piped at the end of:
- `update_post_changeset/3`
- `update_checkin_changeset/3`
- `update_comment_changeset/2`

Create changesets are not changed — `modified_at_utc` stays `nil` until content is deliberately edited.

**`inbound_note_changeset/2`:** `:modified_at_utc` added to the `cast/3` field list. No derived logic — it arrives as a parsed UTC datetime from `extract_note_attrs/2`.

**File:** [lib/revix/entries/entry.ex](lib/revix/entries/entry.ex)

---

### `lib/revix/workers/inbound_note_helpers.ex`

`extract_note_attrs/2` gains one new key:
```elixir
modified_at_utc: parse_datetime(note["updated"])
```
`parse_datetime/1` already handles `nil` and unparseable strings gracefully, so no guard needed.

**File:** [lib/revix/workers/inbound_note_helpers.ex](lib/revix/workers/inbound_note_helpers.ex)

---

### `lib/revix/activity_pub.ex`

**`maybe_add_updated/2` (new private helper):**
```elixir
defp maybe_add_updated(map, %{modified_at_utc: nil}), do: map

defp maybe_add_updated(map, %{modified_at_utc: modified, published_at_utc: published}) do
  if is_nil(published) or DateTime.compare(modified, published) == :gt do
    Map.put(map, "updated", format_datetime(modified))
  else
    map
  end
end
```
Called at the end of `note_base/1`, after `maybe_add_context/2`. Emits `"updated"` only when `modified_at_utc` is strictly later than `published_at_utc` — a newly-created entry with `modified_at_utc: nil` produces no `updated` field.

**File:** [lib/revix/activity_pub.ex](lib/revix/activity_pub.ex)

---

### `lib/revix/workers/deliver_entry_worker.ex`

The generic `wrap/2` was split into two type-specific private functions:

**`wrap_create/1`** — unchanged behavior; includes `"published"` from `entry.published_at_utc` and id `entry.uri <> "#create"`.

**`wrap_update/1`** — new shape:
```elixir
defp wrap_update(entry) do
  modified_at = entry.modified_at_utc || entry.published_at_utc

  %{
    "type" => "Update",
    "id" => entry.uri <> "#update-" <> DateTime.to_iso8601(modified_at),
    "actor" => entry.author_uri,
    "published" => format_datetime(modified_at),
    "object" => build_object(entry),
    "to" => ["https://www.w3.org/ns/activitystreams#Public"],
    "cc" => [RevixWeb.CanonicalRoutes.person_followers_url(entry.author.id)]
  }
  |> Revix.ActivityPub.contextify()
end
```

The `|| entry.published_at_utc` fallback is a safety net for any entry that was updated before the migration ran (i.e., where `modified_at_utc` is still `nil`). In steady state, `modified_at_utc` is always set by the update changeset before the worker fires.

A private `format_datetime/1` helper was added to the worker (`nil` guard + `DateTime.to_iso8601/1`) to avoid calling the private helper in `Revix.ActivityPub` directly.

**File:** [lib/revix/workers/deliver_entry_worker.ex](lib/revix/workers/deliver_entry_worker.ex)

---

## What Was Not Changed

**Outbox:** `PersonCollectionController.outbox/2` was not changed. It serves only `Create` activities sorted by `published_at_utc`, which is standard practice (Mastodon does the same). `Update` activities are not included in the outbox.

**Three-tier datetime pattern:** `modified_at_utc` is a single UTC column — intentionally not a `modified_at_utc` / `modified_at_local` / `modified_tz` triple. It is a system timestamp used for federation, not a user-facing local-time display field.

**Delete activity shape:** Unchanged — a plain URI string as object, which is correct AP spec.

**Activity feed, Atom feed, JSON-LD response for individual entries:** None of these surfaces were changed. The `modified_at_utc` field appears only in the AP Note JSON produced by `Revix.ActivityPub`.

**JavaScript:** No changes.
