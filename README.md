# PROJET_RESEAU — Webmail Météo Madagascar

Messagerie interne pour la Direction Générale de la Météo Madagascar : Postfix, Dovecot,
MariaDB, Rspamd/ClamAV, Roundcube et PostfixAdmin, avec un skin Roundcube sur mesure
(`labo/skins/meteo`) à l'interface française, en mode clair et sombre.

Le projet est développé et validé sur une VM de laboratoire (Ubuntu 22.04) avant tout
déploiement sur le serveur de production.

## Contenu du dépôt

| Dossier | Rôle |
|---|---|
| `labo/skins/meteo/` | Skin Roundcube : `meteo.js`, `styles/meteo.css`, gabarits, polices, logo |
| `labo/scripts/` | Scripts de déploiement et de validation (Postfix, Dovecot, web, skin, sauvegardes) |
| `labo/postfix/`, `labo/dovecot/`, `labo/rspamd/` | Configuration des services de messagerie |
| `labo/web/` | Configuration Roundcube / PostfixAdmin (valeurs sensibles remplacées par des jetons) |
| `labo/prod/`, `labo/simulateur/` | Paramètres de production et simulateur du Portail |
| `docs/` | Conception, plans d'exécution et comptes rendus de passation |

## État du système

`HANDOFF.md` décrit l'état courant : ce qui fonctionne, ce qui est cassé, la prochaine
action et la commande qui prouve chaque résultat. `docs/handoffs/` contient un compte
rendu par changement majeur, le plus récent en dernier.

## Travailler sur le projet

    git clone https://github.com/fanasinahenintsoa73-design/PROJET_RESEAU.git
    cd PROJET_RESEAU

Lire `AGENTS.md` avant toute modification : il fixe les règles (passation obligatoire,
preuves exigées, aucun secret dans le dépôt). Le déploiement vers le serveur Météo se fait
depuis le poste Windows qui a accès à la VM, avec `labo/scripts/19-deploy-skin.sh` pour le
skin.

## Secrets

Aucun mot de passe, jeton ou clé privée n'est versionné. Les fichiers de configuration
suivis contiennent des jetons (`__RC_DB_PW__`, `CHANGEME_roundcube`, …) remplacés au
déploiement ; les valeurs réelles restent sur le serveur.

## Cadre

Projet de réseau et de messagerie réalisé dans un cadre pédagogique pour Météo Madagascar.
Les adresses, domaines et comptes présents dans le dépôt appartiennent au laboratoire
(`meteo-test.lan`) ou sont des exemples.
