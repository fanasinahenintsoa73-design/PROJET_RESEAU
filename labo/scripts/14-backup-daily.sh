#!/bin/bash
# =============================================================================
# Sauvegarde quotidienne - LABO
# Usage : sudo ./14-backup-daily.sh
#
# PERIMETRE (conception) :
#   bases postfix + roundcube, Maildir, config systeme, certificat,
#   cles DKIM/RSA
# HORS PERIMETRE : fichiers temporaires, journaux, OS lui-meme.
#
# Un snapshot = un etat coherent. Le dump des bases est ecrit dans une
# zone de transit AVANT le backup, puis supprime : on ne sauvegarde donc
# jamais un dump a moitie ecrit.
# =============================================================================
set -euo pipefail

[ -f /etc/default/meteo-backup ] || { echo "ERREUR : lancer 13-backup-init.sh d'abord" >&2; exit 1; }
# shellcheck disable=SC1091
. /etc/default/meteo-backup

REPO="${BACKUP_ROOT}/restic-repo"
STAGING=/var/backups/meteo/staging
export RESTIC_PASSWORD_FILE=/root/.restic-password
TAG=meteo

echo "=========================================================="
echo " Sauvegarde quotidienne - $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================================="

# --- 1. Dump des bases ------------------------------------------------------
echo "[1/5] Dump des bases MariaDB"
mkdir -p "${STAGING}"
rm -f "${STAGING}"/*.sql.gz
DUMP_OK=1
for db in postfix roundcube; do
    if mysqldump --single-transaction --quick --routines --triggers \
                 "${db}" 2>/tmp/dump-${db}.err | gzip -9 > "${STAGING}/${db}.sql.gz"; then
        SIZE=$(stat -c%s "${STAGING}/${db}.sql.gz")
        echo "  ${db}.sql.gz : ${SIZE} octets"
    else
        echo "  ECHEC sur la base ${db} :" >&2
        cat /tmp/dump-${db}.err >&2
        DUMP_OK=0
    fi
done
# Sauvegarder une base vide est pire que ne rien sauvegarder : on
# s'arrete plutot que de deposer une sauvegarde qui a l'air correcte.
[ "${DUMP_OK}" -eq 1 ] || { echo "ABANDON : dump incomplet" >&2; exit 1; }

# --- 2. Perimetre -----------------------------------------------------------
echo "[2/5] Constitution du perimetre"
# Un chemin absent ne doit pas faire echouer tout le backup (exemple :
# /var/lib/rspamd/dkim n'existe qu'apres la premiere signature DKIM).
CANDIDATS=(
    "${STAGING}"
    /var/vmail
    /etc/postfix
    /etc/dovecot
    /etc/rspamd
    /etc/ssl
    /etc/hostname
    /etc/mailname
    /etc/hosts
    /etc/resolv.conf
    /etc/aliases
    /opt/postfixadmin/config.local.php
    /var/www/roundcube/config
    /var/lib/rspamd/dkim
)
CHEMINS=()
for p in "${CANDIDATS[@]}"; do
    if [ -e "${p}" ]; then
        CHEMINS+=("${p}")
    else
        echo "  (absent, ignore) ${p}"
    fi
done
echo "  ${#CHEMINS[@]} chemins a sauvegarder"

# --- 3. Backup --------------------------------------------------------------
echo "[3/5] Creation du snapshot"
# On capture la sortie complete dans un log, puis on verifie le resultat
# dans ce log. Ne pas faire transiter le verdict par un `grep` dans une
# affectation : avec `set -o pipefail`, un grep sans correspondance
# interromprait le script ALORS que la sauvegarde, elle, a reussi.
restic -r "${REPO}" backup \
        --tag "${TAG}" \
        --host "$(hostname)" \
        --exclude-caches \
        "${CHEMINS[@]}" > /tmp/restic-backup.log 2>&1 || {
            echo "ERREUR : restic backup a echoue" >&2
            tail -20 /tmp/restic-backup.log >&2
            exit 1
        }
tail -3 /tmp/restic-backup.log | sed 's/^/  /'

SNAP_ID=$(grep -oE 'snapshot [0-9a-f]+ saved' /tmp/restic-backup.log | awk '{print $2}' | head -1)
if [ -z "${SNAP_ID}" ]; then
    echo "ERREUR : le snapshot n'a pas ete confirme par restic" >&2
    cat /tmp/restic-backup.log >&2
    exit 1
fi
echo "  ID du snapshot : ${SNAP_ID}"

# --- 4. Retention -----------------------------------------------------------
# Conception : 7 jours en quotidien. Le depot deporte (15-copie-deportee.sh)
# garde l'historique au-dela : on ne perd donc rien en purgeant ici.
echo "[4/5] Retention (7 versions quotidiennes)"
restic -r "${REPO}" forget \
        --tag "${TAG}" \
        --keep-daily 7 \
        --keep-weekly 4 \
        --prune 2>&1 | tail -3

# --- 5. Verification --------------------------------------------------------
# Une sauvegarde non verifiee n'est pas une sauvegarde.
echo "[5/5] Verification du depot"
restic -r "${REPO}" check --read-data-subset=5% 2>&1 | tail -2

# --- Nettoyage --------------------------------------------------------------
rm -f "${STAGING}"/*.sql.gz

echo
echo "Snapshots restants :"
restic -r "${REPO}" snapshots --compact 2>/dev/null | tail -3
echo "BACKUP_OK"
