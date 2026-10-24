# Labo mail — carnet d'exécution guidée

> Exécution par blocs copier-coller : l'agent écrit les commandes exactes, l'utilisateur les colle
> dans SON terminal SSH et renvoie les sorties. L'agent vérifie, puis donne le bloc suivant.

**VM :** `server_messagerie` — Ubuntu 22.04.4 LTS — NAT (2222→22) — user `messagerie` (sudo NOPASSWD OK, vérifié).
**Domaine labo :** `meteo-test.lan` (fictif, jamais publié en DNS).
**Objectif :** pile complète Postfix + Dovecot + MariaDB + Rspamd + ClamAV + Roundcube + PostfixAdmin,
2 comptes fictifs, test d'envoi/réception interne.

## Conventions

- `VOTRE terminal` = celui de l'utilisateur (colle les blocs, renvoie TOUTE la sortie).
- `Vérif agent` = contrôles lecture seule via clé SSH (autorisés en mode plan).
- En cas d'écart à la sortie attendue : STOP, envoyer la sortie réelle, attendre le bloc corrigé.

## Phases

- [x] **0. Snapshot** `01-avant-pile-mail` (UUID 94d0b4c3, pris par l'agent via VBoxManage le 2026-10-15) — retour arrière.
- [x] **1. Mises à jour + inventaire** — 2026-10-15 : RAM 1,9 Gio, 1 CPU, disque LVM 8,3 Go (3,3 Go libres), 614 paquets, IP 10.0.2.15. Upgrade ~180 paquets OK, `dpkg --audit` propre, pas de reboot. 10 paquets restants sans importance (open-vm-tools, fwupd, netplan…). Postfix 3.6.4 + swaks installés.
- [x] **2. Postfix installé** — mailname `mail.meteo-test.lan`.
- [x] **3. MariaDB** + 2 bases séparées (`postfix`, `roundcube`) + users cloisonnés (dovecot=SELECT mailbox) — PostfixAdmin 3.3.16 officiel dans /opt/postfixadmin, CLI wrapper, schéma via upgrade.php, domaine + admin + 5 comptes créés (Argon2id).
- [x] **4. Dovecot** — actif (IMAP 143/993, ManageSieve 4190, quota 2G+grace 432000s, sieve LMTP-scopé, socket SASL auth-client postfix:postfix 0660). Boucle IMAP/TLS validée : LOGIN SQL+Argon2id, SELECT 2 msgs, FETCH, LOGOUT.
- [x] **5. Pont Postfix↔MariaDB** — 5 boîtes + 4 alias exportés, postmap OK. Livraison swaks validée (contenu headers+body intacts). VRFY=502 disabled, ETRN masqué. 587 STARTTLS+SASL validé (235 auth, livraison OK, submission chroot=n).
- [x] **6. Rspamd** — actif (milter 11332, 4 headers posés sur courrier sain score 0.95/15, GTUBE rejeté au DATA 5.7.1, rien en boîte).
- [x] **7. Apache + Roundcube + PostfixAdmin** — Roundcube 1.7.4 (docroot `public_html` obligatoire depuis 1.6), 2 vhosts TLS snakeoil, base `roundcube` (18 tables), IMAP 993 + SMTP 587, fr_FR, login web + vue boîte validés (41 Ko, messagelist).
- [x] **8. Fail2ban** — 5 prisons actives. Filtre Roundcube = filtre **stock** `roundcube-auth.conf` (le maison est **impossible** : fail2ban prend `<9ind6fld>` pour un tag). Bannissement prouvé de bout en bout sur IP simulée 203.0.113.5 → règle iptables REJECT.
- [x] **9. 5 comptes + validation bout-en-bout** — 5 comptes fictifs, chaîne complète prouvée 3 fois (SMTP direct, 587 authentifié, webmail).
- [x] **10. Sauvegardes Restic** — dépôts local + déporté initialisés (2 clés distinctes), sauvegarde quotidienne OK, copie déportée OK, **test de restauration RÉUSSI** (critère n° 5).
- [x] **11. Cœur** — open relay 4/4, signature DKIM opérationnelle, 34/34 revalidés.
- [x] **12. Interface Roundcube « meteo »** — skin de surcouche (zéro PHP) : logo institutionnel, palette, tableau de bord d'accueil, gros boutons, page de connexion. **Zéro 404** à l'audit.
- [x] **12 bis. Modèles de rédaction** — 5 modèles institutionnels déployés par le mécanisme **natif** `compose_responses_static` : globaux, sans SQL, sans ligne par utilisateur. Insertion dans l'éditeur vérifiée (0 → 582 caractères).
- [x] **13. Cloisonnement web de production** — 2 pools PHP-FPM distincts (`roundcube` / `pfa`), vhosts internes 8080 / 8081, config Roundcube « derrière proxy » (`use_https`, `proxy_whitelist`, `trusted_host_patterns`), simulateur de Portail. 23 PASS / 0 FAIL, limite d'envoi 2 Mo → **50 Mo**.
- [x] **14. ClamAV sur les pièces jointes** — ClamAV 1.5.4 + module antivirus Rspamd, refus 554 5.7.1 sur EICAR. Test de référence **4/4** (sain accepté, PJ binaire refusée, PJ texte refusée, corps **non** scanné). 34/34 revalidés.
- [x] **15. Rspamd 4.2.2 (dépôt officiel)** — migration 2.7 → 4.2.2, D9 fermée, la pile labo est désormais **identique** à la prod. 34/34 revalidés, ClamAV 4/4 revalidé, DKIM toujours signé.
- [x] **16. Import à l'échelle + quotas par profil + politique de mots de passe** — 400 comptes importés (405 boîtes, 0 doublon, 0 erreur), quotas **pilotés par les données** (2/3/5 Go vérifiés par `doveadm quota get`), politique durcie (12 caractères + dictionnaire institutionnel) testée 12/12. Abandon mesuré du « changement de mot de passe à la 1re connexion ».
- [x] **17. Refonte du skin selon le design du site réel + test de continuité** — identité visuelle du site `meteomadagascar.mg` (jaune `#F4C910` en action, teal `#17938A` en accent, Open Sans embarquée, boutons 8 px uppercase) ; 2 défauts de rendu corrigés ; **continuité sans MariaDB prouvée** (réception ET livraison maintenues, authentification en `temp_fail`).
- [x] **18. Le webmail en page unique** — la tâche « mail » devient un **poste de travail en une page** (bandeau + 3 tuiles d'action + panneau latéral unique + liste des messages pleine largeur) ; **lecture en panneau superposé** (la liste reste visible, l'adresse de la page ne change pas) ; **rédaction en panneau superposé** (formulaire pré-rempli) ; **envoi réel validé de bout en bout** ; version téléphone (grille 2×2, panneau en tiroir). Toujours **zéro PHP** : un gabarit, une feuille de style et un script.

## Phase 10 — Sauvegardes (le volet qui manquait)

**Scripts :** `13-backup-init.sh` (dépôts) · `14-backup-daily.sh` (quotidien) · `15-copie-deportee.sh` (hebdo) · `16-test-restauration.sh` (**le test critique**).

**Périmètre implémenté** : `mysqldump` des bases `postfix`+`roundcube` (écrit dans une zone de transit, jamais à moitié sauvegardé) · `/var/vmail` · `/etc/postfix` `/etc/dovecot` `/etc/rspamd` `/etc/ssl` · `/etc/hostname` `/etc/mailname` `/etc/hosts` `/etc/resolv.conf` `/etc/aliases` · `config.local.php` PostfixAdmin · config Roundcube · `/var/lib/rspamd/dkim` (clés DKIM, absent en labo car aucune signature émise).
**Hors périmètre** : journaux, fichiers temporaires, l'OS lui-même.

**Deux clés distinctes** : dépôt local et dépôt déporté n'ont pas le même mot de passe. Compromettre la sauvegarde locale ne donne pas la copie de secours.

**Résultats mesurés :**

| Étape | Résultat |
|---|---|
| `13-backup-init.sh` | 2 dépôts initialisés · `INIT_BACKUP_OK` |
| `14-backup-daily.sh` | 181 fichiers, 866 Kio, snapshot créé · `BACKUP_OK` |
| Rétention | `--keep-daily 7 --keep-weekly 4 --prune` |
| Vérification dépôt | `no errors were found` |
| `15-copie-deportee.sh` | snapshot `753d8df5` → `5d6fe1a6` (**ID différent = réencryption**) · `COPIE_DEPORTEE_OK` |
| `16-test-restauration.sh` | **3 messages → 3, identiques** (chemin, `Date:`, taille, mtime) + relus en IMAP |

**Test de restauration — le point clé du projet.** Le script ne vérifie pas que la sauvegarde *a réussi*, il vérifie qu'on peut *en revenir* : relevé de l'état de la boîte → déplacement de la boîte (simule la perte du disque) → restauration → comparaison avant/après → relecture IMAP. Verdict obtenu :
```
Date: Thu, 15 Oct 2026 14:42:36 +0000
Date: Thu, 15 Oct 2026 19:08:52 +0000
Date: Thu, 15 Oct 2026 19:09:22 +0000
# VERDICT : RESTAURATION VALIDEE
```

**Planification** (systemd, 4 fichiers versionnés dans `labo/systemd/`) :
- `meteo-backup.timer` → quotidien **01:00** + `RandomizedDelaySec=600` (ne pas tomber à la même seconde que les 500 agents) + `Persistent=true` (rattrape un redémarrage)
- `meteo-copie-deportee.timer` → **dimanche 02:00**, après le backup du dimanche 01:00
- Chemin d'exécution systemd validé : `meteo-backup.service` → `BACKUP_OK`, `Deactivated successfully`

**Leçon du volet :** une sauvegarde non restaurée n'est pas une sauvegarde. Les 4 scripts ont été écrits puis *réellement exécutés*, 3 défauts du script de restauration ont été trouvés par l'exécution, pas par la relecture.

## Phase 11 — Vérifications de cœur (open relay + DKIM)

Sur les 5 tests encore possibles, **2 seulement touchent le cœur** : l'open relay (critère n° 3 d'ouverture, sécurité) et la signature DKIM (contrôle d'émission). Les 3 autres — import à l'échelle, quota, anti-bruteforce IMAP — relèvent du *préparatif de déploiement*.

### 11.1 Open relay — VALIDÉ 4/4 (`labo/scripts/17-test-open-relay.sh`)

| # | Scénario | Attendu | Résultat |
|---|---|---|---|
| 1 | Livraison interne sans authentification | accepté | **250 PASS** |
| 2 | Relais vers `example.invalid` sans authentification | **refusé** | **554 PASS** |
| 3 | Relais externe **avec authentification sur 587** | accepté | **250 PASS** |
| 4 | Contournement par IP brute `victim@[203.0.113.5]` | **refusé** | **554 PASS** |

**Le piège le plus important de cette phase.** Testé depuis `127.0.0.1`, le serveur **accepte** le relais (`250 2.1.5 Ok`), parce que `mynetworks = 127.0.0.1/32 10.0.2.15/32` — la machine se fait confiance à elle-même. **Un test d'open relay lancé depuis la machine locale ne teste rien et donne un faux sentiment de sécurité.** Le script réduit temporairement `mynetworks` à `127.0.0.1/32` pour que la source `10.0.2.15` soit traitée comme extérieure, et restaure par `trap ... EXIT INT TERM`.

Autres pièges : `swaks` n'émet pas de marqueur `***` (la réponse est la ligne suivant `RCPT TO:`) ; Postfix refuse avec **554** aussi bien qu'avec 550 ; Postfix n'annonce `AUTH` sur le 587 **qu'après STARTTLS** (`--tls` obligatoire) ; le port 25 est chrooté et ne voit donc pas le socket SASL — **tous les envois sortants passent par le 587**, c'est la conception.

### 11.2 Signature DKIM — VALIDÉE

Signature obtenue sur les envois authentifiés du 587 :
```
DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=meteo-test.lan;
	s=dkim; t=1792135232;
```

**Deux causes racines, ni l'une ni l'autre visibles à la lecture du code :**

1. **`skip_authenticated = true`** dans `local.d/milter_headers.conf`. Or le 587 est le **seul** canal d'envoi sortant de la conception : avec ce réglage, *aucun* message de l'institution n'est traité par Rspamd — ni score, ni signature, et un en-tête `Authentication-Results: ORIGINING;` vide. Passé à `false`. Le coût assumé : Rspamd analyse aussi les envois internes, ce qui empêche un poste infecté d'utiliser la messagerie comme relais.
2. **Nommage de la clé inversé.** Le modèle de chemin est `"$domain.$selector.key"` → **le domaine vient en premier** : `meteo-test.lan.dkim.key`, et non `dkim.meteo-test.lan.key`. Un nom de fichier dans le désordre ne produit qu'une ligne de journal (`dkim_module_load_key_format: cannot parse raw private key`) et le message part **sans signature, silencieusement**. Voir `labo/rspamd/local.d/dkim_signing.conf`.
   Piège d'outillage : `rspamadm dkim_keygen` sur Ubuntu 22.04 (Rspamd **2.7**) **affiche la clé sur stdout et n'écrit aucun fichier** — il faut l'option `-k/--privkey`, et le répertoire doit préexister.

**Preuve que la clé survit à une restauration** — c'est le point critique, une clé non restaurée casse *tous* les envois futurs :

| Étape | Résultat |
|---|---|
| Clé présente dans le snapshot | `/var/lib/rspamd/dkim/meteo-test.lan.dkim.key` ✓ |
| Clé **perdue** (déplacée hors du chemin) | répertoire vide |
| Clé **restaurée** depuis le dépôt | `_rspamd:_rspamd` 640 ✓ |
| Envoi après restauration | **signature DKIM présente** ✓ |

L'enregistrement DNS à publier est dans `/tmp/dkim-record.txt` :
`dkim._domainkey IN TXT ("v=DKIM1; k=rsa; " "p=MIIBIjANBgkqhki…")` → à intégrer à la demande DNS de `meteomadagascar.mg` (Partie A, non encore rédigée).

## Phase 12 — Interface Roundcube « meteo » (skin de surcouche, zéro PHP)

**Fichiers versionnés :** `labo/skins/meteo/` (`meta.json`, `images/logo.png`, `images/logo.svg`, `styles/meteo.css`, `templates/includes/layout.html`, `templates/login.html`, `templates/mail.html`) · `labo/scripts/19-deploy-skin.sh`.

**Décision structurante : zéro PHP.** Personne n'étant assuré de maintenir du code après le stage, le skin est une **surcouche du skin `elastic`** (héritage officiel via `meta.json` → `"extends": "elastic"`), sans une seule ligne de PHP ni de plugin. Un skin survit aux mises à jour de Roundcube ; un plugin PHP non maintenu casse à la première upgrade.

**Contenu :** logo institutionnel (PNG officiel 187×77 → SVG autoportant data-URI), palette du Portail (`#1e3c72` / `#3077ba` / `#3498db`, liseré `#f2c200`), bandeau de tableau de bord en dégradé, **4 tuiles** (Rédiger / Boîte de réception / Contacts / Réglages) + 2 raccourcis (Modèles de rédaction → `?_task=settings&_action=responses`, Site officiel), page de connexion dégradée avec logo 240 px, mode sombre, mobile ≤ 480 px, styles d'impression.

**Les « modèles de rédaction » ne coûtent aucun développement** : le mécanisme **natif** *Réponses enregistrées* de Roundcube (tâche `settings`, action `responses`) fait déjà le travail.

### Trois pièges Roundcube 1.7.4 découverts à l'exécution (tous documentés dans le script)

1. **La feuille de style d'`elastic` n'était plus servie (404) → interface déstylée.** `file_mod()` ne bascule sur la variante `.min.` que via `filemtime()` **dans le skin courant** ; le skin enfant n'ayant pas de `.min.css`, le repli ne se déclenchait plus. → **liens symboliques** `skins/meteo/styles/{styles,print,embed}.min.css` → `../../elastic/styles/…` (ils suivent les mises à jour d'`elastic`). Le lien doit être **relatif**.
2. **Polices en 404.** La feuille d'`elastic` référence les polices en chemin relatif (`url(../fonts/…)`) → servies depuis `skins/meteo/styles/`, le navigateur les demande dans `skins/meteo/fonts/`. `static.php` **refuse un répertoire symlinké** (il fait `realpath()`) alors qu'il accepte un fichier symlinké → il faut **copier les 12 fichiers réels** d'`elastic`.
3. **Le logo de l'écran d'accueil restait celui d'`elastic`** (la page de connexion montrait bien le Météo). La résolution du logo passe par `abs_url()` → `get_skin_file()` → `find_file_path()` et, sur le template *hérité* `menu.html`, aboutit à `skins/elastic/images/logo.svg` : la surcharge par fichier du skin enfant n'y est pas appliquée. → **lien symbolique** `skins/elastic/images/logo.svg` → `../../meteo/images/logo.svg` (original sauvegardé en `.orig`), recréé à chaque déploiement.

