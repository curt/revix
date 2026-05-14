# ActivityPub Follows — Manual Testing Checklist

**Date:** 2026-05-14  
**Branch:** topic/follows  
**Scope:** Outbound Follow/Unfollow; inbound Follow/Accept/Undo; `/following` LiveView; `followers` and `following` collection endpoints.

---

## Setup

- Have a local account available (any role — the `/following` page is not owner-restricted).
- Know the local server base URL (e.g., `http://localhost:4000`) and the person's inbox URL (`/people/{id}/inbox`).
- For signed inbound activity tests, use a cooperating remote ActivityPub server or a signing tool. The `test/support/federation_fixtures.ex` key pair can be used for local signing experiments via `iex -S mix phx.server`.

---

## Migration

- [ ] Run `make migrate-db` — completes without error
- [ ] Verify the `follows` table exists with columns: `id`, `uri`, `follower_uri`, `following_uri`, `origin`, `accepted_at`, `unfollowed_at`, `inserted_at`, `updated_at`
- [ ] Verify unique indexes on `follows_uri_index` and `follows_follower_uri_following_uri_index`

---

## Navigation

- [ ] Sign in — "Following" link appears in the nav
- [ ] Sign out — "Following" link is not shown
- [ ] Navigate to `/following` while signed out — redirected to the sign-in page

---

## `/following` page — Following tab

- [ ] Navigate to `/following` — page loads; "Following" tab is active
- [ ] Empty state: "Not following anyone yet." is shown when there are no outgoing follows

### Follow by URI

- [ ] Enter a remote actor URI in the input field and submit — "Follow request sent." flash appears; the actor appears in the Following list
- [ ] Submit the same URI again — "Follow request sent." flash; actor appears once (idempotent)
- [ ] Submit your own URI — "You cannot follow yourself." error flash; no follow created

### Unfollow

- [ ] Click Unfollow on an active follow — "Unfollowed." flash appears; actor is removed from the list
- [ ] In iex, verify `unfollowed_at` is set on the follow row:
  ```elixir
  Revix.Repo.get_by(Revix.Follows.Follow, following_uri: "https://remote.example.com/users/alice")
  ```

---

## `/following` page — Followers tab

- [ ] Click the Followers tab — tab switches; "No followers yet." is shown when empty

### Pending followers (auto_accept: false)

To test the pending flow, temporarily disable auto-accept:

```elixir
# in iex
Application.put_env(:revix, :follows, auto_accept: false)
```

- [ ] POST a valid signed `Follow` activity to `POST /people/{id}/inbox` — server responds with **202**
- [ ] Navigate to `/following` → Followers tab — the remote actor appears in a "Pending" section with an Accept button
- [ ] Click Accept — "Follower accepted." flash; actor moves from Pending to the accepted list
- [ ] In iex, verify `accepted_at` is set on the follow row
- [ ] Verify a `DeliverAcceptFollowWorker` job was enqueued:
  ```elixir
  Oban.Job |> Ecto.Query.where(worker: "Revix.Workers.DeliverAcceptFollowWorker") |> Revix.Repo.all()
  ```

Reset auto-accept:
```elixir
Application.put_env(:revix, :follows, auto_accept: true)
```

---

## Inbound Follow (unsigned — should be rejected)

```bash
curl -X POST http://localhost:4000/people/{person_id}/inbox \
  -H "Content-Type: application/activity+json" \
  -d '{"@context":"https://www.w3.org/ns/activitystreams","type":"Follow","id":"https://remote.example.com/follows/1","actor":"https://remote.example.com/users/alice","object":"http://localhost:4000/people/{person_id}"}'
```

- [ ] Server responds with **401**

---

## Inbound Follow (malformed — missing object)

```bash
curl -X POST http://localhost:4000/people/{person_id}/inbox \
  -H "Content-Type: application/activity+json" \
  -d '{"type":"Follow","id":"https://remote.example.com/follows/1","actor":"https://remote.example.com/users/alice"}'
```

- [ ] Server responds with **400** (missing required field rejected at controller)

---

## Inbound Follow (valid, signed, auto_accept: true)

Using a cooperating remote server or signing tool, POST:

```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "type": "Follow",
  "id": "https://remote.example.com/follows/abc",
  "actor": "https://remote.example.com/users/alice",
  "object": "http://localhost:4000/people/{person_id}"
}
```

- [ ] Server responds with **202**
- [ ] In iex, verify the follow was recorded:
  ```elixir
  Revix.Repo.get_by(Revix.Follows.Follow, uri: "https://remote.example.com/follows/abc")
  ```
  - `origin` is `:remote`
  - `follower_uri` is `"https://remote.example.com/users/alice"`
  - `following_uri` is the local person's URI
  - `accepted_at` is not nil (auto-accepted)
  - `unfollowed_at` is nil
- [ ] Navigate to `/following` → Followers tab — the remote actor appears in the accepted list
- [ ] Verify a `DeliverAcceptFollowWorker` job was enqueued (Accept activity delivered to remote follower)

---

## Inbound Follow — idempotency

