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


exec "$@"
