# Deployment

Prerequisites: Docker with Compose, an ARM64 host (CI produces ARM64-only images), two S3 buckets (media and database backups), and AWS SES for outbound email.

## Docker

Create a `.env` file alongside `docker-compose.yml`:

```dotenv
# App
DOCKER_TAG=latest
REVIX_HOST=revix.example.com
PHX_SERVER=true
REVIX_PORT=4000          # bound to 127.0.0.1 on the host

# Secrets — generate each with the command in the comment
SECRET_KEY_BASE=         # mix phx.gen.secret
CLOAK_KEY=               # elixir -e "IO.puts(32 |> :crypto.strong_rand_bytes() |> Base.encode64())"

# Database
POSTGRES_PASSWORD=       # choose a strong password
POSTGRES_PORT=5433       # host port for the DB container

# AWS (S3 + SES)
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_S3_REGION=
AWS_S3_BUCKET=           # media uploads
AWS_S3_DUMP_BUCKET=      # database backups
```

Create a `docker-compose.yml`:

```yaml
services:
  db:
    image: ghcr.io/curt/postgis:18-3.6-alpine
    restart: unless-stopped
    ports:
      - "${POSTGRES_PORT}:5432"
    environment:
      POSTGRES_DB: revix
      POSTGRES_USER: revix
      POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"
    volumes:
      - pg_data:/var/lib/postgresql/data

  app:
    image: ghcr.io/curt/revix:${DOCKER_TAG}
    restart: unless-stopped
    env_file: .env
    environment:
      DATABASE_URL: "ecto://revix:${POSTGRES_PASSWORD}@db/revix"
    ports:
      - "127.0.0.1:${REVIX_PORT}:4000"
    depends_on:
      - db

volumes:
  pg_data:
```

Then start everything:

```sh
docker compose up -d
```

The container entrypoint waits for Postgres to be ready, runs migrations automatically, then starts the server. Logs: `docker compose logs -f app`.

**Reverse proxy:** the app listens on `127.0.0.1:${REVIX_PORT}`. Point your proxy at that address and forward `X-Forwarded-For` and `X-Forwarded-Proto` headers so Phoenix generates correct URLs and redirects.

**Optional vars:** `POOL_SIZE` (default 10), `AWS_REGION` (default `us-east-1`), `ECTO_IPV6=true` for IPv6 database connections.
