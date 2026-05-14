# ActivityPub Entry Federation — Manual Testing Checklist

**Date:** 2026-05-14  
**Branch:** topic/follows  
**Scope:** Inbound Create/Update/Delete{Note/Article}; outbound fan-out to followers; broader inbound acceptance via followed actors.

---

## Setup

- Have a local account available (any role).
- Know your local server base URL (e.g., `http://localhost:4000`) and your person's inbox URL (`/people/{id}/inbox`).
- For signed inbound activity tests, use a cooperating remote ActivityPub server or a signing tool. The `test/support/federation_fixtures.ex` RSA key pair can be used for local signing experiments via `iex -S mix phx.server`. The corresponding remote actor URI is `https://remote.example.com/users/alice`.
- Have at least one local checkin in the database. The examples below use `{checkin_uri}` as a placeholder — substitute the actual URI of a local checkin (e.g., `http://localhost:4000/checkins/AbCdEfGhIjK`).

No database migration is required for this feature.

---

## Inbound unsigned activity — should be rejected

```bash
curl -X POST http://localhost:4000/people/{person_id}/inbox \
  -H "Content-Type: application/activity+json" \
  -d '{"@context":"https://www.w3.org/ns/activitystreams","type":"Create","id":"https://remote.example.com/activities/1","actor":"https://remote.example.com/users/alice","object":{"type":"Note","id":"https://remote.example.com/notes/1","content":"<p>Hello</p>","inReplyTo":"{checkin_uri}"}}'
```

- [ ] Server responds with **401**

---

## Inbound Create{Note} — local context

### Reply to a local checkin (should be stored)

POST a valid signed `Create{Note}` with `inReplyTo` pointing to a local checkin URI:

```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "type": "Create",
  "id": "https://remote.example.com/activities/create1",
  "actor": "https://remote.example.com/users/alice",
  "object": {
    "type": "Note",
    "id": "https://remote.example.com/notes/1",
    "content": "<p>Hello!</p>",
    "inReplyTo": "{checkin_uri}",
    "context": "{checkin_uri}",
    "published": "2026-05-14T10:00:00Z"
  }
}
```

- [ ] Server responds with **202**
- [ ] In iex, verify the entry was stored:
  ```elixir
  Revix.Repo.get_by!(Revix.Entries.Entry, uri: "https://remote.example.com/notes/1")
  ```
  - `type` is `:note`
  - `origin` is `:remote`
  - `author_uri` is `"https://remote.example.com/users/alice"`
  - `in_reply_to_uri` is `"{checkin_uri}"`
  - `context` is `"{checkin_uri}"`

### Idempotent second POST

- [ ] POST the same activity again — server responds with **202**
- [ ] In iex, verify only one row exists for that `uri`:
  ```elixir
  import Ecto.Query
  Revix.Repo.aggregate(from(e in Revix.Entries.Entry, where: e.uri == "https://remote.example.com/notes/1"), :count)
  ```
  Result: **1**

### Reply to a remote-origin entry (should be ignored)

First insert a remote checkin in iex:

```elixir
{:ok, remote_checkin} = Revix.Entries.create_inbound_note(%{
  uri: "https://remote.example.com/checkins/xyz",
  url: "https://remote.example.com/checkins/xyz",
  author_uri: "https://remote.example.com/users/alice",
  content: "<p>Remote checkin</p>",
  published_at_utc: ~U[2026-05-14 09:00:00Z]
})
```

POST a valid signed Create with `inReplyTo` pointing to that remote entry's URI.

- [ ] Server responds with **202**
- [ ] In iex, verify the Note was NOT stored (no entry row for the Note URI)

---

## Inbound Create{Note} — followed actor (no local context)

### Followed actor — should be stored

First follow the remote actor from the `/following` page (or in iex):

```elixir
scope = %Revix.People.Scope{person: Revix.Repo.get!(Revix.People.Person, "{person_id}"), role: :user}
Revix.Follows.follow(scope, "https://remote.example.com/users/alice")
```

