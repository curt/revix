# ActivityPub Update{Note} Conformance — Manual Testing Checklist

**Date:** 2026-05-29  
**Branch:** next/16  
**Scope:** `updated` field on outbound Note objects; `modified_at_utc` column; Update activity `published` and unique `id`; inbound `note["updated"]` capture.

---

## Setup

- Have a local account and a running dev server (`make serve`).
- Know your person's `id` (the 11-character Base58 string shown in URLs).
- Have at least one existing local checkin. Examples use `{checkin_id}` and `{checkin_uri}` as placeholders.
- Run the migration before testing: `make migrate-db`.

---

## 1 — `updated` field absent on unedited Note objects

Fetch the AP representation of a checkin that has never been edited:

```bash
curl -s http://localhost:4000/checkins/{checkin_id} \
  -H "Accept: application/activity+json" | jq .
```

- [ ] Response has `"type": "Note"`
- [ ] Response has `"published"` field
- [ ] Response does **not** have an `"updated"` field

---

## 2 — `updated` field appears after editing

Edit the checkin's description via the UI. Then fetch the AP representation again:

```bash
curl -s http://localhost:4000/checkins/{checkin_id} \
  -H "Accept: application/activity+json" | jq '{published, updated}'
```

- [ ] `"updated"` field is present
- [ ] `"updated"` value is an ISO 8601 timestamp later than `"published"`

Verify the DB column was set:

```elixir
entry = Revix.Repo.get_by!(Revix.Entries.Entry, uri: "{checkin_uri}")
entry.modified_at_utc
```

- [ ] `modified_at_utc` is a `%DateTime{}`, not `nil`

---

## 3 — Outbound Update activity shape

To capture the delivered Update activity, insert a remote follower in iex and stub the delivery endpoint (or inspect the Oban job payload directly):

```elixir
# Insert an accepted remote follower
id = Revix.Ecto.Base58Id.autogenerate()
%Revix.Follows.Follow{id: id}
|> Revix.Follows.Follow.create_changeset(%{
  uri: "tag:revix,2026-05-29:follow:#{id}",
  follower_uri: "https://remote.example.com/users/alice",
  following_uri: "{local_person_uri}",
  origin: :remote,
  accepted_at: DateTime.utc_now(:second)
})
|> Revix.Repo.insert!()
```

Then edit a local checkin via the UI. Inspect the enqueued Oban job:

```elixir
import Ecto.Query
job = Revix.Repo.one!(
  from j in Oban.Job,
  where: j.worker == "Revix.Workers.DeliverEntryWorker"
    and j.args["activity_type"] == "Update",
  order_by: [desc: j.inserted_at],
  limit: 1
)
job.args
```

- [ ] `args["activity_type"]` is `"Update"`

Execute the job directly in iex to inspect the delivered payload:

```elixir
Revix.Workers.DeliverEntryWorker.perform(%Oban.Job{args: job.args})
```

Or, if using a real remote server or request inspector, observe the POST to the inbox. The activity should look like:

```json
{
  "@context": ["https://www.w3.org/ns/activitystreams", {"schema": "...", "sameAs": "schema:sameAs"}],
  "type": "Update",
  "id": "https://example.com/checkins/{checkin_id}#update-2026-05-29T...",
  "actor": "https://example.com/people/{person_id}",
  "published": "2026-05-29T...",
  "object": {
    "type": "Note",
    "published": "...",
    "updated": "2026-05-29T...",
    ...
  },
  "to": ["https://www.w3.org/ns/activitystreams#Public"],
  "cc": ["https://example.com/people/{person_id}/followers"]
}
```

- [ ] Activity `"type"` is `"Update"`
- [ ] Activity `"id"` contains `#update-` followed by a timestamp (not just `#update`)
- [ ] Activity `"published"` is present and is an ISO 8601 timestamp
- [ ] Object `"updated"` is present and matches activity `"published"`

### Edit the same entry a second time

- [ ] The second Update activity has a **different** `"id"` from the first (the timestamp suffix changes)

---

## 4 — Create activity shape unchanged

Edit the checkin, then also verify the Create activity for a newly-created checkin:

```bash
curl -s http://localhost:4000/people/{person_id}/outbox \
  -H "Accept: application/activity+json" | jq '.orderedItems[0]'
```

- [ ] First item has `"type": "Create"`
- [ ] First item has `"id"` ending in `#create`
- [ ] First item has `"published"` matching the checkin's `published_at_utc`
- [ ] Object inside does **not** have `"updated"` (if the checkin was never edited), or has `"updated"` if it was edited

---

## 5 — Inbound `updated` field captured

POST a valid signed `Update{Note}` activity that includes an `"updated"` field on the object. Use a note URI that already exists as a remote-origin entry (create it first via a signed `Create` if needed):

```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "type": "Update",
  "id": "https://remote.example.com/activities/update-ts",
  "actor": "https://remote.example.com/users/alice",
  "object": {
    "type": "Note",
    "id": "https://remote.example.com/notes/1",
    "content": "<p>Edited with timestamp</p>",
    "inReplyTo": "{checkin_uri}",
    "published": "2026-05-14T10:00:00Z",
    "updated": "2026-05-29T15:00:00Z"
  }
}
```

After the worker processes, verify in iex:

```elixir
entry = Revix.Repo.get_by!(Revix.Entries.Entry, uri: "https://remote.example.com/notes/1")
entry.modified_at_utc
```

- [ ] `modified_at_utc` is `~U[2026-05-29 15:00:00Z]` (the value from `"updated"`)

### `updated` absent — `modified_at_utc` stays nil

POST an `Update{Note}` without an `"updated"` field on the object:

```json
{
  "object": {
    "type": "Note",
    "id": "https://remote.example.com/notes/2",
    "content": "<p>No timestamp</p>",
    "inReplyTo": "{checkin_uri}",
    "published": "2026-05-14T10:00:00Z"
  }
}
```

```elixir
Revix.Repo.get_by!(Revix.Entries.Entry, uri: "https://remote.example.com/notes/2").modified_at_utc
```

- [ ] `modified_at_utc` is `nil`

---

## 6 — Posts and notes follow the same pattern

Repeat a subset of steps 1–3 for:

- [ ] A local **post** — edit via the post editor; verify `updated` appears in the AP Note JSON and `modified_at_utc` is set in the DB
- [ ] A local **comment** (note) — edit via the comment section; verify same

---

## Automated tests

```
make tests
```

- [ ] Reports **0 failures** (1974 Elixir tests)
