# Partie A — DNS et Matériel — Plan d'implémentation

> **Pour les agents :** SOUS-SKILL REQUIS : utiliser `superpowers:subagent-driven-development` (recommandé) ou `superpowers:executing-plans` pour exécuter ce plan tâche par tâche. Les étapes utilisent la syntaxe à cases (`- [ ]`) pour le suivi.

**Objectif :** preparatory le domaine `meteomadagascar.mg` et valider le matériel du futur serveur de messagerie, sans accès au serveur ni au routeur.

**Architecture :** Le plan travaille en deux volets indépendants. Le volet DNS produit un document de demande d'enregistrements à transmettre au détenteur des accès DNS (l'utilisateur n'a pas lui-même accès au panel), puis vérifie le résultat depuis l'extérieur. Le volet matériel produit un relevé d'inventaire de la machine cible et un verdict go/no-go chiffré.

**Pile technique :** DNS (zone `meteomadagascar.mg`, serveurs `ns.stellarix.africa` / `ns1.stellarix.africa`) · outils de vérification `nslookup` / `dig` · tableur de suivi pour l'inventaire matériel.

## État de départ — relevé DNS réel du 2026-10-13

Ces valeurs sont **vérifiées en production**, pas supposées. Toute modification part de cet état.

| Type | Nom | Valeur actuelle | Action |
|---|---|---|---|
| MX | `meteomadagascar.mg` | `5 mx-int10.dts.mg` | conserver |
| MX | `meteomadagascar.mg` | `20 mx2.dts.mg` | conserver |
| MX | `meteomadagascar.mg` | — | **ajouter** `30 mail.meteomadagascar.mg` |
| A | `mail.meteomadagascar.mg` | `41.207.49.27` | **déjà correct, ne rien changer** |
| TXT | `meteomadagascar.mg` | `v=spf1 ip4:41.188.7.128/27 ip4:102.16.10.150/32 ip4:102.16.3.238/32 -all` | **modifier** (voir T2) |
| TXT | `_dmarc.meteomadagascar.mg` | *inexistant* | **ajouter** `p=none` |
| PTR | `41.207.49.27` | `tgn.41.207.49.27.dts.mg` | **hors périmètre** (dépend YAS, cf. T8) |

**Constat critique :** un service de messagerie DTS existe déjà en production sur ce domaine
(`mx-int10.dts.mg`, `mx2.dts.mg`), avec un SPF en `-all` qui **ne contient pas** notre IP.

## Contraintes globales

- Domaine : `meteomadagascar.mg`. IP du serveur mail : `41.207.49.27`. FQDN : `mail.meteomadagascar.mg`.
- **Un seul enregistrement SPF est autorisé.** Le TXT existant est en `-all` strict et n'autorise que trois plages (dont `41.188.7.128/27` qui appartient à DTS et `102.16.x.x` qui est le site derrière Cloudflare). Toute IP qui envoie réellement en `@meteomadagascar.mg` doit y figurer, sinon le message est rejeté à l'émission.
- **Aucune écriture DNS ne peut être faite par l'agent** : le panel `ns.stellarix.africa` n'est pas accessible à l'utilisateur. Les tâches DNS consistent à **produire un document de demande**, puis à **vérifier** ce que le tiers a réellement appliqué.
- Toute vérification DNS se fait depuis l'extérieur avec `nslookup -type=<TYPE> <nom> 8.8.8.8`, jamais contre le serveur de noms autoritaire, afin d'écarter le cache local.
- Le plan ne modifie **jamais** l'enregistrement `A` de `mail.meteomadagascar.mg` (déjà correct) ni les enregistrements MX DTS (présents jusqu'à la bascule explicite, Phase B).
- Aucun accès serveur, SSH ou root n'est requis pour les tâches 1 à 4 et 7.
- Les tâches 5 et 6 demandent une **présence physique** devant la machine cible, mais uniquement des commandes en lecture. Elles sont structurées pour produire un **relevé** et un **verdict**, pas une intervention.
- **DKIM n'est pas dans le périmètre de la Partie A** : la clé est générée par Rspamd, donc seulement quand le serveur existera (Phase B). Un DMARC `p=none` sans DKIM est sans danger — il ne fait qu'observer.
- Aucun enregistrement ne doit être supprimé pendant la Phase A. Toute suppression est un acte de bascule, traité en Phase B avec validation des 5 critères d'ouverture.

---

### Tâche 1 : Figer l'état de référence DNS

**Fichiers :**
- Créer : `docs/partie-a/00-reference-dns.md`

**Interfaces :**
- Consomme : aucune (point de départ)
- Produit : `docs/partie-a/00-reference-dns.md` — le document que toutes les tâches suivantes citent comme référence de comparaison.

