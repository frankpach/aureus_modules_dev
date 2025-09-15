#!/usr/bin/env bash
set -e

APP_DIR="${APP_DIR:-/var/www/aureus}"
cd "$APP_DIR"

# 1) Cargar .env desde ENV_FILE si se indicó
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
  echo "[entrypoint] Copiando $ENV_FILE -> $APP_DIR/.env"
  cp "$ENV_FILE" "$APP_DIR/.env"
fi

# 2) Permisos básicos
mkdir -p storage framework cache bootstrap/cache
mkdir -p storage/app storage/framework/{cache,views,sessions} storage/logs
chown -R www-data:www-data storage bootstrap/cache

# 3) Composer install (controlado por flags)
#   COMPOSER_INSTALL=1 para ejecutar
#   COMPOSER_NO_DEV=1 en producción
if [ "${COMPOSER_INSTALL}" = "1" ]; then
  echo "[entrypoint] Ejecutando composer install..."
  if [ "${COMPOSER_NO_DEV}" = "1" ]; then
    sudo -u www-data COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --prefer-dist --no-progress --no-interaction --optimize-autoloader
  else
    sudo -u www-data COMPOSER_ALLOW_SUPERUSER=1 composer install --prefer-dist --no-progress --no-interaction
  fi
fi

# 4) NPM build opcional (para prod); requiere package.json en el volumen
#   NODE_BUILD=1 para ejecutar
if [ "${NODE_BUILD}" = "1" ] && [ -f "package.json" ]; then
  echo "[entrypoint] Construyendo assets..."
  sudo -u www-data npm ci || sudo -u www-data npm install
  sudo -u www-data npm run build || true
fi

# 5) Enlaces y optimización
if [ -f artisan ]; then
  php artisan storage:link || true
  if [ "${LARAVEL_OPTIMIZE}" = "1" ]; then
    php artisan optimize || true
    php artisan config:cache || true
    php artisan route:cache || true
    php artisan view:cache || true
  fi

  # Migraciones controladas por flag
  if [ "${RUN_MIGRATIONS}" = "1" ]; then
    php artisan migrate --force || true
  fi
fi

exec "$@"
