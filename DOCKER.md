# Running myCRM with Docker

This repository ships a self-contained image (PHP-FPM + Nginx + Supervisor)
plus a `docker-compose.yml` that wires it up with MySQL, Redis, a queue
worker, a scheduler loop, and MailHog for local email testing.

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
- caches config/routes/views.

The `queue` and `scheduler` containers wait for `app` to report healthy
before starting.

## 3. Finish the CRM setup

The database schema exists after step 2, but Krayin's own data (seed data,
admin user) still needs to be created. Either:

- open `http://localhost:8080/install` and follow the web installer, or
- run the CLI installer once:

  ```bash
  docker compose exec app php artisan krayin-crm:install --skip-env-check
  ```

## Services

| Service     | Purpose                                               |
|-------------|--------------------------------------------------------|
| `app`       | Nginx + PHP-FPM, published on `${APP_PORT:-8080}`       |
| `queue`     | `php artisan queue:work` (same image, different command) |
| `scheduler` | Runs `php artisan schedule:run` every minute — drives `inbound-emails:process` |
| `mysql`     | MySQL 8.0, data persisted in the `mysql_data` volume    |
| `redis`     | Cache / session / queue backend                        |
| `mailhog`   | Catches outgoing mail in dev — UI on `http://localhost:8025` |

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
- The image caches config/routes/views on every `app` container start, which
  assumes `APP_ENV=production`. If you need to iterate quickly, set
  `APP_ENV=local` and drop the `*:cache` lines from `docker/entrypoint.sh`.
