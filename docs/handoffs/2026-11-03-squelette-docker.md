---
type: handoff
date: 2026-11-03
status: in-progress
commit: this commit
deployed: none (aucun conteneur construit ni lancé)
---
# Squelette Docker du webmail, en parallèle du natif et sans accès aux données existantes

## What changed

Nouveau dossier `labo/docker/`, plus `labo/.dockerignore` (contexte de build).

    labo/docker/
    ├── docker-compose.yml       6 services, ports décalés, restart: "no"
    ├── .env.example             domaine, ports, mots de passe SQL, RC_DES_KEY
    ├── README.md                démarrage, ce qui reste, mise à jour, sécurité
    ├── db/init/01-databases.sh  bases postfix + roundcube, comptes SQL
    ├── postfix/                 Dockerfile, main.cf.template, master.cf.append,
    │                            sql/{mailbox,alias}.cf.template, entrypoint.sh
    ├── dovecot/                 Dockerfile, dovecot.conf, dovecot-sql.conf.template,
    │                            entrypoint.sh
    ├── roundcube/               Dockerfile (RC 1.7.4), config.inc.php.template,
    │                            apache-ssl.conf, entrypoint.sh
    └── postfixadmin/            Dockerfile (3.3.13), config.local.php.template,
                                 apache.conf, entrypoint.sh

Choix structurants :

- **Isolation** : volumes nommés pour `/var/vmail`, la base et les sockets ; aucun bind mount vers les chemins du natif. `docker compose down -v` jette l'essai sans toucher au labo.
- **Ports décalés** : 2525/2587/2465 (SMTP), 1143/1993 (IMAP), 8444 (webmail), 8081 (PostfixAdmin). Le natif garde 25/465/587/143/993/8443.
- **Cartes SQL au lieu de fichiers hash** : `virtual_mailbox_maps` et `virtual_alias_maps` lisent MariaDB (`mysql:`), donc plus de `postfix_accounts.cf` à régénérer.
- **Remise par LMTP** : `virtual_transport = lmtp:unix:/var/run/dovecot/lmtp`, pour que Sieve et les quotas s'appliquent comme sur la VM.
- **`vmail` UID/GID 5000** fixés dans les deux images, pour que le volume reste lisible après reconstruction.
- **Le skin n'est pas figé dans l'image** : l'entrypoint de `roundcube` le copie depuis `labo/skins/meteo` à chaque démarrage, refait les liens `.min.css` vers `elastic`, copie les polices, symlinke le logo et régénère `agents.js` depuis la base — la même logique que `19-deploy-skin.sh`.
- **TLS auto-signé** généré dans les images (Postfix, Dovecot, Apache), vérification désactivée côté Roundcube. Let's Encrypt et `verify_peer = true` restent pour la production.
- **ClamAV hors périmètre** (décision du 2026-11-03).

## Why it changed

Demande : savoir où en est Docker et préparer un déploiement sans toucher aux données existantes. Le natif n'a pas été modifié : ce stack est un banc d'essai séparé, à valider avant toute bascule.

## How it was proven

Uniquement statique, et c'est assumé : la commande `docker` **n'existe pas** sur ce PC Windows, donc `docker compose config` et le moindre build sont impossibles ici. Aucun conteneur n'a été construit ni lancé.

Ce qui a été vérifié :

    $ for f in labo/docker/*/entrypoint.sh labo/docker/db/init/01-databases.sh; do bash -n "$f"; done
    labo/docker/db/init/01-databases.sh: OK
    labo/docker/postfix/entrypoint.sh: OK
    labo/docker/dovecot/entrypoint.sh: OK
    labo/docker/roundcube/entrypoint.sh: OK
    labo/docker/postfixadmin/entrypoint.sh: OK

Le YAML n'a pas pu être parsé : ni Python, ni Ruby, ni le module `yaml` de Node ne sont installés sur ce PC. **La première commande sur la VM doit être `docker compose config -q`**, avant tout build.

## What is left

1. `docker compose config -q` sur la VM, puis `docker compose build` (le téléchargement de Roundcube 1.7.4 et de PostfixAdmin 3.3.13 demande Internet).
2. Importer les schémas SQL (PostfixAdmin `DATABASE_MYSQL.TXT`, Roundcube `SQL/mysql.initial.sql`) — voir `labo/docker/README.md`, étape 3. C'est le trou assumé du squelette.
3. Créer un domaine et une boîte de test dans PostfixAdmin, puis la recette : login, envoi interne avec pièce jointe, redémarrage, persistance.
4. Vérifier le tag de l'image `rspamd/rspamd:3.8` ; le remplacer par le tag réellement publié si besoin.
5. Durcir les sockets Dovecot (`0666` aujourd'hui) avec des UID communs avant toute exposition.
6. Faire l'inventaire serveur en lecture seule avant de lancer : `docker --version`, `ss -ltnp`, `systemctl list-units 'postfix*' 'dovecot*'`, `free -h`, `df -h`, `du -sh /var/vmail`.

## How to undo it

    rm -rf labo/docker labo/.dockerignore
    git revert <commit>

Rien n'a été déployé : supprimer le dossier suffit à revenir à l'état précédent. Si des conteneurs ont été créés entre-temps : `docker compose down -v` depuis `labo/docker/`.
