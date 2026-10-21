<?php
/**
 * Sonde de verification du reverse-proxy (LABO - debug uniquement).
 *
 * Ce fichier est depose temporairement dans le docroot par
 * labo/scripts/21-deploy-prod-web.sh, appele en HTTP direct (8080) puis a
 * travers le simulateur du Portail (8444), puis supprime.
 *
 * Il affiche ce que Roundcube COMPREND de la requete. C'est ce qui permet de
 * verifier que la configuration derriere un proxy HTTPS est correcte :
 *
 *   REMOTE_ADDR      l'IP du proxy (le Portail), pas celle de l'agent
 *   X_FORWARDED_FOR  l'IP reelle de l'agent, si le proxy la transmet
 *   CLIENT_IP        l'IP telle que Roundcube la calcule (base de ip_check
 *                    et de login_rate_limit : l'anti-bruteforce doit compter
 *                    les agents separement, pas le Portail)
 *   HTTPS            Roundcube sait-il qu'il est derriere un TLS ?
 *   URL_GENEREE      l'URL absolue que Roundcube produit (elle ne doit
 *                    JAMAIS pointer sur le port interne en http://)
 */

require_once '/var/www/roundcube/program/include/iniset.php';
rcube::get_instance();

echo 'REMOTE_ADDR=' . ($_SERVER['REMOTE_ADDR'] ?? '') . "\n";
echo 'X_FORWARDED_FOR=' . ($_SERVER['HTTP_X_FORWARDED_FOR'] ?? '') . "\n";
echo 'CLIENT_IP=' . implode(',', (array) rcube_utils::remote_ip()) . "\n";
echo 'HTTPS=' . (rcube_utils::https_check() ? 'oui' : 'non') . "\n";
echo 'URL_GENEREE=' . rcube_utils::resolve_url('/') . "\n";
