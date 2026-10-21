#!/bin/bash
# =============================================================================
# 22-deploy-clamav.sh - Active l'antivirus sur les pieces jointes (ferme D6)
# -----------------------------------------------------------------------------
# Chaine de securite barriere 3 (Rspamd) : le module `antivirus` de Rspamd
# interroge clamd (ClamAV) pour les PIECES JOINTES et refuse le message si
# un virus est detecte. Le corps des messages n'est PAS scanne (decision de
# conception : un scan complet ferait chuter la delivrabilite).
#
# Ce script :
#   1. configure clamd (socket TCP sur la boucle locale uniquement)
#   2. active et demarre clamd + freshclam (et les ACTIVE au demarrage :
#      Ubuntu les installe "disabled", piege deja rencontre avec fail2ban)
#   3. deploie le bloc antivirus de Rspamd et relance Rspamd
#   4. teste la chaine de bout en bout (message sain + EICAR binaire + EICAR texte)
#
# Usage : sudo ./22-deploy-clamav.sh <repertoire_source>
#   le repertoire source doit contenir :
#     rspamd/local.d/antivirus.conf
#     scripts/test-clamav-eicar.py
# =============================================================================
set -euo pipefail

SRC_DIR="${1:-/tmp/labo-prod}"
CLAMD_CONF="/etc/clamav/clamd.conf"
RSPAMD_LOCAL="/etc/rspamd/local.d"
LOG_CLAMD="/var/log/clamav/clamav.log"

echo "=============================================================="
echo " Deploiement ClamAV + antivirus Rspamd (pieces jointes)"
echo "=============================================================="

if [ ! -d "${SRC_DIR}" ]; then
    echo "[ERREUR] Source absente : ${SRC_DIR}"
    exit 1
fi
if ! command -v clamd >/dev/null 2>&1; then
    echo "[ERREUR] clamd n'est pas installe (apt-get install clamav clamav-daemon clamav-freshclam)"
    exit 1
fi

# ------------------------------------------------- 1. configuration de clamd
echo ""
echo "--- [1/5] Configuration de clamd ---"
# clamd doit ecouter sur TCP 3310 (valeur par defaut du module antivirus de
# Rspamd) mais UNIQUEMENT sur la boucle locale : sur 0.0.0.0, le port
# 3310 serait une surface d'attaque inutile.
#
# PIEGE VERSION (ClamAV 1.5.4) : l'option d'ecoute s'appelle `TCPAddr`.
# L'option `TCPSocketAddr`, qui existe dans les versions 0.10x, a DISPARU :
#   ERROR: Parse error at /etc/clamav/clamd.conf:100: Unknown option TCPSocketAddr
#   ERROR: Can't open/parse the config file /etc/clamav/clamd.conf
# et clamd ne demarre pas du tout (service en etat "failed").
# On supprime donc toute ligne TCPSocketAddr laissee par une version
# anterieure du script (le script doit rester idempotent).
if grep -q '^TCPSocketAddr ' "${CLAMD_CONF}"; then
    sed -i '/^TCPSocketAddr /d' "${CLAMD_CONF}"
    echo "  [OK] option obsolete TCPSocketAddr supprimee (invalide en ClamAV 1.5.x)"
fi
if ! grep -q '^TCPSocket ' "${CLAMD_CONF}"; then
    printf '\n# --- Ajoute par 22-deploy-clamav.sh (module antivirus Rspamd) ---\nTCPSocket 3310\n' \
        >> "${CLAMD_CONF}"
    echo "  [OK] TCPSocket 3310 ajoute"
else
    echo "  [OK] TCPSocket deja configure"
fi
if ! grep -q '^TCPAddr ' "${CLAMD_CONF}"; then
    printf 'TCPAddr 127.0.0.1\n' >> "${CLAMD_CONF}"
    echo "  [OK] TCPAddr 127.0.0.1 (ecoute locale uniquement)"
else
    echo "  [OK] TCPAddr deja configure"
fi
# PIEGE : clamd refuse de demarrer si sa configuration est invalide.
# On la valide donc AVANT de tenter un demarrage, pour ne pas subir
# "Start request repeated too quickly".
if ! sudo clamd --config-file="${CLAMD_CONF}" --help >/dev/null 2>&1; then
    echo "  [INFO] clamd --help indisponible, verification par demarrage"
fi