- [ ] POST the same signed `Follow` activity a second time — server responds with **202**
- [ ] In iex, verify only one follow row exists for that `uri`

---

## Inbound Follow — activity without `"id"`

- [ ] POST a valid signed `Follow` with no `"id"` field — server responds with **202**
- [ ] In iex, verify a follow was recorded with a `uri` that starts with `"tag:"`

---

## Inbound Undo Follow (object as plain URI)

The most common AP pattern: `"object"` is the URI of the original Follow.

- [ ] First record an inbound follow (see above)
- [ ] POST a valid signed `Undo` activity:
  ```json
  {
    "@context": "https://www.w3.org/ns/activitystreams",
    "type": "Undo",
    "id": "https://remote.example.com/users/alice/undo/1",
    "actor": "https://remote.example.com/users/alice",
    "object": "https://remote.example.com/follows/abc"
  }
  ```
- [ ] Server responds with **202**
- [ ] In iex, verify `unfollowed_at` is set on the follow row
- [ ] Navigate to `/following` → Followers tab — the actor no longer appears

---

## Inbound Undo Follow (object as full Follow map)

- [ ] POST a valid signed `Undo` with a nested Follow map including `"id"`:
  ```json
  {
    "@context": "https://www.w3.org/ns/activitystreams",
    "type": "Undo",
    "id": "https://remote.example.com/users/alice/undo/2",
    "actor": "https://remote.example.com/users/alice",
    "object": {
      "type": "Follow",
      "id": "https://remote.example.com/follows/abc",
      "actor": "https://remote.example.com/users/alice",
      "object": "http://localhost:4000/people/{person_id}"
    }
  }
  ```
- [ ] Server responds with **202**
- [ ] In iex, verify `unfollowed_at` is set

---

## Inbound Undo Follow (object map without `"id"` — fallback)

- [ ] Ensure an active inbound follow exists for the actor + person pair
- [ ] POST a valid signed `Undo` with a nested Follow map that has no `"id"`:
  ```json
  {
    "type": "Undo",
    "id": "https://remote.example.com/users/alice/undo/3",
    "actor": "https://remote.example.com/users/alice",
    "object": {
      "type": "Follow",
      "actor": "https://remote.example.com/users/alice",
      "object": "http://localhost:4000/people/{person_id}"
    }
  }
  ```
- [ ] Server responds with **202**
- [ ] In iex, verify `unfollowed_at` is set

---

## Inbound Undo Follow — idempotency

- [ ] POST the same Undo activity twice — server responds with **202** both times
- [ ] In iex, verify only one follow row exists and `unfollowed_at` is set

---

## Inbound Undo Follow — no matching follow

- [ ] POST a valid signed `Undo` for a follow URI that has never been received — server responds with **202** (silently discarded; no error)

---

## Re-follow after unfollow

### Local re-follow

- [ ] Follow a remote actor, then Unfollow them from the UI
- [ ] Follow the same URI again — "Follow request sent." flash; actor reappears in the Following list
- [ ] In iex, verify the same follow row was reused (same `id`), `unfollowed_at` is nil

### Remote re-follow

- [ ] Record an inbound follow, then POST a signed Undo to soft-delete it
- [ ] POST the same signed Follow again (same `"id"`) — server responds with **202**
- [ ] In iex, verify the same follow row was reused, `accepted_at` is set again, `unfollowed_at` is nil

---

## ActivityPub collection endpoints

### Followers collection

```bash
curl http://localhost:4000/people/{person_id}/followers \
  -H "Accept: application/activity+json"
```

- [ ] Returns JSON with `"type": "OrderedCollection"`
- [ ] `"totalItems"` equals the number of accepted, active followers
- [ ] `"orderedItems"` is an array of follower URI strings

### Following collection

```bash
curl http://localhost:4000/people/{person_id}/following \
  -H "Accept: application/activity+json"
```

- [ ] Returns JSON with `"type": "OrderedCollection"`
- [ ] `"totalItems"` equals the number of active outgoing follows
- [ ] `"orderedItems"` is an array of following URI strings

---

## Outbound Follow delivery

When the local server successfully connects to a cooperating remote server:

- [ ] Follow a remote actor URI from the `/following` page
- [ ] Verify a `Follow` activity was delivered to the remote actor's inbox (check the remote server's logs or admin panel)
- [ ] Unfollow from the UI — verify an `Undo{Follow}` activity was delivered to the remote actor's inbox

---

## PubSub live updates

- [ ] Open `/following` in one browser tab
- [ ] In iex, create a follow for the signed-in person:
  ```elixir
  scope = %Revix.People.Scope{person: Revix.Repo.get!(Revix.People.Person, "person_id"), role: :user}
  Revix.Follows.follow(scope, "https://remote.example.com/users/bob")
  ```
- [ ] The Following list updates in the browser tab without a page reload

---

## Inbox for unknown person

- [ ] POST a valid signed `Follow` to `/people/doesnotexist/inbox` — server responds with **404**

---

## Automated tests

```
make tests
```

Should report **0 failures** (1243 Elixir tests, 35 JS tests).
