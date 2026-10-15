#!/bin/bash
# =============================================================================
# Deploiement web : Roundcube + PostfixAdmin + Apache - LABO
# Usage : sudo ./09-deploy-web.sh
# Idempotent (re-lancable).
# =============================================================================
set -euo pipefail

SRC="${SRC:-/tmp/labo-web}"
COFFRE=/root/labo-credentials.txt
RC_TARBALL=/tmp/roundcubemail-1.7.4-complete.tar.gz

echo "=== 1. Socket PHP-FPM ==="
FPM_SOCK=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -1)
[ -n "${FPM_SOCK}" ] || { echo "ERREUR : aucun socket php-fpm" >&2; exit 1; }
echo "Socket : ${FPM_SOCK}"

echo "=== 2. Mot de passe MySQL roundcube (regenere + stocke) ==="
RC_PW=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
mysql -e "ALTER USER 'roundcube'@'localhost' IDENTIFIED BY '${RC_PW}'; FLUSH PRIVILEGES;"
sed -i '/^RC_DB_PW=/d' "${COFFRE}"
echo "RC_DB_PW=${RC_PW}" >> "${COFFRE}"
chmod 600 "${COFFRE}"

echo "=== 3. Extraction Roundcube ==="
# Idempotence : on ne retelecharge PAS le tarball si Roundcube est deja en place.
# (Le tarball vit dans /tmp, vide a chaque redemarrage ; le lien du labo est
#  lent — ~480 Ko/s mesurés — donc le re-telecharger serait une perte de temps.)
if [ -f /var/www/roundcube/index.php ]; then
    echo "Roundcube deja present (/var/www/roundcube) — extraction ignoree"
else
    [ -f "${RC_TARBALL}" ] || { echo "ERREUR : tarball absent (Roundcube non installe)" >&2; exit 1; }
    [ "$(stat -c%s "${RC_TARBALL}")" -gt 1000000 ] || { echo "ERREUR : tarball tronque" >&2; exit 1; }
    rm -rf /tmp/rc-extract
    mkdir -p /tmp/rc-extract
    tar xzf "${RC_TARBALL}" -C /tmp/rc-extract
    mv /tmp/rc-extract/roundcubemail-* /var/www/roundcube
    rm -rf /tmp/rc-extract
    chown -R www-data:www-data /var/www/roundcube
    chmod 750 /var/www/roundcube/temp /var/www/roundcube/logs

    echo "=== 3b. Init base roundcube ==="
    mysql roundcube < /var/www/roundcube/SQL/mysql.initial.sql
    echo "Tables : $(mysql -N -e 'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema="roundcube";')"
fi

echo "=== 5. config.inc.php (secrets injectes) ==="
DES_KEY=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
sed -e "s|__RC_DB_PW__|${RC_PW}|" -e "s|__RC_DES_KEY__|${DES_KEY}|" \
    "${SRC}/roundcube-config.inc.php.labo" > /var/www/roundcube/config/config.inc.php
chown www-data:www-data /var/www/roundcube/config/config.inc.php
chmod 640 /var/www/roundcube/config/config.inc.php

echo "=== 6. PostfixAdmin web ==="
MVPP=$(grep '^MVPP_POSTFIXADMIN=' /root/labo-credentials.txt | tail -1 | cut -d= -f2-)
if [ -z "${MVPP}" ]; then
    echo "ERREUR : MVPP_POSTFIXADMIN introuvable dans le coffre" >&2
    exit 1
fi
sed "s|__MVPP_POSTFIXADMIN__|${MVPP}|" \
    "${SRC}/postfixadmin-config.local.php" > /opt/postfixadmin/config.local.php
chown www-data:www-data /opt/postfixadmin/config.local.php
chmod 640 /opt/postfixadmin/config.local.php
mkdir -p /opt/postfixadmin/templates_c
chown -R www-data:www-data /opt/postfixadmin/templates_c

echo "=== 7. Vhosts + /etc/hosts ==="
sed "s|unix:/run/php/php[0-9.]*-fpm.sock|unix:${FPM_SOCK}|" \
    "${SRC}/webmail.conf.labo" > /etc/apache2/sites-available/webmail.conf
sed "s|unix:/run/php/php[0-9.]*-fpm.sock|unix:${FPM_SOCK}|" \
    "${SRC}/postfixadmin.conf.labo" > /etc/apache2/sites-available/postfixadmin.conf
grep -q webmail.meteo-test.lan /etc/hosts || echo "127.0.0.1 webmail.meteo-test.lan postfixadmin.meteo-test.lan" >> /etc/hosts

echo "=== 8. Modules + sites ==="
a2enmod ssl rewrite headers proxy_fcgi setenvif > /dev/null
a2dissite 000-default > /dev/null || true
a2ensite webmail postfixadmin > /dev/null
apache2ctl configtest

echo "=== 9. Redemarrage + tests ==="
systemctl restart php*-fpm 2>/dev/null || systemctl restart php8.1-fpm
systemctl restart apache2
sleep 2
systemctl is-active apache2
echo "--- webmail ---"
curl -sk -o /dev/null -w "HTTP %{http_code}\n" https://webmail.meteo-test.lan/
echo "--- postfixadmin ---"
curl -sk -o /dev/null -w "HTTP %{http_code}\n" https://postfixadmin.meteo-test.lan/
echo "DEPLOY_WEB_OK"