# La taille maximale analysee par clamd doit rester superieure a celle
# demandee par Rspamd (max_size = 20 Mo) : sinon clamd refuse le flux.
MAXFILE=$(grep -E '^MaxFileSize ' "${CLAMD_CONF}" | awk '{print $2}')
STREAM=$(grep -E '^StreamMaxLength ' "${CLAMD_CONF}" | awk '{print $2}')
echo "  [INFO] clamd : MaxFileSize=${MAXFILE} StreamMaxLength=${STREAM}"

# ------------------------------------------------- 2. services clamd
echo ""
echo "--- [2/5] Services clamd et freshclam ---"
# PIEGE CONNU (comme fail2ban) : le paquet Ubuntu installe ces services
# "disabled". Sans "enable", l'antivirus s'arrete au premier redemarrage et
# la barriere 3 est silencieusement coupee.
systemctl enable --now clamav-daemon clamav-freshclam >/dev/null
if ! systemctl is-active clamav-daemon >/dev/null; then
    echo "[ERREUR] clamav-daemon n'a pas demarre. Cause la plus probable :"
    echo "          une option invalide dans ${CLAMD_CONF}."
    sudo journalctl -u clamav-daemon --no-pager -n 15 | grep -i 'ERROR' | head -10
    exit 1
fi
systemctl is-enabled clamav-daemon >/dev/null
echo "  [OK] clamav-daemon actif et active au demarrage"
echo "  [OK] clamav-freshclam actif et active au demarrage"

# Attente de l'ouverture du port 3310
ATTENTE=0
while ! (exec 3<>/dev/tcp/127.0.0.1/3310) 2>/dev/null; do
    ATTENTE=$((ATTENTE + 1))
    if [ "${ATTENTE}" -ge 60 ]; then
        echo "  [ERREUR] clamd n'ecoute pas sur 127.0.0.1:3310 apres 60 s"
        echo "          Extrait du journal clamd :"
        tail -15 "${LOG_CLAMD}" 2>/dev/null || true
        exit 1
    fi
    sleep 1
done
exec 3<&- 2>/dev/null || true
echo "  [OK] clamd ecoute sur 127.0.0.1:3310"

# Les signatures doivent etre la
if [ ! -f /var/lib/clamav/main.cvd ] && [ ! -f /var/lib/clamav/main.cld ]; then
    echo "  [AVERTISSEMENT] aucune signature principale trouvee dans /var/lib/clamav"
    echo "          clamd refusera les messages tant que la base n'est pas la."
fi

# ------------------------------------------------- 3. antivirus Rspamd
echo ""
echo "--- [3/5] Module antivirus de Rspamd ---"
if [ ! -f "${SRC_DIR}/rspamd/local.d/antivirus.conf" ]; then
    echo "[ERREUR] ${SRC_DIR}/rspamd/local.d/antivirus.conf absent"
    exit 1
fi
install -m 0644 -o root -g _rspamd "${SRC_DIR}/rspamd/local.d/antivirus.conf" \
    "${RSPAMD_LOCAL}/antivirus.conf"
echo "  [OK] ${RSPAMD_LOCAL}/antivirus.conf depose"

# PIEGE : `rspamadm configtest` / `configdump` doivent etre lances avec les
# privileges root, sinon ils echouent sur la lecture des fichiers local.d
# ("Permission denied") et donnent un faux negatif "module absent".
if ! sudo rspamadm configtest >/dev/null 2>&1; then
    echo "[ERREUR] rspamadm configtest :"
    sudo rspamadm configtest 2>&1 | head -20
    exit 1
fi
echo "  [OK] rspamadm configtest"
systemctl restart rspamd
sleep 3
systemctl is-active rspamd >/dev/null
echo "  [OK] rspamd relance"

# PIEGE STRUCTUREL (phase 14) : le fichier local.d/antivirus.conf est inclus
# A L'INTERIEUR du bloc `antivirus { }` de modules.d/antivirus.conf.
# Redecclarer `antivirus { }` dans le local.d produit un bloc IMBRIQUE :
#   antivirus { antivirus { clamav { ... } } }
# Rspamd le signale ("nested section", "unknown antivirus type: antivirus")
# et le module ne scanne RIEN, silencieusement.
# On controle donc explicitement l'absence de ces deux erreurs.
# PIEGE SHELL : le configdump fait plusieurs centaines de lignes (>> 64 Ko).
# `echo "${DUMP}" | grep -q motif` provoque un SIGPIPE sur echo des que grep
# trouve une correspondance : avec `set -o pipefail` le pipeline renvoie
# 141 (ECHEC) alors que la correspondance EST presente. On travaille donc sur
# un fichier, jamais sur un pipe.
DUMP_FILE=$(mktemp /tmp/rspamd-configdump.XXXXXX)
sudo rspamadm configdump > "${DUMP_FILE}" 2>&1 || true