> Autres conclusions : `find_file_path()` renvoie le **premier** skin trouvé (l'enfant gagne) ; `abs_url()` appelle `get_skin_file()` **sans** `$add_path` (différence avec `file_callback()`) ; `$_SESSION['skin_config']` ne contient que le `config` du skin **parent** → le `config` d'`elastic` est **recopié intégralement** dans `meta.json` ; `check_skin()` refuse un nom contenant `/` ou `\`.

**Garde-fou du script 19** : il refuse de déployer `styles/styles.css` ou `styles/styles.min.css` dans le skin (ces fichiers **remplaceraient** la feuille complète d'`elastic`) et **audite en HTTP toutes les ressources citées** par la page — code de sortie = nombre d'échecs. C'est ce qui a détecté la régression n° 1.

**Validation (Playwright, certificat auto-signé D1)** : page de connexion → logo Météo 207×91 + en-tête « Météo Madagascar / Messagerie institutionnelle — Direction Générale de la Météorologie » ; après connexion → **zéro 404**, logo Météo 78×36, tableau de bord 387×172 avec 4 tuiles, police `Roboto` (d'`elastic`) bien appliquée, interface en français.

### Les modèles de rédaction — mécanisme NATIF, zéro développement

**Ce qu'il ne faut PAS faire :** la table `responses` de Roundcube est **par utilisateur** (`user_id` avec clé étrangère vers `users`), et les comptes Roundcube n'existent qu'**après la première connexion**. Pré-remplir des modèles par SQL obligerait à pré-créer 300-400 lignes `users` — fragile, et les comptes qui n'ont jamais connecté resteraient sans modèle.

**Ce qu'il faut faire : `$config['compose_responses_static']`** (mécanisme natif, lu dans `program/include/rcmail.php`, `get_compose_responses()` / `get_compose_response()`) :
- les modèles sont **globaux** : visibles par tous les agents, dès la première connexion, **sans aucune ligne SQL** ;
- ils sont listés **avant** les modèles personnels de l'agent ;
- un agent **ne peut pas les supprimer** (ils ne sont pas dans SA table `responses`) — c'est voulu, ce sont des modèles de l'institution ;
- structure d'une entrée : `name` (libellé), `text` (corps texte brut) et/ou `html` (corps HTML, prioritaire) ;
- l'identifiant interne est `static-<md5(name)[0:16]>`.

**Fichiers** : `labo/web/roundcube-reponses-static.php` (les modèles, **versionnés**) · `labo/scripts/20-deploy-reponses.sh` (déploiement). Le fichier des modèles est **distinct de `config.inc.php`** — qui porte les secrets et n'est donc pas versionné ; le script y injecte un `require_once __DIR__ . '/reponses-static.php';` idempotent, après sauvegarde `.bak.<date>`.

**Les 5 modèles** : *Bulletin météorologique — diffusion* · *Signalement d'observation — station* · *Demande de relevé / de données — station* · *Demande d'intervention technique* · *Accusé de réception*. Chaque corps est un formulaire à crochets `[ ]` que l'agent remplit (Roundcube ne substitue aucun placeholder).

**Validation fonctionnelle (Playwright)** : menu « Réponses » de la fenêtre de rédaction → les 5 modèles listés avec leurs identifiants `static-` ; clic sur *Signalement d'observation* → le corps passe de **0 à 582 caractères**, texte du modèle et crochets intacts, **zéro erreur HTTP**. La page *Paramètres → Réponses* affiche également les 5 modèles.

> **Piège d'automatisation** : le champ de rédaction est `TEXTAREA#composebody` (et non `#compose-body`), et l'éditeur HTML est une iframe `#rcmbody` qui n'existe pas tant que l'éditeur texte brut est actif. Les liens du menu sont dans un `#responses-menu` **caché** : un `locator.click()` échoue avec « Element is not visible » → passer par `element.click()` en JavaScript ou ouvrir d'abord le déclencheur `a.responses`.

## Architecture cible en production — le Portail Météo

**Découverte structurante (21 octobre) :** `mail.meteomadagascar.mg` est déjà servi par une **plateforme interne de gestion des sous-domaines** (« Portail Météo », SPA Vite, API `auth.meteomadagascar.mg`, backend Node/Express derrière nginx). Elle occupe **le port 443 de `41.207.49.27`** (elle y sert `adl.meteomadagascar.mg` avec un Let's Encrypt valide) et ne fait **pas** de DNS — elle ne crée que des **vhosts nginx** avec un champ `ipCible`.

**Conséquences :**
- Notre Apache **ne peut pas** prendre le 443 de l'IP publique.
- Let's Encrypt **HTTP-01 est impossible** (port 80 déjà pris) et le **DNS-01 est impossible** (pas d'API sur la zone, zone DNS chez Stellarix) → **la seule voie praticable pour un certificat valide est la plateforme** (`POST /api/subdomains/:id/ssl`).
- `mail.` reste le nom **SMTP/IMAP** (ports 25/587/993/4190 pointés en direct sur le serveur mail — le Portail n'y touche pas) ; **`webmail.`** est le nom **web**, en reverse-proxy.

```
Agent → https://webmail.meteomadagascar.mg
      → nginx du Portail  (TLS Let's Encrypt terminé ici)
      → proxy HTTP vers http://<serveur mail>:8080
      → Apache / Roundcube → IMAP/SMTP → Dovecot + Postfix
```

**Le Portail devient une dépendance du *webmail*, pas de la *messagerie*** : si le Portail tombe, IMAP et SMTP continuent de fonctionner.

**Cas de routage à trancher à l'ouverture du SSH** (un seul réglage à basculer) : si le Portail est sur le LAN → `ipCible` = IP **privée** du serveur mail ; sinon → IP **publique**. Le `dst-nat 443 → <IP_PRIVEE_MAIL>` du § 5.2 du document de conception est **faux** dans les deux cas : le 443 public est déjà tenu par le Portail.

## Phase 13 — Cloisonnement web de production + mode « derrière le Portail »

**Fichiers versionnés :** `labo/prod/php-fpm/roundcube.conf` · `labo/prod/php-fpm/postfixadmin.conf` · `labo/prod/apache/20-webmail-interne.conf` · `labo/prod/apache/21-postfixadmin-interne.conf` · `labo/prod/parametres-prod.env` · `labo/simulateur/30-portail.conf` · `labo/simulateur/parametres-labo.env` · `labo/simulateur/probe-proxy.php` · `labo/scripts/21-deploy-prod-web.sh`.

**Ce que la phase apporte (D8 fermé) :** les deux vhosts ne partagent plus le même processus PHP.

| Pool | Utilisateur Unix | Socket | `max_children` |
|---|---|---|---|
| `roundcube` | `www-data` | `/run/php/php8.1-fpm-roundcube.sock` | 40 |
| `postfixadmin` | **`pfa`** (créé pour l'occasion) | `/run/php/php8.1-fpm-postfixadmin.sock` | 6 |

Le compte Unix `pfa` **n'existait pas** (le paquet Debian de PostfixAdmin l'avait créé en `postfixadmin`, mais notre déploiement est un tarball dans `/opt/postfixadmin`, en `root:root`). → `config.local.php` en `root:pfa` 640, `templates_c` en `pfa:pfa` 750.

**Le vhost de production** : `Listen 8080` en **HTTP brut** (le TLS est terminé par le Portail), docroot `/var/www/roundcube/public_html`, `SetHandler "proxy:unix:/run/php/php8.1-fpm-roundcube.sock|fcgi://localhost"`, `Require all denied` sur `config|temp|logs`. PostfixAdmin sur `Listen 8081`, restreint à `127.0.0.1` + plage LAN de la DG + IP du Portail. Les deux fichiers sont **paramétrés par jetons** (`@@HOSTNAME_WEBMAIL@@`, `@@IP_PORTAIL@@`, `@@PLAGE_LAN_DGM@@`, `@@IP_MAIL_PRIVEE@@`, `@@IP_MAIL_PUBLIQUE@@`) : le même fichier sert au labo et à la prod, un seul réglage à basculer.

**La configuration Roundcube derrière un proxy** (relevée dans le code source de 1.7.4, c'est ce qui rend la prod possible) :

| Option | Rôle | Sans elle |
|---|---|---|
| `use_https = true` | déclare la connexion sécurisée même si `$_SERVER['HTTPS']` n'est pas posé | URLs générées en `http://…:8080` → *mixed content* et redirection HTTPS cassée |
| `proxy_whitelist = ['<IP du Portail>']` | seule l'IP du proxy est autorisée à injecter `X-Forwarded-*` | les en-têtes du proxy sont **ignorés** → hôte et port faux |
| `trusted_host_patterns = ['webmail.meteomadagascar.mg', '127.0.0.1', 'localhost']` | refuse un en-tête `Host` injecté | vol d'identifiants par en-tête `Host` |
| `smtp_helo_host = 'meteomadagascar.mg'` | HELO/hostname SMTP correct | le serveur distant voit `localhost` |

Fonctions utiles du code : `rcube_utils::https_check()` (l.886), `check_proxy_whitelist_ip()` (l.916), `resolve_url()` (l.1641 — *pas* `request_url()`, qui n'existe pas), `server_name()` (l.1011), `remote_ip()` (l.1086). **Conséquence à retenir :** sans `proxy_whitelist`, `ip_check` et `login_rate_limit` verraient **tous les agents sous l'IP du Portail** — le rate-limit de Roundcube compterait l'institution entière.

**Le simulateur de Portail** (`labo/simulateur/30-portail.conf`) rejoue en labo ce que fera le nginx du Portail : TLS (snakeoil) sur **8444**, `RequestHeader set X-Forwarded-*`, `ProxyPass / http://127.0.0.1:8080/`. C'est ce qui permet de valider la chaîne complète **sans** le Portail, sans DNS et sans IP publique.

**Résultat mesuré (23 PASS / 0 FAIL)** : webmail 8080 = 200 · postfixadmin 8081 = 302 · simulateur 8444 = 200 · `HTTPS=oui` · **URL générée = `https://webmail.meteomadagascar.mg`** (aucun port interne) · **connexion réelle à travers le proxy = 302 + cookie `secure` + `Location` relatif** (aucun repli en `http://`) · **limite d'envoi passée de 2 Mo à 50 Mo** (`upload_max_filesize=50M`, `post_max_size=52M`) — les agents de la DG envoient des images radar et des rapports. Validation globale rejouée : **34 PASS / 0 FAIL**, aucune régression.

**4 pièges rencontrés :**
1. `mod_proxy_http` n'est **pas** chargé par défaut sur Ubuntu → `ProxyPass` vers un backend `http://` échoue avec « No protocol handler was valid for the URL / (scheme 'http') ». → `a2enmod proxy_http` obligatoire.
2. `systemctl reload apache2` est un redémarrage **gracieux** : vérifier trop tôt donne de faux « connection refused ». → boucle d'attente d'ouverture des ports.
3. Un pool FPM en `ondemand` **sans requête n'a aucun worker** → `pgrep` sur le nom du pool est un faux test. → vérifier la config déployée et produire une preuve fonctionnelle.
4. La fonction d'URL absolue est `resolve_url()`, pas `request_url()`.

## Phase 14 — ClamAV sur les pièces jointes (D6 fermé)

**Fichiers versionnés :** `labo/rspamd/local.d/antivirus.conf` · `labo/scripts/22-deploy-clamav.sh` · `labo/scripts/test-clamav-eicar.py`.

Installation : **ClamAV 1.5.4** (paquets Ubuntu 22.04) — `clamav-daemon`, `clamav-freshclam` (tous deux installés **`disabled`**, comme `fail2ban` : `systemctl enable --now` obligatoire, sinon l'antivirus s'arrête au premier redémarrage et la barrière ③ est **coupée en silence**). Signatures téléchargées par `freshclam` : `main.cvd` (89 Mo) + `daily.cvd` (23 Mo) + `bytecode.cvd`.

**Test de référence (4 cas, `test-clamav-eicar.py`) — résultat mesuré le 21 octobre 2026 :**

| # | Cas | Attendu | Obtenu |
|---|---|---|---|
| 1 | message sain, sans pièce jointe | accepté | **accepté** ✓ |
| 2 | pièce jointe **binaire** EICAR (`octet-stream`) | refusé | **554 5.7.1** « virus detecte (Eicar-Test-Signature) » ✓ |
| 3 | pièce jointe **texte** EICAR (`text/plain`) | refusé | **554 5.7.1** ✓ |
| 4 | EICAR dans le **corps**, sans pièce jointe | accepté | **accepté** ✓ |

Le cas 4 est celui qui **valide la décision de conception n° 4** : le corps du message n'est jamais scanné, donc la délivrabilité n'est pas dégradée. Le cas 3 est une bonne surprise : contrairement à ce que la documentation du module laisse croire, une pièce jointe **de type texte est bien analysée** — la limitation que j'avais d'abord documentée n'existe pas en réalité.

### Trois pièges de configuration (tous invisibles à la lecture)

1. **Le `local.d` est inclus À L'INTÉRIEUR du bloc `antivirus { }`.** `modules.d/antivirus.conf` contient `.include(try=true,priority=1,duplicate=merge) "$LOCAL_CONFDIR/local.d/antivirus.conf"` **à l'intérieur** de ce bloc. Le `local.d` doit donc contenir **uniquement** `clamav { … }`, **sans** l'enveloppe `antivirus { }`. Redeclarer l'enveloppe produit un bloc **imbriqué** :
   - `antivirus { antivirus { clamav { … } } }`
   - Rspamd signale « *nested section … it is likely a configuration error* » et « *unknown antivirus type: antivirus* » ;
   - et **le module ne scanne rien, silencieusement** : les pièces jointes infectées passent.
   Le script de déploiement **refuse** de continuer si `nested section` ou `unknown antivirus type` apparaît dans `rspamadm configdump`.
2. **`TCPSocketAddr` n'existe pas en ClamAV 1.5.4.** L'option d'écoute s'appelle **`TCPAddr`** (`TCPSocketAddr` était valide dans les 0.10x). L'erreur est fatale : `ERROR: Parse error at /etc/clamav/clamd.conf:100: Unknown option TCPSocketAddr` → `clamd` ne démarre pas du tout (`failed` + « Start request repeated too quickly »). Le script supprime toute ligne `TCPSocketAddr` résiduelle avant d'ajouter `TCPAddr 127.0.0.1` (écoute **strictement locale**, le port 3310 n'est pas exposé).
3. **Rspamd 2.7 ne parle qu'en TCP** au scanner : `lua_scanners/clamav.lua` utilise `tcp.request()` (`host` + `port`) — **pas de socket Unix**. Le socket local de clamd (`/var/run/clamav/clamd.ctl`) ne peut donc pas être utilisé malgré ce que suggère la documentation du module.

### Deux pièges de vérification (le test mentait, pas le système)

4. `rspamadm configtest` et `rspamadm configdump` doivent être lancés **avec les privilèges root** : en simple utilisateur ils échouent sur la lecture des fichiers `local.d` (« Permission denied ») et donnent un **faux négatif** « module absent ».
5. **`grep -q` + `set -o pipefail` = faux négatif.** `echo "${DUMP}" | grep -q motif` : dès que `grep` trouve une correspondance il quitte, `echo` reçoit un **SIGPIPE**, et le pipeline renvoie **141** → le script conclut « absent » alors que la correspondance est là. Le `configdump` dépasse largement le tampon de 64 Ko, le piège est donc **systématique**, pas aléatoire. → tous les contrôles se font désormais sur un **fichier temporaire**, jamais sur un pipe.
6. La commande de statistiques est **`rspamc stat`** (client). `rspamadm stat` **n'existe pas** et renvoyait une erreur silencieuse.

> **Piège Freshclam** : le service tourne en arrière-plan et **verrouille son journal** → il faut `systemctl stop clamav-freshclam` avant de le lancer en avant-plan. Et un `curl` manuel sur `database.clamav.net` renvoie 403/429 sans User-Agent, et **écrase `main.cvd` avec 17 octets** (« error code: 1015 ») → supprimer et laisser `freshclam` faire son travail (206 avec `-L` et `User-Agent: ClamAV/1.5.4`).

## Phase 15 — Migration Rspamd 2.7 → 4.2.2 (dépôt officiel) — D9 fermée

**Pourquoi.** Les paquets Ubuntu 22.04 fournissent Rspamd **2.7** (2019), que le projet Rspamd ne supporte pas. La production doit utiliser le dépôt officiel : sans cela, on valide en laboratoire une pile que la production n'exécutera pas. C'était **le dernier écart de version de la pile** (D9).

**Contrainte de poste.** L'hôte Windows n'a que **9,5 Go libres** sur C: → une seconde VM Ubuntu 24.04 de répétition est **infeasible** (OS + pile mail + 1,2 Go de signatures ClamAV dépassent la place disponible). La voie retenue : **installer Rspamd depuis le dépôt officiel dans la VM 22.04 existante** (snapshot VirtualBox `03-avant-rspamd3` pris avant l'opération).

### Le dépôt officiel a changé d'adresse — et le site renvoie du HTML sur tout

| Ce qu'on cherchait | Réponse réelle |
|---|---|
| `https://rspamd.com/rspamd.repo` (ancienne procédure) | **n'existe plus** → renvoie la page d'accueil du site |
| `https://rspamd.com/apt-stable/gpg.key` | ✅ **vraie clé** (4 036 o, `-----BEGIN PGP PUBLIC KEY BLOCK-----`) |
| `https://rspamd.com/apt-stable/dists/jammy/Release` | ✅ **vrai fichier** (commence par `Origin: Rspamd`) |
| `https://docs.rspamd.com/downloads/` | ✅ **la documentation officielle** (le site rspamd.com est une application monopage) |

> **Piège de vérification** : `rspamd.com` renvoie sa page HTML (**54 364 o, HTTP 200**) pour **toute** URL, y compris des chemins inexistants. Un simple « code 200 » ne prouve donc rien — il faut vérifier le **type de contenu** et les **premiers octets** (un vrai `Release` commence par `Origin:`, une vraie clé par `-----BEGIN`).

Procédure réelle (versionnée dans `labo/scripts/23-install-rspamd-officiel.sh`) :
```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://rspamd.com/apt-stable/gpg.key | gpg --dearmor > /etc/apt/keyrings/rspamd.gpg
echo "deb [signed-by=/etc/apt/keyrings/rspamd.gpg] https://rspamd.com/apt-stable/ jammy main" \
     > /etc/apt/sources.list.d/rspamd.list
```
Versions publiées : **jammy 3.3 minimum** (version courante **4.2.2**), noble 3.9 minimum, resolute 4.2.2 ; bullseye et focal ne sont plus servis. Les paquets officiels sont compilés avec **Hyperscan (amd64) + LuaJIT embarqué + Jemalloc**.

### Trois pièges d'installation (tous contournés, tous documentés dans le script)

1. **Conffile supprimé + stdin fermé = blocage.** `DEBIAN_FRONTEND=noninteractive` ne supprime **pas** l'invite de conffile ; lancé sans terminal, dpkg lit EOF et échoue (`dpkg: erreur de traitement du paquet rspamd (--configure)`). → `dpkg --configure -a --force-confnew`.
2. **Désinstallation incomplète = configuration invalide.** Après installation, `/etc/rspamd/` ne contenait que les conffiles : il manquait `settings.conf`, `logging.inc` et **22 fichiers de `modules.d/`** (dont `dkim_signing.conf` et `milter_headers.conf`) → `rspamadm configdump` échouait (`ucl parser error: cannot open file /etc/rspamd/settings.conf`) alors que `dpkg --audit` était vide et que `dpkg -L` annonçait 116 fichiers. Le `.deb` était complet (vérifié par `dpkg-deb -c`) : c'était l'**état dpkg**, pas le paquet. `apt-get install --reinstall` ne corrige **rien** (dpkg juge les fichiers déjà installés) → il faut **`dpkg --purge` puis réinstaller**. *Contrôle ajouté au script : comparer `dpkg -L` avec l'existence réelle des fichiers.*
3. **La purge emporte `/var/lib/rspamd/dkim`.** Ce répertoire n'appartient pas au paquet mais il a été supprimé : **la clé privée DKIM a disparu**, donc tous les envois signés sont devenus impossibles. Elle a été **restaurée depuis la sauvegarde Restic** (`restic restore latest --target / --include /var/lib/rspamd/dkim`, droits `_rspamd:_rspamd` 640 réappliqués) → **la sauvegarde a fait ses preuves une fois de plus**. La restauration ciblée par `--include` évite d'écraser la configuration 4.x, que le snapshot contient aussi dans sa version 2.7.

### Ce qui a changé dans la configuration entre 2.7 et 4.x (cartographié dans le code)

- En 3.x/4.x, les modules sont **réécrits en Lua** (`/usr/share/rspamd/plugins/*.lua`) ; `/usr/lib/rspamd/modules/` n'existe plus.
- **La règle de `local.d` est inchangée et uniforme** : un fichier de `local.d` ne doit contenir **que le corps du module**, jamais l'enveloppe `module { }` (l'inclusion se fait à l'intérieur du bloc du module). Vérifié pour `antivirus`, `dkim_signing`, `milter_headers`, `actions`. → **les 4 fichiers `local.d` du labo sont valides tels quels en 4.x** (comparaison par `diff` : identiques).
- `dkim_signing` : le modèle de chemin par défaut reste `"$domain.$selector.key"` → la clé `meteo-test.lan.dkim.key` reste correcte, et mes réglages 2.7 sont **identiques aux défauts 4.x** (`selector="dkim"`, `sign_authenticated=true`, `sign_local=true`, `allow_envfrom_empty=true`).
- `milter_headers` : `skip_authenticated` n'agit plus que sur l'**ajout** d'en-têtes, plus sur le traitement global → en 4.x la signature DKIM des messages authentifiés fonctionnerait même avec `skip_authenticated=true`. On conserve `false` (sémantique 2.7 + en-têtes `Authentication-Results` utiles aux agents).
- `antivirus` : **`attachments_only` est déprécié** (remplacé par `scan_mime_parts`, avec avertissement) ; le scanner ClamAV reste **TCP uniquement**.

### Scripts mis à jour
- `labo/scripts/08-deploy-rspamd.sh` : ajout du déploiement de **`dkim_signing.conf`** (absent du déploiement précédent), `install -o root -g _rspamd -m 640` au lieu de `cp`+`chown`+`chmod`, **génération de la clé DKIM** si absente (avec le nommage exact `$domain.$selector.key`), et **contrôles de structure 4.x** sur **fichier temporaire** (jamais sur un pipe) : refus de continuer si `nested section` ou `unknown antivirus type` apparaît, présence effective de `clamav` et `dkim_signing` dans la configuration effective.
- `labo/scripts/23-install-rspamd-officiel.sh` (nouveau) : clé GPG (avec contrôle du type de contenu) + liste de sources + purge/install propre + contrôle d'intégrité `dpkg -L` vs fichiers réels + restauration de la clé DKIM (copie locale ou sauvegarde Restic) + redéploiement de `local.d` + validation.

### Résultats mesurés après migration
| Contrôle | Résultat |
|---|---|
| `rspamd --version` | **4.2.2** (Hyperscan ✓, LuaJIT ✓, Jemalloc ✓) |
| `rspamadm configtest` | syntax OK |
| `12-validation-finale.sh` | **34 PASS / 0 FAIL** — aucune régression |
| ClamAV (`test-clamav-eicar.py`) | **4/4** : sain accepté · EICAR binaire refusé 554 · EICAR texte refusé 554 · EICAR dans le **corps** accepté (le corps n'est jamais scanné) |
| DKIM | `DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=meteo-test.lan;` présent sur les envois via 587 |
| Open relay (`17-test-open-relay.sh`) | **4/4** : relais externe refusé, relais authentifié accepté, contournement par IP brute refusé |

> **Conséquence sur les seuils** : la **ligne de base du score a changé** entre 2.7 et 4.x (0.95 en 2.7 → −0.10 / 0.40 en 4.x pour un message sain). Le seuil de rejet reste à **15** et le test GTUBE est toujours rejeté → pas d'action requise, mais c'est un repère à connaître avant de comparer des scores entre les deux versions (→ D23).

## Phase 16 — Import à l'échelle, quotas par profil, politique de mots de passe

**Scripts :** `24-import-comptes-masse.sh` (import) · `generer-noms-test.py` (échantillon) · `test-password-policy.php` (politique) · `dovecot-sql.conf.labo` (quota piloté par les données) · `postfixadmin-config.local.php` (politique durcie).

### 16.1 Le quota est désormais piloté par les données, plus par une constante

La conception prévoit 2 Go (agent), 3 Go (station), 5 Go (cadre). Le labo avait `quota_rule = *:storage=2G` en dur dans `dovecot.conf` : la colonne `quota` de PostfixAdmin n'était lue par personne.

**Mécanisme mesuré dans le code de Dovecot 2.3** (`src/plugins/quota/quota.c`, branche `release-2.3`) : `quota = maildir:User quota` définit une **racine** nommée « User quota » ; la limite par utilisateur se lit dans le champ userdb **`quota_rule`** (`quota_root_add_rules()` → `mail_user_plugin_getenv(user, "<racine>_rule")`), au format `<masque>:<ressource>=<montant>`.

| Piège | Symptôme | Correctif |
|---|---|---|
| Champ userdb `quota` | `Unknown quota backend: storage=5120.0000M` | le backend et la limite ne se melangeent pas : utiliser `quota_rule` |
| Champ nommé d'après la racine | limite ignorée | `quota_root_parse_set()` n'accepte que `dict:` pour un surcharge ; c'est `quota_rule` qui porte la limite |
| Unité de la colonne PostfixAdmin | 2 Go = 2 097 152 000 (et non 2 147 483 648) | la CLI stocke des **Mo × 1 024 000 octets** |
| `ROUND` manquant | Dovecot refuse `5120.0000M` | `ROUND(quota/1024000)` obligatoire |

Requête user_query retenue :

```sql
SELECT CONCAT('/var/vmail/', maildir) AS home,
       CASE WHEN quota IS NULL OR quota <= 0 THEN '*:storage=2048M'
            ELSE CONCAT('*:storage=', ROUND(quota/1024000), 'M') END AS quota_rule
FROM mailbox WHERE username = '%u' AND active = 1 AND domain = '%d'
```

**Vérification sur l'import réel** (400 comptes) : répartition en base 315 × 2 Go · 50 × 3 Go · 40 × 5 Go, et `doveadm quota get` confirme les limites appliquées : **5 242 880 Ko** (5 Go) · **3 145 728 Ko** (3 Go) · **2 097 152 Ko** (2 Go).

### 16.2 Import de 400 comptes — 3 blocages d'échelle trouvés et contournés

| Blocage | Symptôme réel | Correctif |
|---|---|---|
| `domain.aliases = 1` | « You have reached your limit to create aliases! » | le script relève les limites du domaine avant l'import |
| `domain.mailboxes = 10` | l'import s'arrêterait à la 10e boîte | idem (relevé automatique) |
| `postfixadmin mailbox list` **n'existe pas** | aucune collision détectée, comptage faux | une seule requête SQL charge les parties locales de `mailbox` **et** `alias` |
| table `mailbox` sans colonne `update_password` | le script s'arrêtait au premier compte (`set -euo pipefail`) | commande de mise à jour supprimée |

**Résultat mesuré** : **405 boîtes** (400 importées + 5 de test), **0 doublon** de partie locale, **0 erreur**, 59 collisions d'homonyme résolues par suffixe numérique (`basile.rakoto` → `basile.rakoto2`). Sorties : `adresses-generees.csv` (liste de relecture humaine) et `remise-mots-de-passe.csv` (mode 600, **hors dépôt git**).

### 16.3 Politique de mots de passe durcie — 12/12

**Sémantique réelle de `validate_password()`** (PostfixAdmin 3.3) : chaque entrée de `$CONF['password_validation']` est soit une **regex** (le mot de passe doit la **correspondre**), soit un **callable** (une valeur de retour non vide = échec). Défaut d'origine : 5 caractères minimum, 3 lettres, 2 chiffres — bien en dessous de la conception.

Règle appliquée : 12 caractères minimum · 3 lettres · 2 chiffres · **dictionnaire** (mots de passe courants **et** institutionnels : `meteo`, `meteomadagascar`, `antananarivo`, `bulletin`, `observation`…) · refus des caractère répétés. **Pas d'exigence de caractère spécial** : la conception écrit elle-même que « la longueur compte plus que la complexité » et que `Meteo2024!` est devinable.

**Deux pièges de l'outillage PostfixAdmin :**

1. Le retour d'un **callable n'est pas traduit** (`$result[] = $ret;` sans `Config::lang()`) → le callable doit renvoyer le **texte final**, pas une clé de langue.
2. `language_hook` est le **nom d'une fonction** qui doit **renvoyer** le tableau `$PALANG` (`common.php` l.100-103) ; les clés personnalisées doivent porter le préfixe `x_`.

Test unitaire `test-password-policy.php` (12 cas, appelle la **vraie** `validate_password()`, détecte aussi les clés de langue non traduites) : **12/12 conformes, 0 clé brute**.

### 16.4 Abandon mesuré du « changement de mot de passe à la première connexion »

La conception (design §8.5) promettait un changement imposé à la 1re connexion. **Mesure** : Roundcube 1.7.4 ne gère pas la réponse IMAP `pass_expired` (recherche « expired » vide dans `rcube_imap.php` et dans les étapes `mail/` et `settings/`). Un agent en webmail — le canal principal, servi par le Portail — verrait donc un **échec de connexion** au lieu de la demande de changement : risque de **verrouiller 300 agents**.

**Décision** : pas d'expiration IMAP. Le contrôle équivalent est un **mot de passe provisoire aléatoire et unique par compte** (20 caractères), remis **individuellement** — un mot de passe partagé par 500 comptes serait devinable par le premier agent qui le teste. Corrigé dans le design doc (§8.5) et §8.7.

### 16.5 Le test de validation lui-même a été corrigé

`12-validation-finale.sh` exigeait « 5 comptes actifs dans la base » ; l'import à l'échelle en a ajouté 400 → **33 PASS / 1 FAIL**, un échec d'artefact. Le critère est devenu un **minimum** paramétrable (`NB_COMPTES_MIN`, défaut 5) → **34 PASS / 0 FAIL**.

## Phase 17 — Refonte du skin selon le design du site réel + test de continuité

### 17.1 La référence visuelle change : le site institutionnel, pas un système de design générique

Consigne : « utilise comme le design de site web meteomadagascar.mg ; integre ce design ». Les couleurs et les règles ont été **extraites du site réel** (WordPress, thème `meteo`, lecture seule des feuilles de style) et non choisies au goût :

| Rôle | Valeur relevée sur le site |
|---|---|
| Police | **Open Sans**, corps 14 px / interligne 1.7 (embarquée **localement**, aucun CDN) |
| Fond / texte | `#FBFBFB` / `#5A5A5A` |
| Titres | `#333333`, gras 700 |
| **Action** | **`#F4C910`** (jaune), texte `#333`, **uppercase**, gras 600, `padding 7px 16px`, **rayon 8 px** |
| **Accent** | **`#17938A`** (teal) : états actifs, icônes, liens, filet de dossier actif |
| Bandeau / pied | `#34495E` (la couleur du pied de page du site) |
| Champs | hauteur 38 px, `padding 8px 12px`, bordure `1px solid #CCC`, rayon 6 px |
| Cartes | rayons 8 à 10 px, bordure `#EFEFEF` |
| Points de rupture | 576 / 768 / 992 / 1200 px (présets WordPress) + 320 / 635 px (thème) |

Conséquence assumée : le **bleu du Portail `#1E3C72` est abandonné** — la référence est désormais le site institutionnel, le jaune et le teal en tiennent lieu.

### 17.2 Deux défauts de rendu trouvés à la capture, pas à la relecture

1. **Le logo débordait du rail.** Le rail fait 78 px de large ; le logo officiel fait 187 × 77 px. Le skin le dimensionnait à 120 px → débordement masqué par la colonne utilisateur. **Correctif sans traitement d'image** : `object-fit: none` + `object-position: left center` dans un cadre de 46 px → le navigateur dessine le PNG à sa taille naturelle et n'en retient que l'**emblème** (soleil + nuage). Le fichier officiel reste intact.
2. **La page de connexion perdait une ligne de texte.** `elastic` applique `.task-login #logo { position: relative; top: 16vh }` : le logo sortait du bandeau navy et les deux lignes de texte passaient en **blanc sur blanc**. Correctif : `top: auto` sur `.meteo-login #logo`.

### 17.3 Continuité sans MariaDB — la promesse architecturale, mesurée

`25-test-continuite-sans-mariadb.sh` arrête MariaDB, envoie un message en réception, observe, puis relance la base. **Résultat : `CONTINUITE_OK`.**

| Ce qui a été mesuré | Résultat |
|---|---|
| Arrêt de MariaDB | postfix, dovecot et rspamd restent `active` |
| Envoi en réception (port 25) | accepté : `250 2.0.0 Ok: queued as 8C18A195A` |
| **Livraison dans le Maildir** | **effective, base toujours arrêtée** : `status=sent (delivered to maildir)`, 1,3 s |
| Authentification (passdb SQL) | **`code=temp_fail`** — erreur **temporaire**, pas un refus |
| Après relance de la base | authentification de nouveau opérationnelle, message livré |

**Pourquoi la livraison survit à la panne de base** : `mail_location = maildir:/var/vmail/%d/%n` — le chemin de la boîte est dérivé de l'**adresse** (domaine + partie locale), et non d'une lecture en base. La livraison n'interroge donc pas SQL. C'est la propriété qui rend la promesse n°1 réellement tenue.

**Point de vigilance assumé** : le quota vient de l'annuaire (champ `quota_rule`), il n'est **pas appliqué** pendant la panne. Sans conséquence sur la perte de données, mais à garder en tête.

### 17.4 Trois pièges de vérification rencontrés dans ce seul test

| Piège | Symptôme trompeur | Correctif |
|---|---|---|
| Les réponses de `swaks` sont préfixées par `<-  ` | la regex `^\s+250 ` ne matche **jamais** → le script concluait « SMTP n'a pas accepté » alors que le message était accepté | chercher `250 2.0.0 Ok` |
| `doveadm auth test` renvoie **toujours 0** | le test d'échec paraissait réussi | lire la **sortie** (`auth succeeded` / `auth failed` / `code=temp_fail`) |
| `grep -q` + `set -o pipefail` | `grep` quitte à la première correspondance, l'écriture en amont est coupée par **SIGPIPE** → code 141 → le test **inverse** son résultat | capturer la sortie dans une variable, puis tester avec `case` (aucun pipeline) |

> Le troisième est **le même piège** que celui rencontré sur `rspamadm configdump` en phase 14. Il est désormais une règle du projet : **ne jamais décider sur la seule foi d'un pipeline `grep -q`**.

## Phase 18 — Le webmail en une seule page (poste de travail)

**Pourquoi.** Le premier écran (la page « mail » de Roundcube, en trois colonnes) a été jugé
« vraiment moche et difficile à utiliser pour le staff ». La cible n'est plus une boîte aux
lettres relookée, mais **un poste de travail** : tout ce dont l'agent a besoin est à l'écran,
et la lecture comme la rédaction se font **par-dessus** la liste, sans jamais quitter la page.

**Décisions arrêtées** (grille de questions posée à l'utilisateur, 10 points) : 4 actions toujours
visibles (Écrire un message, Boîte de réception, Envoyés, Recherche) · un **panneau latéral unique**
(les 5 boîtes avec compteur, puis les 4 actions non-dossier : Contacts, Modèles de rédaction,
Paramètres, Déconnexion) · **lecture et rédaction superposées** · identité visuelle du site
institutionnel + un bloc « Autres services » (liens vers les services météo) en bas de page ·
version téléphone allégée (grille 2×2, liste sans panneau de prévisualisation, rédaction plein
écran, panneau latéral réduit à un bouton « ☰ »).

**Toujours zéro PHP.** Un skin de surcouche peut faire tout cela : le moteur de Roundcube sait
déjà produire la vue d'un message et le formulaire de rédaction en mode « cadre » (le paramètre
natif `_framed=1`), il suffit à les afficher dans des cadres superposés.

### 18.1 La page en une seule page

`#layout` passe de `display:flex` (trois colonnes) à **`display:grid`** : `280px minmax(0,1fr)`
en colonnes, `56px auto minmax(0,1fr)` en lignes, avec des zones nommées
(`band` / `actions` / `side` / `list`). Le rail vertical d'`elastic` disparaît (`display:none`),
les 5 boîtes réelles et leurs compteurs viennent du moteur (`mailboxlist`), le titre de la liste
est rempli à partir du dossier sélectionné, et le champ de recherche est **déplacé** par le script
selon la largeur (bandeau sur grand écran, 4e case de la grille 2×2 sur téléphone).

### 18.2 Lecture : le clic ne doit pas quitter la page

**Découverte mesurée** : dans Roundcube 1.7, cliquer un message **remplace la page entière**
(`action-show`, le cadre de lecture disparaît du DOM) — il n'existe pas de panneau de
prévisualisation à superposer. En revanche **l'identifiant du message est dans l'adresse du
lien** (`&_uid=19`). Le script intercepte donc le clic **en phase de capture**, empêche la
navigation, et affiche `…&_action=show&_framed=1` dans un cadre superposé. La barre de ce cadre
porte le sujet et les actions **Répondre / Répondre à tous / Transférer / Imprimer / Fermer**,
construites à partir de l'identifiant.

### 18.3 Rédaction : l'obstacle des `X-Frame-Options`

**Piège majeur, invisible à la lecture.** La page de composition refuse d'être affichée dans un
cadre : Roundcube envoie `X-Frame-Options: deny` en dehors du mode cadre, pour des raisons de
sécurité liées aux navigateurs ([#6688]). Et l'action « répondre » **n'existe pas côté serveur** :
c'est le script client qui construit la demande à partir du message sélectionné.

La séquence qui fonctionne, en trois temps :
1. le script demande l'URL `?_task=mail&_action=compose&_mbox=…&_reply_uid=…&_framed=1` ;
2. le serveur **crée un brouillon** et redirige vers `…&_action=compose&_id=<brouillon>` — la
   redirection perd le drapeau `_framed`, et la page non cadre est refusée par le navigateur ;
3. le script récupère cet identifiant dans l'adresse finale de sa requête, puis **recharge la
   page du brouillon en mode cadre** (`&_id=…&_framed=1`) : plus de redirection, donc
   `X-Frame-Options: sameorigin`, et le formulaire s'affiche.

Les paramètres `_reply_uid`, `_forward_uid` et `_all` ont été relevés **dans le code source**
(`program/actions/mail/compose.php`) : ce sont eux qui distinguent une réponse d'un transfert et
le « répondre à tous ».

### 18.4 Ce qui a été mesuré

| Contrôle | Résultat |
|---|---|
| Mise en page | grille 280 px + 1160 px, bandeau 56 px, tuiles 59 px, **aucun débordement** du panneau latéral |
| Lecture superposée | cadre ouvert, sujet affiché, **adresse de la page inchangée**, 0 erreur JavaScript |
| Réponse | formulaire pré-rempli (destinataire, objet `Re: …`) dans le cadre de rédaction |
| **Envoi réel** | message **reçu** par le destinataire (contrôlé en IMAP : `From`, `To`, `Subject`, `Date`) |
| Téléphone (375 × 812) | 1 colonne, grille d'actions **2 × 2**, panneau latéral en tiroir, recherche déplacée |
| Validation globale | **34 PASS / 0 FAIL** |

### 18.5 Deux erreurs de syntaxe corrigées

Le premier jet du gabarit réutilisait la classe `header-title` d'`elastic` pour le titre de la
liste : cette classe est masquée (`display:none`) dans l'en-tête de la liste, le texte était
donc bien écrit mais **invisible**. Le titre a son propre élément désormais. Et le panneau
latéral débordait en bas (bloc « Autres services » coupé) : le conteneur a été rendu défilable.

## Résultat final — script `labo/scripts/12-validation-finale.sh`

**34 PASS / 0 FAIL** — rejoué le 2026-10-21 après la phase 14 (ClamAV) et la phase 15 (Rspamd 4.2.2) : aucune régression, **8 services** `active` (postfix, dovecot, rspamd, apache2, mariadb, fail2ban, redis-server, clamav-daemon). Rejoué une dernière fois le **2026-10-22** après les phases 16 et 17 (import de 400 comptes + refonte du skin) : toujours **34 PASS / 0 FAIL**, le critère « nombre de comptes » étant désormais un minimum.

| Bloc | Critères |
|---|---|
| 1. Services | 8 services `active` |
| 2. Ports | 25, 143, 993, 4190, 587, 11332, 443, 80 |
| 3. Postfix | `postfix check` OK · pont fichier plat (pas de SQL) · VRFY désactivé · Rspamd joignable |
| 4. Dovecot | `doveconf` valide · auth SQL+Argon2id |
| 5. Comptes | 5 comptes actifs · export vers fichier plat |
| 6. Cloisonnement | roundcube 18 tables · roundcube **0 droit** sur postfix · dovecot **0 droit** sur roundcube |
| 7. Sécurité | POP3 **non exposé** · SMTPS **non exposé** · TLS 1.2 mini · 5 prisons |
| 8. Web | webmail 200 · postfixadmin 302 |
| 9. Bout-en-bout | SMTP 587 → Maildir → IMAP, message livré **et relu** |

## Hygiène des secrets (appliquée avant commit)

- Aucun secret en clair dans le dépôt. Mots de passe dans `/root/labo-credentials.txt` (mode 600),
  injectés à l'exécution par `03-reset-dovecot-pw.sh` et `09-deploy-web.sh`.
- Placeholders : `__MVPP_POSTFIXADMIN__`, `__RC_DB_PW__`, `__RC_DES_KEY__`, `__MVPD_DOVECOT__`.
- `.gitignore` bloque `*.secret`, `*.key`, `*.pem`, `config.inc.php`, `*credentials*`.
- **3 pièges de vérificationauto-inventés** (le test mentait, pas le système) :
  `doveconf -n` omet les valeurs par défaut (TLSv1.2 **est** le défaut) → utiliser `doveconf -h` ;
  `doveconf <clé>` renvoie la ligne entière, pas la valeur ; `postfixadmin-cli mailbox list`
  n'existe pas (compter en SQL) ; `grep -c` compte des lignes, la liste des prisons
  fail2ban tient sur une seule ligne.

## Chaîne de sécurité réellement active en labo

| Barrière | État labo | État prod |
|---|---|---|
| ① MikroTik (pare-feu + port 25 bridé) | **absent** (VM en NAT, pas de routeur) | à faire, phases B/A3 |
| ② Durcissement noyau + TLS | TLS 1.2 mini, SSL `required` sur Dovecot | durcissement complet |
| ③ Rspamd | ✅ actif, GTUBE rejeté, **ClamAV sur pièces jointes (4/4)** | idem (Rspamd 3.x) |
| ④ Dovecot (quota + anti-bruteforce) | ✅ quota 2 Go / grâce 5 j | idem |
| ⑤ Roundcube (limitation tentatives) | ✅ login_rate_limit 5/min + ip_check | idem |

## Divergences labo / prod (carnet — à reporter tel quel en prod)

| # | Labo | Prod |
|---|------|------|
| D1 | Certificat auto-signé (snakeoil) | Let's Encrypt (`mail.`, `webmail.`, `postfixadmin.`) |
| D2 | Pas de DNS réel, pas de PTR | SPF fusionné + MX + DMARC + PTR YAS |
| D3 | **5 comptes fictifs** | 300–400 comptes réels (même procédure d'import) |
| D4 | Pas de tests Gmail/Outlook | 5 critères d'ouverture (dont mail-tester ≥ 9/10) |
| D5 | NAT isolé, 2222→22 | IP publique 41.207.49.27, ports MikroTik |
| D6 | ~~ClamAV écarté~~ → **ClamAV 1.5.4 en place, 4/4 au test EICAR** | **identique** — la barrière ③ est désormais réelle des deux côtés |
| D7 | `emailcheck_resolve_domain = false` (`.lan` ne résout pas) | **doit rester `true`** |
| D8 | ~~1 seul pool PHP-FPM~~ → **2 pools distincts** (`roundcube` sous `www-data`, `postfixadmin` sous `pfa`) | **identique** — plus d'écart, la clôture a été faite en labo (phase 13) |
| D9 | ~~Rspamd 2.7 (paquets Ubuntu)~~ → **Rspamd 4.2.2 (dépôt officiel rspamd.com)** | **identique** — plus aucun écart de version sur la pile (phase 15) |
| D10 | Pas de Fail2ban sur IP de la machine (`ignoreself`) | test par vraies IP distantes possible |
| D11 | Dépôt **déporté simulé** sur le même disque (`/srv/sauvegarde-deportee`) | disque **physiquement séparé** du RAID mail, copie hebdo **sortie du bâtiment** |
| D12 | `/var/lib/rspamd/dkim` absent (aucune signature émise) | présent dès le 1er envoi signé — **ne jamais l'exclure** |
| D13 | Volume sauvegardé ≈ 866 Kio | 500 boîtes ≈ 1 To (RAID 1 : 2 To utiles) |
| D14 | Signature DKIM **produite** mais **jamais vérifiée** (domaine `.lan`, pas d'enregistrement DNS) | `dkim._domainkey` en TXT à publier, puis `dkim=pass` côté destinataire |
| D15 | Skin `meteo` servi **en direct** sur le vhost local (Apache termine le TLS) | **`webmail.`** derrière le nginx du Portail, TLS terminé par le Portail, Apache en **HTTP interne** (8080) |
| D16 | Un seul enregistrement de peau en base (`$config['skin']`) | **purger la préférence `skin`** stockée par agent à l'import des 300-400 comptes, sinon un agent peut rester sur l'ancienne peau |
| D17 | Logo d'`elastic` **redirigé** par lien symbolique vers le logo Météo | même contournement à rejouer à chaque déploiement (bug de résolution d'`elastic` sur le template hérité `menu.html`) |
| D18 | Aucun modèle de réponse préchargé | **réponses enregistrées préchargées** (bulletin, fiche d'observation) — mécanisme natif Roundcube, zéro développement |
| D19 | Certificat **snakeoil** sur le simulateur de Portail (8444) | TLS Let's Encrypt terminé par le **Portail** (`POST /api/subdomains/:id/ssl`) |
| D20 | `ipCible` du Portail simulé en `127.0.0.1` | à trancher à l'ouverture du SSH : IP **privée** (Portail sur le LAN) ou **publique** (Portail hors LAN) — un seul jeton à basculer dans `parametres-prod.env` |
| D21 | `clamav-freshclam` **forcé au premier lancement** (signatures téléchargées à la main) | téléchargement automatique au démarrage + surveillance de l'expiration des signatures |
| D22 | `scan_text_mime = false` mais les **pièces jointes texte sont quand même analysées** (mesuré en 2.7) | **re-mesuré en 4.2.2 : comportement identique** (EICAR en PJ texte refusé 554). Reste à revérifier à chaque montée de version de Rspamd |
| D23 | **Ligne de base du score Rspamd différente** : 0.95 en 2.7 → −0.10 / 0.40 en 4.2.2 pour un message sain (seuil de rejet inchangé à 15) | idem — ne **jamais** comparer un score de labo à un score de prod d'une autre version |
| D24 | La **purge dpkg** emporte `/var/lib/rspamd/dkim` (la clé DKIM n'appartient pas au paquet) | Conséquence réelle d'un changement de version de Rspamd : **restaurer la clé depuis la sauvegarde avant de purger**, ou la réappliquer après (le script `23-install-rspamd-officiel.sh` le fait) |
| D25 | Quota **piloté par les données** : PostfixAdmin porte la valeur, Dovecot la lit via le champ userdb `quota_rule` (2 Go / 3 Go / 5 Go par profil) | **identique** — la requête SQL du userdb est la même en prod ; ne pas revenir à un `quota_rule` en dur |
| D26 | `domain.aliases` / `domain.mailboxes` **relevés automatiquement** avant l'import (valeurs par défaut du paquet : 1 et 10) | idem — un import de 300-400 comptes **échoue** sans ce relevé préalable |
| D27 | Politique de mots de passe durcie (12 caractères + dictionnaire institutionnel) ; **changement à la 1re connexion abandonné** (Roundcube 1.7.4 ne gère pas `pass_expired`) | **identique** — mot de passe provisoire **aléatoire et unique** par compte, remis individuellement |
| D28 | Le quota **n'est pas appliqué** pendant une panne de MariaDB (il vient de l'annuaire) ; en revanche la **livraison** se poursuit (chemin de boîte dérivé de l'adresse) | idem — point de vigilance, sans conséquence sur la perte de données |
| D29 | Identité visuelle du skin = **design du site `meteomadagascar.mg`** (jaune `#F4C910` en action, teal `#17938A` en accent, Open Sans embarquée localement) | **identique** — le logo est recadré par CSS (`object-fit: none`), le fichier officiel 187 × 77 reste intact |
| D30 | La lecture et la rédaction sont affichées **par-dessus** la liste, dans des cadres superposés | **identique** — mais la vue en cadre est **obligatoire** : Roundcube envoie `X-Frame-Options: deny` hors du mode `_framed=1`. Le skin demande donc la création du brouillon puis recharge sa page en mode cadre. À reprendre tel quel en prod |

## Ce qui reste à demander à l'encadrant — checklist interne

> **Note d'usage.** Ce bloc est un **outil de travail interne**, pas un document à remettre. La décision prise est : l'utilisateur **explique oralement** à l'encadrant à la fin du projet, et l'encadrant fait les demandes manuellement. Aucun document n'est produit ici.

### A. Ce qui bloque la messagerie (à demander en premier)

| # | Demande | À qui | Pourquoi c'est critique |
|---|---|---|---|
| A1 | **PTR (enregistrement inverse)** de `41.207.49.27` → un nom de la DG | **YAS** (hébergeur) | **Chemin critique.** Sans PTR, le courrier **reçu** de Gmail/Outlook arrive en spam ou n'arrive pas. Le déploiement technique peut réussir et la messagerie rester inutilisable. Délai possible : plusieurs semaines. |
| A2 | **Accès SSH** au serveur mail (compte dédié + clé publique, `sudo` limité) | Encadrant / service informatique | conditionne toute la phase B (installation, mise à jour, durcissement) |
| A3 | **Matériel** : 32 Go RAM + 2 × 2 To SSD en **RAID 1** | Service informatique | 500 boîtes × 2 Go = 1 To sur 2 To utiles. En dessous de 16 Go : arrêt net (verdict go/no-go). |

### B. Ce qui fait tourner le webmail

| # | Demande | À qui | Détail |
|---|---|---|---|
| B1 | **Créer le sous-domaine `webmail.meteomadagascar.mg`** dans le Portail | Équipe qui administre le Portail | le Portail pilotant la configuration nginx, c'est **lui** qui crée le sous-domaine et délivre le certificat (TLS). `mail.` est déjà pris par le Portail, c'est `webmail.` qui portera le webmail. |
| B2 | **Pointer le sous-domaine vers le serveur mail** | Équipe Portail | le Portail a un champ « IP cible » : y mettre l'IP du serveur mail — **privée** si le Portail est sur le LAN, **publique** sinon — et le port **8080** (notre Apache y sert en HTTP simple, le TLS étant terminé par le Portail). |
| B3 | **Un compte administrateur du Portail** | Équipe Portail | pour créer et rectifier le sous-domaine soi-même, sans repasser par une demande à chaque fois |

### C. Ce qui fait sortir et entrer le courrier (DNS)

| # | Demande | À qui | Détail |
|---|---|---|---|
| C1 | **SPF — fusionner** (ne pas ajouter une seconde ligne) | Stellarix (zone DNS) | le SPF existant est strict et **ne contient pas notre IP**. Il faut y ajouter `ip4:41.207.49.27` **avant** le `-all`. Deux enregistrements SPF = `permerror` = plus rien ne sort. |
| C2 | **MX** — ajouter `mail.meteomadagascar.mg` en **priorité 30** | Stellarix | le MX existant (DTS, priorités 5 et 20) reste prioritaire le temps de la bascule. |
| C3 | **DMARC en `p=none`** (+ adresse `rua` de collecte) | Stellarix | observation d'abord, 2 à 4 semaines, **jamais** `p=reject` d'emblée. |
| C4 | **Enregistrement DKIM** `dkim._domainkey` en **TXT** | Stellarix | la clé publique est produite par le serveur (déjà générée et validée en labo). Sans elle, les messages sortants ne sont pas signés. |
| C5 | **Pointeur `webmail.`** (enregistrement A) | Stellarix ou Portail | selon qui crée le sous-domaine (B1). |

> **Ordre impératif** : SPF → DKIM → **attendre 48 h** → DMARC `p=none`. Activer DMARC avant que DKIM soit publié fait rejeter les envois légitimes de l'institution.

### D. Ce qui relève du réseau (quand l'utilisateur sera sur place)

| # | Demande | Détail |
|---|---|---|
| D1 | **Accès MikroTik** | ouverture des ports 25, 587, 993, 4190, 443 ; limitation du port 25 (`connection-rate=20/min`) ; blocage de `postfixadmin.` hors LAN ; désactivation de telnet/ftp/www/api/UPnP. **Le 443 public est déjà tenu par le Portail** — ne pas essayer de le prendre. |

### E. Questions ouvertes à trancher avec l'encadrant

- **Combien de comptes réels ?** La conception dimensionne pour **500 maximum** (stations régionales comprises) ; l'évocation courante est **300-400**. Le quota total (1 To sur 2 To utiles) tient dans les deux cas, mais la procédure d'import, les tests et le pilote sont à dimensionner sur le chiffre réel.
- **Qui écrit et maintient le code ?** Le skin `meteo` a été écrit **sans une ligne de PHP** précisément pour que personne n'ait à le maintenir. Cette contrainte doit rester vraie : **ne pas introduire de plugin PHP** sans décision explicite.
- **Faut-il garder le Portail comme intermédiaire du webmail ?** Il est le seul chemin pour obtenir un certificat valide sur `webmail.` aujourd'hui, mais il devient un **point de rupture** : s'il tombe, le webmail tombe (IMAP et SMTP, eux, continuent de fonctionner).

## Journal des sorties

- Phase 15 : Rspamd **4.2.2** (Hyperscan ✓, LuaJIT ✓, Jemalloc ✓) · `configtest` OK · structure `local.d` validée (pas de section imbriquée) · **34 PASS / 0 FAIL** · ClamAV **4/4** · open relay **4/4** · DKIM signé sur tous les envois 587.
- Durabilité : `12-validation-finale.sh` et `17-test-open-relay.sh` installés dans **`/usr/local/sbin/`**. Ils vivaient dans `/tmp/labo-backup/`, que le redémarrage **vide** — c'est ce qui avait fait perdre les scripts de sauvegarde lors du test navigateur. Les scripts de déploiement doivent tous vivre dans `/usr/local/sbin/`, pas dans `/tmp`.
- Phase 5 : swaks tiana→luc « 250 Ok: queued » ; 2 fichiers dans `new/` ; headers Return-Path/Delivered-To/Received + From/To/Subject + body intacts.
- Phase 4 : IMAP LOGIN OK, `SELECT INBOX` = 2 messages, FETCH headers corrects, LOGOUT OK.
- Phase 7 : login web tiana → redirect `?_task=mail` → vue boîte 41 Ko en français.
- Phase 8 : `fail2ban-regex` 13 matched / 31 lignes ; test E2E 3 échecs → 1 IP bannie → iptables REJECT.
- Phase 10 : `BACKUP_OK` · `COPIE_DEPORTEE_OK` (ID déporté différent) · `RESTAURATION VALIDEE` (3 msgs identiques, dates intactes).
- Phase 12 : audit HTTP du script 19 → **zéro 404** ; tableau de bord 387×172, 4 tuiles ; logo Météo 207×91 (connexion) et 78×36 (accueil) ; police `Roboto` confirmée.

## Pièges rencontrés dans le volet sauvegarde

- **Le backup pouvait réussir et le script planter après** : `SNAP=$(restic … | grep …)` avec `set -o pipefail` — le `grep` sans correspondance interromp le script **alors que le snapshot était déjà écrit**. Le verdict passe désormais par un `grep` sur le log, jamais par le code de sortie d'un pipeline.
- **JSON restic sans espace** : `"short_id":"753d8df5"`, pas `"short_id": "…"`. Motif trop strict → échec silencieux, snapshot vide. Deux tentatives successives ont échoué là-dessus.
- **`restic` 0.12.1 (Ubuntu) n'a pas `--from-repo`** : la syntaxe est `-r` = source, `--repo2` = destination, `-p`/`--password-file` vs `--password-file2`. Vérifié sur `restic copy --help` avant d'écrire, pas après.
- **`RESTIC_PASSWORD_FILE` plutôt que `RESTIC_PASSWORD`** : le mot de passe dans l'environnement est lisible dans `/proc/<pid>/environ`. Le fichier `/root/.restic-password` est en 600.
- **`imaplib` imbrique les réponses** : `d[0]` est un *tuple* `(en-tête, littéral)`, `d[1]` vaut `b')'`. Un simple `b"".join(x for x in d if isinstance(x, bytes))` ne récupère que la parenthèse fermante → il faut aplatir les tuples imbriqués.
- **`set -e` tue le script avant la capture** : un `python3 … ; RC=$?` avorte sur le code de sortie non nul. `set +e` / `set -e` autour du test.
- **Un chemin absent ne doit pas faire échouer le backup** : `/var/lib/rspamd/dkim` n'existe qu'après la première signature DKIM. Filtré, avec mention explicite `[absent, ignore]`.

### 🔴 Piège majeur découvert par le test lui-même (16, octobre)

**`restic snapshots --latest 1` ne renvoie PAS « le plus récent ».** La doc dit *« for each host and path »* : des snapshots dont le **jeu de chemins diffère** forment des groupes distincts, et l'option en renvoie **un par groupe**. Symptôme observé :
```
restic snapshots --tag meteo --latest 1 --json
→ 2 snapshots :  84f50971 (06:48, 13 chemins)   3f0bc640 (08:02, 14 chemins)
```
Le périmètre avait changé parce que la clé DKIM avait fait apparaître `/var/lib/rspamd/dkim` (13 → 14 chemins). Un `head -1` sur le tableau attrapait le **premier**, pas le plus récent.

**Conséquence en production** : la restauration rétablirait un **instantané périmé** tout en affichant « RESTAURATION VALIDÉE ». Le pire scénario — une fausse assurance.

**Correctif appliqué** (`16-test-restauration.sh`) : sélection par **horodatage réel**, sans `--latest` ni `head -1` :
```bash
SNAP=$(restic … snapshots --tag meteo --json | python3 -c '
import json, sys
snaps = json.load(sys.stdin)
if not snaps: sys.exit(1)
print(max(snaps, key=lambda s: s["time"])["short_id"])')
```

**Second défaut, plus grave : le test détruisait les données qu'il protégeait.** Le `rm -rf "${BOITE}.SAVEGARDE-TEST"` était inconditionnel — y compris quand la restauration échouait. Les 5 messages du jour ont été perdus au premier essai. **Correctif** : la copie de sécurité n'est supprimée que si la restauration a **réussi** ; en cas d'échec elle est conservée avec un avertissement explicite.

> Ce second défaut est exactement le scénario catastrophe qu'un test de restauration doit couvrir : un script de reprise qui, en cas d'erreur, achève le destruction de la donnée qu'il devait sauver.

## Journal des sorties

(Les sorties validées de chaque phase sont recopiées ici au fil de l'eau.)

### Phase 16 — import à l'échelle (22 octobre 2026)

| Sortie | Valeur mesurée |
|---|---|
| Import | **405 boîtes** (400 importées + 5 de test) · 0 doublon de partie locale · 0 erreur · 59 collisions d'homonyme résolues |
| Quotas en base | 315 × 2 Go · 50 × 3 Go · 40 × 5 Go |
| Quotas appliqués par Dovecot | **5 242 880 Ko** / **3 145 728 Ko** / **2 097 152 Ko** (3 tirages) |
| Politique de mots de passe | **12/12** (dont 2 mots de passe communs, 2 institutionnels, 1 répétitif refusés) |
| Validation globale | **34 PASS / 0 FAIL** |
| Contrôle de continuité | `CONTINUITE_OK` (voir phase 17) |

### Phase 17 — skin « design du site » + continuité (22 octobre 2026)

| Sortie | Valeur mesurée |
|---|---|
| Déploiement du skin | `EXIT=0` · audit HTTP **17/17 PASS** (13 ressources + 4 polices) |
| Police embarquée | Open Sans Light / Regular / SemiBold / Bold (4 × woff2, signature `wOF2` vérifiée) — **aucun CDN** |
| Page de connexion | Open Sans 14 px, fond `#FBFBFB`, bouton `#F4C910` / `#333` / uppercase / gras 600 / rayon 8 px / `padding 7px 16px`, champ 38 px / rayon 6 px |
| Rail de navigation | emblème institutionnel recadré par CSS dans un cadre 46 × 46 (rail 78 px), dossier actif teal + filet gauche 3 px |
| Tableau de bord | bandeau `#34495E` à titre blanc uppercase, 1 seule action jaune (« Rédiger »), 3 tuiles blanches à icône teal, 2 raccourcis pilules teal |
| Continuité sans MariaDB | réception **acceptée** (`250 2.0.0 Ok: queued as 8C18A195A`) **et livrée** (`status=sent (delivered to maildir)`, 1,3 s) · authentification en `code=temp_fail` · `CONTINUITE_OK` |

### Phase 18 — le webmail en page unique (22 octobre 2026)

| Sortie | Valeur mesurée |
|---|---|
| Mise en page | grille `280px` + `1160px` · bandeau 56 px · rangée d'actions 59 px · **aucun débordement** du panneau latéral |
| Lecture superposée | cadre ouvert sur `&_action=show&_framed=1` · sujet affiché · **adresse de la page inchangée** · 0 erreur JavaScript |
| Réponse | formulaire pré-rempli dans le cadre de rédaction (destinataire `luc.ranaivo@meteo-test.lan`, objet `Re: [VALIDATION] bout-en-bout`) |
| **Envoi réel** | message **reçu** par le destinataire (IMAP : `From: tiana.rakoto@…`, `To: luc.ranaivo@…`, `Date: Thu, 22 Oct 2026 15:40:30 +0300`) |
| Téléphone (375 × 812) | 1 colonne · grille d'actions **2 × 2** (176 px × 2) · panneau latéral en tiroir (`translateX(-280)`) · recherche déplacée dans la grille |
| Validation globale | **34 PASS / 0 FAIL** |

### Phase 19 — écrans natifs harmonisés (22 octobre 2026)

Demande : « tous les boutons doivent rediriger vers le Roundcube, et ce Roundcube doit être facile à utiliser ».

Choix : les gabarits d'elastic restent hérités tels quels (aucun recopiage des templates settings/addressbook, zéro risque sur la logique Roundcube et toujours zéro PHP) ; `meteo.js` installe le bandeau Météo sur les tâches hors messagerie, et `meteo.css` (section 13) écarte le rail technique. Les pages internes encadrées (formulaire d'édition d'une identité, etc.) ne reçoivent pas le bandeau (elles servent de cadre à un formulaire seul).

| Sortie | Valeur mesurée |
|---|---|
| Bandeau hors messagerie | installé sur `task-settings` et `task-addressbook` : marque « Meteo Madagascar » + nav « Mes messages / Mes contacts / Mes parametres », pastille jaune sur le service affiché |
| Rail technique caché | `#taskmenu` (Mode sombre, À propos de, Rédiger…) et `#layout-menu` (rail vertical) en `display: none` — mesuré `none` sur les deux écrans |
| Chaîne validée au clic | page unique → tuile « Parametres » → écran bandé (`sub = Parametres`) → lien « Mes contacts » → contacts (`sub = Contacts`, groupes Adresses personnelles / Destinataires recueillis / Expéditeurs de confiance) |
| Bureau (1440 × 900) | capture `Temp/opencode/sp-settings-v11.png` et `sp-addr-v11.png` : deux listes calmes, barre d'outils contacts intacte (Créer, Rechercher, Importer, Exporter…) |
| Erreurs console | 0 sur l'enchaînement complet |
| Contrôle CJK | 0 caractère CJK dans `meteo.js` et `meteo.css` |

## Phase 20 — redaction allégée + divers demandés (22 oct 2026)

Demandes de l'utilisateur : six points, dont « envoyer un message → un écran simple comme Gmail », « un seul lien vers le site », le libellé « Pourriel », et des explications (message envoyé, Contacts, boutons d'actions).

| Mesure | Résultat |
| --- | --- |
| Écran de rédaction | gabarit elastic conservé, habillage CSS seule (`meteo.css` section 14, cible `body.action-compose`) ; les trois barres d'outils techniques `.menu.toolbar` (brouillon, signature, orthographe, chiffrement…) = `display:none` — mesuré 0 barre visible |
| Boutons restés visibles | « Envoyer » (pastille teal) et « Joindre un fichier » (pastille discrète, panneau Options et fichiers joints) ; lien technique « Ouvrir dans une nouvelle fenêtre » caché ; `#composebodycontainer` hauteur 320 px, objet 1.05 rem (mesuré 14.7 px / 41 px) |
| Envoyés preuve bout-en-bout | clic Envoyer → message envoyé : `doveadm status Sent messages=4` et boîte `luc.ranaivo@…` contient « Test phase 20 redaction simple » ; l'encadrement de rédaction se referme tout seul après l'envoi |
| Libellé dossier | le squelette `#mailboxlist` affiche « Pourriels » (locale fr) ; script skin remplace → mesuré « Indesirables » (« courriel » = l'e-mail) |
| Liens externes | la liste de huit liens « Autres services » deviennent un seul bouton « Site Meteo Madagascar » → https://www.meteomadagascar.mg/ (mesuré 1 entrée) |
| Bureau 1440 × 900 | capture sp20-final2.png : rédaction épurée, champ prévôts, liste d'options à droite |
| Erreurs console | 0 sur l'enchaînement complet |
| Contrôle CJK | 0 caractère CJK dans `meteo.js` et `meteo.css` |
