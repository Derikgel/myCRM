# Running myCRM with Docker

This repository ships a self-contained image (PHP-FPM + Nginx + Supervisor)
plus a `docker-compose.yml` that wires it up with MySQL, Redis, a queue
worker, a scheduler loop, Caddy (reverse proxy + automatic HTTPS), and
MailHog for local email testing.

## Prerequisites

- Docker Engine + Docker Compose v2 (`docker compose version`)

## 1. Create your environment file

```bash
cp .env.docker.example .env
```

Edit `.env` and adjust at least:

- `APP_URL` — the public URL you'll access the app on
- `DB_PASSWORD` / `DB_ROOT_PASSWORD` — set real passwords before going to production
- `MAIL_*` — point at a real SMTP provider once you're past local testing (MailHog is dev-only)
- `DOMAIN` — set this to get automatic HTTPS (see below); leave empty for plain HTTP

The compose file bind-mounts this exact `.env` into the `app`, `queue` and
`scheduler` containers, so all three always share the same configuration and
the same generated `APP_KEY`.

## 2. Build and start

```bash
docker compose up -d --build
```

On first boot the `app` container automatically:

- waits for MySQL to accept connections,
- generates `APP_KEY` if it's still empty,
- runs `php artisan storage:link`,
- runs `php artisan migrate --force`,
- caches config and views (not routes: `routes/api.php` has a closure-based
  route, which Laravel's route cache cannot serialize).

The `queue` and `scheduler` containers wait for `app` to report healthy
before starting.

## 3. Finish the CRM setup

The database schema exists after step 2, but Krayin's own data (seed data,
admin user) still needs to be created. Either:

- open `http://localhost/install` (or `https://your-domain/install` once
  HTTPS is set up) and follow the web installer, or
- run the CLI installer once:

  ```bash
  docker compose exec app php artisan krayin-crm:install --skip-env-check
  ```

## HTTPS

Caddy sits in front of `app` and is the only service publishing ports 80/443
to the host.

1. Point a DNS A record for your domain at the server's public IP.
2. Set `DOMAIN=crm.example.com` (no scheme) in `.env`.
3. Set `APP_URL=https://crm.example.com` in `.env`.
4. `docker compose up -d` (or `restart caddy` if it's already running).

Caddy requests and renews the Let's Encrypt certificate automatically the
first time it sees a request for that domain, and redirects HTTP to HTTPS.
Certificates persist in the `caddy_data` volume, so they survive container
recreation — don't run `docker compose down -v` casually, that wipes them
along with the database.

Without `DOMAIN` set, Caddy just serves plain HTTP on port 80.

## Services

| Service     | Purpose                                               |
|-------------|--------------------------------------------------------|
| `caddy`     | Reverse proxy on 80/443, automatic HTTPS when `DOMAIN` is set |
| `app`       | Nginx + PHP-FPM, reachable from `caddy` only (no host port) |
| `queue`     | `php artisan queue:work` (same image, different command) |
| `scheduler` | Runs `php artisan schedule:run` every minute — drives `inbound-emails:process` |
| `mysql`     | MySQL 8.0, data persisted in the `mysql_data` volume    |
| `redis`     | Cache / session / queue backend                        |
| `mailhog`   | Catches outgoing mail in dev — UI on `http://localhost:8025`, bound to localhost only (not internet-facing); tunnel with `ssh -L 8025:localhost:8025 <user>@<server>` to view it remotely |

## Useful commands

```bash
docker compose logs -f app
docker compose exec app php artisan tinker
docker compose exec app php artisan migrate:status
docker compose down          # stop
docker compose down -v       # stop and wipe database/redis/storage volumes
```

## Notes

- `storage/` is a named volume (`storage_data`) shared by `app`, `queue` and
  `scheduler`, so uploaded files and logs survive container recreation.
- Front-end assets (`public/build`) are compiled at image build time — rerun
  `docker compose up -d --build` after changing anything under `resources/`.
- The image caches config/views on every `app` container start, which
  assumes `APP_ENV=production`. If you need to iterate quickly, set
  `APP_ENV=local` and drop the `*:cache` lines from `docker/entrypoint.sh`.