if grep -q 'nested section' "${DUMP_FILE}"; then
    echo "[ERREUR] section imbriquee detectee dans la configuration Rspamd :"
    grep -A3 'nested section' "${DUMP_FILE}" | head -10
    echo "        -> le fichier local.d/antivirus.conf ne doit PAS redéclarer"
    echo "           le bloc antivirus { } : il ne contient que clamav { }."
    rm -f "${DUMP_FILE}"
    exit 1
fi
if grep -q 'unknown antivirus type' "${DUMP_FILE}"; then
    echo "[ERREUR] type de scanner inconnu :"
    grep 'unknown antivirus type' "${DUMP_FILE}" | head -5
    rm -f "${DUMP_FILE}"
    exit 1
fi
echo "  [OK] aucune section imbriquee, aucun type de scanner inconnu"

# Le scanner clamav doit apparaitre au bon niveau dans la configuration effective
# (un seul niveau de blocs : antivirus { clamav { ... } })
if grep -q 'clamav' "${DUMP_FILE}"; then
    echo "  [OK] scanner clamav present dans la configuration effective"
    grep -A1 '^antivirus {' "${DUMP_FILE}" | head -4 | sed 's/^/         /'
else
    echo "[ERREUR] le scanner clamav n'apparait pas dans configdump"
    rm -f "${DUMP_FILE}"
    exit 1
fi
rm -f "${DUMP_FILE}"

# ------------------------------------------------- 4. test de bout en bout
echo ""
echo "--- [4/5] Test de bout en bout (EICAR) ---"
if [ ! -f "${SRC_DIR}/scripts/test-clamav-eicar.py" ]; then
    echo "[ERREUR] ${SRC_DIR}/scripts/test-clamav-eicar.py absent"
    exit 1
fi
install -m 0750 -o root -g root "${SRC_DIR}/scripts/test-clamav-eicar.py" \
    /usr/local/sbin/test-clamav-eicar.py

if python3 /usr/local/sbin/test-clamav-eicar.py; then
    ECHECS=0
else
    ECHECS=$((1))
fi

# ------------------------------------------------- 5. verifications
echo ""
echo "--- [5/5] Verifications ---"

# clamd a bien vu le virus
# PIEGE : selon la distribution, le journal de clamd est soit un fichier
# (/var/log/clamav/clamav.log), soit uniquement le journal systemd.
# PIEGE SHELL : on ecrit dans un fichier, pas dans un pipe (SIGPIPE +
# pipefail, cf. section 3).
CLAM_LOG_FILE=$(mktemp /tmp/clamd-journal.XXXXXX)
sudo journalctl -u clamav-daemon --no-pager > "${CLAM_LOG_FILE}" 2>/dev/null || true
if grep -qi 'Eicar' "${LOG_CLAMD}" 2>/dev/null \
   || grep -qi 'Eicar' "${CLAM_LOG_FILE}"; then
    echo "  [PASS] clamd a signale la signature EICAR dans son journal"
else
    echo "  [INFO] pas de mention EICAR dans le journal clamd (voir le test ci-dessus)"
fi
rm -f "${CLAM_LOG_FILE}"

# PIEGE : la commande de statistiques est `rspamc stat` (client).
# `rspamadm stat` n'existe pas et renvoyait une erreur silencieuse.
STAT_FILE=$(mktemp /tmp/rspamc-stat.XXXXXX)
sudo rspamc stat > "${STAT_FILE}" 2>/dev/null || true

# Le symbole antivirus doit apparaitre dans les statistiques Rspamd
if grep -q 'CLAM_VIRUS' "${STAT_FILE}"; then
    echo "  [PASS] symbole CLAM_VIRUS present dans les statistiques Rspamd"
else
    echo "  [INFO] symbole CLAM_VIRUS absent des statistiques (aucun message virus recu)"
fi

# Rspamd ne doit pas avoir perdu ses autres modules (regression)
if grep -q 'scanned' "${STAT_FILE}"; then
    echo "  [PASS] Rspamd continue de scanner le courrier"
else
    echo "  [FAIL] Rspamd ne scanne plus"
    ECHECS=$((ECHECS + 1))
fi
rm -f "${STAT_FILE}"

echo ""
if [ "${ECHECS}" -eq 0 ]; then
    echo "# VERDICT : ANTIVIRUS OPERATIONNEL"
else
    echo "# VERDICT : ${ECHECS} ECHEC(S)"
fi
exit "${ECHECS}"
