# ActivityPub Ping — Manual Testing Checklist

**Date:** 2026-05-09
**Branch:** topics/activitypub-ping
**Scope:** Owner-only Ping/Pong federation at `/pings`; inbox at `POST /people/:id/inbox`.

---

## Setup

- Have an **owner-role** account available.
- Have a separate **non-owner** account available.
- Optionally, have a second ActivityPub server (e.g., a local Mastodon or Honk instance, or a public test actor) reachable for end-to-end delivery tests.
- Note the local server's base URL (e.g., `http://localhost:4000`).

---

## Navigation

- [ ] Sign in as the **owner** — a "Pings" item appears in the dropdown menu between Settings and Sign out
- [ ] Sign in as a **non-owner** — no "Pings" item appears in the dropdown menu

---

## Authentication & authorization at `/pings`

- [ ] Navigate to `/pings` while **not signed in** — redirected to `/people/signin`
- [ ] Sign in as a **non-owner** and navigate to `/pings` — redirected to `/` with a flash error
- [ ] Sign in as the **owner** and navigate to `/pings` — the "ActivityPub Pings" page loads with a "Send Ping" form and a table

---

## Empty state

- [ ] With no pings recorded, the table shows a single row: "No pings yet."

---

## Sending a ping

- [ ] Enter a well-formed actor URI in the "Target Actor URI" field and click **Send Ping** — a "Ping sent." flash appears and a new row appears in the table immediately
- [ ] The new row shows **outbound**, **ping**, the owner's avatar and display name as Actor, and a Status of either **pending**, **delivered**, or **failed**
- [ ] Once the remote actor has been fetched and stored locally, the Target column also shows their avatar and display name; before that it shows the raw URI in monospace
- [ ] Submit the form with an empty field — behavior depends on the server's response; verify no crash occurs

---

## Delivery status updates (live)

- [ ] Send a ping to a reachable remote actor — within a few seconds the Status column updates from "pending" to "delivered" without a page refresh
- [ ] Send a ping to an unreachable or invalid URI — the Status column updates to "failed"; the error reason appears below the status in the row

---

## Inbound Ping (receiving)

To test inbound Pings, use `curl` or a second ActivityPub server to POST a signed Ping to the owner's inbox. The inbox URL is `{base_url}/people/{person_id}/inbox`.

**Unsigned request — should be rejected:**

```bash
curl -X POST http://localhost:4000/people/{person_id}/inbox \
  -H "Content-Type: application/activity+json" \
  -d '{"@context":"https://www.w3.org/ns/activitystreams","type":"Ping","id":"https://example.com/ping/1","actor":"https://example.com/users/tester","to":"{person_uri}"}'
```

- [ ] Server responds with **401**

**Malformed activity (missing required fields) — should be rejected:**

```bash
curl -X POST http://localhost:4000/people/{person_id}/inbox \
  -H "Content-Type: application/activity+json" \
  -d '{"type":"Ping"}'
```

- [ ] Server responds with **400**

**Valid signed Ping from a cooperating server:**

- [ ] Server responds with **202**
- [ ] A new row appears in the `/pings` table showing **inbound**, **ping**, the remote actor URI, the owner URI, and **pending** status
- [ ] Shortly after, the status updates to **delivered** (the local server has sent a Pong in reply)

---

## Inbound Pong (receiving)

When a valid Ping has been sent and the remote server replies:

- [ ] A new row appears in the `/pings` table showing **inbound**, **pong**, the remote actor URI, the owner URI, and **delivered** status
- [ ] The `object` field of the inbound Pong matches the `id` of the original outbound Ping

---

## Non-owner inbox (owner constraint enforced in worker)

- [ ] POST a valid signed Ping to a non-owner person's inbox — server responds with **202** (activity accepted)
- [ ] No ping row appears in the `/pings` table (the worker silently discards it)
- [ ] No Pong is sent in reply

---

## Inbox for unknown person

- [ ] POST to `/people/doesnotexist/inbox` — server responds with **404**

---

## Unknown activity type

- [ ] POST a valid signed `Follow` activity to the owner's inbox — server responds with **202**; no row appears in the table (unknown types are accepted and discarded)

---

## Self-ping round trip

When the owner's own actor URI is used as the target:

- [ ] Enter the owner's own actor URI (e.g. `http://localhost:4000/people/{id}`) in the Target Actor URI field and click **Send Ping**
- [ ] A "Ping sent." flash appears and one outbound ping row appears with status **pending**, then **delivered**
- [ ] The server receives the Ping at its own inbox and sends a Pong back to itself — an outbound pong row appears, then its status updates to **delivered**
- [ ] No duplicate rows appear for either the ping or the pong URI (the self-send/receive collision is handled gracefully)
- [ ] Both rows show the owner's avatar and display name in both the Actor and Target columns

---

## End-to-end round trip

Using a cooperating remote server:

- [ ] Send a Ping to the remote actor — the outbound Ping row appears in the table with status **pending**, then **delivered**
- [ ] The remote server sends a Pong back — an inbound Pong row appears in the table with status **delivered**
- [ ] Both the outbound Ping and inbound Pong are visible in a single table view

---

## Key refresh (signature verifier staleness)

- [ ] If the remote actor's public key has been cached for more than 24 hours (the default `key_refresh_hours`), the verifier automatically re-fetches the actor document before verification — there is no observable difference in behavior; a 202 is returned normally

---

## Daily purge

The `PurgePingsWorker` runs at midnight UTC via Oban cron and deletes pings older than 7 days (configurable via `retention_days`). To verify manually:

- [ ] Confirm the Oban cron schedule is correct: `crontab: [{"0 0 * * *", Revix.Workers.PurgePingsWorker}]` in `config.exs`
- [ ] Trigger a purge from IEx: `Revix.Pings.purge_older_than(0)` — returns `{:ok, count}` and removes all rows

---

## Regression: existing ActivityPub endpoints

- [ ] `GET /@{username}` with `Accept: application/activity+json` — responds with the Person actor document including the `inbox` URL pointing to `/people/{id}/inbox`
- [ ] `GET /.well-known/webfinger?resource=acct:{username}@{host}` — responds with the actor's WebFinger document
- [ ] `GET /.well-known/nodeinfo` — responds with the NodeInfo pointer document
- [ ] Existing checkin, like, and note flows are unaffected

---

## Regression: remote person upsert

When the signature verifier fetches a remote actor for the first time:

- [ ] A row is inserted in the `people` table with `origin: remote`, a synthetic email of the form `{sha256hex}@example.invalid`, and `public_key` populated
- [ ] The synthetic email cannot be used to log in (there is no magic-link entry for it)

---

## Browser console checks

- [ ] No JavaScript errors in the browser console during any of the above flows
- [ ] No server-side errors or crashes in the application log

---

## Automated tests

```
make tests
```

Should report **0 failures** (732 Elixir tests, 51 JS tests).
