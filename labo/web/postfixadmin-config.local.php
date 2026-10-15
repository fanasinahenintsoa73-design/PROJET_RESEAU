<?php
/**
 * PostfixAdmin - configuration locale LABORATOIRE
 * Labo : meteo-test.lan
 *
 * DECISION : Argon2id, identique a la prod. Le hash Argon2id n'inclut PAS le
 * nom d'utilisateur, donc la connexion de l'administrateur a PostfixAdmin
 * fonctionne (cf. config.inc.php ligne 190).
 */
$CONF['configured'] = true;

// --- Base de donnees : base `postfix`, utilisateur `postfixadmin` -----------
$CONF['database_type'] = 'mysql';
$CONF['database_host'] = 'localhost';
$CONF['database_user'] = 'postfixadmin';
// SECRET : injecte a l'execution par 09-deploy-web.sh depuis le coffre
// /root/labo-credentials.txt. Ne JAMAIS commiter un vrai mot de passe ici.
$CONF['database_password'] = '__MVPP_POSTFIXADMIN__';
$CONF['database_name'] = 'postfix';
$CONF['database_port'] = '3306';

// --- Hachage des mots de passe ---------------------------------------------
// Format attendu par PostfixAdmin 3.3 : "dovecot:<SCHEMA>".
// ARGON2ID = choix de la conception (conception : Argon2id ou bcrypt, 12 car. min.)
$CONF['encrypt'] = 'dovecot:ARGON2ID';

// --- Securite ---------------------------------------------------------------
$CONF['admin_email'] = 'admin@meteo-test.lan';
$CONF['admin_name'] = 'Administrateur Labo';
$CONF['webmaster'] = 'admin@meteo-test.lan';

// En PROD : acces PostfixAdmin restreint au reseau interne (decision conception
// : pas de DNS public pour postfixadmin., blocage Apache par IP LAN).
$CONF['allowed_sending_networks'] = '127.0.0.0/8 10.0.2.0/24';

// --- DIVERGENCE LABO (D7) ---------------------------------------------------
// meteo-test.lan est un domaine FICTIF qui ne resout pas. PostfixAdmin refuse
// par defaut tout domaine non decouvrable en DNS (A, AAAA, MX ou NS).
// On desactive ce controle pour le labo UNIQUEMENT.
// EN PROD : meteomadagascar.mg resout -> ce controle doit RESTE a true.
// C'est un garde-fou utile : il empeche de creer un domaine mal orthographe.
$CONF['emailcheck_resolve_domain'] = false;