#!/bin/bash
# =============================================================================
# 21-deploy-prod-web.sh - Cloisonnement web et chaine de production Portail
# -----------------------------------------------------------------------------
# Ce script deploie et VALIDE les 4 elements de la production web :
#
#   1. Deux pools PHP-FPM DEDIES (ferme la divergence D8) :
#        - pool "roundcube"    -> socket php8.1-fpm-roundcube.sock    (www-data)
#        - pool "postfixadmin" -> socket php8.1-fpm-postfixadmin.sock (pfa)
#      Roundcube et PostfixAdmin ne partagent plus le meme interpreteur PHP.
#
#   2. Le compte Unix "pfa" (manquant jusque-la) : PostfixAdmin tourne sous
#      son propre utilisateur, jamais sous www-data.
#
#   3. Les vhosts INTERNES de production :
#        - webmail      -> 8080 (HTTP brut ; le TLS est termine par le Portail)
#        - postfixadmin -> 8081 (HTTP brut ; RESEAU INTERNE SEUL)
#
#   4. La configuration Roundcube derriere un reverse-proxy HTTPS :
#        use_https, proxy_whitelist, trusted_host_patterns, smtp_helo_host.
#      Sans cela, Roundcube genere des URL en http://...:8080 : mixed content
#      et liens casses pour les agents.
#
# Le script est le MEME en labo et en production : seul le fichier de
# parametres change. La validation en labo prouve donc le deploiement prod.
#
# Usage :
#   sudo PARAM_FILE=<fichier.env> ./21-deploy-prod-web.sh <repertoire_source>
# Exemple :
#   sudo PARAM_FILE=/tmp/labo-prod/parametres-labo.env \
#        ./21-deploy-prod-web.sh /tmp/labo-prod
# =============================================================================
set -euo pipefail

SRC_DIR="${1:-/tmp/labo-prod}"
PARAM_FILE="${PARAM_FILE:-${SRC_DIR}/parametres.env}"

RC_ROOT="/var/www/roundcube"
RC_CONF="${RC_ROOT}/config/config.inc.php"
FPM_POOL_DIR="/etc/php/8.1/fpm/pool.d"
APACHE_AVAIL="/etc/apache2/sites-available"
APACHE_ENABLED="/etc/apache2/sites-enabled"

echo "=============================================================="
echo " Deploiement web production (cloisonnement + reverse-proxy)"
echo "=============================================================="

# ---------------------------------------------------------------- 0. controle
if [ ! -d "${SRC_DIR}" ]; then
    echo "[ERREUR] Source absente : ${SRC_DIR}"
    exit 1
fi
if [ ! -f "${PARAM_FILE}" ]; then
    echo "[ERREUR] Fichier de parametres absent : ${PARAM_FILE}"
    exit 1
fi

# Chargement des parametres
set -a
# shellcheck disable=SC1090
. "${PARAM_FILE}"
set +a

for var in HOSTNAME_WEBMAIL HOSTNAME_POSTFIXADMIN IP_PORTAIL PLAGE_LAN_DGM \
           IP_MAIL_PRIVEE IP_MAIL_PUBLIQUE; do
    if [ -z "${!var:-}" ]; then
        echo "[ERREUR] Parametre manquant dans ${PARAM_FILE} : ${var}"
        exit 1
    fi
done
HOSTNAME_SMTP="${HOSTNAME_SMTP:-mail.meteomadagascar.mg}"

echo "[INFO] webmail         : ${HOSTNAME_WEBMAIL}"
echo "[INFO] postfixadmin   : ${HOSTNAME_POSTFIXADMIN}"
echo "[INFO] Portail (proxy) : ${IP_PORTAIL}"
echo "[INFO] LAN autorise   : ${PLAGE_LAN_DGM}"
echo "[INFO] SMTP HELO      : ${HOSTNAME_SMTP}"

# ------------------------------------------------- 1. pools PHP-FPM dedies
echo ""
echo "--- [1/6] Pools PHP-FPM dedies ---"
install -m 0644 -o root -g root \
    "${SRC_DIR}/php-fpm/roundcube.conf"    "${FPM_POOL_DIR}/roundcube.conf"
