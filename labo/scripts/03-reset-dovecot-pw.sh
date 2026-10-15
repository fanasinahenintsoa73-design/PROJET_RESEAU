#!/bin/bash
# =============================================================================
# Reinitialise le mot de passe MySQL de l'utilisateur `dovecot`
# (lecture seule sur postfix.mailbox) et le consigne dans le coffre labo.
#
# Usage : sudo ./03-reset-dovecot-pw.sh
# Idempotent : peut etre relance sans casse.
# =============================================================================
set -euo pipefail

COFFRE=/root/labo-credentials.txt

PW=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)

mysql -e "ALTER USER 'dovecot'@'localhost' IDENTIFIED BY '${PW}'; FLUSH PRIVILEGES;"

# On retire les anciennes lignes avant de re-ecrire, pour eviter les doublons
sed -i '/^MVPD_DOVECOT=/d' "${COFFRE}"
echo "MVPD_DOVECOT=${PW}" >> "${COFFRE}"
chmod 600 "${COFFRE}"

# Verification que les droits restent bien en lecture seule
echo "--- DROITS DOVECOT ---"
mysql -e "SHOW GRANTS FOR 'dovecot'@'localhost';"

echo "MVPD_DOVECOT=${PW}"