POST a valid signed `Create{Note}` with no local `inReplyTo` (pointing to a foreign or absent URI):

```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "type": "Create",
  "id": "https://remote.example.com/activities/create2",
  "actor": "https://remote.example.com/users/alice",
  "object": {
    "type": "Note",
    "id": "https://remote.example.com/notes/2",
    "content": "<p>From someone you follow!</p>",
    "published": "2026-05-14T10:00:00Z"
  }
}
```

- [ ] Server responds with **202**
- [ ] In iex, verify the entry was stored with `origin: :remote`

### Unfollowed actor, no local context — should be ignored

Ensure you are not following the actor (or use a different actor URI).

POST a valid signed Note with no local `inReplyTo` from an actor you don't follow.

- [ ] Server responds with **202**
- [ ] In iex, verify the Note was NOT stored

---

## Inbound Update{Note} — update path

First create the entry via a Create activity (see above). Then POST a valid signed `Update`:

```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "type": "Update",
  "id": "https://remote.example.com/activities/update1",
  "actor": "https://remote.example.com/users/alice",
  "object": {
    "type": "Note",
    "id": "https://remote.example.com/notes/1",
    "content": "<p>Updated content!</p>",
    "inReplyTo": "{checkin_uri}",
    "context": "{checkin_uri}",
    "published": "2026-05-14T10:00:00Z"
  }
}
```

- [ ] Server responds with **202**
- [ ] In iex, verify the content was updated:
  ```elixir
  Revix.Repo.get_by!(Revix.Entries.Entry, uri: "https://remote.example.com/notes/1").content
  ```
  Result: `"<p>Updated content!</p>"`

### Idempotent re-delivery

- [ ] POST the same Update activity again — server responds with **202**
- [ ] In iex, verify still only one row exists for that URI

---

## Inbound Update{Note} — upsert path

POST a valid signed `Update` for a Note URI that was never created:

```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "type": "Update",
  "id": "https://remote.example.com/activities/update-new",
  "actor": "https://remote.example.com/users/alice",
  "object": {
    "type": "Note",
    "id": "https://remote.example.com/notes/new",
    "content": "<p>Created by Update!</p>",
    "inReplyTo": "{checkin_uri}",
    "context": "{checkin_uri}",
    "published": "2026-05-14T10:00:00Z"
  }
}
```

- [ ] Server responds with **202**
- [ ] In iex, verify the entry was created:
  ```elixir
  Revix.Repo.get_by!(Revix.Entries.Entry, uri: "https://remote.example.com/notes/new")
  ```
  - `origin` is `:remote`

---

## Inbound Update{Note} — local-origin guard

POST a valid signed `Update` where `object["id"]` is the URI of a local checkin:

```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "type": "Update",
  "id": "https://remote.example.com/activities/update-local",
  "actor": "https://remote.example.com/users/alice",
  "object": {
    "type": "Note",
    "id": "{checkin_uri}",
    "content": "<p>Malicious overwrite attempt</p>"
  }
}
```

- [ ] Server responds with **202**
- [ ] In iex, verify the local checkin is unchanged:
  ```elixir
  Revix.Repo.get_by!(Revix.Entries.Entry, uri: "{checkin_uri}").origin
  ```
  Result: `:local`

---

## Inbound Delete — plain URI object

First ensure the remote note exists (`https://remote.example.com/notes/1` from the Create tests above). Then POST a valid signed `Delete`:

```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "type": "Delete",
  "id": "https://remote.example.com/activities/delete1",
  "actor": "https://remote.example.com/users/alice",
  "object": "https://remote.example.com/notes/1"
}
```

- [ ] Server responds with **202**
- [ ] In iex, verify the row is gone:
  ```elixir
  Revix.Repo.get_by(Revix.Entries.Entry, uri: "https://remote.example.com/notes/1")
  ```
  Result: `nil`

---

## Inbound Delete — Tombstone object

Re-create the note (or use a different note URI). Then POST a Delete with a Tombstone object:

