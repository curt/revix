# ActivityPub Inbound Likes — Manual Testing Checklist

**Date:** 2026-05-11  
**Branch:** topics/inbound-likes  
**Scope:** Inbound `Like` and `Undo Like` at `POST /people/:id/inbox`; `like_uri` column backfill.

---

## Setup

- Have a local account available (any role — unlike Ping, Like activities are not owner-restricted).
- Note the local server's base URL (e.g., `http://localhost:4000`) and a person's inbox URL (`/people/{id}/inbox`).
- Optionally, have a cooperating remote ActivityPub server to test end-to-end delivery.
- To construct a signed request manually, the `test/support/federation_fixtures.ex` test key pair can be used with `iex -S mix phx.server` for local experiments.

---

## Migration

- [ ] Run `make migrate-db` — completes without error
- [ ] Connect to the database and verify the `likes` table now has a `like_uri` column
- [ ] Verify all existing local likes have `like_uri` populated as `http://localhost:4000/likes/{id}` (or the equivalent production base URL)
- [ ] Verify the `likes_like_uri_index` unique index exists
- [ ] Confirm no likes have a `NULL` `like_uri`

---

## Local like creation (regression)

Verify that the `like_uri` column is populated correctly for new locally-created likes.

- [ ] Sign in and navigate to a checkin or post authored by another person
- [ ] Click the Like button — the like count increments
- [ ] In iex (`make serve`), inspect the new like:
  ```elixir
  Revix.Repo.all(Revix.Likes.Like) |> Enum.map(& &1.like_uri)
  ```
  Each URI should be of the form `http://localhost:4000/likes/{11-char-Base58-id}`
- [ ] Unlike the entry — the like count decrements; `unliked_at` is set
- [ ] Re-like the entry — `liked_at` resumes; `like_uri` remains unchanged from the original

---

## Inbound Like (unsigned — should be rejected)

```bash
curl -X POST http://localhost:4000/people/{person_id}/inbox \
  -H "Content-Type: application/activity+json" \
  -d '{"@context":"https://www.w3.org/ns/activitystreams","type":"Like","id":"https://remote.example.com/likes/1","actor":"https://remote.example.com/users/alice","object":"http://localhost:4000/checkins/someId"}'
```

- [ ] Server responds with **401**

---

## Inbound Like (malformed — should be rejected)

```bash
curl -X POST http://localhost:4000/people/{person_id}/inbox \
  -H "Content-Type: application/activity+json" \
  -d '{"type":"Like","actor":"https://remote.example.com/users/alice"}'
```

- [ ] Server responds with **400** (missing `"id"` field fails activity validation in the controller)

---

## Inbound Like (valid, signed)

Using a cooperating remote server or a signing tool:

- [ ] POST a valid signed `Like` activity to `POST /people/{id}/inbox`
  ```json
  {
    "@context": "https://www.w3.org/ns/activitystreams",
    "type": "Like",
    "id": "https://remote.example.com/users/alice/likes/abc",
    "actor": "https://remote.example.com/users/alice",
    "object": "http://localhost:4000/checkins/{checkin_id}"
  }
  ```
- [ ] Server responds with **202**
- [ ] In iex, verify the like was recorded:
  ```elixir
  Revix.Repo.get_by(Revix.Likes.Like, like_uri: "https://remote.example.com/users/alice/likes/abc")
  ```
  - `origin` is `:remote`
  - `author_uri` is `"https://remote.example.com/users/alice"`
  - `object_uri` is the checkin URI
  - `published_tz` is `"UTC"`
  - `unliked_at` is `nil`

---

## Inbound Like — idempotency

- [ ] POST the same signed `Like` activity a second time — server responds with **202** again
- [ ] In iex, verify only one `Like` row exists for that `like_uri`

---

## Inbound Like — activity without `"id"`

Some implementations may omit the `"id"` field from a `Like` activity.

- [ ] POST a valid signed `Like` activity with no `"id"` field — server responds with **202**
- [ ] In iex, verify a like was recorded with a `like_uri` that starts with `"tag:"`

---

## Inbound Undo Like (object as plain URI)

The most common AP pattern: the `"object"` field is the URI of the original `Like`.

- [ ] First record an inbound like (see above)
- [ ] POST a valid signed `Undo` activity:
  ```json
  {
    "@context": "https://www.w3.org/ns/activitystreams",
    "type": "Undo",
    "id": "https://remote.example.com/users/alice/undo/1",
    "actor": "https://remote.example.com/users/alice",
    "object": "https://remote.example.com/users/alice/likes/abc"
  }
  ```
- [ ] Server responds with **202**
- [ ] In iex, verify `unliked_at` is now set on the like:
  ```elixir
  Revix.Repo.get_by(Revix.Likes.Like, like_uri: "https://remote.example.com/users/alice/likes/abc")
  ```

---

## Inbound Undo Like (object as full Like map)

Some implementations embed the full Like object in the Undo:

- [ ] POST a valid signed `Undo` activity with a nested Like map including `"id"`:
  ```json
  {
    "@context": "https://www.w3.org/ns/activitystreams",
    "type": "Undo",
    "id": "https://remote.example.com/users/alice/undo/2",
    "actor": "https://remote.example.com/users/alice",
    "object": {
      "type": "Like",
      "id": "https://remote.example.com/users/alice/likes/abc",
      "actor": "https://remote.example.com/users/alice",
      "object": "http://localhost:4000/checkins/{checkin_id}"
    }
  }
  ```
- [ ] Server responds with **202**
- [ ] In iex, verify `unliked_at` is set

---

## Inbound Undo Like (object map without `"id"` — fallback)

Edge case: the nested Like has no `"id"`.

- [ ] Ensure an active inbound like exists for the actor + object pair
- [ ] POST a valid signed `Undo` with a nested map that has no `"id"`:
  ```json
  {
    "type": "Undo",
    "id": "...",
    "actor": "https://remote.example.com/users/alice",
    "object": {
      "type": "Like",
      "actor": "https://remote.example.com/users/alice",
      "object": "http://localhost:4000/checkins/{checkin_id}"
    }
  }
  ```
- [ ] Server responds with **202**
- [ ] In iex, verify `unliked_at` is set

---

## Inbound Undo Like — idempotency

- [ ] POST the same Undo activity twice — server responds with **202** both times
- [ ] In iex, verify only one like row exists and `unliked_at` is set

---

## Inbound Undo Like — no matching like

- [ ] POST a valid signed `Undo` for a `like_uri` that has never been received — server responds with **202** (silently discarded; no error)

---

## Undo of non-Like (should be discarded)

- [ ] POST a valid signed `Undo` whose `"object"` references a non-Like activity type — server responds with **202**; no changes in the database

---

## Like count in the UI (regression)

- [ ] Navigate to a checkin that has received an inbound like — the like count reflects the remote like
- [ ] Process the corresponding Undo — the like count decrements
- [ ] Verify the liker avatar is shown / removed correctly

---

## Inbox for unknown person

- [ ] POST a valid signed `Like` to `/people/doesnotexist/inbox` — server responds with **404**

---

## Automated tests

```
make tests
```

Should report **0 failures** (932 Elixir tests, 35 JS tests).