install -m 0644 -o root -g root \
    "${SRC_DIR}/php-fpm/postfixadmin.conf" "${FPM_POOL_DIR}/postfixadmin.conf"
echo "  [OK] ${FPM_POOL_DIR}/roundcube.conf"
echo "  [OK] ${FPM_POOL_DIR}/postfixadmin.conf"

# ------------------------------------------------- 2. compte Unix "pfa"
echo ""
echo "--- [2/6] Compte Unix dedie pour PostfixAdmin ---"
if ! id -u pfa >/dev/null 2>&1; then
    useradd --system --no-create-home --home-dir /opt/postfixadmin \
            --shell /usr/sbin/nologin pfa
    echo "  [OK] utilisateur 'pfa' cree"
else
    echo "  [OK] utilisateur 'pfa' deja present"
fi

# Arborescence PostfixAdmin : root possede le code, pfa possede le cache.
chown -R root:root /opt/postfixadmin
chmod -R u=rwX,go=rX /opt/postfixadmin
if [ -f /opt/postfixadmin/config.local.php ]; then
    chown root:pfa /opt/postfixadmin/config.local.php
    chmod 0640 /opt/postfixadmin/config.local.php
fi
mkdir -p /opt/postfixadmin/templates_c
chown -R pfa:pfa /opt/postfixadmin/templates_c
chmod 0750 /opt/postfixadmin/templates_c
echo "  [OK] /opt/postfixadmin : code en root:root, cache en pfa:pfa"

# ------------------------------------------------- 3. vhosts internes prod
echo ""
echo "--- [3/6] Vhosts internes de production ---"
sed -e "s|@@HOSTNAME_WEBMAIL@@|${HOSTNAME_WEBMAIL}|g" \
    -e "s|@@HOSTNAME_POSTFIXADMIN@@|${HOSTNAME_POSTFIXADMIN}|g" \
    -e "s|@@IP_PORTAIL@@|${IP_PORTAIL}|g" \
    -e "s|@@PLAGE_LAN_DGM@@|${PLAGE_LAN_DGM}|g" \
    -e "s|@@IP_MAIL_PRIVEE@@|${IP_MAIL_PRIVEE}|g" \
    -e "s|@@IP_MAIL_PUBLIQUE@@|${IP_MAIL_PUBLIQUE}|g" \
    "${SRC_DIR}/apache/20-webmail-interne.conf" > "${APACHE_AVAIL}/20-webmail-interne.conf"

sed -e "s|@@HOSTNAME_WEBMAIL@@|${HOSTNAME_WEBMAIL}|g" \
    -e "s|@@HOSTNAME_POSTFIXADMIN@@|${HOSTNAME_POSTFIXADMIN}|g" \
    -e "s|@@IP_PORTAIL@@|${IP_PORTAIL}|g" \
    -e "s|@@PLAGE_LAN_DGM@@|${PLAGE_LAN_DGM}|g" \
    -e "s|@@IP_MAIL_PRIVEE@@|${IP_MAIL_PRIVEE}|g" \
    -e "s|@@IP_MAIL_PUBLIQUE@@|${IP_MAIL_PUBLIQUE}|g" \
    "${SRC_DIR}/apache/21-postfixadmin-interne.conf" > "${APACHE_AVAIL}/21-postfixadmin-interne.conf"

chmod 0644 "${APACHE_AVAIL}/20-webmail-interne.conf" \
           "${APACHE_AVAIL}/21-postfixadmin-interne.conf"

ln -sfn ../sites-available/20-webmail-interne.conf     "${APACHE_ENABLED}/20-webmail-interne.conf"
ln -sfn ../sites-available/21-postfixadmin-interne.conf "${APACHE_ENABLED}/21-postfixadmin-interne.conf"
echo "  [OK] vhost webmail      -> 8080"
echo "  [OK] vhost postfixadmin -> 8081 (LAN seulement)"

