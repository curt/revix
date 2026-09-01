# Revix

[![CI](https://github.com/curt/revix/actions/workflows/ci.yml/badge.svg)](https://github.com/curt/revix/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/curt/revix/badge.svg)](https://coveralls.io/github/curt/revix)

A personal location journal with ActivityPub federation. Check in to places, write posts, tag companions, leave notes, follow other actors, and like entries. Built with Elixir/Phoenix.

## Features

- **Check-ins and notes** — record visits to places with optional notes and companions
- **Posts** — standalone entries not tied to a place, for freeform writing
- **Places** — backed by a local PostGIS database with live search via the OpenStreetMap Overpass API
- **Activity feed** — Atom 1.0 feed of check-ins, notes, and likes
- **Sitemap** — XML sitemap of public places, posts, and profiles
- **Likes and comments** — like any check-in; leave short notes as comments
- **Companions** — tag other users who were present at a check-in
- **Follows** — follow remote ActivityPub actors by URI
- **Pings** — peer-to-peer ActivityPub ping/pong between instances (owner-only)
- **Email notifications** — hourly, daily (default), weekly, or monthly digests of new posts, comments, likes, and companion tags on threads you follow
- **Magic-link auth** — passwordless sign-in via email

## Federation

Revix speaks ActivityPub: per-person RSA keypairs, HTTP Signatures, WebFinger discovery, NodeInfo, and JSON-LD responses for check-ins and places. Implemented activities: Follow/Accept/Undo (follows), Create/Update/Delete (entries, inbound and outbound), Like/Undo (inbound and outbound), and Ping/Pong. Inbound follows are auto-accepted by default. Local entries are fanned out to followers on create, update, and delete. Pages include structured data (Schema.org JSON-LD) and microformats2 markup.

## Tech Stack

- **Elixir / Phoenix 1.8** with LiveView for the check-in flow
- **PostgreSQL + PostGIS** for location data
- **Tailwind CSS v4**
- **Waffle + S3** for avatar and image uploads
- **cloak_ecto** for AES-256-GCM encryption of private keys at rest

## Development

Requires Elixir, PostgreSQL with PostGIS, and a `.env` file. Copy `.env.example` if present, or set the variables listed in `config/runtime.exs`.

```sh
mix setup        # install deps, create and migrate DB, build assets
make serve       # start the server
make tests       # run the test suite
make precommit   # compile, format, and test (run before committing)
```

Database operations:

```sh
make migrate-db
make rollback-db
```

After registering the first account, promote it to owner manually via `iex`:

```elixir
Revix.People.set_person_role(Revix.Repo.get_by!(Revix.People.Person, email: "you@example.com"), :owner)
```

## Deployment

See [DEPLOYMENT.md](DEPLOYMENT.md) for Docker-based production setup, required environment variables, and reverse proxy notes. AWS (S3 for media and backups, SES for email) is required in production; local development uses local storage and the test mail adapter.

## License

Copyright &copy; 2026 Curt Gilman

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the [GNU Affero General Public License](LICENSE.txt) for more details.