**Pourquoi cette tâche existe :** sans état de référence figé, on ne peut pas prouver qu'une modification DNS n'a rien cassé. C'est la seule preuve de non-régression disponible ici.

- [ ] **Étape 1 : créer le répertoire**

```bash
mkdir -p docs/partie-a
```

- [ ] **Étape 2 : relever l'état de référence**

Créer `docs/partie-a/00-reference-dns.md` avec le contenu exact ci-dessous (remplacer la date par celle du jour) :

```markdown
# Référence DNS — meteomadagascar.mg

Relevé du : <JJ/MM/AAAA, ex. 13/10/2026>
Méthode : nslookup depuis un poste externe, résolveur 8.8.8.8
Raison d'être : état de départ figé, permet de prouver qu'aucune tâche
ultérieure n'a dégradé un enregistrement existant.

## MX

| Préférence | Échangeur | Statut |
|---|---|---|
| 5 | mx-int10.dts.mg | existant (DTS) |
| 20 | mx2.dts.mg | existant (DTS) |

## A

| Nom | Adresse | Statut |
|---|---|---|
| mail.meteomadagascar.mg | 41.207.49.27 | existant, correct |

## TXT

| Nom | Valeur |
|---|---|
| meteomadagascar.mg | v=spf1 ip4:41.188.7.128/27 ip4:102.16.10.150/32 ip4:102.16.3.238/32 -all |
| _dmarc.meteomadagascar.mg | (inexistant) |

## PTR

| Adresse résolue en | Nom |
|---|---|
| 41.207.49.27 | tgn.41.207.49.27.dts.mg |

## NS

| Serveur |
|---|
| ns.stellarix.africa |
| ns1.stellarix.africa |
```

- [ ] **Étape 3 : vérifier que le document correspond bien au DNS réel**

```bash
nslookup -type=MX meteomadagascar.mg 8.8.8.8
nslookup -type=A mail.meteomadagascar.mg 8.8.8.8
nslookup -type=TXT meteomadagascar.mg 8.8.8.8
nslookup -type=TXT _dmarc.meteomadagascar.mg 8.8.8.8
nslookup -type=PTR 41.207.49.27 8.8.8.8
nslookup -type=NS meteomadagascar.mg 8.8.8.8
```

Expected : chaque sortie correspond exactement au tableau du document. Si une diffère, **corriger le document avec la valeur réellement observée** — le document décrit la réalité, pas l'inverse.

- [ ] **Étape 4 : commiter**

```bash
git add docs/partie-a/00-reference-dns.md
git commit -m "docs(partie-a): figer l'etat de reference DNS avant toute modification"
```

---

### Tâche 2 : Fusionner notre IP dans le SPF existant

**Fichiers :**
- Créer : `docs/partie-a/01-demande-modifs-dns.md`

**Interfaces :**
- Consomme : `docs/partie-a/00-reference-dns.md` (ligne SPF de référence)
- Produit : `docs/partie-a/01-demande-modifs-dns.md`, qui contient la section « SPF » consommée en vérification par la tâche 7.

**Pourquoi cette tâche est la plus importante du volet DNS :** le SPF est en `-all` (rejet strict). Sans ajout de `41.207.49.27`, **tout** courriel sortant du nouveau serveur sera rejeté par les destinataires. Et comme il ne peut y avoir qu'un seul SPF, la fusion doit être exacte — une faute de frappe dans l'enregistrement fait échouer toute la messagerie sortante.

- [ ] **Étape 1 : déterminer la nouvelle valeur SPF**

Le TXT existant est :

```
v=spf1 ip4:41.188.7.128/27 ip4:102.16.10.150/32 ip4:102.16.3.238/32 -all
```

La nouvelle valeur conserve les trois `ip4:` existantes (DTS et le site web émettent peut-être encore) et ajoute la nôtre :

```
v=spf1 ip4:41.188.7.128/27 ip4:102.16.10.150/32 ip4:102.16.3.238/32 ip4:41.207.49.27 -all
```

Différences : **un ajout** de ` ip4:41.207.49.27`, **aucune suppression**, le `-all` reste.

- [ ] **Étape 2 : créer la demande de modification SPF**

Créer `docs/partie-a/01-demande-modifs-dns.md` avec :

