#!/bin/bash
# =============================================================================
# Installation de Rspamd depuis le DEPOT OFFICIEL (rspamd.com) - LABO
# Usage : sudo ./23-install-rspamd-officiel.sh
# Idempotent.
#
# POURQUOI LE DEPOT OFFICIEL ET NON LES PAQUETS UBUNTU
# ------------------------------------------------------
# Les paquets Ubuntu 22.04 fournissent Rspamd 2.7, qui date de 2019. Le projet
# Rspamd ne les supporte pas ("They are typically outdated... Always use the
# official Rspamd repositories"). En production, la pile doit etre celle du
# depot officiel, sinon ce que l'on valide en laboratoire n'est pas ce qui
# tourne. Ecart ferme en phase 15 (D9).
#
# OU EST LA DOCUMENTATION OFFICIELLE
# ------------------------------------
# Elle n'est PLUS sur rspamd.com : ce site est une application monopage qui
# renvoie sa page d'accueil (HTTP 200, 54 Ko de HTML) pour TOUTE URL, y
# compris "rspamd.repo" qui n'existe plus. Un simple "code 200" ne prouve donc
# rien : il faut verifier le type de contenu et les premiers octets.
# La procedure officielle se trouve sur https://docs.rspamd.com/downloads/
#
# PROCEDURE REELLE (verifiee)
# ----------------------------
#   sudo mkdir -p /etc/apt/keyrings
#   wget -O- https://rspamd.com/apt-stable/gpg.key | gpg --dearmor \
#        | sudo tee /etc/apt/keyrings/rspamd.gpg > /dev/null
#   CODENAME=$(lsb_release -c -s)
#   echo "deb [signed-by=/etc/apt/keyrings/rspamd.gpg] \
#        http://rspamd.com/apt-stable/ $CODENAME main" \
#        | sudo tee /etc/apt/sources.list.d/rspamd.list
# Le depot utilise la disposition apt standard : dists/<codename>/...
# Versions publiees : jammy 3.3 minimum (version courante 4.2.2),
# noble 3.9 minimum, resolute 4.2.2. bullseye et focal ne sont plus servis.
#
# TROIS PIEGES D'INSTALLATION (tous contournes ici)
# --------------------------------------------------
# 1. dpkg + conffile + stdin ferme = blocage
#    DEBIAN_FRONTEND=noninteractive ne supprime PAS l'invite de conffile.
#    Sans terminal, dpkg lit EOF et echoue :
#      "dpkg: erreur de traitement du paquet rspamd (--configure)"
#    Contournement : dpkg --configure -a --force-confnew
#
# 2. Desinstallation incomplete = configuration INVALIDE
#    Apres installation, /etc/rspamd ne contenait que les conffiles : il
#    manquait settings.conf, logging.inc et 22 fichiers de modules.d/ (dont
#    dkim_signing.conf et milter_headers.conf). Consequence :
#      "ucl parser error: cannot open file /etc/rspamd/settings.conf"
#    alors que dpkg --audit est vide et que dpkg -L annonce 116 fichiers.
#    Le .deb etait complet (verifie par dpkg-deb -c) : c'etait l'etat dpkg.
#    "apt-get install --reinstall" ne corrige RIEN (dpkg juge les fichiers
#    deja installes). Solution appliquee : dpkg --purge puis reinstallation.
#    Controle obligatoire apres toute installation : comparer dpkg -L avec
#    l'existence reelle des fichiers.
#
# 3. La purge emporte /var/lib/rspamd/dkim
#    Ce repertoire n'appartient pas au paquet mais il a ete supprime par la
#    purge : la cle privee DKIM a disparu, donc TOUS les envois signes
#    deviennent impossibles. Elle est ici restauree depuis la sauvegarde
#    Restic (preuve que la sauvegarde sert a quelque chose), puis les droits
#    _rspamd:_rspamd 640 sont reappliques.
# =============================================================================
set -euo pipefail

CODENAME="${CODA:-$(lsb_release -c -s)}"
DOMAINE="${DOMAINE:-meteo-test.lan}"
SELECTEUR="${SELECTEUR:-dkim}"
DKIM_DIR="/var/lib/rspamd/dkim"
DKIM_KEY="${DKIM_DIR}/${DOMAINE}.${SELECTEUR}.key"
BACKUP_ROOT="${BACKUP_ROOT:-/srv/sauvegarde}"
REPO="${BACKUP_ROOT}/restic-repo"
SRC="${SRC:-/tmp/labo-rspamd}"

echo "=== 1. Sauvegarde de la configuration et de la cle DKIM ==="
if [ -d /etc/rspamd ] && [ ! -d /root/rspamd-backup-avant-officiel ]; then
    cp -a /etc/rspamd /root/rspamd-backup-avant-officiel
    echo "Config sauvegardee dans /root/rspamd-backup-avant-officiel"
fi
if [ -f "${DKIM_KEY}" ] && [ ! -f "/root/${DOMAINE}.${SELECTEUR}.key.sauvegarde" ]; then
    cp -a "${DKIM_KEY}" "/root/${DOMAINE}.${SELECTEUR}.key.sauvegarde"
    echo "Cle DKIM sauvegardee dans /root/${DOMAINE}.${SELECTEUR}.key.sauvegarde"
