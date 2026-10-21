#!/bin/bash
# =============================================================================
# 20-deploy-reponses.sh - Deploie les modeles de redaction institutionnels
# -----------------------------------------------------------------------------
# Mecanisme NATIF de Roundcube : $config['compose_responses_static'].
#   - les modeles sont GLOBAUXS (visibles par tous les agents des la premiere
#     connexion) ;
#   - AUCUNE ligne SQL, AUCUN compte utilisateur pre-cree : le fichier de
#     configuration est injecte dans config.inc.php par un require_once ;
#   - un agent ne peut pas les supprimer : ce sont des modeles de l'institution.
#
# Le fichier des modeles est versionne (labo/web/roundcube-reponses-static.php)
# et distinct de config.inc.php, qui porte les secrets et n'est pas versionne.
#
# Usage : sudo ./20-deploy-reponses.sh [chemin_source]
# =============================================================================
set -euo pipefail

RC_ROOT="/var/www/roundcube"
RC_CONF="${RC_ROOT}/config/config.inc.php"
RC_MODELS="${RC_ROOT}/config/reponses-static.php"
SRC_FILE="${1:-/tmp/roundcube-reponses-static.php}"

echo "=============================================================="
echo " Deploiement des modeles de redaction institutionnels"
echo "=============================================================="

# ---------------------------------------------------------------- 1. controle
if [ ! -f "${SRC_FILE}" ]; then
    echo "[ERREUR] Source absente : ${SRC_FILE}"
    echo "          Envoyer d'abord le fichier (scp) vers ${SRC_FILE}"
    exit 1
fi

if ! php -l "${SRC_FILE}" > /tmp/php-lint.txt 2>&1; then
    echo "[ERREUR] Syntaxe PHP invalide dans ${SRC_FILE} :"
    cat /tmp/php-lint.txt
    exit 1
fi
echo "[OK] syntaxe PHP valide"

# Le fichier doit definir compose_responses_static, sinon le require est inutile.
if ! grep -q "compose_responses_static" "${SRC_FILE}"; then
    echo "[ERREUR] 'compose_responses_static' absent de ${SRC_FILE}"
    exit 1
fi
echo "[OK] compose_responses_static present"

# ---------------------------------------------------------------- 2. copie
echo "[..] copie vers ${RC_MODELS}"
sudo cp -a "${SRC_FILE}" "${RC_MODELS}"
sudo chown www-data:www-data "${RC_MODELS}"
sudo chmod 640 "${RC_MODELS}"
echo "[OK] copie terminee"

# ---------------------------------------------------------------- 3. injection
# require_once idempotent : on ne l'ajoute que s'il n'est pas deja present.
echo "[..] injection du require dans ${RC_CONF}"
sudo cp -a "${RC_CONF}" "${RC_CONF}.bak.$(date +%Y%m%d-%H%M%S)"
sudo python3 - "${RC_CONF}" <<'PY'
import re
import sys

path = sys.argv[1]
line = "require_once __DIR__ . '/reponses-static.php';"

with open(path, encoding='utf-8') as fh:
    content = fh.read()

if re.search(r"reponses-static\.php", content):
    print("    require deja present : rien a faire")
else:
    if not content.endswith("\n"):
        content += "\n"
    content += (
        "\n// --- Modeles de redaction institutionnels (labo/web/) ---\n"
        + line
        + "\n"
    )
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(content)
    print("    require injecte")
PY

if ! sudo php -l "${RC_CONF}" > /tmp/php-lint-conf.txt 2>&1; then
    echo "[ERREUR] Syntaxe PHP invalide dans config.inc.php :"
    cat /tmp/php-lint-conf.txt
    echo "        Restauration : cp ${RC_CONF}.bak.<date> ${RC_CONF}"
    exit 1
fi
echo "[OK] syntaxe de config.inc.php validee"

# ---------------------------------------------------------------- 4. cache
echo "[..] purge du cache Roundcube"
sudo rm -rf "${RC_ROOT}/temp/"* 2>/dev/null || true
sudo mkdir -p "${RC_ROOT}/temp"
sudo chown www-data:www-data "${RC_ROOT}/temp"

# ---------------------------------------------------------------- 5. verification
echo "[..] verification fonctionnelle (chargement de la configuration)"
sudo php -r '
$config = [];
include "/var/www/roundcube/config/config.inc.php";
$r = isset($config["compose_responses_static"]) ? $config["compose_responses_static"] : null;
if (!is_array($r) || count($r) === 0) {
    fwrite(STDERR, "ERREUR: compose_responses_static vide ou absent\n");
    exit(1);
}
foreach ($r as $i => $m) {
    $name = isset($m["name"]) ? $m["name"] : "(sans nom)";
    $has_text = !empty($m["text"]);
    $has_html = !empty($m["html"]);
    if (!$has_text && !$has_html) {
        fwrite(STDERR, "ERREUR: modele sans corps : " . $name . "\n");
        exit(1);
    }
    $type = $has_html ? "html" : "text";
    printf("    [PASS] %-45s (%s)\n", $name, $type);
}
printf("    %d modele(s) charge(s)\n", count($r));
'

echo "[..] verification HTTP (la page de connexion doit rester servie)"
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' https://webmail.meteo-test.lan/)
echo "    page de connexion -> HTTP ${HTTP_CODE}"
if [ "${HTTP_CODE}" != "200" ]; then
    echo "    [FAIL] la page de connexion ne repond pas 200"
    exit 1
fi

echo "=============================================================="
echo " MODELES DE REDACTION DEPLOYES"
echo "=============================================================="
