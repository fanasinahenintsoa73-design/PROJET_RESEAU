#!/bin/bash
# =============================================================================
# Deploiement de Rspamd - LABO meteo-test.lan
# Usage : sudo ./08-deploy-rspamd.sh
# Idempotent.
#
# PREREQUIS : paquets rspamd + redis-server installes.
# Postfix doit pointer vers le milter (applique par ce script via postconf).
# =============================================================================
set -euo pipefail

SRC="${SRC:-/tmp/labo-rspamd}"

echo "=== 1. Utilisateur _rspamd (cree par le paquet, on verifie) ==="
getent passwd _rspamd || { echo "ERREUR : paquet rspamd non installe" >&2; exit 1; }

echo "=== 2. Redis actif ? ==="
systemctl is-active redis-server > /dev/null || sudo systemctl start redis-server || systemctl start redis-server
systemctl is-active redis-server && echo "REDIS_ACTIF"

echo "=== 3. Deploiement local.d ==="
cp "${SRC}/actions.conf" /etc/rspamd/local.d/actions.conf
cp "${SRC}/milter_headers.conf" /etc/rspamd/local.d/milter_headers.conf
cp "${SRC}/antivirus.conf" /etc/rspamd/local.d/antivirus.conf
chown -R root:_rspamd /etc/rspamd/local.d/
chmod 640 /etc/rspamd/local.d/*.conf
ls -la /etc/rspamd/local.d/

echo "=== 4. Validation + redemarrage ==="
rspamadm configtest && echo "RSPAMD_CONFIG_OK"
systemctl restart rspamd
sleep 4
systemctl is-active rspamd && echo "RSPAMD_ACTIF"
rspamc stat 2>&1 | head -8 || true

echo "=== 5. Milter Postfix -> Rspamd ==="
postconf -e 'smtpd_milters = inet:127.0.0.1:11332'
postconf -e 'non_smtpd_milters = $smtpd_milters'
postconf -e 'milter_protocol = 6'
postconf -e 'milter_mail_macros = i {mail_addr} {client_addr} {client_name} {auth_type} {auth_authen} {auth_author}'
postconf -e 'milter_default_action = accept'
postfix reload
postconf -n | grep -E 'milter|smtpd_milters' || true

echo "=== 6. Test bout-en-bout via le milter ==="
echo "From: tiana.rakoto@meteo-test.lan
To: luc.ranaivo@meteo-test.lan
Subject: [RSPAMD-TEST] verification milter

Corps de test." | swaks --to luc.ranaivo@meteo-test.lan --from tiana.rakoto@meteo-test.lan --server 127.0.0.1 --port 25 --data - 2>&1 | grep -E '^(250|250 |354|250-|250 Ok)' | tail -2 || true
sleep 2
echo "--- Headers ajoutes par Rspamd sur le dernier message ---"
sudo bash -c 'ls -t /var/vmail/meteo-test.lan/luc.ranaivo/new/ | head -1 | xargs -I{} grep -iE "^(X-Spamd|X-Rspamd|Authentication-Results)" /var/vmail/meteo-test.lan/luc.ranaivo/new/{}' || echo "(pas de headers rspamd trouves)"
echo "EXIT=0 (fin script 08)"