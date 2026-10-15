#!/bin/bash
# =============================================================================
# Deploiement de Postfix - LABO meteo-test.lan
# Usage : sudo ./06-deploy-postfix.sh
# Pre-requis : Dovecot deplooye (socket auth-client), comptes en base,
#              05-export-postfix-maps.sh present dans le meme dossier.
# Idempotent.
# =============================================================================
set -euo pipefail

SRC="${SRC:-/tmp/labo-postfix}"

echo "=== 1. Certificat snakeoil present ? ==="
if [ ! -f /etc/ssl/certs/ssl-cert-snakeoil.pem ]; then
    echo "Installation du paquet ssl-cert (fournit le cert auto-signe)..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y ssl-cert
fi
ls -la /etc/ssl/certs/ssl-cert-snakeoil.pem

echo "=== 2. Deployment de main.cf ==="
cp /etc/postfix/main.cf /etc/postfix/main.cf.avant-labo 2>/dev/null || true
cp "${SRC}/main.cf.labo" /etc/postfix/main.cf
chown root:root /etc/postfix/main.cf
chmod 644 /etc/postfix/main.cf

echo "=== 2b. Chroot du transport virtual : rien a faire sur Ubuntu 22.04 ==="
# Le defaut Ubuntu est deja `virtual unix - n n - - virtual` (chroot=n).
# On a tente `postconf -Me ...` mais la syntaxe est rejetee par Postfix 3.6
# ("requires service_name/type") ; comme le defaut convient, on ne touche
# a rien. Si un jour un OS livre virtual en chroot=y, editer
# /etc/postfix/master.cf a la main (5e colonne de la ligne `virtual` : y->n).

echo "=== 2c. UID/GID numeriques du vmail LOCAL (cf. RESOLUTION NUMERIQUE) ==="
VMAIL_UID=$(id -u vmail)
VMAIL_GID=$(id -g vmail)
postconf -e "virtual_uid_maps = static:${VMAIL_UID}"
postconf -e "virtual_gid_maps = static:${VMAIL_GID}"
echo "vmail local : uid=${VMAIL_UID} gid=${VMAIL_GID}"

echo "=== 3. Installation du script d'export (pont) ==="
cp "${SRC}/05-export-postfix-maps.sh" /usr/local/bin/05-export-postfix-maps.sh
chmod 755 /usr/local/bin/05-export-postfix-maps.sh

echo "=== 4. Generation des maps (export SQL -> plat -> postmap) ==="
/usr/local/bin/05-export-postfix-maps.sh

echo "=== 5. Validation + rechargement ==="
postfix check && echo "POSTFIX_CHECK_OK"
systemctl restart postfix
sleep 2
systemctl is-active postfix && echo "POSTFIX_ACTIF"
echo "--- PORTS SMTP ---"
ss -tlnp | grep -E ':(25|587)\b' || echo "AUCUN PORT SMTP !"