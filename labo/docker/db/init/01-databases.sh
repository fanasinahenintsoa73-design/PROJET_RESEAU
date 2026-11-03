#!/bin/bash
# =============================================================================
# Cree les bases et les comptes SQL du stack Docker.
# Execute une seule fois, par l'entrypoint MariaDB, quand le volume est vide.
# Les comptes sont en '%' : les conteneurs se connectent par le reseau Docker,
# pas par la socket locale.
# =============================================================================
set -euo pipefail

: "${MARIADB_ROOT_PASSWORD:?}"
: "${DB_ROUNDCUBE_PASSWORD:?}"
: "${DB_DOVECOT_PASSWORD:?}"
: "${DB_POSTFIXADMIN_PASSWORD:?}"

mysql --protocol=socket -uroot -p"${MARIADB_ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS roundcube
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'roundcube'@'%' IDENTIFIED BY '${DB_ROUNDCUBE_PASSWORD}';
GRANT ALL PRIVILEGES ON roundcube.* TO 'roundcube'@'%';
-- L'annuaire agents.js du skin lit la liste des boites actives.
GRANT SELECT ON postfix.mailbox TO 'roundcube'@'%';

CREATE USER IF NOT EXISTS 'dovecot'@'%' IDENTIFIED BY '${DB_DOVECOT_PASSWORD}';
GRANT SELECT ON postfix.mailbox TO 'dovecot'@'%';

CREATE USER IF NOT EXISTS 'postfixadmin'@'%' IDENTIFIED BY '${DB_POSTFIXADMIN_PASSWORD}';
GRANT ALL PRIVILEGES ON postfix.* TO 'postfixadmin'@'%';

FLUSH PRIVILEGES;
SQL

echo "[db] bases postfix + roundcube et comptes SQL crees"
echo "[db] reste a importer les schemas (voir labo/docker/README.md, etape 3)"
