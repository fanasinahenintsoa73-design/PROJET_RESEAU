#!/bin/bash
# =============================================================================
# Initialisation du depot de sauvegarde Restic - LABO
# Usage : sudo ./13-backup-init.sh
#
# Idempotent : relancer sur un depot existant ne le reinitalise pas.
#
# PROD : deux differences, rien d'autre.
#   1. BACKUP_ROOT   = /mnt/backup   (disque PHYSIQUEMENT SEPARE du RAID mail)
#   2. OFFSITE_ROOT  = chemin du depot hors site (disque USB chiffre, ou
#                      depot SFTP). En labo les deux sont sur le meme disque :
#                      c'est une divergence assumee (D11), le mecanisme de
#                      copie est identique.
# =============================================================================
set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/srv/sauvegarde}"
OFFSITE_ROOT="${OFFSITE_ROOT:-/srv/sauvegarde-deportee}"
REPO="${BACKUP_ROOT}/restic-repo"
OFFSITE_REPO="${OFFSITE_ROOT}/restic-repo"
COFFRE=/root/labo-credentials.txt
DOMAINE="${DOMAINE:-meteo-test.lan}"

gen_password() {
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-40
}

ensure_password() {
    # $1 = nom de la variable dans le coffre
    if ! grep -q "^$1=" "${COFFRE}" 2>/dev/null; then
        gen_password > "${COFFRE}.tmp"
        echo "$1=$(cat "${COFFRE}.tmp")" | sudo tee -a "${COFFRE}" > /dev/null
        rm -f "${COFFRE}.tmp"
        echo "  -> $1 genere et depose dans le coffre"
    else
        echo "  -> $1 deja present dans le coffre"
    fi
    chmod 600 "${COFFRE}"
}

echo "=== 1. Coffre de secrets ==="
# Deux mots de passe DISTINCTS : le depot local et le depot hors site
# n'ont pas le meme degre d'exposition, ils ne doivent donc pas partager
# la meme cle. Compromettre la sauvegarde locale ne donne pas la copie
# de secours.
ensure_password RESTIC_PASSWORD
ensure_password RESTIC_PASSWORD_OFFSITE

RESTIC_PW=$(grep '^RESTIC_PASSWORD=' "${COFFRE}" | tail -1 | cut -d= -f2-)
RESTIC_PW_OFF=$(grep '^RESTIC_PASSWORD_OFFSITE=' "${COFFRE}" | tail -1 | cut -d= -f2-)

echo "=== 2. Arborescence ==="
mkdir -p "${BACKUP_ROOT}" "${OFFSITE_ROOT}" /var/backups/meteo/staging
chmod 700 "${BACKUP_ROOT}" "${OFFSITE_ROOT}"
echo "  Depot local   : ${REPO}"
echo "  Depot deporte : ${OFFSITE_REPO}"

echo "=== 3. Depot local ==="
if [ -f "${REPO}/config" ]; then
    echo "  Deja initialise (${REPO})"
else
    export RESTIC_PASSWORD="${RESTIC_PW}"
    restic -r "${REPO}" init
    unset RESTIC_PASSWORD
    echo "  Initialise"
fi

echo "=== 4. Depot deporte (simule en labo) ==="
if [ -f "${OFFSITE_REPO}/config" ]; then
    echo "  Deja initialise (${OFFSITE_REPO})"
else
    export RESTIC_PASSWORD="${RESTIC_PW_OFF}"
    restic -r "${OFFSITE_REPO}" init
    unset RESTIC_PASSWORD
    echo "  Initialise"
fi

echo "=== 5. Fichier de secrets pour les scripts suivants ==="
# restic lit RESTIC_PASSWORD_FILE : on evite d'exporter le mot de passe
# dans l'environnement (visible par /proc/<pid>/environ pour root).
PWFILE=/root/.restic-password
grep '^RESTIC_PASSWORD=' "${COFFRE}" | cut -d= -f2- > "${PWFILE}"
chmod 600 "${PWFILE}"
PWFILE_OFF=/root/.restic-password-offsite
grep '^RESTIC_PASSWORD_OFFSITE=' "${COFFRE}" | cut -d= -f2- > "${PWFILE_OFF}"
chmod 600 "${PWFILE_OFF}"
echo "  ${PWFILE} et ${PWFILE_OFF} (600)"

echo "=== 6. Repaired : les scripts 14/15/16 unattendent le coffre ==="
cat > /etc/default/meteo-backup <<EOF
# Genere par 13-backup-init.sh - NE PAS EDITER A LA MAIN
BACKUP_ROOT="${BACKUP_ROOT}"
OFFSITE_ROOT="${OFFSITE_ROOT}"
DOMAINE="${DOMAINE}"
EOF
chmod 644 /etc/default/meteo-backup
cat /etc/default/meteo-backup

echo
echo "INIT_BACKUP_OK"
