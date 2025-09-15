# ====== Base PHP-FPM con extensiones necesarias ======
FROM php:8.2-fpm-bullseye

# Args opcionales
ARG NODE_MAJOR=20
ARG DEBIAN_FRONTEND=noninteractive

# Paquetes del sistema y extensiones PHP requeridas por Aureus (Laravel 11 + paquetes)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl unzip cron supervisor nginx \
    libpq-dev libzip-dev libicu-dev libxml2-dev \
    libpng-dev libjpeg-dev libwebp-dev libfreetype6-dev \
    pkg-config ca-certificates gnupg \
    && docker-php-ext-configure intl \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) pdo pdo_pgsql bcmath intl pcntl gd zip opcache

# Redis (extensión PHP)
RUN pecl install redis \
    && docker-php-ext-enable redis

# Composer (desde imagen oficial)
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# NodeJS (para build de assets cuando se requiera)
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs

# Limpieza
RUN rm -rf /var/lib/apt/lists/*

# ====== Estructura y configs ======
# Directorio de la app (código se montará como volumen)
ENV APP_DIR=/var/www/aureus
RUN mkdir -p ${APP_DIR}
WORKDIR ${APP_DIR}

# Nginx config
RUN rm -f /etc/nginx/sites-enabled/default
COPY ./infra/nginx.conf /etc/nginx/nginx.conf
COPY ./infra/nginx-site.conf /etc/nginx/conf.d/aureus.conf

# PHP-FPM tuning opcional
COPY ./infra/php-fpm.ini /usr/local/etc/php/conf.d/zz-custom.ini

# Supervisor: php-fpm, nginx, queue, scheduler
COPY ./infra/supervisor.conf /etc/supervisor/conf.d/supervisor.conf

# Entrypoint: instala dependencias, prepara .env, permisos, cachea y lanza procesos
COPY ./infra/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Permisos para Laravel
RUN usermod -u 1000 www-data && groupmod -g 1000 www-data || true
RUN chown -R www-data:www-data ${APP_DIR}

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=5 \
  CMD curl -fsS http://127.0.0.1:8080/ || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/supervisord","-c","/etc/supervisor/supervisord.conf","-n"]