# Simulateur du Portail : LABO UNIQUEMENT (le vrai Portail le remplace).
if [ -f "${SRC_DIR}/simulateur/30-portail.conf" ]; then
    install -m 0644 -o root -g root "${SRC_DIR}/simulateur/30-portail.conf" \
        "${APACHE_AVAIL}/30-portail-simulateur.conf"
    ln -sfn ../sites-available/30-portail-simulateur.conf "${APACHE_ENABLED}/30-portail-simulateur.conf"
    echo "  [OK] simulateur du Portail (8444) : LABO uniquement"
fi

# Vhosts de labo (acces direct TLS) : ils doivent aussi utiliser les pools
# dedies, sinon le cloisonnement ne serait pas reellement exerce.
if [ -f "${SRC_DIR}/web/webmail.conf.labo" ]; then
    install -m 0644 -o root -g root "${SRC_DIR}/web/webmail.conf.labo" \
        "${APACHE_AVAIL}/webmail.conf"
    echo "  [OK] vhost labo webmail majore (pool dedie)"
fi
if [ -f "${SRC_DIR}/web/postfixadmin.conf.labo" ]; then
    install -m 0644 -o root -g root "${SRC_DIR}/web/postfixadmin.conf.labo" \
        "${APACHE_AVAIL}/postfixadmin.conf"
    echo "  [OK] vhost labo postfixadmin majore (pool dedie + LAN)"
fi

# ------------------------------------------------- 4. config Roundcube proxy
echo ""
echo "--- [4/6] Configuration Roundcube derriere le reverse-proxy ---"
if [ ! -f "${RC_CONF}" ]; then
    echo "[ERREUR] ${RC_CONF} introuvable"
    exit 1
fi
cp -a "${RC_CONF}" "${RC_CONF}.bak.$(date +%Y%m%d-%H%M%S)"

RC_CONF="${RC_CONF}" \
IP_PORTAIL="${IP_PORTAIL}" \
HOSTNAME_WEBMAIL="${HOSTNAME_WEBMAIL}" \
HOSTNAME_SMTP="${HOSTNAME_SMTP}" \
python3 - <<'PYEOF'
import os, re

path = os.environ['RC_CONF']
ip_portail = os.environ['IP_PORTAIL']
host_webmail = os.environ['HOSTNAME_WEBMAIL']
host_smtp = os.environ['HOSTNAME_SMTP']

with open(path, 'r', encoding='utf-8') as fh:
    lines = fh.readlines()

managed = ('use_https', 'proxy_whitelist', 'trusted_host_patterns',
           'smtp_helo_host', 'force_https')
kept = []
for line in lines:
    m = re.match(r"\s*\$config\['([a-z_]+)'\]\s*=", line)
    if m and m.group(1) in managed:
        continue
    kept.append(line)

# Hotes de confiance : le nom public du webmail + loopback + localhost.
trusted = [host_webmail, '127.0.0.1', 'localhost']

block = [
    "\n",
    "// --- Reverse-proxy (Portail Meteo) : ajoute par 21-deploy-prod-web.sh ---\n",
    "// use_https : le TLS est termine par le Portail, Roundcube ne le voit pas.\n",
    "// Sans ce reglage, les URL generees seraient en http://...:8080.\n",
    "$config['use_https'] = true;\n",
    "\n",
    "// proxy_whitelist : SEUL le Portail est autorise a poser X-Forwarded-*\n",
    "// (IP exacte ou CIDR). Hors de cette liste, ces en-tetes sont ignores.\n",
    "$config['proxy_whitelist'] = ['%s'];\n" % ip_portail,
    "\n",
    "// trusted_host_patterns : refuse un en-tete Host injectable (vol d'identifiants).\n",
    "$config['trusted_host_patterns'] = ['%s'];\n" % "', '".join(trusted),
    "\n",
    "// smtp_helo_host : nom annonce au serveur SMTP (EHL0). Sans lui, Roundcube\n",
    "// annonce le SERVER_NAME d'Apache, qui n'est pas le FQDN du serveur mail.\n",
    "$config['smtp_helo_host'] = '%s';\n" % host_smtp,
]

