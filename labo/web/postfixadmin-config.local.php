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

// --- Politique des mots de passe (durcie) ------------------------------------
// La conception exige : 12 caracteres minimum, anti-bruteforce (Fail2ban),
// liste des mots de passe courants bloquee.
//
// DEFAUT POSTFIXADMIN 3.3 (config.inc.php l.231) : 5 caracteres minimum,
// 3 lettres, 2 chiffres, AUCUNE liste de mots de passe courants -> trop
// faible, on le remplace.
//
// SEMANTIQUE EXACTE de validate_password() (functions.inc.php l.872) :
//   - pour une regex, le mot de passe doit CORRESPONDRE a la regex
//     (preg_match sans ancres) ;
//   - une valeur callable est appelee avec le mot de passe ; une valeur de
//     retour non vide = echec, et DOIT etre une cle PALANG ;
//   - un texte PALANG custom se declare via $CONF['language_hook'] qui doit
//     RENVOYER le tableau $PALANG (les cles custom doivent porter le
//     prefixe x_).
//
// Choix de conception : pas de regle "1 caractere special obligatoire".
// La conception l'ecrit elle-meme : "la longueur compte plus que la
// complexite" et les regles "1 caractere special + 1 chiffre" produisent
// des mots de passe devinables (Meteo2024!). On impose donc la longueur,
// la variety minimal et le blocage des mots de passe courants.
$CONF['password_validation'] = array(
    '/.{12,}/'              => 'password_too_short 12',   // 12 caracteres minimum
    '/([a-zA-Z].*){3}/'     => 'password_no_characters 3', // 3 lettres minimum
    '/([0-9].*){2}/'        => 'password_no_digits 2',     // 2 chiffres minimum
    'x_meteo_dictionary'    => 'meteo_password_dictionary_check',
    'x_meteo_repetition'    => 'meteo_password_repetition_check',
);

// Liste des mots de passe a bloquer. Volontairement courte et explicite :
// ce sont les mots de passe les plus utilises en francais et les mots
// lies a l'institution. En production, cette liste doit etre remplacee ou
// completee par un vrai dictionnaire (RockYou, HIBP) si la direction en
// fournit un -- sinon le blocage ne couvre que le-evident.
function meteo_common_passwords() {
    return array(
        'password', 'passw0rd', 'motdepasse', 'azerty', 'qwerty', '123456',
        '12345678', '123456789', '1234567890', '000000', '111111',
        'meteo', 'meteomadagascar', 'meteorologie', 'meteo2026', 'meteo2024',
        'madagascar', 'antananarivo', 'toamasina', 'mahajanga', 'fianarantsoa',
        'tana', 'dgmeteo', 'direction', 'prevision', 'bulletin', 'observation',
        'administrateur', 'admin', 'welcome', 'letmein', 'monadresse',
        'soleil', 'pluie', 'cyclone', 'tsunami', 'inondation',
    );
}

// Mot de passe trop courant -> echec.
// ATTENTION : validate_password() ne traduit PAS le retour d'un callable
// (functions.inc.php l.885 : $result[] = $ret, sans Config::lang()) ;
// le callable doit donc renvoyer le TEXTE FINAL. On passe par
// Config::lang() pour que la traduction vienne du language_hook.
function meteo_password_dictionary_check($password) {
    $p = strtolower($password);
    foreach (meteo_common_passwords() as $word) {
        if (strpos($p, $word) !== false) {
            return Config::lang('x_password_too_common');
        }
    }
    return '';
}

// Mot de passe trop repitif (un seul caractere repete) -> echec.
// On ne peut PAS tester le nom d'utilisateur ici : validate_password() ne
// reçoit que le mot de passe. Le controle du nom d'utilisateur est assure
// ailleurs : mot de passe provisoire aleatoire et unique par compte.
function meteo_password_repetition_check($password) {
    if (preg_match('/^(.)\1+$/', $password)) {
        return Config::lang('x_password_too_simple');
    }
    return '';
}

// Textes de l'interface pour les deux regles ci-dessus.
function meteo_language_hook($PALANG, $language) {
    $PALANG['x_password_too_common'] = "Mot de passe refuse : il est trop courant ou contient un mot trop courant.";
    $PALANG['x_password_too_simple'] = "Mot de passe refuse : il est trop repetitif.";
    return $PALANG;
}
$CONF['language_hook'] = 'meteo_language_hook';

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