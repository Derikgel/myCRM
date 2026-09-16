# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1: build front-end assets (Vite)
# ---------------------------------------------------------------------------
FROM node:20-alpine AS assets

WORKDIR /app

COPY . .

RUN npm install \
    && npm run build

# ---------------------------------------------------------------------------
# Stage 2: application image (php-fpm + nginx + supervisor)
# ---------------------------------------------------------------------------
FROM php:8.3-fpm-alpine AS app

# Runtime + build dependencies for the PHP extensions this project needs
RUN apk add --no-cache \
        nginx \
        supervisor \
        bash \
        curl \
        freetype \
        libjpeg-turbo \
        libpng \
        libzip \
        icu-libs \
        libxml2 \
        oniguruma \
    && apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        freetype-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        libzip-dev \
        icu-dev \
        libxml2-dev \
        oniguruma-dev \
        curl-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" \
        gd \
        pdo_mysql \
        mbstring \
        exif \
        pcntl \
        bcmath \
        intl \
        zip \
        curl \
        opcache \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apk del .build-deps \
    && rm -rf /var/cache/apk/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Application source (see .dockerignore for what is excluded)
COPY . .

# Pre-built front-end assets from the assets stage
COPY --from=assets /app/public/build ./public/build

RUN composer install \
        --no-dev \
        --optimize-autoloader \
        --no-interaction \
        --no-progress \
    && mkdir -p \
        storage/app/public \
        storage/framework/cache/data \
        storage/framework/sessions \
        storage/framework/testing \
        storage/framework/views \
        storage/logs \
        bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

COPY docker/nginx/default.conf /etc/nginx/http.d/default.conf
COPY docker/php/php.ini /usr/local/etc/php/conf.d/zz-app.ini
COPY docker/supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80

ENTRYPOINT ["entrypoint.sh"]

CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf", "-n"]