with open(path, 'w', encoding='utf-8') as fh:
    fh.writelines(kept)
    fh.writelines(block)

print('  [OK] config.inc.php mis a jour')
PYEOF

php -l "${RC_CONF}" >/dev/null
echo "  [OK] syntaxe PHP valide"

# Purge du cache de templates Roundcube (les valeurs de config sont relues).
rm -rf "${RC_ROOT}/temp"/* 2>/dev/null || true

# ------------------------------------------------- 5. redemarrage des services
echo ""
echo "--- [5/6] Redemarrage FPM et Apache ---"

# mod_proxy_http : sousmodule du proxy HTTP, charge SEPAREMENT sur Ubuntu.
# Sans lui, ProxyPass vers un backend "http://..." echoue avec :
#   "No protocol handler was valid for the URL / (scheme 'http')"
if ! ls /etc/apache2/mods-enabled/ | grep -qx 'proxy_http.load'; then
    a2enmod proxy_http >/dev/null
    echo "  [OK] module proxy_http active"
else
    echo "  [OK] module proxy_http deja actif"
fi

systemctl restart php8.1-fpm
sleep 2
if ! apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
    echo "[ERREUR] Apache configtest :"
    apache2ctl configtest
    exit 1
fi
systemctl reload apache2
echo "  [OK] php8.1-fpm et apache2 recharges"

# ATTENTE ACTIVE : un reload Apache est un redemarrage GRACIEUX. Les
# nouvelles sockets (8080, 8081, 8444) ne sont ouvertes qu'a la fin, et les
# anciens workers servent encore l'ancienne configuration. Verifier trop tot
# donne des "connection refused" qui font crier a tort.
echo "  [...] attente de l'ouverture des ports"
for port in 8080 8081 8444 443; do
    ATTENTE=0
    while ! (exec 3<>/dev/tcp/127.0.0.1/${port}) 2>/dev/null; do
        ATTENTE=$((ATTENTE + 1))
        if [ "${ATTENTE}" -ge 30 ]; then
            echo "  [AVERTISSEMENT] port ${port} toujours ferme apres 30 s"
            break
        fi
        sleep 1
    done
    exec 3<&- 2>/dev/null || true
done
echo "  [OK] ports prets"

# ------------------------------------------------- 6. verifications
echo ""
echo "--- [6/6] Verifications ---"
ECHECS=0

verif() {
    local libelle="$1" attendu="$2" obtenu="$3"
    if [ "${attendu}" = "${obtenu}" ]; then
        echo "  [PASS] ${libelle} : ${obtenu}"
    else
        echo "  [FAIL] ${libelle} : attendu ${attendu}, obtenu ${obtenu}"
        ECHECS=$((ECHECS + 1))
    fi
}

# Sockets FPM dedies
for sock in php8.1-fpm-roundcube.sock php8.1-fpm-postfixadmin.sock; do
    if [ -S "/run/php/${sock}" ]; then
        echo "  [PASS] socket ${sock} present"
    else
        echo "  [FAIL] socket ${sock} ABSENT"
        ECHECS=$((ECHECS + 1))
    fi
done

# Les deux pools sont-ils bien distincts ?
# PIEGE : un pool "ondemand" sans requete n'a AUCUN worker en vie, donc
# pgrep sur le nom du pool echoue alors que le pool est parfaitement
# configure. On verifie la configuration deployee ; la preuve FONCTIONNELLE
# vient plus bas (la sonde ini passe par le socket du pool dedie).
for pool in roundcube postfixadmin; do
    if grep -qE "^\[${pool}\]" "${FPM_POOL_DIR}/${pool}.conf" \
       && grep -q "php8.1-fpm-${pool}.sock" "${FPM_POOL_DIR}/${pool}.conf"; then
        echo "  [PASS] pool '${pool}' configure et dedie"
    else
        echo "  [FAIL] pool '${pool}' mal configure"
        ECHECS=$((ECHECS + 1))
    fi
done

# Le pool PostfixAdmin doit tourner sous 'pfa', jamais sous www-data.
if grep -A6 '^\[postfixadmin\]' "${FPM_POOL_DIR}/postfixadmin.conf" | grep -qE '^user = pfa'; then
    echo "  [PASS] pool 'postfixadmin' execute sous l'utilisateur 'pfa'"
else
    echo "  [FAIL] pool 'postfixadmin' ne tourne pas sous 'pfa'"
    ECHECS=$((ECHECS + 1))
fi

# Le pool Roundcube, lui, tourne sous www-data (le code et le docroot).
if grep -A6 '^\[roundcube\]' "${FPM_POOL_DIR}/roundcube.conf" | grep -qE '^user = www-data'; then
    echo "  [PASS] pool 'roundcube' execute sous 'www-data'"
else
    echo "  [FAIL] pool 'roundcube' ne tourne pas sous 'www-data'"
    ECHECS=$((ECHECS + 1))
fi

# vhost interne webmail (8080)
CODE=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/ || echo 000)
verif "webmail interne 8080" "200" "${CODE}"

# vhost interne postfixadmin (8081)
CODE=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8081/ || echo 000)
verif "postfixadmin interne 8081" "302" "${CODE}"

# Le vhost webmail interne ne doit PAS etre joignable en clair sur 443
# (le TLS est au Portail) : on verifie que 8080 ne redirige pas vers https.
CODE=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/?_task=login || echo 000)
verif "webmail 8080 sans redirection" "200" "${CODE}"

# Simulateur du Portail (8444) : la chaine complete doit fonctionner.
if [ -f "${APACHE_ENABLED}/30-portail-simulateur.conf" ]; then
    CODE=$(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:8444/ || echo 000)
    verif "simulateur Portail 8444" "200" "${CODE}"

    # --- Sonde : ce que Roundcube COMPREND de la requete ------------------
    PROBE_SRC="${SRC_DIR}/simulateur/probe-proxy.php"
    if [ -f "${PROBE_SRC}" ]; then
        install -m 0644 -o www-data -g www-data "${PROBE_SRC}" \
            "${RC_ROOT}/public_html/_probe_proxy.php"
        SONDE=$(curl -sk https://127.0.0.1:8444/_probe_proxy.php || true)
        rm -f "${RC_ROOT}/public_html/_probe_proxy.php"

        if printf '%s' "${SONDE}" | grep -q '^HTTPS=oui'; then
            echo "  [PASS] Roundcube detecte HTTPS derriere le proxy"
        else
            echo "  [FAIL] Roundcube ne detecte pas HTTPS : ${SONDE}"
            ECHECS=$((ECHECS + 1))
        fi

        if printf '%s' "${SONDE}" | grep -q "^URL_GENEREE=https://${HOSTNAME_WEBMAIL}"; then
            echo "  [PASS] URL absolue : https://${HOSTNAME_WEBMAIL} (pas de port interne)"
        else
            echo "  [FAIL] URL generee incorrecte : $(printf '%s' "${SONDE}" | grep '^URL_GENEREE=')"
            ECHECS=$((ECHECS + 1))
        fi

        if printf '%s' "${SONDE}" | grep -q ':8080'; then
            echo "  [FAIL] une URL pointe encore sur le port interne 8080"
            ECHECS=$((ECHECS + 1))
        else
            echo "  [PASS] aucune URL ne pointe sur le port interne"
        fi
    fi

    # --- Connexion REELLE a travers le proxy : le test qui compte ---------
    if [ -f /root/labo-credentials.txt ] && [ -n "${LOGIN_TEST:-}" ]; then
        MDP=$(grep -E '^MDP_TEST=' /root/labo-credentials.txt | cut -d= -f2-)
        JAR=$(mktemp)
        PAGE=$(curl -sk -c "${JAR}" https://127.0.0.1:8444/ || true)
        TOKEN=$(printf '%s' "${PAGE}" | grep -oE 'name="_token" value="[^"]+"' \
                | head -1 | sed -E 's/.*value="([^"]+)".*/\1/')
        if [ -n "${TOKEN}" ] && [ -n "${MDP}" ]; then
            REP=$(curl -sk -i -b "${JAR}" -c "${JAR}" -X POST \
                  "https://127.0.0.1:8444/?_task=login&_action=login" \
                  --data-urlencode "_token=${TOKEN}" \
                  --data-urlencode "_task=login" \
                  --data-urlencode "_action=login" \
                  --data-urlencode "_user=${LOGIN_TEST}" \
                  --data-urlencode "_pass=${MDP}" || true)

            if printf '%s' "${REP}" | grep -q '^HTTP/1.1 302'; then
                echo "  [PASS] connexion a travers le reverse-proxy : 302 (authentifie)"
            else
                echo "  [FAIL] connexion a travers le reverse-proxy : $(printf '%s' "${REP}" | head -1)"
                ECHECS=$((ECHECS + 1))
            fi

            if printf '%s' "${REP}" | grep -qi '^Set-Cookie: roundcube_sessid=.*secure'; then
                echo "  [PASS] cookie de session marque 'secure' (HTTPS reconnu)"
            else
                echo "  [FAIL] cookie de session non marque 'secure'"
                ECHECS=$((ECHECS + 1))
            fi

            if printf '%s' "${REP}" | grep -qi '^Location:.*http://'; then
                echo "  [FAIL] redirection vers une URL en http:// (mixed content)"
                ECHECS=$((ECHECS + 1))
            else
                echo "  [PASS] redirection relative, aucun downgrade en http://"
            fi
        else
            echo "  [INFO] test de connexion saute (jeton ou mot de passe introuvable)"
        fi
        rm -f "${JAR}"
    fi
