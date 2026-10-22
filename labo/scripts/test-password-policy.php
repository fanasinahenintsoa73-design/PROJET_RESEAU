<?php
/**
 * Test unitaire de la politique de mots de passe de PostfixAdmin.
 *
 * Usage : php test-password-policy.php
 * Retour : 0 si tous les cas sont conformes aux expectations, 1 sinon.
 *
 * Ce test appelle directement validate_password() (functions.inc.php de
 * PostfixAdmin) : il verifie donc la regle REELLE appliquee par l'interface
 * d'administration et par la CLI, pas une reimplementation de notre regle.
 */

if (!defined('POSTFIXADMIN_DIR')) {
    define('POSTFIXADMIN_DIR', getenv('PFA_DIR') ?: '/opt/postfixadmin');
}
// Même amorce que postfixadmin-cli.php (scripts/postfixadmin-cli.php l.392-394) :
// le define evite le bootstrap web, common.php charge Config, la config et
// les traductions.
if (!defined('POSTFIXADMIN_CLI')) {
    define('POSTFIXADMIN_CLI', 1);
}
chdir(POSTFIXADMIN_DIR);
require_once POSTFIXADMIN_DIR . '/common.php';
require_once POSTFIXADMIN_DIR . '/functions.inc.php';

// Cas : mot de passe => attendu (true = doit etre accepte, false = refuse)
$cas = array(
    // Trop court
    array('abc', false, 'trop court (3 caracteres)'),
    array('Abcdefgh1', false, 'trop court (9 caracteres)'),
    // Mot de passe courant ou contenant un mot courant
    array('password', false, 'mot de passe courant'),
    array('motdepasse2026', false, 'contient un mot courant'),
    array('MeteoMadagascar2026', false, 'contient un mot de l institution'),
    array('soleil2026', false, 'contient un mot courant'),
    // Repitif
    array('aaaaaaaaaaaaaa', false, 'caractere unique repete'),
    // Cas valides
    array('K7mQ2xR9tZ4nB6vY1cW', true, '20 caracteres aleatoires'),
    array('MeteoTest2026', false, 'contient meteo'),
    array('Kanto7Mialo9Ra', true, '14 caracteres, sans mot interdit'),
    array('Tana2026Bize', false, 'contient tana (Antananarivo)'),
    array('Vaovao2026Mada', true, '13 caracteres, sans mot interdit'),
);

// Un message brut cle PALANG (x_...) trahit une traduction manquante.
$cles_brutes = 0;

$echecs = 0;
foreach ($cas as $c) {
    list($mdp, $attendu, $libelle) = $c;
    $erreurs = validate_password($mdp);
    $accepte = (count($erreurs) === 0);
    $ok = ($accepte === $attendu);
    foreach ($erreurs as $err) {
        if (strpos($err, 'x_') === 0) {
            $cles_brutes++;
            $ok = false;
        }
    }
    if (!$ok) {
        $echecs++;
    }
    printf(
        "%-4s %-22s %-40s %s\n",
        $ok ? '[OK]' : '[KO]',
        $mdp,
        $libelle,
        $accepte ? 'accepte' : 'refuse : ' . implode(' | ', $erreurs)
    );
}

echo "\n";
if ($cles_brutes > 0) {
    echo "ATTENTION : {$cles_brutes} message(s) non traduits (cle PALANG brute renvoyee).\n";
}
if ($echecs === 0) {
    echo "POLITIQUE_MOTS_DE_PASSE_OK : " . count($cas) . " cas conformes.\n";
    exit(0);
}
echo "POLITIQUE_MOTS_DE_PASSE_KO : {$echecs} cas non conformes sur " . count($cas) . ".\n";
exit(1);
