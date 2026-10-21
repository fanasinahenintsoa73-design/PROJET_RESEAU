#!/bin/bash
# =============================================================================
# Deploiement de Rspamd - LABO meteo-test.lan
# Usage : sudo ./08-deploy-rspamd.sh
# Idempotent.
#
# PREREQUIS : paquets rspamd + redis-server installes.
#             Pour la version officielle (4.x) : voir 23-install-rspamd-officiel.sh
# Postfix doit pointer vers le milter (applique par ce script via postconf).
#
# Compatible Rspamd 2.7 (paquets Ubuntu) et 4.x (depot officiel rspamd.com) :
# les 4 fichiers de local.d sont valides dans les deux versions.
# =============================================================================
set -euo pipefail

SRC="${SRC:-/tmp/labo-rspamd}"
DOMAINE="${DOMAINE:-meteo-test.lan}"
SELECTEUR="${SELECTEUR:-dkim}"
# Modele de chemin de Rspamd : "$domain.$selector.key" -> le DOMAINE en premier.
# Une clef mal nommee produit "dkim_module_load_key_format: cannot parse raw
# private key" et le message part SANS signature, silencieusement.
DKIM_DIR="/var/lib/rspamd/dkim"
DKIM_KEY="${DKIM_DIR}/${DOMAINE}.${SELECTEUR}.key"

echo "=== 1. Utilisateur _rspamd (cree par le paquet, on verifie) ==="
getent passwd _rspamd || { echo "ERREUR : paquet rspamd non installe" >&2; exit 1; }
rspamd --version 2>&1 | head -2

echo "=== 2. Redis actif ? ==="
systemctl is-active redis-server > /dev/null || systemctl start redis-server
systemctl is-active redis-server && echo "REDIS_ACTIF"

echo "=== 3. Deploiement local.d (install : proprietaire + mode en une fois) ==="
# install -o root -g _rspamd -m 640 remplace cp + chown + chmod.
for f in actions.conf milter_headers.conf antivirus.conf dkim_signing.conf; do
    if [ ! -f "${SRC}/${f}" ]; then
        echo "ERREUR : fichier source manquant : ${SRC}/${f}" >&2
        exit 1
    fi
    install -o root -g _rspamd -m 640 "${SRC}/${f}" "/etc/rspamd/local.d/${f}"
done
ls -la /etc/rspamd/local.d/

echo "=== 4. Cle de signature DKIM ==="
mkdir -p "${DKIM_DIR}"
if [ -f "${DKIM_KEY}" ]; then
    echo "Cle presente : ${DKIM_KEY} (conservee)"
else
    # rspamadm dkim_keygen n'ECRIT aucun fichier sans -k : il affiche la cle
    # sur la sortie standard. Sans -k, aucune cle n'est produite.
    rspamadm dkim_keygen -d "${DOMAINE}" -s "${SELECTEUR}" -b 2048 -k "${DKIM_KEY}" > /tmp/dkim-record.txt
    chown _rspamd:_rspamd "${DKIM_KEY}"
    chmod 640 "${DKIM_KEY}"
    echo "Cle generee : ${DKIM_KEY}"
    echo "--- Enregistrement DNS a publier (a poser dans la zone) ---"
    cat /tmp/dkim-record.txt
fi
stat -c '%n %U:%G %a' "${DKIM_KEY}"

echo "=== 5. Validation de la configuration ==="
# ATTENTION : rspamadm configtest/configdump exigent les privileges root.
# En utilisateur simple : "Permission denied" sur les fichiers de local.d,
# et le script conclut a tort que le module est absent.
rspamadm configtest && echo "RSPAMD_CONFIG_OK"

echo "=== 6. Controles de structure (4.x) ==="
# PIEGE : le fichier de sortie de configdump depasse le tampon de 64 Ko.
# Un "echo | grep -q motif" avec "set -o pipefail" renvoie 141 (SIGPIPE sur le
# grep qui sort des la premiere correspondance) : le script conclut alors a tort
# que le motif est ABSENT. On travaille donc sur un FICHIER, jamais sur un pipe.
DUMP="$(mktemp)"
trap 'rm -f "${DUMP}"' EXIT
rspamadm configdump > "${DUMP}" 2>&1 || true

# a) un fichier local.d NE DOIT PAS redeclarer l'enveloppe du module :
#    "antivirus { antivirus { ... } }" est un bloc imbrique, Rspamd le signale
#    "nested section" et ignore le module (le module ne scanne RIEN, sans
#    message d'erreur visible dans le journal de Postfix).
if grep -q "nested section" "${DUMP}"; then
    echo "ERREUR : section imbriquee detectee dans /etc/rspamd/local.d/" >&2
    grep -n "nested section" "${DUMP}" >&2 || true
    exit 1
fi
if grep -q "unknown antivirus type" "${DUMP}"; then
    echo "ERREUR : type de scanner inconnu (enveloppe antivirus { } de trop)" >&2
    grep -n "unknown antivirus type" "${DUMP}" >&2 || true
    exit 1
fi
echo "STRUCTURE_OK (pas de section imbriquee, pas de type inconnu)"

# b) le module antivirus doit reellement voir la configuration clamav
if grep -q "clamav" "${DUMP}"; then
    echo "ANTIVIRUS_CONFIG_OK"
else
    echo "ATTENTION : le scanner clamav n'apparait pas dans la configuration effective" >&2
fi

# c) le module de signature DKIM doit voir le modele de chemin
if grep -q "dkim_signing" "${DUMP}"; then
    echo "DKIM_SIGNING_CONFIG_OK"
else
    echo "ATTENTION : dkim_signing absent de la configuration effective" >&2
fi

echo "=== 7. Redemarrage ==="
systemctl restart rspamd
sleep 4
systemctl is-active rspamd && echo "RSPAMD_ACTIF"
# La commande de statistiques est "rspamc stat" ; "rspamadm stat" n'existe pas
# (erreur silencieuse).
rspamc stat 2>&1 | head -8 || true

echo "=== 8. Milter Postfix -> Rspamd ==="
postconf -e 'smtpd_milters = inet:127.0.0.1:11332'
postconf -e 'non_smtpd_milters = $smtpd_milters'
postconf -e 'milter_protocol = 6'
postconf -e 'milter_mail_macros = i {mail_addr} {client_addr} {client_name} {auth_type} {auth_authen} {auth_author}'
postconf -e 'milter_default_action = accept'
postfix reload
postconf -n | grep -E 'milter|smtpd_milters' || true

echo "=== 9. Test bout-en-bout via le milter ==="
echo "From: tiana.rakoto@meteo-test.lan
To: luc.ranaivo@meteo-test.lan
Subject: [RSPAMD-TEST] verification milter

Corps de test." | swaks --to luc.ranaivo@meteo-test.lan --from tiana.rakoto@meteo-test.lan --server 127.0.0.1 --port 25 --data - 2>&1 | grep -E '^(250|250 |354|250-|250 Ok)' | tail -2 || true
sleep 2
echo "--- Headers ajoutes par Rspamd sur le dernier message ---"
sudo bash -c 'ls -t /var/vmail/meteo-test.lan/luc.ranaivo/new/ | head -1 | xargs -I{} grep -iE "^(X-Spamd|X-Rspamd|Authentication-Results)" /var/vmail/meteo-test.lan/luc.ranaivo/new/{}' || echo "(pas de headers rspamd trouves)"
echo "EXIT=0 (fin script 08)"
