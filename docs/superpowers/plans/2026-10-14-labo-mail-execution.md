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

## Journal des sorties

- Phase 5 : swaks tiana→luc « 250 Ok: queued » ; 2 fichiers dans `new/` ; headers Return-Path/Delivered-To/Received + From/To/Subject + body intacts.
- Phase 4 : IMAP LOGIN OK, `SELECT INBOX` = 2 messages, FETCH headers corrects, LOGOUT OK.
- Phase 7 : login web tiana → redirect `?_task=mail` → vue boîte 41 Ko en français.
- Phase 8 : `fail2ban-regex` 13 matched / 31 lignes ; test E2E 3 échecs → 1 IP bannie → iptables REJECT.
- Phase 10 : `BACKUP_OK` · `COPIE_DEPORTEE_OK` (ID déporté différent) · `RESTAURATION VALIDEE` (3 msgs identiques, dates intactes).

## Pièges rencontrés dans le volet sauvegarde

- **Le backup pouvait réussir et le script planter après** : `SNAP=$(restic … | grep …)` avec `set -o pipefail` — le `grep` sans correspondance interromp le script **alors que le snapshot était déjà écrit**. Le verdict passe désormais par un `grep` sur le log, jamais par le code de sortie d'un pipeline.
- **JSON restic sans espace** : `"short_id":"753d8df5"`, pas `"short_id": "…"`. Motif trop strict → échec silencieux, snapshot vide. Deux tentatives successives ont échoué là-dessus.
- **`restic` 0.12.1 (Ubuntu) n'a pas `--from-repo`** : la syntaxe est `-r` = source, `--repo2` = destination, `-p`/`--password-file` vs `--password-file2`. Vérifié sur `restic copy --help` avant d'écrire, pas après.
- **`RESTIC_PASSWORD_FILE` plutôt que `RESTIC_PASSWORD`** : le mot de passe dans l'environnement est lisible dans `/proc/<pid>/environ`. Le fichier `/root/.restic-password` est en 600.
- **`imaplib` imbrique les réponses** : `d[0]` est un *tuple* `(en-tête, littéral)`, `d[1]` vaut `b')'`. Un simple `b"".join(x for x in d if isinstance(x, bytes))` ne récupère que la parenthèse fermante → il faut aplatir les tuples imbriqués.
- **`set -e` tue le script avant la capture** : un `python3 … ; RC=$?` avorte sur le code de sortie non nul. `set +e` / `set -e` autour du test.
- **Un chemin absent ne doit pas faire échouer le backup** : `/var/lib/rspamd/dkim` n'existe qu'après la première signature DKIM. Filtré, avec mention explicite `[absent, ignore]`.

## Journal des sorties

(Les sorties validées de chaque phase sont recopiées ici au fil de l'eau.)
