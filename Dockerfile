# ------------------------------------------------------------------------------
# Aureus ERP Runtime (Ubuntu 24.04 + Nginx + PHP-FPM 8.4 + Supervisor)
# - SIN Node en runtime
# - Código de la app montado en /var/www/aureus (volumen persistente de EasyPanel)
# - Copia configs desde ./docker/*.*
# ------------------------------------------------------------------------------

FROM ubuntu:24.04

# ------------------
# Variables de entorno
# ------------------
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    APP_DIR=/var/www/aureus \
    PHP_VERSION=8.4 \
    FPM_USER=www-data \
    FPM_GROUP=www-data \
    PHP_MEMORY_LIMIT=512M \
    PHP_UPLOAD_MAX_FILESIZE=64M \
    PHP_POST_MAX_SIZE=64M \
    PHP_MAX_EXECUTION_TIME=120 \
    PHP_OPCACHE_ENABLE=1 \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS=0 \
    PHP_OPCACHE_MEMORY_CONSUMPTION=256 \
    PHP_OPCACHE_MAX_ACCELERATED_FILES=20000

# ------------------
# Paquetes del sistema + PHP 8.4 (Ondřej Surý PPA) + Composer
# ------------------
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
      gnupg ca-certificates curl wget nano unzip git supervisor \
      nginx \
      software-properties-common lsb-release tzdata \
      libzip4 zip \
      libicu-dev \
      libpng-dev libjpeg-turbo8-dev libfreetype6-dev libwebp-dev \
      libpq-dev libmysqlclient-dev && \
    add-apt-repository ppa:ondrej/php -y && apt-get update && \
    apt-get install -y --no-install-recommends \
      php8.4 php8.4-fpm php8.4-cli php8.4-common \
      php8.4-xml php8.4-mbstring php8.4-curl php8.4-gd \
      php8.4-mysql php8.4-mysqli \
      php8.4-intl php8.4-zip php8.4-bcmath php8.4-pgsql \
      php8.4-readline php8.4-opcache php8.4-redis && \
    curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php && \
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer && \
    rm -f /tmp/composer-setup.php && \
    apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/*

# ------------------
# Directorios y permisos básicos
# ------------------
RUN mkdir -p ${APP_DIR} /run/php /var/log/supervisor /var/cache/nginx && \
    chown -R ${FPM_USER}:${FPM_GROUP} ${APP_DIR} /run/php /var/cache/nginx

# ------------------
# Nginx - eliminar default y copiar configuración del proyecto
# ------------------
RUN rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default
COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/site.conf  /etc/nginx/conf.d/aureus.conf

# ------------------
# PHP-FPM y overrides de PHP
# ------------------
COPY docker/php-fpm.conf /etc/php/8.4/fpm/pool.d/www.conf
COPY docker/php.ini      /etc/php/8.4/fpm/conf.d/zzz-custom.ini

# ------------------
# Supervisor (Nginx + PHP-FPM)
# ------------------
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# ------------------
# Entrypoint (prepara .env, composer, caches; arranca supervisor)
# ------------------
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ------------------
# Healthcheck simple (requiere curl)
# ------------------
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/health || exit 1

# ------------------
# Puerto, volumen y workdir
# ------------------
EXPOSE 8080
VOLUME ["/var/www/aureus"]
WORKDIR ${APP_DIR}

# ------------------
# Lanzar entrypoint (no usar CMD; supervisor se lanza desde entrypoint)
# ------------------
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
