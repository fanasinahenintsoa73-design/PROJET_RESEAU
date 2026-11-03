# Stack Docker du webmail Météo

Banc d'essai **en parallèle** du serveur natif. Aucun volume ne monte
`/var/vmail`, `/var/lib/mysql`, `/etc/postfix` ou `/etc/dovecot` de l'hôte :
les données du labo restent intactes, et un essai raté se jette avec
`docker compose down -v`.

## Ce que contient le stack

| Service | Rôle | Port publié (défaut) |
|---|---|---|
| `db` | MariaDB 10.11 : bases `postfix` et `roundcube` | — |
| `rspamd` | Anti-spam, milter | — |
| `postfix` | SMTP 25, submission 587, smtps 465 | 2525, 2587, 2465 |
| `dovecot` | IMAP 143/993, LMTP, Sieve | 1143, 1993 |
| `roundcube` | Webmail + skin `meteo` (HTTPS auto-signé) | 8444 |
| `postfixadmin` | Gestion des domaines et des boîtes | 8081 |

Les ports sont décalés pour ne jamais toucher à ceux du natif
(25/465/587/143/993/8443).

## Démarrage

    cd labo/docker
    cp .env.example .env
    # renseigner les mots de passe et RC_DES_KEY (openssl rand -base64 32)
    docker compose up -d --build

Le premier démarrage crée les bases et les comptes SQL. **Les schémas ne sont
pas encore importés** : c'est l'étape 3 ci-dessous.

## Ce qui reste à faire avant un vrai essai

1. **Schémas SQL.** Importer le schéma PostfixAdmin puis celui de Roundcube
   (fichiers `DATABASE_MYSQL.TXT` de PostfixAdmin et `SQL/mysql.initial.sql`
   de Roundcube 1.7.4) :

       docker compose exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" postfix < DATABASE_MYSQL.TXT
       docker compose exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" roundcube < mysql.initial.sql

2. **Compte de test.** Créer un domaine et une boîte dans PostfixAdmin
   (`https://127.0.0.1:8081/`), puis vérifier la connexion au webmail
   (`https://127.0.0.1:8444/`).
3. **Recette.** Login, envoi interne avec pièce jointe, lecture, redémarrage
   du stack, vérification que les messages sont toujours là.
4. **TLS.** Les certificats sont auto-signés et générés dans les images.
   En production : Let's Encrypt, et `verify_peer` remis à `true` dans
   `roundcube/config.inc.php.template`.
5. **ClamAV** est hors périmètre de cette première version (décision du
   2026-11-03).

## Mise à jour après un `git pull`

Le skin n'est pas figé dans l'image : l'entrypoint de `roundcube` le copie
depuis `labo/skins/meteo` à chaque démarrage, avec les mêmes liens que
`19-deploy-skin.sh` sur la VM.

    git pull
    docker compose restart roundcube

Une modification de `Dockerfile`, de `docker-compose.yml` ou d'un modèle
(`*.template`) demande un rebuild :

    docker compose up -d --build

## Vérifications utiles

    docker compose ps
    docker compose logs -f postfix dovecot roundcube
    docker compose exec postfix postconf -n | head -40
    docker compose exec dovecot doveadm auth test <boite> <mot-de-passe>

## Sécurité

- `.env` contient les secrets et n'est pas commité.
- Les mots de passe SQL doivent être alphanumériques : ils traversent
  `envsubst` et les chaînes de connexion (`mysql://…`, `connect = …`).
- Les sockets Dovecot partagées avec Postfix sont en mode `0666` : elles ne
  circulent que sur le réseau Docker interne. À durcir (UID fixes communs)
  avant toute exposition.
- `restart: "no"` partout : un redémarrage de la VM ne relance pas l'essai.

## Retour arrière

    docker compose down -v     # supprime les conteneurs ET les volumes du stack

Le natif n'a jamais été arrêté ni modifié : il suffit de ne pas publier les
ports du stack pour revenir à l'état antérieur.
