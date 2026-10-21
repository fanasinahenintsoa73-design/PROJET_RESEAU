#!/bin/bash
# =============================================================================
# 19-deploy-skin.sh - Deploie et active le skin "meteo" (Roundcube 1.7.x)
# -----------------------------------------------------------------------------
# Le skin meteo est une SURCOUCHE du skin "elastic" (heritage via meta.json
# "extends"). Il ne contient QUE du HTML / CSS / JSON : aucune ligne de PHP.
#
# Regle de non-regression : ce script ne doit jamais creer
#   skins/meteo/styles/styles.css  ni  skins/meteo/styles/styles.min.css
# car le premier skin trouve gagne (find_file_path) : ces deux fichiers
# REMPLAACERAient la feuille de style complete de "elastic" et casseraient
# toute l'interface.
#
# Usage : sudo ./19-deploy-skin.sh [nom_du_skin]
# =============================================================================
set -euo pipefail

SKIN_NAME="${1:-meteo}"
RC_ROOT="/var/www/roundcube"
SKIN_DIR="${RC_ROOT}/skins/${SKIN_NAME}"
RC_CONF="${RC_ROOT}/config/config.inc.php"
SRC_DIR="${2:-/tmp/meteo-skin}"

echo "=============================================================="
echo " Deploiement du skin '${SKIN_NAME}'"
echo "=============================================================="

# ---------------------------------------------------------------- 1. controle
if [ ! -d "${SRC_DIR}" ]; then
    echo "[ERREUR] Source absente : ${SRC_DIR}"
    echo "          Envoyer d'abord le skin (scp) vers ${SRC_DIR}"
    exit 1
fi

if [ ! -f "${SRC_DIR}/meta.json" ]; then
    echo "[ERREUR] meta.json absent de ${SRC_DIR} : ce n'est pas un skin Roundcube"
    exit 1
fi

if [ ! -f "${SRC_DIR}/styles/meteo.css" ]; then
    echo "[ERREUR] styles/meteo.css absent : la feuille de style est obligatoire"
    exit 1
fi

for forbidden in styles/styles.css styles/styles.min.css; do
    if [ -f "${SRC_DIR}/${forbidden}" ]; then
        echo "[ERREUR] INTERDIT : ${forbidden} remplacerait la feuille 'elastic'."
        exit 1
    fi
done

echo "[OK] controle de non-regression du skin"

# ---------------------------------------------------------------- 2. copie
echo "[..] copie vers ${SKIN_DIR}"
sudo mkdir -p "${SKIN_DIR}"
sudo cp -a "${SRC_DIR}/." "${SKIN_DIR}/"
sudo chown -R www-data:www-data "${SKIN_DIR}"
sudo find "${SKIN_DIR}" -type d -exec chmod 755 {} \;
sudo find "${SKIN_DIR}" -type f -exec chmod 644 {} \;
echo "[OK] copie terminee"

# ------------------------------------------------- 2b. liens symboliques .min.css
# Roundcube resout "/styles/styles.css" vers <skin_courant>/styles/styles.css
# puis, via file_mod(), tente <skin_courant>/styles/styles.min.css.
# Ce mecanisme ne fonctionne QUE si la version minifiee existe DANS LE SKIN
# COURANT : le skin "meteo" herite d'"elastic" mais ne contient pas les
# .min.css -> la feuille complete d'elastic n'etait plus servie (404).
# On cree donc des liens symboliques vers les fichiers reels d'"elastic" :
# ils suivent automatiquement les futures mises a jour d'elastic.
echo "[..] liens symboliques vers les .min.css d'elastic"
for f in styles.min.css print.min.css embed.min.css; do
    dst="${SKIN_DIR}/styles/${f}"
    if [ -e "${dst}" ] && [ ! -L "${dst}" ]; then
        echo "    suppression du fichier reel ${f} (serait fige a cette version)"
        sudo rm -f "${dst}"
    fi
    if [ ! -L "${dst}" ]; then
        sudo ln -s "../../elastic/styles/${f}" "${dst}"
        echo "    ${f} -> ../../elastic/styles/${f}"
    fi
done

# Polices : la feuille "elastic" reference les polices par chemin relatif
# (url(../fonts/...)) ; servie depuis skins/meteo/styles/, le navigateur les
# demande dans skins/meteo/fonts/. static.php refuse de servir un repertoire
# symlinke -> on copie les fichiers reels d'elastic.
echo "[..] copie des polices depuis elastic"
sudo rm -rf "${SKIN_DIR}/fonts"
sudo mkdir -p "${SKIN_DIR}/fonts"
if [ -d "${RC_ROOT}/skins/elastic/fonts" ]; then
    sudo cp -a "${RC_ROOT}/skins/elastic/fonts/." "${SKIN_DIR}/fonts/"
    sudo chown -R www-data:www-data "${SKIN_DIR}/fonts"
    echo "    $(ls -1 "${SKIN_DIR}/fonts" | wc -l) fichiers de police copies"