```markdown
# Demande de modifications DNS — meteomadagascar.mg

Destinataire : détenteur des accès du panel DNS (ns.stellarix.africa)
Demandeur : Service informatique — Direction Générale de la Météorologie
Objet : préparation de la messagerie institutionnelle @meteomadagascar.mg

## Règle absolue

**Un seul enregistrement SPF sur le domaine.** Si un TXT `v=spf1` existe
déjà, il se MODIFIE. Il ne faut jamais en créer un second : deux enregistrements
SPF provoquent une erreur permanente (« permerror ») et **aucun** courriel ne peut
plus sortir du domaine, plus aucune réception.

## Modification 1 — SPF (enregistrement existant)

| Champ | Valeur |
|---|---|
| Type | TXT |
| Nom | meteomadagascar.mg (apex, tel quel, sans sous-domaine) |
| TTL | valeur actuelle |
| Ancienne valeur | v=spf1 ip4:41.188.7.128/27 ip4:102.16.10.150/32 ip4:102.16.3.238/32 -all |
| **Nouvelle valeur** | **v=spf1 ip4:41.188.7.128/27 ip4:102.16.10.150/32 ip4:102.16.3.238/32 ip4:41.207.49.27 -all** |

Modifications apportées : ajout de ` ip4:41.207.49.27` avant le `-all`.
Aucune suppression. Les trois autres plages sont conservées à l'identique :
`41.188.7.128/27` (DTS), `102.16.10.150/32` et `102.16.3.238/32` (site web).
Supprimer l'une d'elles ferait échouer tout courriel qu'elle émet.

## Modification 2 — MX secondaire

| Champ | Valeur |
|---|---|
| Type | MX |
| Préférence | 30 |
| Échangeur | mail.meteomadagascar.mg |
| TTL | 3600 |

Les MX existants (`5 mx-int10.dts.mg` et `20 mx2.dts.mg`) sont **conservés**.
La préférence 30 place le nouveau serveur en position secondaire : aucun
courriel n'est perdu si DTS tombe, mais tout le trafic passe encore par DTS.

**Pourquoi 30 et pas 10 :** c'est la préférence la **plus basse** qui est servie en premier. En
mettant 30, DTS reste primaire et rien n'est interrompu. Une valeur 5 ou 10
basculerait immédiatement le trafic et couperait le service en cours.

**Pourquoi pas 20 :** 20 est déjà pris par `mx2.dts.mg`. Deux MX de même
préférence rendent la sélection aléatoire — un tiers du courrier partirait
dans un sens, deux tiers dans l'autre.

## Enregistrements à ne PAS toucher en Phase A

- `mail.meteomadagascar.mg` A → 41.207.49.27 : déjà correct
- `mx-int10.dts.mg` MX 5 et `mx2.dts.mg` MX 20 : conservés
- Aucun enregistrement ne doit être supprimé
```

- [ ] **Étape 3 : faire relire la valeur SPF avant tout envoi**

Relire la ligne `Nouvelle valeur` caractère par caractère. Une espace en trop,
une virgule au lieu d'un espace, un `/32` manquant : le domaine cesse d'émettre.
Vérifier que les 4 `ip4:` et le `-all` sont présents.

- [ ] **Étape 4 : transmettre la demande et demander un accusé de réception**

Le document est destiné au détenteur des accès. Transmettre par le canal habituel du service et **demander explicitement une confirmation écrite** de ce qui a été appliqué.

- [ ] **Étape 5 : commiter**

```bash
git add docs/partie-a/01-demande-modifs-dns.md
git commit -m "docs(partie-a): demande de fusion SPF et ajout MX secondaire"
```

---

### Tâche 3 : Publier un DMARC en observation

**Fichiers :**
- Modifier : `docs/partie-a/01-demande-modifs-dns.md` (ajouter une section)

**Interfaces :**
- Consomme : `docs/partie-a/01-demande-modifs-dns.md`
- Produit : section « DMARC » dans le même fichier, vérifiée en T7.

**Pourquoi `p=none` et rien de plus :** `p=none` ne demande aucune action en cas d'échec — le message est livré normalement, seul un rapport est envoyé. C'est le seul mode déployable sans risque de perdre du courrier. Passer à `quarantine` ou `reject` avant d'avoir des rapports est la cause n°1 de courriers légitimes perdus.

- [ ] **Étape 1 : ajouter la section DMARC au fichier de demande**

Ajouter dans `docs/partie-a/01-demande-modifs-dns.md` :

