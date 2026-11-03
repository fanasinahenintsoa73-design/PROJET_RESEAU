#!/bin/bash
# =============================================================================
# Demarrage de Roundcube dans le conteneur :
# 1. rend config.inc.php depuis le modele
# 2. copie le skin meteo du depot et refait les liens que 19-deploy-skin.sh
#    fait sur la VM (styles .min.css d'elastic, polices, logo)
# 3. regenere l'annuaire agents.js depuis la base postfix
# 4. lance Apache au premier plan
# =============================================================================
set -euo pipefail

: "${DB_HOST:?}" "${DB_NAME:?}" "${DB_USER:?}" "${DB_PASSWORD:?}"
: "${IMAP_HOST:?}" "${IMAP_PORT:?}" "${SMTP_HOST:?}" "${SMTP_PORT:?}"
: "${RC_DES_KEY:?}" "${MAIL_DOMAIN:?}"

RC_ROOT=/var/www/roundcube
SKIN_SRC=/opt/meteo-skin
SKIN_DST="${RC_ROOT}/skins/meteo"

VARS='${DB_HOST} ${DB_NAME} ${DB_USER} ${DB_PASSWORD} ${IMAP_HOST} ${IMAP_PORT} ${SMTP_HOST} ${SMTP_PORT} ${RC_DES_KEY} ${MAIL_DOMAIN}'

# --- 1. configuration --------------------------------------------------------
envsubst "${VARS}" < /opt/roundcube/config.inc.php.template > "${RC_ROOT}/config/config.inc.php"
chown www-data:www-data "${RC_ROOT}/config/config.inc.php"
chmod 0640 "${RC_ROOT}/config/config.inc.php"

# --- 2. skin -----------------------------------------------------------------
rm -rf "${SKIN_DST}"
cp -a "${SKIN_SRC}" "${SKIN_DST}"

# Roundcube cherche styles.min.css DANS le skin courant : sans ces liens, la
# feuille complete d'elastic n'est plus servie (404). Voir 19-deploy-skin.sh.
for f in styles.min.css print.min.css embed.min.css; do
    if [ -e "${SKIN_DST}/styles/${f}" ] && [ ! -L "${SKIN_DST}/styles/${f}" ]; then
        rm -f "${SKIN_DST}/styles/${f}"
    fi
    ln -sfn "../../elastic/styles/${f}" "${SKIN_DST}/styles/${f}"
done

# Polices d'elastic (Roboto) sans ecraser celles du skin (Open Sans).
mkdir -p "${SKIN_DST}/fonts"
if [ -d "${RC_ROOT}/skins/elastic/fonts" ]; then
    cp -an "${RC_ROOT}/skins/elastic/fonts/." "${SKIN_DST}/fonts/"
fi

# Logo Meteo partout, y compris les pages qui utilisent celui d'elastic.
ln -sf "../../meteo/images/logo.svg" "${RC_ROOT}/skins/elastic/images/logo.svg"

chown -R www-data:www-data "${SKIN_DST}" "${RC_ROOT}/skins/elastic/images"

# --- 3. annuaire des agents --------------------------------------------------
AGENTS_TSV="$(mktemp)"
if mysql --protocol=tcp -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASSWORD}" -N -B \
        -e "SELECT username, COALESCE(NULLIF(name, ''), username) FROM postfix.mailbox WHERE active = 1 ORDER BY name, username" \
        > "${AGENTS_TSV}" 2>/dev/null; then
    php -r '
        $rows = file($argv[1], FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        $agents = [];
        foreach ($rows as $row) {
            $parts = explode("\t", $row, 2);
            if (count($parts) < 2) { continue; }
            $agents[] = ["email" => $parts[0], "name" => $parts[1]];
        }
        file_put_contents($argv[2], "window.METEO_AGENTS = " . json_encode($agents, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . ";\n");
    ' "${AGENTS_TSV}" "${SKIN_DST}/agents.js"
    echo "[roundcube] annuaire : $(wc -l < "${AGENTS_TSV}") agents"
else
    echo "window.METEO_AGENTS = [];" > "${SKIN_DST}/agents.js"
    echo "[roundcube] annuaire : base postfix illisible, liste vide"
fi
rm -f "${AGENTS_TSV}"
chown www-data:www-data "${SKIN_DST}/agents.js"

echo "[roundcube] demarrage, base ${DB_NAME}, IMAP ${IMAP_HOST}:${IMAP_PORT}"
exec apache2-foreground