```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "type": "Delete",
  "id": "https://remote.example.com/activities/delete2",
  "actor": "https://remote.example.com/users/alice",
  "object": {
    "type": "Tombstone",
    "id": "https://remote.example.com/notes/1"
  }
}
```

- [ ] Server responds with **202**
- [ ] In iex, verify the row is gone

---

## Inbound Delete — edge cases

### Unknown URI (idempotent)

- [ ] POST a valid signed Delete for a note URI that has never existed — server responds with **202** (silently discarded; no error)

### Wrong actor

First create a remote note authored by Alice. Then POST a Delete from a different actor:

```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "type": "Delete",
  "id": "https://remote.example.com/activities/delete-bad-actor",
  "actor": "https://remote.example.com/users/mallory",
  "object": "https://remote.example.com/notes/1"
}
```

- [ ] Server responds with **202**
- [ ] In iex, verify the row still exists and is unchanged

### Local-origin entry

POST a valid signed Delete where `object` is the URI of a local checkin:

- [ ] Server responds with **202**
- [ ] In iex, verify the local checkin still exists with `origin: :local`

---

## Outbound fan-out — Create

In iex, insert an accepted follow from a remote actor to the local person (so the local person has a follower who will receive fan-out):

```elixir
id = Revix.Ecto.Base58Id.autogenerate()
%Revix.Follows.Follow{id: id}
|> Revix.Follows.Follow.create_changeset(%{
  uri: "https://remote.example.com/follows/#{id}",
  follower_uri: "https://remote.example.com/users/alice",
  following_uri: "{local_person_uri}",
  origin: :remote,
  accepted_at: DateTime.utc_now(:second)
})
|> Revix.Repo.insert!()
```

Then create a local checkin via the UI.

- [ ] In iex, verify a `DeliverEntryWorker` job was enqueued with `activity_type: "Create"`:
  ```elixir
  import Ecto.Query
  Revix.Repo.all(from j in Oban.Job, where: j.worker == "Revix.Workers.DeliverEntryWorker", order_by: [desc: j.inserted_at], limit: 3)
  ```
  - `args["activity_type"]` is `"Create"`

---

## Outbound fan-out — Update

Edit an existing local checkin or comment via the UI.

- [ ] In iex, verify a `DeliverEntryWorker` job was enqueued with `activity_type: "Update"`

---

## Outbound fan-out — Delete

Delete a local comment via the UI.

- [ ] In iex, verify a `DeliverEntryWorker` job was enqueued with `activity_type: "Delete"`
- [ ] Note: the entry row is deleted before the job runs; `DeliverEntryWorker` loads the entry by ID at execution time — confirm the job ran and delivered correctly by checking Oban job state:
  ```elixir
  import Ecto.Query
  Revix.Repo.all(from j in Oban.Job, where: j.worker == "Revix.Workers.DeliverEntryWorker" and j.state == "completed")
  ```

---

## PubSub live updates

Subscribe to the context topic in iex:

```elixir
Phoenix.PubSub.subscribe(Revix.PubSub, "context:{checkin_uri}")
```

Then in a separate process (or via the inbox) trigger each activity:

- [ ] Inbound Create → `assert_receive {:comment_created, _entry}`
- [ ] Inbound Update → `assert_receive {:comment_updated, _entry}`
- [ ] Inbound Delete → `assert_receive {:comment_deleted, _id}`

---

## Inbox for unknown person

- [ ] POST a valid signed activity to `/people/doesnotexist/inbox` — server responds with **404**

---

## Malformed activities

- [ ] POST without `actor` or `id` fields → server responds with **400**
- [ ] POST a `Update` where `object` is a string (not a map) → server responds with **202** (InboxController accepts; worker returns `{:error, :invalid_activity}`, Oban marks as failed — not retried at `max_attempts: 1`)

---

## Automated tests

```
make tests
```

Should report **0 failures** (1292 Elixir tests, 35 JS tests).
