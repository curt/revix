# Revix

[![CI](https://github.com/curt/revix/actions/workflows/ci.yml/badge.svg)](https://github.com/curt/revix/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/curt/revix/badge.svg)](https://coveralls.io/github/curt/revix)

A personal location journal. Check in to places, tag companions, leave notes, and like entries. Built with Elixir/Phoenix.

## Features

- **Check-ins** — record visits to places with optional notes and companions
- **Places** — backed by a local PostGIS database with live search via the OpenStreetMap Overpass API
- **Activity feed** — Atom 1.0 feed of check-ins and likes
- **Likes and comments** — like any check-in; leave short notes as comments
- **Companions** — tag other users who were present at a check-in
- **Magic-link auth** — passwordless sign-in via email

## Federation

Revix speaks ActivityPub at the edges: per-person RSA keypairs, WebFinger discovery, NodeInfo, and ActivityPub JSON-LD responses for check-ins and places. Full federation is not yet implemented.

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

## AWS (production)

Production deployments require an AWS account with:

- **S3** — two buckets: one for media uploads (avatars, images), one for database dump backups
- **SES** — for sending magic-link login emails
- **IAM credentials** — a single key pair with permissions for S3 (both buckets) and SES

Set `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `AWS_S3_REGION`, `AWS_S3_BUCKET`, and `AWS_S3_DUMP_BUCKET` accordingly. Local development uses local storage and the test mail adapter, so AWS is not required to run the app locally.

## License

Copyright (C) 2026 Curt Gilman

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the [GNU Affero General Public License](LICENSE.txt) for more details.
