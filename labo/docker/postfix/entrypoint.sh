#!/bin/bash
# =============================================================================
# Demarrage de Postfix dans le conteneur.
# 1. rend main.cf et les cartes SQL depuis les modeles (envsubst cible)
# 2. ajoute les services submission/smtps au master.cf (une seule fois)
# 3. lance Postfix au premier plan
# =============================================================================
set -euo pipefail

: "${MAIL_DOMAIN:?}" "${MAIL_HOSTNAME:?}" "${DB_HOST:?}" "${DB_NAME:?}" "${DB_USER:?}" "${DB_PASSWORD:?}"
: "${RSPAMD_HOST:=rspamd}"

VARS='${MAIL_DOMAIN} ${MAIL_HOSTNAME} ${DB_HOST} ${DB_NAME} ${DB_USER} ${DB_PASSWORD} ${RSPAMD_HOST}'

mkdir -p /etc/postfix/sql

envsubst "${VARS}" < /etc/postfix/main.cf.template > /etc/postfix/main.cf
envsubst "${VARS}" < /etc/postfix/sql/mailbox.cf.template > /etc/postfix/sql/mailbox.cf
envsubst "${VARS}" < /etc/postfix/sql/alias.cf.template > /etc/postfix/sql/alias.cf

chown root:root /etc/postfix/main.cf
chmod 0644 /etc/postfix/main.cf
chown root:postfix /etc/postfix/sql/mailbox.cf /etc/postfix/sql/alias.cf
chmod 0640 /etc/postfix/sql/mailbox.cf /etc/postfix/sql/alias.cf

if ! grep -q '^submission_meteo ' /etc/postfix/master.cf; then
    cat /etc/postfix/master.cf.append >> /etc/postfix/master.cf
    echo "[postfix] services submission (587) et smtps (465) ajoutes"
fi

# En conteneur, le chroot de Postfix n'a pas l'arborescence /etc complete.
# On le desactive partout : c'est l'isolation du conteneur qui joue ce role.
postconf -F '*/*/chroot=n'

echo "[postfix] demarrage, domaine ${MAIL_DOMAIN}, hote ${MAIL_HOSTNAME}"
exec postfix start-fg
