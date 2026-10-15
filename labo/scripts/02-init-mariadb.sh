#!/bin/bash
# =============================================================================
# Phase 3 - Initialisation MariaDB (LABO)
# Cree : 2 bases separees + 3 utilisateurs distincts + mots de passe aleatoires
# Reutilisable tel quel en prod (seuls les secrets changent)
# =============================================================================
set -euo pipefail

echo "=== 1. Demarrage de MariaDB ==="
sudo systemctl enable mariadb
sudo systemctl start mariadb
sleep 3
sudo systemctl is-active mariadb

echo ""
echo "=== 2. Generation des mots de passe aleatoires ==="
# 24 caracteres alphanumeriques : pas de caractere special = pas de souci
# d'echappement dans les fichiers de configuration
gen_pwd() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 24; }

PW_POSTFIXADMIN="$(gen_pwd)"
PW_ROUNDCUBE="$(gen_pwd)"
PW_DOVECOT="$(gen_pwd)"

echo "postfixadmin : genere"
echo "roundcube    : genere"
echo "dovecot      : genere"

echo ""
echo "=== 3. Creation des bases et des utilisateurs ==="
sudo mysql <<SQL
CREATE DATABASE IF NOT EXISTS postfix CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'postfixadmin'@'localhost' IDENTIFIED BY '${PW_POSTFIXADMIN}';
GRANT ALL PRIVILEGES ON postfix.* TO 'postfixadmin'@'localhost';

CREATE DATABASE IF NOT EXISTS roundcube CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'roundcube'@'localhost' IDENTIFIED BY '${PW_ROUNDCUBE}';
GRANT ALL PRIVILEGES ON roundcube.* TO 'roundcube'@'localhost';

CREATE USER IF NOT EXISTS 'dovecot'@'localhost' IDENTIFIED BY '${PW_DOVECOT}';
GRANT SELECT ON postfix.mailbox TO 'dovecot'@'localhost';
FLUSH PRIVILEGES;
SQL
echo "Bases et utilisateurs crees."

echo ""
echo "=== 4. Sauvegarde des secrets (labo uniquement) ==="
sudo install -m 600 /dev/null /root/labo-credentials.txt
sudo tee -a /root/labo-credentials.txt > /dev/null <<EOF
# Mots de passe LABO - generes le $(date -u '+%Y-%m-%d %H:%M UTC')
# JAMAIS REUTILISER EN PRODUCTION.
postfixadmin : ${PW_POSTFIXADMIN}
roundcube    : ${PW_ROUNDCUBE}
dovecot      : ${PW_DOVECOT}
EOF
sudo chmod 600 /root/labo-credentials.txt
echo "Secrets ecrits dans /root/labo-credentials.txt (mode 600)"

echo ""
echo "=== 5. Verification des cloisonnements ==="
echo "-- dovecot ne doit voir QUE la table mailbox en lecture :"
sudo mysql -e "SHOW GRANTS FOR 'dovecot'@'localhost';"
echo "-- postfixadmin ne doit PAS avoir de droits sur roundcube :"
sudo mysql -e "SHOW GRANTS FOR 'postfixadmin'@'localhost';"
echo "-- roundcube ne doit PAS avoir de droits sur postfix :"
sudo mysql -e "SHOW GRANTS FOR 'roundcube'@'localhost';"

echo ""
echo "=== 6. Etat final ==="
sudo mysql -e "SHOW DATABASES;"
echo "PHASE3_OK"