else
    echo "    [AVERTISSEMENT] skins/elastic/fonts introuvable"
fi

# Logo : sur l'ecran d'accueil (tache mail), Roundcube resout le logo vers
# skins/elastic/images/logo.svg (la surcharge par fichier du skin enfant n'est
# pas appliquee sur le template "menu" herite). On fait pointer le logo
# d'elastic vers celui du skin meteo : le logo Meteo est ainsi affiche
# partout, et suit automatiquement les evolutions du skin.
echo "[..] logo d'elastic -> logo meteo"
ELASTIC_LOGO="${RC_ROOT}/skins/elastic/images/logo.svg"
if [ -f "${ELASTIC_LOGO}" ] && [ ! -L "${ELASTIC_LOGO}" ]; then
    sudo cp -a "${ELASTIC_LOGO}" "${ELASTIC_LOGO}.orig"
    sudo rm -f "${ELASTIC_LOGO}"
fi
if [ ! -L "${ELASTIC_LOGO}" ]; then
    sudo ln -s "../../meteo/images/logo.svg" "${ELASTIC_LOGO}"
    echo "    skins/elastic/images/logo.svg -> ../../meteo/images/logo.svg"
fi

# ---------------------------------------------------------------- 3. activation
echo "[..] activation dans ${RC_CONF}"
sudo cp -a "${RC_CONF}" "${RC_CONF}.bak.$(date +%Y%m%d-%H%M%S)"
sudo python3 - "${RC_CONF}" "${SKIN_NAME}" <<'PY'
import re
import sys

path, skin = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as fh:
    content = fh.read()

line = "$config['skin'] = '%s';" % skin
pattern = re.compile(r"(?m)^\s*\$config\['skin'\]\s*=.*$")

if pattern.search(content):
    content = pattern.sub(line, content, count=1)
else:
    content = content.rstrip() + "\n\n// --- skin actif (labo/skins/) ---\n" + line + "\n"

with open(path, 'w', encoding='utf-8') as fh:
    fh.write(content)
PY

echo "[OK] skin actif : $(sudo grep -E "^\\\$config\['skin'\]" "${RC_CONF}")"

# ---------------------------------------------------------------- 4. cache
echo "[..] purge du cache Roundcube"
sudo rm -rf "${RC_ROOT}/temp/"* 2>/dev/null || true
sudo mkdir -p "${RC_ROOT}/temp"
sudo chown www-data:www-data "${RC_ROOT}/temp"

# ---------------------------------------------------------------- 5. verification
echo "[..] verification HTTP"
HTTP_CODE=$(curl -sk -o /tmp/meteo-login.html -w '%{http_code}' https://webmail.meteo-test.lan/)
echo "    page de connexion -> HTTP ${HTTP_CODE}"

CHECKS=0
FAILS=0

check() {
    CHECKS=$((CHECKS + 1))
    if grep -q "$1" /tmp/meteo-login.html; then
        echo "    [PASS] $2"
    else
        echo "    [FAIL] $2"
        FAILS=$((FAILS + 1))
    fi
}

check "meteo.css"          "feuille meteo.css referencee"
check "skins/meteo/"        "ressources servies depuis skins/meteo"
check "logo.svg"            "logo reference"

# Repercussion : toutes les ressources citees par la page doivent repondre 200.
# C'est le garde-fou contre la regression "feuille elastic non servie".
echo "    -- audit des ressources citees --"
REFS=$(grep -oE '(href|src)="[^"]+"' /tmp/meteo-login.html | sed -E 's/.*="([^"]+)"/\1/' | grep -vE '^(#|data:|javascript:)' | sort -u)
for ref in ${REFS}; do
    code=$(curl -sk -o /dev/null -w '%{http_code}' "https://webmail.meteo-test.lan/${ref}")
    if [ "${code}" = "200" ]; then
        echo "    [PASS] 200  ${ref}"
    else
        echo "    [FAIL] ${code}  ${ref}"
        FAILS=$((FAILS + 1))
    fi
    CHECKS=$((CHECKS + 1))
done

echo "=============================================================="
if [ "${FAILS}" -eq 0 ]; then
    echo " DEPLOIEMENT DU SKIN OK"
else
    echo " DEPLOIEMENT DU SKIN : ${FAILS} ECHEC(S) SUR ${CHECKS}"
fi
echo "=============================================================="
exit "${FAILS}"