```markdown
## Ajout 1 — DMARC en observation

| Champ | Valeur |
|---|---|
| Type | TXT |
| Nom | _dmarc.meteomadagascar.mg |
| TTL | 3600 |
| Valeur | v=DMARC1; p=none; rua=mailto:dmarc@meteomadagascar.mg; fo=1; pct=100 |

Lecture de la valeur :

- `v=DMARC1` — version du protocole, obligatoire
- `p=none` — **observation seule**. Aucun message n'est rejeté ni mis en quarantaine.
- `rua=mailto:dmarc@meteomadagascar.mg` — adresse de réception des rapports.
  Elle est prévue comme **adresse de service** dans la conception (troisième
  catégorie d'adresses). Elle est créée en Phase B, avant l'ouverture : un
  `rua` vers une adresse inexistante fait revenir les rapports en erreur.
- `fo=1` — un rapport est envoyé dès qu'un seul alignement échoue.
- `pct=100` — 100 % des messages sont évalués.

**Ce que ce mode ne fait pas :** il n'influence pas l'acceptation des messages.
Ce n'est qu'un rapport. Rien ne peut être perdu en le déployant.

**Progression prévue :** `p=none` pendant 2 à 4 semaines, lecture des rapports,
puis `p=quarantine`, puis `p=reject` une fois le taux d'échec nul. Ce ne sera
pas avant la Phase B, quand DKIM sera en place.
```

- [ ] **Étape 2 : vérifier la cohérence avec la tâche 2**

Le DMARC ne peut émettre de rapports utiles que si le SPF est en place (T2 fait dans le même lot) et, plus tard, si DKIM existe. Puisque le lot est transmis ensemble, DMARC et SPF arrivent simultanément : correct.

- [ ] **Étape 3 : vérifier que l'adresse de rapport est couverte**

