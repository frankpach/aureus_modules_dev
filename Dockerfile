# ========= 1) CÓDIGO =========
FROM alpine/git:latest AS code
ARG AUREUS_REPO=https://github.com/aureuserp/aureuserp.git
ARG AUREUS_REF=master
WORKDIR /src
RUN set -eux; \
  git init; git remote add origin "${AUREUS_REPO}"; \
  if git ls-remote --heads --tags origin "${AUREUS_REF}" | grep -q .; then \
    echo "Using ref ${AUREUS_REF}"; git fetch --depth 1 origin "${AUREUS_REF}"; \
  else \
    DEFAULT_REF="$(git ls-remote --symref origin HEAD | awk '/^ref:/ {print $2}' | sed 's#refs/heads/##')"; \
    echo "Ref ${AUREUS_REF} no existe, fallback -> ${DEFAULT_REF}"; \
    git fetch --depth 1 origin "${DEFAULT_REF}"; \
  fi; \
  git checkout -qf FETCH_HEAD

# ========= 2) COMPOSER (vendor) =========
FROM composer:2 AS vendor
WORKDIR /app
COPY --from=code /src ./
# Instala dependencias de producción según composer.json provisto
RUN composer install --no-dev --prefer-dist --no-interaction --no-scripts --optimize-autoloader

# ========= 3) ASSETS (Vite) =========
FROM node:20 AS assets
WORKDIR /app
COPY --from=code /src/package*.json ./
RUN npm ci --no-audit --no-fund || npm install
COPY --from=code /src ./
RUN npm run build

# ========= 4) RUNTIME PHP 8.3 + Apache =========
FROM php:8.3-apache
SHELL ["/bin/bash","-lc"]

# Parámetro: se sobreescribe por servicio (_prod / _dev)
ARG APP_DIR=/var/www/html/code
ENV APP_DIR=${APP_DIR}
ENV APACHE_DOCUMENT_ROOT=${APP_DIR}/public
ENV COMPOSER_ALLOW_SUPERUSER=1

# Paquetes + extensiones PHP (incluye pgsql)
RUN apt-get update && apt-get install -y \
    git unzip curl libzip-dev libpng-dev libjpeg-dev libfreetype6-dev libicu-dev \
    libpq-dev \
 && docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" pdo_pgsql bcmath intl zip gd exif mbstring opcache \
 && pecl install redis \
 && docker-php-ext-enable redis \
 && a2enmod rewrite headers \
 && sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' \
      /etc/apache2/sites-available/*.conf /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf \
 && rm -rf /var/lib/apt/lists/*

# Opcache recomendado (prod seguro)
RUN printf "\nopcache.enable=1\nopcache.enable_cli=1\nopcache.validate_timestamps=0\nopcache.max_accelerated_files=20000\nopcache.memory_consumption=256\nopcache.interned_strings_buffer=16\n" > /usr/local/etc/php/conf.d/opcache-recommended.ini

# Código + vendor + assets
WORKDIR ${APP_DIR}
COPY --from=code   /src               ${APP_DIR}
COPY --from=vendor /app/vendor        ${APP_DIR}/vendor
COPY --from=assets /app/public/build  ${APP_DIR}/public/build

# Entrypoint embebido
RUN set -eux && cat > /usr/local/bin/entrypoint.sh <<'SCRIPT'
#!/usr/bin/env bash
set -e

APP_DIR="${APP_DIR:-/var/www/html/code}"
cd "$APP_DIR"

# .env base
[ -f .env ] || cp .env.example .env

# Sustituye variables críticas en .env (idempotente)
php -r '
$env = file_exists(".env") ? file_get_contents(".env") : "";
function putenvline($k,$v){ global $env; $k=trim($k); $v=str_replace(["\n","\r"],"",$v); if(preg_match("/^$k=/m",$env)){ $env=preg_replace("/^$k=.*$/m","$k=$v",$env);} else { $env .= PHP_EOL."$k=$v";}}
$map=["APP_ENV"=>getenv("APP_ENV")?: "production",
      "APP_URL"=>getenv("APP_URL")?: "http://localhost",
      "APP_DEBUG"=>(getenv("APP_DEBUG")?: "false"),
      "DB_CONNECTION"=>getenv("DB_CONNECTION")?: "pgsql",
      "DB_HOST"=>getenv("DB_HOST")?: "postgres",
      "DB_PORT"=>getenv("DB_PORT")?: "5432",
      "DB_DATABASE"=>getenv("DB_DATABASE")?: "aureus",
      "DB_USERNAME"=>getenv("DB_USERNAME")?: "aureus",
      "DB_PASSWORD"=>getenv("DB_PASSWORD")?: "aureus",
      "CACHE_DRIVER"=>getenv("CACHE_DRIVER")?: "redis",
      "QUEUE_CONNECTION"=>getenv("QUEUE_CONNECTION")?: "redis",
      "REDIS_HOST"=>getenv("REDIS_HOST")?: "redis",
      "REDIS_PORT"=>getenv("REDIS_PORT")?: "6379"];
foreach($map as $k=>$v){ putenvline($k,$v); }
file_put_contents(".env",$env);
';

# Esperar DB si está configurada
if [ -n "${DB_HOST:-}" ]; then
  echo "Waiting for DB ${DB_HOST}:${DB_PORT:-5432}..."
  for i in {1..90}; do
    php -r 'try{$c=new PDO("pgsql:host=".getenv("DB_HOST").";port=".getenv("DB_PORT").";dbname=".getenv("DB_DATABASE"), getenv("DB_USERNAME"), getenv("DB_PASSWORD")); exit(0);}catch(Exception $e){exit(1);}'; \
    && break || sleep 2
  done || echo "DB not reachable, continuing..."
fi

# Preparación Laravel/Aureus (idempotente)
php artisan key:generate --force || true
php artisan package:discover --ansi || true
php artisan storage:link || true
php artisan migrate --force || true
php artisan optimize || true

# Instalación Aureus (opcional: crea admin/roles/datos iniciales)
if [ "${AUREUS_AUTO_INSTALL:-false}" = "true" ]; then
  php artisan erp:install || true
fi

# Procesos opcionales
if [ "${RUN_QUEUE:-false}" = "true" ]; then
  php artisan queue:work --tries=3 --max-time=3600 & disown
fi
if [ "${RUN_SCHEDULE:-false}" = "true" ]; then
  php artisan schedule:work & disown
fi

exec "$@"
SCRIPT
RUN chmod +x /usr/local/bin/entrypoint.sh \
 && chown -R www-data:www-data ${APP_DIR}/storage ${APP_DIR}/bootstrap/cache

HEALTHCHECK --interval=30s --timeout=10s --retries=5 CMD curl -fsS http://localhost/ || exit 1
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2-foreground"]
