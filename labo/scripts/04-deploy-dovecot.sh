#!/bin/bash
# =============================================================================
# Deploiement de Dovecot - LABO meteo-test.lan
# Usage : sudo ./04-deploy-dovecot.sh
# Idempotent.
# =============================================================================
set -euo pipefail

SRC="${SRC:-/tmp/labo-dovecot}"
COFFRE=/root/labo-credentials.txt

echo "=== 1. Utilisateur Unix vmail ==="
if ! getent group vmail > /dev/null; then
    groupadd -r vmail
fi
if ! getent passwd vmail > /dev/null; then
    useradd -r -g vmail -d /var/vmail -s /usr/sbin/nologin vmail
fi
getent passwd vmail

echo "=== 2. Arborescence des boites ==="
mkdir -p /var/vmail/meteo-test.lan
chown -R vmail:vmail /var/vmail
chmod 700 /var/vmail

echo "=== 3. Mot de passe MySQL dovecot ==="
MVPD=$(grep '^MVPD_DOVECOT=' "${COFFRE}" | tail -1 | cut -d= -f2-)
if [ -z "${MVPD}" ]; then
    echo "ERREUR : MVPD_DOVECOT introuvable dans ${COFFRE}" >&2
    exit 1
fi

echo "=== 4. Deployment de la conf SQL (secret injecte, fichier en 600) ==="
sed "s|__MVPD_DOVECOT__|${MVPD}|" "${SRC}/dovecot-sql.conf.labo" > /etc/dovecot/dovecot-sql.conf
chown root:root /etc/dovecot/dovecot-sql.conf
chmod 600 /etc/dovecot/dovecot-sql.conf
echo "OK (/etc/dovecot/dovecot-sql.conf, 600)"

echo "=== 5. Deployment de dovecot.conf ==="
cp "${SRC}/dovecot.conf.labo" /etc/dovecot/dovecot.conf
chown root:root /etc/dovecot/dovecot.conf
chmod 644 /etc/dovecot/dovecot.conf

echo "=== 6. Sieve global ==="
mkdir -p /var/lib/dovecot/sieve/global

echo "=== 7. Validation de la configuration ==="
doveconf -n > /dev/null && echo "CONFIG_VALIDE"

echo "=== 8. Redemarrage ==="
systemctl restart dovecot
sleep 3
systemctl is-active dovecot && echo "DOVECOT_ACTIF"
systemctl --no-pager --lines=15 status dovecot | tail -12