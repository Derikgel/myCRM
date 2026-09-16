#!/bin/bash
set -e

cd /var/www/html

ROLE="${CONTAINER_ROLE:-app}"

if [ ! -f .env ]; then
    echo "[entrypoint] .env not found. Copy .env.docker.example (or .env.example) to .env on the host and mount it before starting the containers."
    exit 1
fi

wait_for_db() {
    # Read straight from the .env file rather than exporting into the process
    # environment: an exported DB_HOST/DB_PORT would leak into the exec'd PHP
    # process below and make Laravel's immutable Dotenv loader skip re-reading
    # these values later if the .env file changes.
    local db_host db_port
    db_host=$(grep -E '^DB_HOST=' .env | tail -n1 | cut -d '=' -f2-)
    db_port=$(grep -E '^DB_PORT=' .env | tail -n1 | cut -d '=' -f2-)
    db_port=${db_port:-3306}

    if [ -z "$db_host" ]; then
        return 0
    fi

    echo "[entrypoint] Waiting for database at ${db_host}:${db_port}..."

    for i in $(seq 1 60); do
        if php -r "exit(@fsockopen('${db_host}', ${db_port}) ? 0 : 1);"; then
            echo "[entrypoint] Database is reachable."
            return 0
        fi
        sleep 2
    done

    echo "[entrypoint] Database was not reachable in time." >&2
    exit 1
}

wait_for_db

if [ "$ROLE" = "app" ]; then
    if grep -qE '^APP_KEY=\s*$' .env; then
        echo "[entrypoint] Generating application key..."
        php artisan key:generate --force --no-interaction
    fi

    php artisan storage:link || true

    echo "[entrypoint] Running database migrations..."
    php artisan migrate --force --no-interaction

    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
fi

exec "$@"