fi

echo "=== 2. Depot officiel : cle GPG + liste de sources ==="
mkdir -p /etc/apt/keyrings
curl -fsSL https://rspamd.com/apt-stable/gpg.key | gpg --dearmor > /etc/apt/keyrings/rspamd.gpg
# Verification du type de contenu : une vraie cle commence par
# "-----BEGIN PGP PUBLIC KEY BLOCK-----", pas par "<!DOCTYPE html>".
if ! head -c 30 /etc/apt/keyrings/rspamd.gpg | grep -q "PGP PUBLIC KEY BLOCK"; then
    echo "ERREUR : la cle GPG telechargee n'est pas une cle (le site a renvoye du HTML)" >&2
    exit 1
fi
echo "deb [signed-by=/etc/apt/keyrings/rspamd.gpg] https://rspamd.com/apt-stable/ ${CODENAME} main" > /etc/apt/sources.list.d/rspamd.list
cat /etc/apt/sources.list.d/rspamd.list
echo "CLE_GPG_OK"

echo "=== 3. Mise a jour des index APT ==="
apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/rspamd.list -o Dir::Etc::sourceparts=/dev/null -o APT::Get::List-Cleanup=0 2>&1 | tail -3
apt-get update 2>&1 | tail -3

echo "=== 4. Purge propre puis reinstallation depuis le depot officiel ==="
# La purge garantit un etat dpkg coherent (piege 2). Elle emporte la cle DKIM
# (piege 3) : elle est restauree a l'etape 5.
dpkg --purge rspamd > /dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends rspamd 2>&1 | tail -8 || true
# Piege 1 : sur conffile supprime, dpkg lit EOF et echoue -> on force.
dpkg --configure -a --force-confnew 2>&1 | tail -5 || true
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends -o Dpkg::Options::=--force-confnew rspamd 2>&1 | tail -5 || true

echo "=== 5. Controle d'integrite : dpkg -L vs fichiers reels ==="
MANQUANTS=0
while read -r f; do
    case "${f}" in
        /etc/*|/usr/*|/var/*)
            if [ ! -e "${f}" ]; then
                echo "MANQUANT : ${f}"
                MANQUANTS=$((MANQUANTS + 1))
            fi
            ;;
    esac
done < <(dpkg -L rspamd)
if [ "${MANQUANTS}" -gt 0 ]; then
    echo "ERREUR : ${MANQUANTS} fichier(s) du paquet absent(s) sur le disque" >&2
    echo "       -> dpkg --purge rspamd puis reinstaller" >&2
    exit 1
fi
echo "INTEGRITE_OK (tous les fichiers du paquet sont presents)"
echo "Fichiers de modules.d : $(ls /etc/rspamd/modules.d/ | wc -l)"

echo "=== 6. Restauration de la cle DKIM ==="
if [ ! -f "${DKIM_KEY}" ]; then
    if [ -f "/root/${DOMAINE}.${SELECTEUR}.key.sauvegarde" ]; then
        install -o _rspamd -g _rspamd -m 640 "/root/${DOMAINE}.${SELECTEUR}.key.sauvegarde" "${DKIM_KEY}"
        echo "Cle restauree depuis la copie locale"
    elif [ -f /root/.restic-password ] && [ -d "${REPO}" ]; then
        # Restauration ciblee : --include evite d'ecraser la configuration
        # 4.x, que le snapshot contient aussi dans sa version 2.7.
        RESTIC_PASSWORD_FILE=/root/.restic-password restic -r "${REPO}" restore latest \
            --target / --include "/var/lib/rspamd/dkim" 2>&1 | tail -3
        chown _rspamd:_rspamd "${DKIM_KEY}" 2>/dev/null || true
        chmod 640 "${DKIM_KEY}" 2>/dev/null || true
        echo "Cle restauree depuis la sauvegarde Restic"
    else
        echo "ERREUR : aucune source pour la cle DKIM" >&2
        exit 1
    fi
else
    echo "Cle presente, conservee"
fi
stat -c '%n %U:%G %a' "${DKIM_KEY}"

echo "=== 7. Deploiement de la configuration local.d ==="
if [ -f "${SRC}/actions.conf" ]; then
    for f in actions.conf milter_headers.conf antivirus.conf dkim_signing.conf; do
        install -o root -g _rspamd -m 640 "${SRC}/${f}" "/etc/rspamd/local.d/${f}"
    done
    echo "local.d deploie depuis ${SRC}"
else
    echo "ATTENTION : ${SRC} absent, lancer 08-deploy-rspamd.sh apres ce script" >&2
fi

echo "=== 8. Version et validite ==="
rspamd --version 2>&1 | head -3
rspamadm configtest && echo "RSPAMD_CONFIG_OK"
systemctl enable rspamd > /dev/null 2>&1 || true
systemctl restart rspamd
sleep 4
systemctl is-active rspamd && echo "RSPAMD_ACTIF"
ss -lntp 2>/dev/null | grep 11332 || true
echo "EXIT=0 (fin script 23)"