fi

# Les valeurs critiques sont bien presentes dans la config
for cle in use_https proxy_whitelist trusted_host_patterns smtp_helo_host; do
    if grep -q "config\['${cle}'\]" "${RC_CONF}"; then
        echo "  [PASS] config ${cle} present"
    else
        echo "  [FAIL] config ${cle} ABSENT"
        ECHECS=$((ECHECS + 1))
    fi
done

# L'utilisateur pfa est bien celui qui execute PostfixAdmin
if [ -f "${APACHE_AVAIL}/21-postfixadmin-interne.conf" ] \
   && grep -q "php8.1-fpm-postfixadmin.sock" "${APACHE_AVAIL}/21-postfixadmin-interne.conf"; then
    echo "  [PASS] PostfixAdmin pointe vers le pool dedie (pfa)"
else
    echo "  [FAIL] PostfixAdmin pointe encore vers le pool partage"
    ECHECS=$((ECHECS + 1))
fi

# La limite d'envoi doit etre celle du pool dedie, pas le 2 Mo par defaut
# (constate au test navigateur : "2,0 Mo"). Verification FONCTIONNELLE :
# on fait executer un script PHP par le vhost interne et on lit la valeur.
PROBE="${RC_ROOT}/public_html/_probe_ini.php"
cat > "${PROBE}" <<'PHPEOF'
<?php echo ini_get('upload_max_filesize') . '|' . ini_get('post_max_size') . '|' . php_sapi_name();
PHPEOF
chown www-data:www-data "${PROBE}"
chmod 0644 "${PROBE}"
PROBE_OUT=$(curl -s "http://127.0.0.1:8080/_probe_ini.php" || true)
rm -f "${PROBE}"
if printf '%s' "${PROBE_OUT}" | grep -q '^50M|52M|'; then
    echo "  [PASS] limite d'envoi du webmail : ${PROBE_OUT} (etait 2M par defaut)"
else
    echo "  [FAIL] limite d'envoi inattendue : '${PROBE_OUT}' (attendu 50M|52M|)"
    ECHECS=$((ECHECS + 1))
fi

echo ""
if [ "${ECHECS}" -eq 0 ]; then
    echo "# VERDICT : DEPLOIEMENT WEB PRODUCTION OK"
else
    echo "# VERDICT : ${ECHECS} ECHEC(S)"
fi
exit "${ECHECS}"
