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

## Résultat final — script `labo/scripts/12-validation-finale.sh`

**34 PASS / 0 FAIL** — rejoué le 2026-10-15 à 19:07.

| Bloc | Critères |
|---|---|
| 1. Services | 7 services `active` |
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
| ③ Rspamd | ✅ actif, GTUBE rejeté | + ClamAV sur pièces jointes |
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
| D6 | **ClamAV écarté** (signatures ~1,5 Go, pas de place) | ClamAV sur pièces jointes uniquement |
| D7 | `emailcheck_resolve_domain = false` (`.lan` ne résout pas) | **doit rester `true`** |
| D8 | **1 seul pool PHP-FPM** partagé par les 2 vhosts | **2 pools distincts**, aucun include croisé |
| D9 | Rspamd 2.7 (paquets Ubuntu) | dépôt officiel, Rspamd 3.x |
| D10 | Pas de Fail2ban sur IP de la machine (`ignoreself`) | test par vraies IP distantes possible |
| D11 | Dépôt **déporté simulé** sur le même disque (`/srv/sauvegarde-deportee`) | disque **physiquement séparé** du RAID mail, copie hebdo **sortie du bâtiment** |
| D12 | `/var/lib/rspamd/dkim` absent (aucune signature émise) | présent dès le 1er envoi signé — **ne jamais l'exclure** |
| D13 | Volume sauvegardé ≈ 866 Kio | 500 boîtes ≈ 1 To (RAID 1 : 2 To utiles) |
| D14 | Signature DKIM **produite** mais **jamais vérifiée** (domaine `.lan`, pas d'enregistrement DNS) | `dkim._domainkey` en TXT à publier, puis `dkim=pass` côté destinataire |
| D15 | Skin `meteo` servi **en direct** sur le vhost local (Apache termine le TLS) | **`webmail.`** derrière le nginx du Portail, TLS terminé par le Portail, Apache en **HTTP interne** (8080) |
| D16 | Un seul enregistrement de peau en base (`$config['skin']`) | **purger la préférence `skin`** stockée par agent à l'import des 300-400 comptes, sinon un agent peut rester sur l'ancienne peau |
| D17 | Logo d'`elastic` **redirigé** par lien symbolique vers le logo Météo | même contournement à rejouer à chaque déploiement (bug de résolution d'`elastic` sur le template hérité `menu.html`) |
| D18 | Aucun modèle de réponse préchargé | **réponses enregistrées préchargées** (bulletin, fiche d'observation) — mécanisme natif Roundcube, zéro développement |

## Journal des sorties

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
