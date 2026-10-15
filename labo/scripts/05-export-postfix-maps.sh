#!/bin/bash
# =============================================================================
# Pont Postfix <-> MariaDB - DECISION N°1 DU DESIGN
# =============================================================================
# Postfix ne touche JAMAIS MariaDB directement. PostfixAdmin ecrit en base,
# ce script exporte vers des fichiers plats, `postmap` les compile.
# Si la base tombe, Postfix continue de livrer.
#
# Usage : sudo ./05-export-postfix-maps.sh
# A mettre en cron toutes les 5 minutes en production :
#   */5 * * * * root /usr/local/bin/05-export-postfix-maps.sh >/dev/null 2>&1
# Idempotent.
# =============================================================================
set -euo pipefail

MYSQL="mysql --batch --skip-column-names postfix"
MAP_MAILBOX=/etc/postfix/postfix_accounts.cf
MAP_ALIAS=/etc/postfix/virtual_alias.cf

echo "=== Export des boites actives ==="
# La colonne `maildir` de PostfixAdmin contient deja `domaine/compte/`
# (ex : meteo-test.lan/tiana.rakoto/). Concatene a virtual_mailbox_base
# (/var/vmail), cela donne le chemin exact de la boite. On reutilise la
# donnee maintenue par PostfixAdmin plutot que de la reconstruire.
${MYSQL} -e "SELECT CONCAT(username,' ',maildir) FROM mailbox WHERE active=1;" > "${MAP_MAILBOX}.tmp"

NB_MBOX=$(wc -l < "${MAP_MAILBOX}.tmp")
echo "Boites exportees : ${NB_MBOX}"

echo "=== Export des alias actifs (hors auto-alias boite->boite) ==="
${MYSQL} -e "SELECT CONCAT(address,' ',goto) FROM alias WHERE active=1 AND address <> goto;" > "${MAP_ALIAS}.tmp"

# Les goto de PostfixAdmin utilisent des virgules, Postfix les accepte telles quelles.
NB_ALIAS=$(wc -l < "${MAP_ALIAS}.tmp")
echo "Alias exportes : ${NB_ALIAS}"

echo "=== Compilation postmap ==="
cp "${MAP_MAILBOX}.tmp" "${MAP_MAILBOX}"
postmap "hash:${MAP_MAILBOX}"
cp "${MAP_ALIAS}.tmp" "${MAP_ALIAS}"
postmap "hash:${MAP_ALIAS}"

chown root:postfix "${MAP_MAILBOX}" "${MAP_MAILBOX}.db" "${MAP_ALIAS}" "${MAP_ALIAS}.db"
chmod 640 "${MAP_MAILBOX}" "${MAP_MAILBOX}.db" "${MAP_ALIAS}" "${MAP_ALIAS}.db"
rm -f "${MAP_MAILBOX}.tmp" "${MAP_ALIAS}.tmp"

echo "=== Verification ==="
postmap -q "tiana.rakoto@meteo-test.lan" "hash:${MAP_MAILBOX}" && echo "MAP_MBOX_OK" || echo "MAP_MBOX_VIDE_OU_ABSENT"
postfix reload && echo "POSTFIX_RECHARGE"
echo "TERMINE : ${NB_MBOX} boites, ${NB_ALIAS} alias."