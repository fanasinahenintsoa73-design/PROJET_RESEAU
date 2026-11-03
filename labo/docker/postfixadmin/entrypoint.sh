#!/bin/bash
# =============================================================================
# Demarrage de PostfixAdmin dans le conteneur.
# =============================================================================
set -euo pipefail

: "${DB_HOST:?}" "${DB_NAME:?}" "${DB_USER:?}" "${DB_PASSWORD:?}" "${MAIL_DOMAIN:?}"

VARS='${DB_HOST} ${DB_NAME} ${DB_USER} ${DB_PASSWORD} ${MAIL_DOMAIN}'

envsubst "${VARS}" < /opt/postfixadmin/config.local.php.template \
    > /var/www/postfixadmin/config.local.php

chown www-data:www-data /var/www/postfixadmin/config.local.php
chmod 0640 /var/www/postfixadmin/config.local.php

echo "[postfixadmin] demarrage, base ${DB_NAME} sur ${DB_HOST}"
exec apache2-foreground