`dmarc@meteomadagascar.mg` doit exister comme **adresse de service** dans la conception (section « Trois types d'adresses » du document de conception). Elle n'a pas besoin d'être une boîte Dovecot : une adresse de redirection vers une boîte existante suffit, et c'est ce que prévoit la conception.

Si elle n'est pas couverte, lever le point ici et non à l'ouverture : un `rua` vers une adresse inexistante génère des rapports qui reviennent en erreur, ce qui nuit à la réputation de l'expéditeur.

- [ ] **Étape 4 : commiter**

```bash
git add docs/partie-a/01-demande-modifs-dns.md
git commit -m "docs(partie-a): ajouter DMARC p=none en observation"
```

---

### Tâche 4 : Préparer les noms de service (autodiscover, autoconfig)

**Fichiers :**
- Modifier : `docs/partie-a/01-demande-modifs-dns.md` (ajouter une section)

**Interfaces :**
- Consomme : `docs/partie-a/01-demande-modifs-dns.md`
- Produit : section « Noms de service », vérifiée en T7.

**Pourquoi c'est différé et non fait maintenant :** `autodiscover` sert à configurer Outlook automatiquement. Outlook ne le demande que lorsqu'un agent crée sa boîte. Le publier avant l'existence du serveur expose un service à moitié fonctionnel — Outlook se connecte, échoue, et l'agent conclut que « ça ne marche pas ». On publie au moment de la bascule, pas avant.

- [ ] **Étape 1 : documenter les enregistrements pour plus tard**

Ajouter dans `docs/partie-a/01-demande-modifs-dns.md` :

```markdown
## Ajout 2 — Noms de service (À NE PAS PUBLIER EN PHASE A)

Ces enregistrements ne font **pas** partie du lot Phase A. Ils sont
documentés ici pour être transmis au moment de la bascule (Phase B), quand le
serveur répond réellement.

| Type | Nom | Cible | Rôle |
|---|---|---|---|
| CNAME | autodiscover.meteomadagascar.mg | mail.meteomadagascar.mg | configuration automatique Outlook |
| CNAME | autoconfig.meteomadagascar.mg | mail.meteomadagascar.mg | configuration automatique Thunderbird |

`webmail.meteomadagascar.mg` (A → 41.207.49.27) et
`postfixadmin.meteomadagascar.mg` (A → 41.207.49.27) sont également à publier
en Phase B, le second avec un blocage réseau (accès interne uniquement).

Rappel obligatoire : `mail.meteomadagascar.mg` doit rester en DNS seul, jamais
derrière un proxy. Un proxy ne relaie pas SMTP ni IMAP.
```

- [ ] **Étape 2 : vérifier que rien de tout cela n'est déjà publié**

```bash
nslookup -type=CNAME autodiscover.meteomadagascar.mg 8.8.8.8
nslookup -type=A webmail.meteomadagascar.mg 8.8.8.8
nslookup -type=A postfixadmin.meteomadagascar.mg 8.8.8.8
```

Expected : chaque commande retourne « n'existe pas » ou « ne parvient pas à trouver ». Si l'un existe déjà, **ne rien écraser** — le noter dans `00-reference-dns.md` et demander qui l'a créé.

- [ ] **Étape 3 : commiter**

```bash
git add docs/partie-a/01-demande-modifs-dns.md
git commit -m "docs(partie-a): documenter les noms de service pour la bascule"
```

---

### Tâche 5 : Relever le matériel de la machine cible

**Fichiers :**
- Créer : `docs/partie-a/02-inventaire-materiel.md`
- Créer : `docs/partie-a/02-inventaire-materiel.csv`

**Interfaces :**
- Consomme : le cahier des charges du document de conception, section « Dimensionnement »
- Produit : `02-inventaire-materiel.md` (tableau) et `02-inventaire-materiel.csv` (brut, à remplir sur place)

**Pourquoi un relevé et pas une commande distante :** la machine n'est pas accessible. L'utilisateur n'a ni SSH ni présence sur le réseau Météo. Le livrable de cette tâche est donc un **formulaire de relevé à remplir sur place**, conçu pour que le remplissage prenne 2 minutes sur le serveur lui-même.

- [ ] **Étape 1 : créer le fichier CSV de relevé**

Créer `docs/partie-a/02-inventaire-materiel.csv` avec ces colonnes (une seule ligne d'en-tête, prête à remplir) :

```csv
poste,processeur,coeurs,ram_go,disque_systeme,disques_donnees,type_disques,capacite_par_disque_go,raid_actuel,interface_reseau,vitesse_reseau,os_version,noyau,utilisateur_actuel
```

- [ ] **Étape 2 : créer la procédure de relevé sur place**

Créer `docs/partie-a/02-inventaire-materiel.md` avec :

```markdown
# Inventaire matériel — serveur de messagerie

## Pourquoi ce document

La conception dimensionne la machine à **8 cœurs / 32 Go RAM / 2 × 2 To SSD en
RAID 1**. Ce sont des cibles, pas des constats : elles ont été calculées à
partir du nombre d'agents (500) et des quotas. Tant que la machine réelle
n'a pas été relevée, le dimensionnement reste théorique.

Ce document est à remplir **sur place**, sur le serveur, par une personne
qui a accès à la machine physique.

## Cahier des charges (cible)

| Composant | Cible | Justification |
|---|---|---|
| Processeur | 8 cœurs | 500 boîtes : antispam, indexation, chiffrement |
| RAM | **32 Go** | poste le plus sous-budgété ; sous 16 Go, Rspamd + ClamAV sature |
| Disque système | 256 Go SSD | OS, logs, programmes |
| Données | 2 × 2 To SSD, **RAID 1** | 500 × 2 Go = 1 To ; 2 To utiles = marge réelle |
| Sauvegarde | 2 × 4 To HDD, RAID 1 | hors tableau mail, physiquement séparés |

**RAID 1 avec 2 disques de 2 To = 2 To utiles**, pas 4. Un miroir ne double
pas la capacité.

## Relevé à effectuer (sur place)

Coller les sorties de ces commandes dans le tableau. Aucune ne modifie le
système.

```bash
# Vue d'ensemble
hostnamectl
uname -a

# Processeur
lscpu | grep -E 'Model name|^CPU\(s\)|Thread|Core'

# Mémoire
free -h

# Disques et RAID
lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINT
cat /proc/mdstat
mdadm --detail --scan

# Réseau
ip -br addr
ethtool eth0 2>/dev/null | grep -E 'Speed|Duplex'

# Charge
uptime
```

## Remplissage du CSV

Copier les valeurs relevées dans `02-inventaire-materiel.csv`, une ligne.
Le séparateur est la virgule. Les valeurs contenant une virgule (RAM
`32,0 GiB`) doivent être entre guillemets.

## Verdict (à remplir après le relevé)

| Critère | Cible | Constat | Verdict |
|---|---|---|---|
| Cœurs | 8 | | conforme / insuffisant |
| RAM | 32 Go | | conforme / insuffisant |
| Données | 2 To utiles RAID 1 | | conforme / insuffisant |
| Réseau | 1 Gbps | | conforme / insuffisant |

**Décision :** si RAM < 32 Go, il est possible de démarrer avec 16 Go en
acceptant une dégradation (ClamAV plus lent, risque de saturation en
pic d'envoi). C'est un compromis à valider avec la direction, pas un
silence technique.
```

- [ ] **Étape 3 : vérifier que les commandes du bloc sont sûres**

Relire chaque commande : toutes sont en lecture seule (`hostnamectl`, `uname`,
`lscpu`, `free`, `lsblk`, `cat /proc/mdstat`, `mdadm --detail --scan`,
`ip -br`, `ethtool`, `uptime`). Aucune n'écrit, aucune ne reformate. C'est
volontaire : la personne qui remplit le formulaire ne doit avoir aucun doute
sur l'innocuité.

- [ ] **Étape 4 : commiter**

```bash
git add docs/partie-a/02-inventaire-materiel.md docs/partie-a/02-inventaire-materiel.csv
git commit -m "docs(partie-a): formulaire de releve materiel et cahier des charges"
```

---

### Tâche 6 : Trancher les conséquences d'un matériel sous-dimensionné

**Fichiers :**
- Modifier : `docs/partie-a/02-inventaire-materiel.md` (section Verdict)

**Interfaces :**
- Consomme : `02-inventaire-materiel.md` rempli après T5
- Produit : section Verdict renseignée, exploitable par la direction

- [ ] **Étape 1 : comparer le constat à la cible**

Une fois `02-inventaire-materiel.csv` rempli, reporter les valeurs dans le tableau Verdict de `02-inventaire-materiel.md`. Chaque ligne doit porter « conforme » ou « insuffisant ». Ne pas laisser de cellule vide : une cellule vide n'est pas une mesure.

- [ ] **Étape 2 : choisir une des trois trajectoires selon le RAM relevé**

- **≥ 32 Go** — le dimensionnement est validé. Aucune action.
- **16 à 31 Go** — viable avec compromis : désactiver ClamAV sur le corps (la conception ne le fait de toute façon pas — ClamAV ne scanne que les pièces jointes), réduire la rétention des logs Rspamd, allonger l'intervalle de scan clamav. Documenter chaque compromis dans le tableau Verdict.
- **< 16 Go** — non tenable pour 500 boîtes. Deux options : réduire le nombre d'agents servis (ex. 150), ou acquérir de la RAM. **Ne pas démarrer le déploiement** avec moins de 16 Go : Rspamd et ClamAV sont en mémoire, la machine sature et le courrier est refusé en entrée.

- [ ] **Étape 3 : vérifier la cohérence avec la capacité disque**

Si 2 To utiles ne sont pas disponibles, recalculer : 500 × 2 Go = 1 To requis. Avec des quotas de 2 Go, il faut **au moins 1,5 To utile** pour garder une marge. En dessous, réduire le quota par défaut ou le nombre de boîtes. Reporter le chiffre dans le tableau Verdict.

- [ ] **Étape 4 : obtenir un arbitrage écrit**

Si une trajectoire dégradée est choisie, la faire **valider par écrit** par la direction. Une dégradation technique doit être une décision, pas un fait accompli.

- [ ] **Étape 5 : commiter**

```bash
git add docs/partie-a/02-inventaire-materiel.md docs/partie-a/02-inventaire-materiel.csv
git commit -m "docs(partie-a): relever le verdict materiel et la trajectoire retenue"
```

---

### Tâche 7 : Vérifier que les modifications DNS ont été appliquées

**Fichiers :**
- Créer : `docs/partie-a/03-verification-dns.md`
- Modifier : `docs/partie-a/00-reference-dns.md` (colonne « Action »)

**Interfaces :**
- Consomme : `docs/partie-a/01-demande-modifs-dns.md` (valeurs attendues), `docs/partie-a/00-reference-dns.md` (état de départ)
- Produit : `docs/partie-a/03-verification-dns.md` — le constat écrit opposable

**Pourquoi cette tâche n'est pas optionnelle :** une erreur de saisie DNS ne produit aucune erreur visible. Le panel affiche « enregistré » et le mail ne sort pas. La seule détection est la lecture depuis l'extérieur. Si personne ne vérifie, on découvre le problème au moment de l'ouverture, devant 500 agents.

- [ ] **Étape 1 : attendre la propagation**

Demander au détenteur des accès l'horaire de l'application. Tester **au moins 4 heures après**, pour couvrir le TTL des enregistrements modifiés.

- [ ] **Étape 2 : vérifier le SPF**

```bash
nslookup -type=TXT meteomadagascar.mg 8.8.8.8
```

Expected : exactement une ligne, contenant les quatre plages et le `-all` :

```
v=spf1 ip4:41.188.7.128/27 ip4:102.16.10.150/32 ip4:102.16.3.238/32 ip4:41.207.49.27 -all
```

**Si deux lignes `v=spf1` apparaissent :** erreur critique. Un second enregistrement SPF a été créé au lieu de modifier l'existant. Demander sa suppression immédiate — tant qu'il existe, aucun courriel ne sort.

**Si `-all` manque ou a disparu :** erreur critique. Un `+all`(open relaying) ou l'absence de `-all` affaiblit toute la protection anti-usur de la Phase B.

- [ ] **Étape 3 : vérifier le MX**

```bash
nslookup -type=MX meteomadagascar.mg 8.8.8.8
```

Expected : trois lignes, par ordre de préférence :

```
meteomadagascar.mg MX preference = 5, mail exchanger = mx-int10.dts.mg
meteomadagascar.mg MX preference = 20, mail exchanger = mx2.dts.mg
meteomadagascar.mg MX preference = 30, mail exchanger = mail.meteomadagascar.mg
```

**Si `mail.meteomadagascar.mg` n'apparaît pas :** l'enregistrement n'a pas été créé. Rien ne casse (DTS reste primaire), mais le serveur ne recevra rien. Le signaler et relancer la demande.

**Si une préférence 5 ou 10 apparaît pour le nouveau serveur :** la bascule a été faite par erreur, contre la stratégie retenue. Le trafic DTS est coupé. Demander le retour au 30 immédiatement.

- [ ] **Étape 4 : vérifier l'A de mail et le DMARC**

```bash
nslookup -type=A mail.meteomadagascar.mg 8.8.8.8
nslookup -type=TXT _dmarc.meteomadagascar.mg 8.8.8.8
```

Expected pour l'A : `41.207.49.27`, inchangé.
Expected pour le DMARC : une ligne contenant `v=DMARC1` et `p=none`.

- [ ] **Étape 5 : vérifier que le site web n'a pas été touché**

```bash
nslookup -type=A meteomadagascar.mg 8.8.8.8
nslookup -type=A www.meteomadagascar.mg 8.8.8.8
```

Expected : valeurs identiques à la référence. Le site derrière Cloudflare doit rester **inchangé**. Toute variation ici signifie qu'une erreur a été faite sur l'apex pendant la modification du TXT.

- [ ] **Étape 6 : créer le document de vérification**

Créer `docs/partie-a/03-verification-dns.md` :

```markdown
# Vérification DNS — meteomadagascar.mg

Vérifié le : <JJ/MM/AAAA>
Méthode : nslookup depuis un poste externe, résolveur 8.8.8.8

## Résultat par enregistrement

| Enregistrement | Attendu | Constaté | Verdict |
|---|---|---|---|
| TXT SPF | un seul, 4 ip4, -all | | OK / ANOMALIE |
| MX | 5, 20, 30 | | OK / ANOMALIE |
| A mail | 41.207.49.27 | | OK / ANOMALIE |
| TXT DMARC | v=DMARC1 p=none | | OK / ANOMALIE |
| A site | inchangé | | OK / ANOMALIE |

## Anomalies constatées

Pour chaque anomalie, décrire : ce qui a été trouvé, ce qui était attendu,
l'impact concret, et l'action demandée.

## Copies exactes des sorties

<sorties brutes des six commandes, non réécrites>
```

- [ ] **Étape 7 : mettre à jour la référence**

Ajouter dans `docs/partie-a/00-reference-dns.md` une section « Relevé après application » reprenant le tableau d'état ci-dessus, mise à jour : SPF en « fusionné », MX « ajouté en préf. 30 », DMARC « publié en p=none », A `mail` et A du site « inchangés ».

- [ ] **Étape 8 : commiter**

```bash
git add docs/partie-a/03-verification-dns.md docs/partie-a/00-reference-dns.md
git commit -m "docs(partie-a): verifier l'application des modifications DNS"
```

---

### Tâche 8 : Consigner les éléments reportés (PTR et MikroTik)

**Fichiers :**
- Créer : `docs/partie-a/04-reportes.md`

**Interfaces :**
- Consomme : le document de conception, sections PTR et MikroTik
- Produit : `docs/partie-a/04-reportes.md` — trace des points non traités en Phase A et de leur condition de déblocage

**Pourquoi cette tâche existe :** A1 et A3 ont été volontairement exclus. Les écarter est légitime, mais les **oublier** ferait échouer l'ouverture du service sans que personne ne le sache. Le PTR est un chemin critique : sans lui, la réception depuis Gmail et Outlook est inutilisable, même avec un déploiement parfait.

- [ ] **Étape 1 : créer le fichier de report**

Créer `docs/partie-a/04-reportes.md` :

```markdown
# Éléments reportés hors Phase A

## A1 — Demande PTR auprès de YAS

**Statut :** non fait (reporté par décision de pilotage).
**Pourquoi :** l'utilisateur a choisi de traiter la demande en fin de projet.

**État constaté le 2026-10-13 :**

```
41.207.49.27 → tgn.41.207.49.27.dts.mg
```

Le PTR actuel pointe vers un nom de **DTS**, pas vers notre domaine. Ce n'est
pas bloquant pour émettre, mais c'est bloquant pour recevoir.

**Pourquoi c'est critique :** un PTR incohérent avec le domaine émetteur est
l'un des premiers signaux de fraude utilisés par Gmail et Outlook. Sans PTR
correct, le courrier **reçu** depuis ces services finit en spam ou n'arrive pas.
Le déploiement technique peut réussir à 100 % et la messagerie rester inutilisable.

**Contenu exact de la demande à YAS :**

> Objet : Demande de configuration PTR (résolution inverse) pour une IP publique
>
> Nous hébergeons le site institutionnel meteomadagascar.mg au nom de la
> Direction Générale de la Météorologie. Nous mettons en place un service de
> messagerie électronique sur l'IP publique 41.207.49.27.
>
> Cette IP est utilisée pour un serveur de messagerie (SMTP entrant et
> sortant, IMAP). Elle sert uniquement au courrier électronique, pas à
> l'hébergement de site web.
>
> Nous vous demandons de configurer l'enregistrement PTR (reverse DNS) de
> l'adresse 41.207.49.27 sur : mail.meteomadagascar.mg
>
> Cet enregistrement doit être stable dans le temps et ne pas être modifié.
>
> Merci de nous confirmer par retour de courriel lorsque la modification est
> effective.

**Note :** si YAS exige un ticket de support et non un simple courriel, la
demande doit passer par ce canal — le délai est alors plus long, ce qui justifie
de la lancer tôt.

**Condition de déblocage :** PTR = `mail.meteomadagascar.mg` ET résolution
inverse cohérente.

**Vérification :**

```bash
nslookup -type=PTR 41.207.49.27 8.8.8.8
```

Expected : `mail.meteomadagascar.mg.` (avec le point final).

## A3 — Configuration MikroTik

**Statut :** non fait (reporté — l'utilisateur n'est pas connecté au réseau Météo,
le routeur est dans les locaux).
**Pourquoi :** impossible sans présence physique ni accès administration.

**Rappel du périmètre à exécuter :**

- Ouvrir 25, 587, 993, 4190, 443. POP3 (110/995) et 465 restent fermés.
- Port 80 : ouvert **temporairement**, uniquement pour l'émission du certificat
  Let's Encrypt (HTTP-01), puis refermé.
- Masquerade pour la liste `mailservers` uniquement.
- Port 25 bridé à `connection-rate=20/min` (address-list `mta-abus`).
- Aucun poste du LAN en sortie SMTP (`action=reject`).
- Désactiver `telnet`, `ftp`, `www`, `api`, `www-ssl` et UPnP.
- Chaîne `input` : established/related → invalid drop → icmp accept → reste depuis WAN drop.
- Chaîne `forward` : invalid drop → established/related accept → `connection-nat-state=!dstnat` drop depuis WAN.

**Condition de déblocage :** présence sur place + accès administration MikroTik.
**Dépend de :** la Partie B doit être au moins partiellement déployée pour
tester les règles (en particulier le masquerade, qui se teste en envoyant un
courriel de test).

## Récapitulatif des conditions de déblocage de l'ouverture

| Blocage | Déblocé par | Statut |
|---|---|---|
| PTR | réponse YAS | en attente |
| DNS (SPF, MX, DMARC) | vérification T7 | en cours |
| Matériel conforme | relevé T5 + verdict T6 | en attente |
| Règles MikroTik | accès routeur | en attente |
| Serveur déployé | Phase B | non commencée |

**Aucun des 5 critères d'ouverture ne peut être évalué avant que le serveur
existe (Phase B).**
```

- [ ] **Étape 2 : vérifier que la demande PTR est en français correct et exploitable**

Relire le texte fourni pour YAS. Il doit être autoportant : YAS ne connaît pas le projet et ne doit pas avoir besoin d'un échange d'e-mails pour agir. Le ton est direct, la demande précise (un seul PTR, un seul nom, ne pas changer).

- [ ] **Étape 3 : commiter**

```bash
git add docs/partie-a/04-reportes.md
git commit -m "docs(partie-a): consigner PTR et MikroTik reports avec conditions de deblocage"
```

---

## Ce que ce plan ne fait pas

À l'issue de la Partie A, **la messagerie ne fonctionne pas encore**. Le domaine est prêt à recevoir le nouveau serveur, le matériel est validé, mais le serveur lui-même n'existe pas côté installation.

Restent hors périmètre, faute d'accès :

- **A1** — PTR auprès de YAS (reporté, T8)
- **A3** — règles MikroTik (reporté, T8)
- **Partie B complète** — recette machine, durcissement, installation de la pile,
  comptes pilotes, tests de délivrabilité, sauvegarde et test de restauration,
  import des 500 comptes
- **DKIM** — impossible à générer avant que Rspamd tourne sur le serveur (Phase B)
- **Bascule du MX** — quand le serveur sera prêt et les 5 critères d'ouverture
  validés, le MX passera de préférence 30 à 5, et les MX DTS seront retirés.
  **Ce n'est pas une tâche de ce plan.**

Le DMARC est déployé en `p=none` (observation). Le passage à `quarantine` puis
`reject` est une décision distincte, postérieure à la mise en service et à la
lecture des rapports.