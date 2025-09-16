#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/var/www/aureus}"
FPM_USER="${FPM_USER:-www-data}"
FPM_GROUP="${FPM_GROUP:-www-data}"
APP_ENV="${APP_ENV:-production}"
APP_DEBUG="${APP_DEBUG:-false}"
RUN_MIGRATIONS="${RUN_MIGRATIONS:-false}"

echo "[entrypoint] APP_DIR=${APP_DIR} | APP_ENV=${APP_ENV} | APP_DEBUG=${APP_DEBUG}"

if [ ! -d "${APP_DIR}" ]; then
  echo "[entrypoint] ERROR: ${APP_DIR} no existe. ¿Montaste el volumen persistente en EasyPanel?"
  exit 1
fi

cd "${APP_DIR}"

# 1) Asegurar permisos mínimos
echo "[entrypoint] Ajustando permisos en storage/ y bootstrap/cache/"
mkdir -p storage bootstrap/cache
chown -R "${FPM_USER}:${FPM_GROUP}" storage bootstrap/cache || true
find storage -type d -exec chmod 775 {} \; || true
chmod -R 775 bootstrap/cache || true

# 2) .env
if [ ! -f ".env" ]; then
  if [ -f ".env.example" ]; then
    echo "[entrypoint] .env no existe, copiando desde .env.example"
    cp .env.example .env
  else
    echo "[entrypoint] .env y .env.example no existen, creando .env básico"
    cat > .env <<'EOF'
APP_NAME="AureusERP"
APP_ENV=production
APP_DEBUG=false
APP_URL=https://aureus-prod.qpppgy.easypanel.host
SESSION_SECURE_COOKIE=true
TRUSTED_PROXIES=*
APP_KEY=base64:LXUQWoVycEYjPWeXhH+pg1rB26gZElO1l9JAMsIz7nw=

DB_CONNECTION=pgsql
DB_HOST=aureus_postgres
DB_PORT=5432
DB_DATABASE=aureus_prod
DB_USERNAME=aureus
DB_PASSWORD=aad92db2838125518380

# Redis
CACHE_DRIVER=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis
SESSION_LIFETIME=120

REDIS_HOST=aureus_redis          # nombre del servicio Redis en EasyPanel
REDIS_USER=default
REDIS_PASSWORD=ac1bf51870062b699d89       # si creas Redis sin password, déjalo en null
REDIS_PORT=6379

COMPOSER_INSTALL=1
COMPOSER_NO_DEV=1
NODE_BUILD=1
LARAVEL_OPTIMIZE=1
RUN_MIGRATIONS=0
EOF
  fi
fi

# 3) Composer install (sin Node en runtime)
if [ ! -d "vendor" ] || [ ! -f "vendor/autoload.php" ]; then
  echo "[entrypoint] Ejecutando composer install (no se detectó vendor/)"
  if [ "${APP_ENV}" = "production" ]; then
    composer install --no-dev --prefer-dist --no-progress --optimize-autoloader
  else
    composer install --prefer-dist --no-progress
  fi
else
  echo "[entrypoint] vendor/ presente, omitiendo composer install"
fi

# 4) Generar APP_KEY si falta
if ! grep -qE '^APP_KEY=base64:' .env || [ -z "${APP_KEY:-}" ]; then
  echo "[entrypoint] Generando APP_KEY"
  php artisan key:generate --force || true
fi

# 5) Storage link
if [ ! -L "public/storage" ]; then
  echo "[entrypoint] Creando symlink public/storage"
  php artisan storage:link || true
fi

# 6) Optimizaciones / caches según entorno
if [ "${APP_ENV}" = "production" ]; then
  echo "[entrypoint] Optimizando (config/route/view caches)"
  php artisan config:cache || true
  php artisan route:cache || true
  php artisan view:cache || true
else
  echo "[entrypoint] Entorno dev/local: limpiando caches"
  php artisan config:clear || true
  php artisan route:clear || true
  php artisan view:clear || true
fi

# 7) Migraciones (opcional)
if [ "${RUN_MIGRATIONS}" = "true" ]; then
  echo "[entrypoint] Ejecutando migraciones --force"
  php artisan migrate --force || true
fi

# 8) Ajustar permisos finales para runtime
chown -R "${FPM_USER}:${FPM_GROUP}" storage bootstrap/cache || true

# 9) Iniciar Supervisor (Nginx + PHP-FPM)
echo "[entrypoint] Iniciando Supervisor..."
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
