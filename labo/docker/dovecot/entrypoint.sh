#!/bin/bash
# =============================================================================
# Demarrage de Dovecot dans le conteneur.
# =============================================================================
set -euo pipefail

: "${DB_HOST:?}" "${DB_NAME:?}" "${DB_USER:?}" "${DB_PASSWORD:?}"

VARS='${DB_HOST} ${DB_NAME} ${DB_USER} ${DB_PASSWORD}'

envsubst "${VARS}" < /etc/dovecot/dovecot-sql.conf.template > /etc/dovecot/dovecot-sql.conf
chown root:dovecot /etc/dovecot/dovecot-sql.conf
chmod 0640 /etc/dovecot/dovecot-sql.conf

mkdir -p /var/run/dovecot /var/lib/dovecot /var/vmail/sieve
chown -R vmail:vmail /var/vmail

echo "[dovecot] demarrage, base ${DB_NAME} sur ${DB_HOST}"
exec dovecot -F
