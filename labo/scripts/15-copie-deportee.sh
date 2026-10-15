#!/bin/bash
# =============================================================================
# Copie deportee hebdomadaire - LABO
# Usage : sudo ./15-copie-deportee.sh
#
# Le depot local est sur le meme batiment que la messagerie. Si le local
# est vole, pillé ou detruit (incendie), il est perdu avec le serveur.
# On recopie donc chaque semaine vers un depot hors site.
#
# LABO : le "depot hors site" est un second repertoire local. Ce n'est
# PAS un vrai site distant (divergence D11), mais le mecanisme, lui, est
# rigoureusement identique a ce qui tournera en prod.
#
# PROD : le depot de destination sera un disque USB chiffre ou un depot
# SFTP chez un tiers, sorti du batiment chaque semaine.
# =============================================================================
set -euo pipefail

[ -f /etc/default/meteo-backup ] || { echo "ERREUR : lancer 13-backup-init.sh d'abord" >&2; exit 1; }
# shellcheck disable=SC1091
. /etc/default/meteo-backup

REPO="${BACKUP_ROOT}/restic-repo"
OFFSITE_REPO="${OFFSITE_ROOT}/restic-repo"
TAG=meteo

export RESTIC_PASSWORD_FILE=/root/.restic-password
export RESTIC_PASSWORD_FILE2=/root/.restic-password-offsite

echo "=========================================================="
echo " Copie deportee - $(date '+%Y-%m-%d %H:%M:%S')"
echo " Source      : ${REPO}"
echo " Destination : ${OFFSITE_REPO}"
echo "=========================================================="

if [ ! -f "${OFFSITE_REPO}/config" ]; then
    echo "ERREUR : depot de destination absent (lancer 13-backup-init.sh)" >&2
    exit 1
fi

# Combien de snapshots a-t-on a copier ? On reprend exactement la
# retention locale : au-dela de 7 jours, le depot local n'a rien et on
# ne peut pas le recopier. Le depot distant ALORS sert d'archive longue.
NB_LOCAL=$(restic -r "${REPO}" snapshots --tag "${TAG}" --json 2>/dev/null | grep -o '"short_id"' | wc -l)
echo "[1/3] Snapshots presents en local : ${NB_LOCAL}"

if [ "${NB_LOCAL}" -eq 0 ]; then
    echo "ERREUR : aucun snapshot local a copier" >&2
    exit 1
fi

echo "[2/3] Copie vers le depot de distance"
# restic 0.12 : -r = source, --repo2 = destination.
# Les deux depots ayant des CLES DIFFERENTES, restic doit relire puis
# reecrire les donnees : c'est lent mais c'est ce qui rend la copie
# independante du depot d'origine.
restic -r "${REPO}" copy \
        --tag "${TAG}" \
        --repo2 "${OFFSITE_REPO}" 2>&1 | tail -3

echo "[3/3] Verification du depot de distance"
# On ouvre le depot de destination AVEC SON PROPRE MOT DE PASSE et on
# verifie que les donnees y sont lisibles et non corrompues.
export RESTIC_PASSWORD_FILE=/root/.restic-password-offsite
restic -r "${OFFSITE_REPO}" check --read-data-subset=5% 2>&1 | tail -2
NB_OFF=$(restic -r "${OFFSITE_REPO}" snapshots --tag "${TAG}" --json 2>/dev/null | grep -o '"short_id"' | wc -l)
echo "  Snapshots dans le depot de distance : ${NB_OFF}"

if [ "${NB_OFF}" -eq 0 ]; then
    echo "ERREUR : aucun snapshot dans le depot de distance" >&2
    exit 1
fi

echo
echo "Snapshots du depot de distance :"
restic -r "${OFFSITE_REPO}" snapshots --compact 2>/dev/null | tail -3
echo "COPIE_DEPORTEE_OK"
