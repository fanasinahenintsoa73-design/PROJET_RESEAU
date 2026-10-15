-- =============================================================================
-- Labo meteo-test.lan - creation des 2 bases et des 2 utilisateurs
-- DECISION : deux bases separees, deux utilisateurs distincts, aucun droit croise.
--
--   postfixadmin  -> base `postfix`      (comptes, quotas, alias)
--   roundcube     -> base `roundcube`    (sessions, contacts, brouillons, filtres)
--   dovecot       -> lecture seule sur `postfix`.mailbox
--
-- Roundcube est du PHP expose sur Internet : s'il est compromis, il recupere
-- les sessions, PAS les 500 comptes.
-- =============================================================================

-- --- Base PostfixAdmin ------------------------------------------------------
CREATE DATABASE IF NOT EXISTS postfix CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'postfixadmin'@'localhost' IDENTIFIED BY 'CHANGEME_postfixadmin';
GRANT ALL PRIVILEGES ON postfix.* TO 'postfixadmin'@'localhost';

-- --- Base Roundcube ---------------------------------------------------------
CREATE DATABASE IF NOT EXISTS roundcube CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'roundcube'@'localhost' IDENTIFIED BY 'CHANGEME_roundcube';
GRANT ALL PRIVILEGES ON roundcube.* TO 'roundcube'@'localhost';

-- --- Utilisateur Dovecot : LECTURE SEULE sur la table mailbox -------------
CREATE USER IF NOT EXISTS 'dovecot'@'localhost' IDENTIFIED BY 'CHANGEME_dovecot';
GRANT SELECT ON postfix.mailbox TO 'dovecot'@'localhost';

FLUSH PRIVILEGES;

-- NOTE : 'dovecot' n'a AUCUN droit sur roundcube, et 'roundcube' aucun droit
-- sur postfix. Une compromission de l'un ne donne pas acces a l'autre.