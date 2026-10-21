# Conception de la messagerie institutionnelle @meteomadagascar.mg

Date : 2026-10-13
Statut : validé en conception, en attente d'accès serveur pour la phase de déploiement

---

## 1. Objet et contexte

La Direction Générale de la Météorologie de Madagascar souhaite doter l'ensemble de son personnel
— cadres, prévisionnistes, agents administratifs et stations régionales — d'une adresse
e-mail professionnelle officielle sous le domaine `@meteomadagascar.mg`.

Le projet est **100 % autonome** : auto-hébergé sur site, sans aucun abonnement payant chez
l'opérateur YAS. Cette contrainte oriente tous les choix techniques de ce document.

### 1.1 Décisions de cadrage

| Sujet | Décision |
|---|---|
| Rôle du serveur | **MX public complet** : réception du monde entier + envoi sortant |
| Échelle cible | **500 agents maximum**, dont les stations régionales |
| IP publique du serveur mail | `41.207.49.27` (fixe YAS) |
| FQDN du serveur | `mail.meteomadagascar.mg` (enregistré DNS) |
| Site web existant | `102.16.63.110`, derrière Cloudflare → **totalement indépendant** |
| Accès distant | IMAP public + restriction anti-bruteforce |
| Sauvegardes | Local + copie déportée, 100 % gratuit |
| Local des serveurs | **Sécurisé** → pas de chiffrement du disque au repos |
| Topologie machines | Serveur web et serveur mail séparés, aucune machine mutualisée |

> ⚠️ **Correction du 21 octobre 2026 (après vérification sur le terrain).** Ce paragraphe disait : « les ports 80 et 443 de `41.207.49.27` sont libres ». **C'est faux.** Une plateforme interne de gestion des sous-domaines (« Portail Météo ») répond déjà sur `41.207.49.27:80` et `:443` : elle y sert `mail.meteomadagascar.mg` et `adl.meteomadagascar.mg`, ce dernier avec un certificat Let's Encrypt valide. Voir le **§ 4.4** pour l'architecture qui en découle.
>
> Ce qui reste vrai : le site `meteomadagascar.mg` est sur une autre IP (`102.16.63.110`, derrière Cloudflare) et **n'est pas touché** par ce projet. Le courrier (ports 25, 587, 993, 4190) ne passe pas par le Portail : il est pointé en direct sur le serveur mail. **Le Portail ne devient une dépendance que du *webmail*.**

---

## 2. Architecture retenue et alternatives écartées

### 2.1 Architecture retenue : serveur unique cloisonné

Un seul serveur Debian, avec chaque composant isolé de façon stricte.

**Pourquoi ce choix plutôt que deux serveurs** (mail d'un côté, webmail de l'autre) :

- 500 boîtes sur un serveur dédié est une configuration standard et éprouvée.
- La contrainte budgétaire « aucun abonnement » se traduit par un parc matériel minimal.
- L'isolation utile — permissions Unix, vhosts séparés, comptes de service distincts — est
  parfaitement réalisable sur une seule machine.

**Quand la séparation en deux serveurs deviendrait pertinente :** si la direction exige une
disponibilité contractuelle, ou si le serveur doit héberger d'autres services critiques.
Pas avant.

### 2.2 Alternatives écartées

| Alternative | Raison de l'écarter |
|---|---|
| Deux serveurs (mail / webmail) | Coût matériel doublé, latence IMAP, deux fois les sauvegardes. L'isolation par permissions Unix suffit à cette échelle. Reste documenté comme plan B. |
| OpenLDAP au lieu de MariaDB | PostfixAdmin ne parle pas LDAP nativement (patch non maintenu), dépendance supplémentaire, LDAP notoriément pénible à dépanner. Sur-ingénierie pour 500 comptes. |
| Postfix + Amavis (amavis-new) | Plus lourd et plus ancien que l'intégration antivirus de Rspamd. Doublon fonctionnel. |
| Dovecot + Solr pour la recherche | Un deuxième serveur quasi autonome à cette échelle. `fts = maildir` suffit. Réversible plus tard si besoin. |

---

## 3. Composants et interfaces

### 3.1 Identité de la machine

| | |
|---|---|
| Hostname | `mail.meteomadagascar.mg` |
| IP publique | `41.207.49.27` (fixe YAS) |
| IP privée | réseau LAN Météo — à fixer lors de la recette |
| OS | Debian 12 (Bookworm) — cycle de support long, paquets maintenus |

Le serveur ne porte **pas** d'IP publique sur sa carte réseau. Toute la traduction d'adresses
est faite par le MikroTik.

### 3.2 Les composants

| Composant | Rôle | Ports exposés |
|---|---|---|
| **Postfix** | Réception MX et envoi SMTP | 25, 587 |
| **Dovecot** | Stockage Maildir, IMAP, Sieve | 993, 4190 |
| **MariaDB** | Comptes/quotas (PostfixAdmin) + sessions Roundcube | localhost uniquement |
| **Rspamd** | Antispam, antivirus, limitation de débit | aucun |
| **ClamAV** | Analyse des pièces jointes via Rspamd | aucun (127.0.0.1:3310) |
| **Roundcube** | Webmail du personnel | 443 |
| **PostfixAdmin** | Console d'administration | 443, accès réseau interne |
| **Restic** | Sauvegardes incrémentales dédupliquées | aucun |
| **Fail2ban** | Blocage des tentatives répétées | aucun |

### 3.3 Ports ouverts sur le MikroTik

```
25/tcp    SMTP        réception MX depuis Internet
587/tcp   soumission  envoi authentifié (STARTTLS)
993/tcp   IMAPS       accès des clients
4190/tcp  ManageSieve  filtres Roundcube
```

**Ports 80 et 443 : retirés de cette liste (correction du 21 octobre 2026).** Ils sont **déjà
tenus par le Portail Météo** sur `41.207.49.27`. Le webmail y arrive par le reverse-proxy du
Portail (voir § 4.4) ; notre Apache n'écoute qu'en **HTTP interne** sur 8080 (webmail) et 8081
(administration). Aucun port supplémentaire n'est donc à ouvrir.

**POP3 (110/995) est volontairement absent.** Aucun client moderne ne l'utilise ; cela supprime
une surface d'attaque. Si un agent en a besoin, la règle NAT s'ajoutera à ce moment-là.

**Le port 465 (SMTPS implicite) est absent.** Le port 587 avec STARTTLS remplit le même rôle et
mieux supporté. Certains vieux clients Apple le réclament : à vérifier en recette, c'est une règle
NAT à ajouter le cas échéant.

Le port 4190 (ManageSieve) est souvent oublié. Sans lui, les filtres créés dans Roundcube ne
fonctionnent pas.

---

## 4. Décisions structurantes

### 4.1 Postfix ne touche jamais MariaDB directement

PostfixAdmin écrit les comptes en base. Postfix les reçoit via `postmap` dans un fichier plat
(`/etc/postfix/postfix_accounts.cf`) et ne lit rien d'autre.

**Conséquence :** si la base est compromise ou indisponible, Postfix **continue de livrer le
courrier**. Sans cette séparation, une panne de base signifie plus de messagerie du tout.

### 4.2 Un compte Unix par composant, aucun partage

| Compte | Rôle |
|---|---|
| `vmail` | Stockage des boîtes |
| `postfix` | MTA |
| `dovecot` | IMAP / Sieve |
| `clamav` | Antivirus |
| `_rspamd` | Filtre |
| `www-data` | Roundcube (PHP-FPM) |
| `pfa` | PostfixAdmin (PHP-FPM) — **compte distinct de Roundcube** |

**C'est la vraie frontière de sécurité.** Si du PHP s'exécute dans Roundcube, il ne peut pas lire
les boîtes mail. Aucun `include` croisé entre les deux arborescences.

### 4.3 Vhosts séparés

`webmail.meteomadagascar.mg` et `postfixadmin.meteomadagascar.mg` sont deux vhosts Apache
distincts, avec deux pools PHP-FPM distincts et deux comptes Unix distincts.

### 4.4 Le webmail passe par le Portail Météo (correction du 21 octobre 2026)

**Constat de terrain.** `mail.meteomadagascar.mg` est déjà servi par une plateforme interne de
gestion des sous-domaines (« Portail Météo »), qui occupe les ports **80 et 443** de
`41.207.49.27`. Cette plateforme ne fait **pas** de DNS : elle crée des **vhosts nginx** avec un
champ « IP cible », et sait délivrer un certificat par elle-même. `adl.meteomadagascar.mg` prouve
que le mécanisme fonctionne déjà.

**Conséquence directe :** notre Apache **ne peut pas** prendre le 443 public, et Let's Encrypt
**HTTP-01 est impossible** (port 80 déjà pris) comme **DNS-01** (pas d'API sur la zone, qui est
chez Stellarix). **La seule voie praticable pour un certificat valide sur `webmail.` est donc la
plateforme.**

**Architecture cible :**

```
Agent → https://webmail.meteomadagascar.mg
      → nginx du Portail          (TLS Let's Encrypt terminé ici)
      → proxy HTTP
      → http://<serveur mail>:8080  (Apache, HTTP simple)
      → Roundcube → IMAP/SMTP → Dovecot + Postfix
```

**`mail.` reste le nom SMTP/IMAP** (ports 25, 587, 993, 4190 pointés en direct sur le serveur
mail : le Portail n'y touche pas). **`webmail.` est le nom web**, en reverse-proxy. Le Portail
devient donc une dépendance du **webmail**, pas de la **messagerie** : s'il tombe, IMAP et SMTP
continuent de fonctionner.

**Le serveur mail n'écoute qu'en HTTP interne** : vhost `webmail` sur le port **8080**, vhost
`postfixadmin` sur le port **8081** (restreint au réseau interne de la DG et à l'IP du Portail).
Le TLS n'est jamais terminé deux fois.

**Trois réglages Roundcube sont obligatoires** dans ce mode (vérifiés dans le code de
Roundcube 1.7.4) :

| Réglage | Rôle | Conséquence de l'oubli |
|---|---|---|
| `use_https = true` | déclare la connexion sécurisée malgré l'absence de `$_SERVER['HTTPS']` | URLs générées en `http://…:8080` → *mixed content*, redirection HTTPS cassée |
| `proxy_whitelist = ['<IP du Portail>']` | seule l'IP du proxy est autorisée à injecter `X-Forwarded-*` | les en-têtes du proxy sont ignorés → hôte et port faux ; de plus, **tous les agents seraient vus sous l'IP du Portail** (conséquence sur `ip_check` et le rate-limit) |
| `trusted_host_patterns = ['webmail.meteomadagascar.mg', …]` | refuse un en-tête `Host` injecté | vol d'identifiants par en-tête `Host` |

**Le cas de routage** (un seul réglage à basculer à l'ouverture du SSH) : si le Portail est sur le
LAN → « IP cible » = IP **privée** du serveur mail ; sinon → IP **publique**. Le `dst-nat 443`
du § 5.2 est **à supprimer** dans les deux cas.

---

## 5. Conception réseau MikroTik

Le MikroTik assure deux fonctions : traduction des ports entrants vers le serveur mail, et
masquillage du trafic sortant.

### 5.1 Interfaces

| Interface | Rôle |
|---|---|
| `ether1` — WAN | `41.207.49.27`, passerelle YAS |
| `ether2` — LAN | réseau Météo |

### 5.2 Traduction d'adresses

`<IP_PRIVEE_MAIL>` est un paramètre : l'adresse privée réelle du serveur, **fixée en phase B1**
(recette). Toutes les règles dst-nat la partagent.

```routeros
# Trafic SORTANT : le serveur mail devient 41.207.49.27
/ip firewall nat
add chain=srcnat action=masquerade out-interface=ether1 out-address-list=mailservers

# Trafic ENTRANT : uniquement les ports nécessaires
add chain=dstnat action=dst-nat protocol=tcp in-interface=ether1 dst-port=25  to-addresses=<IP_PRIVEE_MAIL>
add chain=dstnat action=dst-nat protocol=tcp in-interface=ether1 dst-port=587 to-addresses=<IP_PRIVEE_MAIL>
add chain=dstnat action=dst-nat protocol=tcp in-interface=ether1 dst-port=993 to-addresses=<IP_PRIVEE_MAIL>
add chain=dstnat action=dst-nat protocol=tcp in-interface=ether1 dst-port=4190 to-addresses=<IP_PRIVEE_MAIL>
```

> ⚠️ **Correction du 21 octobre 2026.** La règle `dst-port=443` a été **retirée** : le 443 public
> de `41.207.49.27` est **déjà tenu par le Portail Météo** (voir § 4.4). Le webmail y arrive par
> le reverse-proxy du Portail, pas par une redirection de port. Le 443 n'est donc **ni ouvert ni
> redirigé** par le MikroTik.

**Note sur le port 80.** Let's Encrypt n'a besoin du port 80 que **pendant l'émission du
certificat** (challenge HTTP-01). Une fois le certificat obtenu, cette redirection peut être
supprimée — c'est une réduction d'attaque gratuite.

> ⚠️ **Correction du 21 octobre 2026.** Cette option est **caduc** : le port 80 public est déjà
> pris par le Portail, et le certificat de `webmail.` est **délivré par la plateforme** (route
> `/ssl` de son API), pas par Let's Encrypt sur notre IP. **Ni HTTP-01 ni DNS-01 ne sont donc
> applicables** : le renouvellement du certificat `webmail.` relève de l'équipe qui administre le
> Portail, et non de nous. Le certificat du **serveur mail lui-même** (aucun nom public n'est
> directement servi par Apache) n'est pas concerné.

**Le masquillage ne doit s'appliquer qu'aux serveurs de la liste `mailservers`.** Un masquilage
appliqué à tout le LAN peut réécrire le trafic de réponse d'un SMTP entrant, au point où Postfix
se voit livrer son propre courrier.

### 5.3 Pare-feu

```routeros
/ip firewall filter
add chain=input action=accept connection-state=established,related
add chain=input action=drop   connection-state=invalid
add chain=input action=accept protocol=icmp
add chain=input action=drop   in-interface=ether1

add chain=forward action=drop   connection-state=invalid
add chain=forward action=accept connection-state=established,related
add chain=forward action=drop   in-interface=ether1 connection-nat-state=!dstnat
```

### 5.4 Limitation du port 25

Seul le port 25 est bridé. Un serveur compromis qui envoie des milliers de messages d'un coup
fait blacklister l'IP par Gmail, et la messagerie sortante est perdue pour des semaines.

```routeros
/ip firewall filter
add chain=forward action=drop connection-nat-state=dstnat protocol=tcp \
    dst-port=25 connection-rate=20/min address-list=mta-abus
```

Aucun autre poste du LAN ne sort en SMTP :

```routeros
/ip firewall nat
add chain=srcnat action=reject out-interface=ether1 protocol=tcp \
    dst-port=25 out-address-list=!mailservers
```

### 5.5 Durcissement du routeur

```routeros
/ip service
set telnet  disabled=yes
set ftp     disabled=yes
set www     disabled=yes
set api     disabled=yes
set www-ssl disabled=yes

/ip upnp enabled=no
```

Le routeur est physiquement dans les locaux : `www` et `api` désactivés suppriment une surface
d'attaque majeure.

---

## 6. DNS et identité de domaine

Le DNS déclare au monde entier l'existence légitime du serveur. Deux familles distinctes, souvent
confondues :

| | ÉMISSION (envoyer) | RÉCEPTION (recevoir) |
|---|---|---|
| Risque | le serveur est utilisé pour du spam → IP blacklistsée | le serveur est intrusif ou lent → courrier ignoré |
| Enregistrements | **SPF, DKIM, DMARC** | **MX, PTR** |
| Vérifié par | le serveur du destinataire | le serveur de l'expéditeur |

> SPF, DKIM et DMARC protègent la réputation en sortie. MX et PTR protègent l'existence en
> entrée. Les deux sont indispensables : sans PTR, l'envoi vers Gmail fonctionne mais le
> courrier des agents en provenance de Gmail n'arrive jamais.

### 6.1 Identité du serveur

| Enregistrement | Valeur | Rôle |
|---|---|---|
| `mail.meteomadagascar.mg` | A → `41.207.49.27` | adresse physique du serveur — **existe déjà** |
| `meteomadagascar.mg` | MX 10 → `mail.meteomadagascar.mg` | destination du courrier du domaine |

### 6.2 Authentification des envois

| Enregistrement | Rôle |
|---|---|
| **SPF** | autorise uniquement `41.207.49.27` à émettre pour le domaine |
| **DKIM** | signature cryptographique par Rspamd, clef publique publiée |
| **DMARC** | consigne aux destinataires que faire si SPF et DKIM échouent tous deux |

**Ordre impératif :** SPF et DKIM doivent être en place **avant** d'activer DMARC. L'inverse fait
rejeter les envois légitimes.

**DMARC se déploie en trois temps :** `p=none` (observation) pendant 2 à 4 semaines → lecture des
rapports `rua` → `p=quarantine` → `p=reject`. C'est le seul déploiement sans risque de perdre du
courrier.

**Attention SPF :** un seul enregistrement est autorisé. Si un SPF existe déjà, il faut le fusionner,
jamais en ajouter un second.

### 6.3 Confort des agents

| Enregistrement | Rôle | Qui le crée |
|---|---|---|
| `autodiscover.meteomadagascar.mg` | Outlook et Thunderbird découvrent le serveur seuls | zone DNS (Stellarix) |
| `autoconfig.meteomadagascar.mg` | idem pour les autres clients | zone DNS (Stellarix) |
| `webmail.meteomadagascar.mg` | webmail, en reverse-proxy derrière le Portail | **le Portail** (voir § 4.4) + zone DNS |
| `postfixadmin.meteomadagascar.mg` | console d'administration, **restreinte au réseau interne** | zone DNS (Stellarix), sans pointerie publique |

> **Correction du 21 octobre 2026.** `webmail.meteomadagascar.mg` **n'existait pas** au moment de la
> vérification DNS, et `mail.meteomadagascar.mg` est **déjà occupé par le Portail**. La
> création du sous-domaine `webmail.` et la délivrance de son certificat relèvent de
> **l'équipe qui administre le Portail** (son API pilote la configuration nginx et sait délivrer
> un certificat), et non de nous.

### 6.4 La console d'administration n'est pas publique

`postfixadmin.meteomadagascar.mg` crée les comptes et change les mots de passe. Un intrus qui y
entre prend le contrôle de toute la messagerie.

→ Aucun enregistrement DNS public, ou enregistrement public **et** blocage au niveau du serveur
web qui n'accepte que les adresses du réseau interne de la Météo. L'administrateur y accède depuis
le bureau. Les agents n'y ont jamais accès.

**Mise en œuvre retenue :** le vhost d'administration écoute sur le port **8081** et la règle
Apache est une liste blanche (`Require ip`) : boucle locale + plage réseau de la DG + IP du
Portail. Aucun nom public ne pointe donc vers lui. Le DNS n'est même pas nécessaire pour y accéder
depuis le LAN.

### 6.5 Précaution Cloudflare

Le site est derrière Cloudflare. `mail.meteomadagascar.mg` doit être en **nuage gris (DNS seul)**.
Passé en nuage orange, le trafic SMTP et IMAP ne fonctionnerait pas — le proxy ne relaie pas ces
protocoles. À vérifier avant toute chose.

> **Correction du 21 octobre 2026.** La zone DNS de `meteomadagascar.mg` n'est **pas** chez
> Cloudflare mais chez **Stellarix** (serveurs `ns.stellarix.africa`). La précaution reste
> applicable en principe (aucun enregistrement de messagerie ne doit passer en proxy), mais
> **c'est Stellarix qu'il faut contacter**, et non Cloudflare. Le site `www.meteomadagascar.mg`
> (`102.16.63.110`) est, lui, bien derrière Cloudflare — et n'est pas touché par ce projet.

### 6.6 Reverse DNS (prerequisite bloquant)

```
41.207.49.27 → mail.meteomadagascar.mg
```

À obtenir de YAS. **C'est le chemin critique du projet** : sans PTR, les signatures DKIM sont
valides et l'envoi fonctionne, mais le courrier reçu depuis Gmail et Outlook arrive en spam ou
n'arrive pas. Le déploiement technique peut réussir et la messagerie rester inutilisable.

---

## 7. Sécurité

### 7.1 Cinq barrières

```
Internet │
   ├─① MikroTik        pare-feu + limitation port 25
   ├─② Serveur         durcissement noyau + TLS obligatoire
   ├─③ Rspamd          antispam, antivirus, anti-débit
   ├─④ Dovecot         quota + anti-bruteforce sur l'accès
   └─⑤ Roundcube       limitation des tentatives de connexion
```

### 7.2 Chiffrement des transports

| Emplacement | Exigence |
|---|---|
| Soumission (587) | STARTTLS obligatoire, sinon refus de l'authentification |
| IMAP (993) | TLS dès la connexion, jamais antérieur à TLS 1.2 |
| SMTP entrant (25) | TLS **optionnel** — imposé par certains Gmail, refusé par d'autres segments antérieurs |
| Webmail (443) | TLS obligatoire, **terminé par le Portail** (voir § 4.4) |

Le SMTP entrant reste tolérant : refuser les messages sans TLS casserait la réception depuis des
réseaux d'états africains.

> ⚠️ **Correction du 21 octobre 2026.** Ce paragraphe annonçait un certificat Let's Encrypt
> unique couvrant `mail`, `webmail` et `postfixadmin`, obtenu en HTTP-01 « car le port 80 est
> libre ». **Les deux présupposés sont faux** : le port 80 est tenu par le Portail (HTTP-01
> impossible) et la zone DNS est chez Stellarix, sans API (DNS-01 impossible).
> **Conséquence :** le certificat de `webmail.` est **délivré par le Portail** (route `/ssl` de
> son API). Aucun nom public n'est plus directement servi par notre Apache, qui ne travaille
> qu'en **HTTP interne** (8080 / 8081) entre le Portail et lui — le saut du Portail vers notre
> serveur se fait en clair **sur le réseau interne**, ce qui est acceptable si et seulement si
> ce réseau est maîtrisé (à vérifier : si le réseau n'est pas maîtrisé, ce saut doit être
> chiffré). `postfixadmin.` n'a pas d'enregistrement public et reste accessible en 8081 par
> liste blanche d'adresses.

### 7.3 Fail2ban

| Prison | Déclencheur |
|---|---|
| `sshd` | échecs SSH |
| `postfix-sasl` | échec d'authentification en soumission |
| `dovecot` | échec IMAP |
| `roundcube-login` | échec sur le webmail |
| `postfix-admin` | échec sur la console d'administration |

**Point critique :** par défaut Fail2ban ne sait pas lire les journaux de Roundcube. Un filtre
supplémentaire, capable de reconnaître la ligne d'échec, est indispensable. Sans lui, la prison
existe mais ne se déclenche jamais.

### 7.4 Rspamd

| Module | Effet |
|---|---|
| `ratelimit` | plafond par boîte et global — empêche l'usage du serveur comme relais |
| `antivirus` | ClamAV sur les pièces jointes uniquement |
| `dkim` / `spf` / `dmarc` | authentification des messages reçus |
| `bayes` | apprentissage sur les messages légitimes du personnel |
| `greylisting` | retarde le premier message d'un expéditeur inconnu |

`ratelimit` est le module le plus sous-estimé : c'est lui qui empêche qu'une boîte compromise ne
fasse glisser la réputation de tout le serveur.

**ClamAV n'analyse que les pièces jointes**, pas les corps de mail. À cette échelle, un scan
complet ferait chuter visiblement la délivrabilité pour un bénéfice faible — la surface d'attaque
réelle d'une messagerie institutionnelle, ce sont les pièces jointes.

> **Validé en labo le 21 octobre 2026** (ClamAV 1.5.4, test de référence à 4 cas) : message sain
> **accepté** ; pièce jointe binaire EICAR **refusée** (554 5.7.1) ; pièce jointe **texte** EICAR
> **refusée** ; EICAR placé dans le **corps** **accepté** — le corps n'est jamais scanné, comme
> voulu. Une surprise favorable : contrairement à ce que la documentation du module laisse croire,
> les pièces jointes de type texte **sont** analysées. La surface réelle est donc : toute pièce
> jointe jusqu'à 20 Mo est analysée, le corps ne l'est pas.

> **Version de Rspamd — le dépôt officiel, pas les paquets de la distribution.** Rspamd 4.x est
> installé depuis le dépôt officiel `rspamd.com` (clé GPG + `apt-stable`), **pas** depuis les
> paquets de la distribution : ceux-ci fournissent 2.7, que le projet ne supporte plus, et
> valideraient en laboratoire une pile que la production n'exécutera pas. Le scanner ClamAV est
> joigné **en TCP sur 127.0.0.1:3310** (le socket Unix `clamd.ctl` n'est pas exploitable par le
> module). Deux conséquences à connaître avant toute intervention : la **ligne de base du score change**
> entre les versions (0.95 en 2.7, ≈0 en 4.2.2 pour un message sain ; le seuil de rejet reste à
> 15), et une **désinstallation du paquet emporte le répertoire `/var/lib/rspamd/dkim`** — donc la
> clé privée de signature, qu'il faut **restaurer depuis la sauvegarde** avant de purger.
> Détail opératoire : la configuration de `local.d` s'inclut **à l'intérieur** du bloc de son
> module. Un fichier de `local.d` qui redéclarerait l'enveloppe (`antivirus { antivirus { … } }`)
> produirait une section imbriquée — Rspamd la signale « nested section » puis **ignore le
> module**, sans scanner la moindre pièce jointe et sans message d'erreur visible du côté
> Postfix. Les fichiers de `local.d` ne contiennent donc **que le corps** de leur module.

### 7.5 Durcissement des composants

**Postfix** : pas d'open relay, pas de `vrfy`/`etrn` (recensement d'utilisateurs), rejet des
destinataires inconnus, plafond global d'envoi quotidien par boîte.

**Dovecot** : IMAP en clair et POP3 désactivés — seul 993 subsiste. Une connexion sans TLS est
refusée, pas seulement dépréciée.

**Noyau** : cookies TCP anti-SYN, filtres anti-IP-forged, mises à jour de sécurité automatiques.

**Disque** : pas de chiffrement au repos — le local serveur est sécurisé, le risque de vol physique
est couvert autrement, et le chiffrement ne complique que la récupération après incident.

**Horloge** : NTP obligatoire. Si l'horloge du serveur est décalée de plus de quelques minutes, les
signatures DKIM deviennent invalides et Gmail/Outlook rejettent le courrier. C'est une cause
fréquente de « tout est installé et rien n'arrive ».

**Résolveur DNS** : `unbound` local plutôt que `8.8.8.8`, pour ne pas dépendre d'un service
étranger pour la résolution des MX.

### 7.6 Point à vérifier en recette : le site envoie-t-il du courriel ?

Si le site `meteomadagascar.mg` envoie des messages en `@meteomadagascar.mg` (formulaire de
contact, inscription à une newsletter, mot de passe oublié), il est hors de l'IP déclarée dans le
SPF, et son courrier sera jeté ou classé en spam. Si son hébergeur n'a pas configuré DKIM, il
sera rejeté purement et simplement.

→ Cette vérification appartient à la phase de recette, pas au déploiement.

### 7.7 Vérifier que ça marche

1. Test vers une adresse Gmail et une Outlook réelles, avec une vraie conversation derrière. Le
   premier message d'un nouveau serveur atterrit presque toujours en spam, même parfaitement configuré.
2. `mail-tester.com` sur plusieurs messages réels — objectif ≥ 9/10.
3. Vérification que MX, SPF, DKIM et DMARC sont publics et corrects.
4. Test d'open relay : un serveur externe ne doit pas pouvoir s'appuyer sur le nôtre.
5. Test de réception en port 25 depuis l'extérieur.

### 7.8 Surveillance

| Signal | Ce qu'il indique |
|---|---|
| Journaux Rspamd | bascule de la répartition spam/légitime |
| Statistiques Postfix | pic d'envoi ou de rejet inhabituel |
| Rapports DMARC `rua` | qui usurpe notre domaine |

Sans surveillance, un problème de réputation se découvre quand les agents se plaignent — trop tard.

---

## 8. Gestion des comptes des agents

### 8.1 Convention de nommage

Format : `prenom.nom@meteomadagascar.mg`

**(a) Accents** — les noms malgaches sont déjà en ASCII, mais pas les prénoms d'origine française
(*Éric, François, Hélène, Céline, Benoît*).

→ Règle : translittération ASCII non accentuée — `eric.rasolofoniaina`, `helene.rakoto`.

**(b) Traits d'union et apostrophes** — *Jean-Claude*, *N'Andrianina*, *Sambatra*.

→ `jean-claude.rasoanaivo` (le trait d'union est autorisé). L'apostrophe est supprimée :
`nandrianina.rasoanaivo`.

**(c) Homonymes** — le vrai problème. *Rakoto*, *Rasoa*, *Ramanana*, *Andrianina* sont parmi les
noms les plus fréquents. Un service de prévision aura plusieurs « Jean Rakoto ».

→ Règle : `prenom.nom`, et en cas de collision, suffixe numérique automatique :
`jean.rakoto2`, `jean.rakoto3`.

**Principe qui gouverne tous les autres : une adresse ne change jamais.** Un agent qui l'a
communiquée pendant trois ans ne doit pas la voir disparaître. Si un nom change, on crée un
nouveau compte et on redirige l'ancien.

### 8.2 Aucun compte Unix par agent

Avec PostfixAdmin et Dovecot, les 500 agents ne génèrent pas 500 comptes Unix : Dovecot lit les
utilisateurs et mots de passe directement en base.

Créer un agent = une ligne en base. Et surtout, aucune surface d'attaque supplémentaire.

### 8.3 Trois types d'adresses

| Type | Exemple | Rôle |
|---|---|---|
| Compte personnel | `prenom.nom@` | boîte de l'agent, gérée par lui |
| Adresse de service | `direction@`, `prevision@`, `informatique@` | point d'entrée stable d'un service |
| Adresse de diffusion | `staff@`, `cadres@` | un message, plusieurs destinataires |

Les adresses de service ne stockent rien et se ré-expédient. On peut nommer `prevision@` au
service et remplacer l'abonné plus tard sans que rien ne change pour la DDS.

**Hors périmètre :** les listes de discussion (archives, abonnement) nécessitent un logiciel
distinct (Sympa, Mailman). Inutile pour une messagerie de service. On se limite aux alias.

### 8.4 Deux bases de données séparées

| Base | Contenu | Utilisée par |
|---|---|---|
| `postfix` | comptes, mots de passe, quotas, alias | PostfixAdmin |
| `roundcube` | sessions, contacts, brouillons, filtres | Roundcube |

**Deux bases, deux utilisateurs MySQL distincts, aucun droit croisé.**

Roundcube est du PHP exposé sur Internet : c'est la cible n°1. Si un attaquant y obtient
l'exécution de code, il récupère les sessions — **pas** les 500 comptes et leurs mots de passe.
Sans cette séparation, une seule intrusion réussie dans Roundcube donne toute la messagerie.

### 8.5 Authentification des agents

Chaque agent possède son propre login `prenom.nom` et son propre mot de passe, valide sur l'ensemble
des accès : IMAP (993), soumission (587) et webmail.

| Règle | Choix | Raison |
|---|---|---|
| Algorithme | Argon2id, ou bcrypt si indisponible | MD5 est cassable en quelques secondes |
| Longueur | 12 caractères minimum | la longueur compte plus que la complexité |
| Première connexion | changement imposé | permet une création en masse avec mot de passe provisoire |
| Limitation | anti-bruteforce sur webmail et IMAP | une liste de mots de passe courants est bloquée |

Les règles du type « 1 caractère spécial, 1 chiffre » produisent `Meteo2024!` que tout le monde
devine. 12 caractères de mots normaux sont plus sûrs et moins pénibles.

**Protection de la console d'administration :** accès réservé au réseau interne **et** mot de passe
d'administration. Le 2FA n'existe pas nativement dans PostfixAdmin et nécessiterait un composant
tiers — écarté de la version 1.

**Sessions web :** durée courte avec expiration et avertissement avant déconnexion. Un agent de
station régionale sur un poste partagé au cybercafé ne doit pas laisser sa boîte ouverte. Une
session Roundcube expirée ne ferme pas la session IMAP — d'où l'importance de sessions courtes.

### 8.6 Quotas

| Profil | Quota |
|---|---|
| Directeur, cadre avec archivage | 5 Go |
| Agent standard | 2 Go |
| Station régionale (rapports, images radar) | 3 Go |
| Comptes de service | aucun — ils ne stockent pas |

Maximum théorique : 500 × 2 Go = **1 To**, sur 2 To utiles. La marge est réelle.

Le quota est appliqué par **Dovecot**, pas par Postfix. Un agent qui le dépasse reçoit une alerte,
et sa boîte en débordement est conservée 5 jours le temps qu'il trie. Personne ne perd de
courrier.

### 8.7 Création des 500 comptes

Créer 500 comptes un par un prend des jours. La méthode :

1. **Source unique de vérité** : export du fichier du personnel en CSV. Pas de double saisie.
2. **Génération des adresses en masse** : minuscules, sans accents, apostrophes supprimées,
   collision → suffixe numérique.
3. **Import en une passe**, chaque ligne portant adresse, nom complet et quota.
4. **Mots de passe provisoires**, changement imposé à la première connexion.
5. **Vérification** : comparer le nombre d'importés au nombre attendu et vérifier 5 comptes au hasard.

**Point d'honnêteté :** une adresse générée automatiquement ne doit jamais être publiée sans
vérification humaine. `randriamampionona.rasoanaivo@` peut appartenir à deux personnes, et une
adresse fausse communiquée à un partenaire externe est très difficile à corriger. Le CSV doit être
relu par le service RH ou par l'encadrant.

---

## 9. Dimensionnement du serveur

| Poste | Spécification | Rôle |
|---|---|---|
| CPU | 8 cœurs | les workers ClamAV sont CPU-bound |
| RAM | **32 Go** | poste le plus souvent sous-budgété : ClamAV, Rspamd, index Dovecot, MariaDB, PHP-FPM |
| Système | 1 × 256 Go SSD | Debian sur disque séparé |
| Messagerie | 2 × 2 To SSD en **RAID 1** → 2 To utiles | 500 × 2 Go de quota maximum |
| Sauvegarde | 2 × 4 To HDD en RAID 1 | hors du tableau mail, sinon les deux ensembles tombent ensemble |

Ce tableau est une **cible**, pas un constat. La recette établira la configuration réelle et
adaptera le dimensionnement si nécessaire. Le design tient dans les deux cas ; seule la phase de
recette change.

---

## 10. Plan de sauvegarde

### 10.1 Périmètre

| Donnée | Sauvegardée |
|---|---|
| Bases `postfix` + `roundcube` | oui |
| Boîtes Maildir (500) | oui |
| Configuration système des services | oui |
| Certificat Let's Encrypt | oui |
| **Clés DKIM / RSA** | oui — **critique**, sans la clef privée tout l'envoi authentifié casse |
| Fichiers temporaires, journaux | non |
| Système d'exploitation | non |

### 10.2 Restic plutôt que rsync

| | rsync | Restic |
|---|---|---|
| Coût d'une sauvegarde quotidienne | proche du total | 1 à 5 % du volume |
| Fenêtre nocturne | 4 à 6 h | ~30 min |
| Corruption pendant la sauvegarde | visible et exploitable | snapshots cohérents |
| Version de la veille | non | oui |
| Chiffrement du dépôt | à faire à part | intégré |

Le chiffrement du dépôt est le point décisif : un disque de sauvegarde volé ne contient pas les
courriels de 500 agents.

### 10.3 Rythme

| Niveau | Contenu | Fréquence | Rétention |
|---|---|---|---|
| Complet initial | tout | une fois, avant ouverture du service | 7 versions |
| Quotidien | boîtes + bases | chaque nuit 01:00 | 7 jours |
| Déporté | copie du dépôt Restic | chaque semaine | hors du site |

Le **complet initial** est l'étape qu'on oublie toujours, et c'est celle qui compte le plus : les
sauvegardes incrémentales sont inutilisables sans leur base.

### 10.4 Le point faible de tout plan : la restauration

**Une sauvegarde jamais restaurée n'est pas une sauvegarde.** C'est le seul critère de qualité.

> **Test obligatoire avant ouverture du service :** restaurer une boîte complète sur le poste d'un
> agent pilote et vérifier qu'il retrouve tous ses messages, ses dossiers, ses filtres et ses
> contacts, avec les dates de réception intactes.

Test répété **une fois par an** ensuite, sur un échantillon.

### 10.5 Objectifs de reprise

| Paramètre | Valeur |
|---|---|
| RPO (perte de données maximale) | 24 h |
| RTO (délai de reprise du service) | 4 h sur serveur reconstruit |

Une erreur de suppression faite à 14 h est récupérable à partir du soir même. Au-delà de 24 h, elle
ne l'est plus. C'est la limite du plan, et elle doit être connue.

### 10.6 Organisation matérielle

Les disques de sauvegarde sont **physiquement séparés** du RAID de messagerie. Sur la même machine,
si le boîtier ou le contrôleur tombe, les données et leur sauvegarde disparaissent ensemble.

Complément : une copie hebdomadaire sur disque chiffré, sortie du bâtiment.

---

## 11. Séquencement

### Partie A — réalisable dès aujourd'hui, sans accès serveur

| # | Action | Dépendance |
|---|---|---|
| A1 | Demande de PTR à YAS | **chemin critique** — peut prendre des semaines |
| A2 | Enregistrement DNS : MX, SPF, `autodiscover`, sous-domaines web | contrôle de la zone — disponible |
| A3 | Configuration MikroTik : NAT + pare-feu | accès admin routeur — disponible |
| A4 | Validation du matériel : 32 Go RAM + RAID 1 | budget |
| **A5** | **Sous-domaine `webmail.` + certificat, créés par le Portail** | **équipe qui administre le Portail** — voir § 4.4. Sans lui, le webmail n'a pas de certificat valide. |
| **A6** | **Enregistrement DNS `dkim._domainkey`** (clé publique produite par le serveur) | zone DNS — **doit suivre A1 et précéder l'activation du DMARC** |

### Partie B — nécessite l'accès SSH au serveur

| # | Action | Sortie attendue |
|---|---|---|
| B1 | Recette de la machine réelle | rapport OS, CPU, RAM, disques, réseau |
| B2 | Durcissement système + installation de la pile | composants fonctionnels |
| B3 | Création de 3 à 5 comptes pilotes | test d'usage réel |
| B4 | Tests de délivrabilité | score ≥ 9/10, Gmail et Outlook |
| B5 | Sauvegarde complète + **test de restauration** | preuve que le plan fonctionne |
| B6 | Import des 500 comptes | les 500 comptes créés |

### Critères d'ouverture

Le service n'ouvre que si les cinq tests suivants passent :

1. **Réception** depuis Gmail et Outlook — le message arrive en boîte de réception
2. **Envoi** vers Gmail et Outlook — score ≥ 9/10, boîte de réception
3. **Open relay** — un serveur externe ne peut pas envoyer via le nôtre
4. **Webmail** — création, envoi, réponse, pièce jointe, filtre, sur Firefox et Chrome
5. **Restauration** — une boîte restaurée à l'identique, dates de réception comprises

### Phase pilote

1. Créer 5 comptes pilotes (encadrant + agents volontaires).
2. Faire tourner les 5 tests sur des usages réels pendant 2 semaines.
3. Corriger ce qui casse.
4. Importer les 500 comptes seulement ensuite.

Deux semaines de pilote coûtent infiniment moins cher que 500 agents découvrant le premier jour
que les pièces jointes Excel ne s'ouvrent pas.

---

## 12. Risques identifiés

| Risque | Impact | Traitement |
|---|---|---|
| PTR non obtenu de YAS | réception inutilisable malgré un déploiement réussi | demande lancée en priorité, A1 |
| Matériel insuffisant vs cible 32 Go | performances dégradées avec 500 agents | recette B1 avant déploiement |
| IP blacklistsée | messagerie sortante perdue des semaines | limitation port 25, `ratelimit`, plafond d'envoi |
| DMARC activé trop tôt | envois légitimes rejetés | déploiement `p=none` → `quarantine` → `reject` |
| Le site envoie en `@meteomadagascar.mg` hors SPF/DKIM | courriels du site jetés | vérification en recette B1 |
| Sauvegarde jamais testée | perte totale en cas d'incident | test de restauration obligatoire B5 |
| Attaque sur Roundcube | compromission de 500 comptes | deux bases séparées, comptes Unix distincts |
| Recensement d'utilisateurs | fuite de la liste des agents | `vrfy`/`etrn` désactivés, postmaster en.no-reply |

---

## 13. Hors périmètre (reporté)

- Migration de boîtes existantes : le domaine `@meteomadagascar.mg` est nouveau, aucune migration.
- Listes de discussion (Sympa, Mailman) : à ajouter si un besoin apparaît.
- Recherche full-text avec Solr : `fts = maildir` suffit à cette échelle.
- POP3 / SMTP port 465 : ajoutables par une règle NAT si un client le réclame.
- Chiffrement du disque au repos : local serveur sécurisé, risque couvert autrement.
- Double serveur (mail / webmail) : documenté comme plan B si une disponibilité contractuelle
  est exigée.
- 2FA sur la console d'administration : non natif dans PostfixAdmin, hors version 1.

---

## 14. Journal des corrections de ce document

Ce document a été écrit **avant** toute vérification sur le terrain. Les paragraphes ci-dessous
ont été **corrigés** le 21 octobre 2026, après constat sur l'infrastructure existante et
validation en laboratoire. Ils sont conservés en place (et non réécrits) pour que la trace du
raisonnement reste visible.

| § | Ce qui était écrit | Ce qui est vrai |
|---|---|---|
| 1.1 | « les ports 80 et 443 de `41.207.49.27` sont libres » | **faux** : le Portail Météo les tient déjà (il y sert `mail.` et `adl.`) |
| 3.3 | ports ouverts 25, 587, 993, 4190, **443**, 80 temporaire | seuls **25, 587, 993, 4190** sont ouverts ; le webmail passe par le Portail |
| 4.3 | (inexistant) | nouveau § 4.4 : architecture du reverse-proxy du Portail et les trois réglages Roundcube obligatoires |
| 5.2 | `dst-nat` sur 443, port 80 pour Let's Encrypt | règle 443 **retirée** ; HTTP-01 et DNS-01 **impossibles** |
| 6.3 | `webmail.` comme enregistrement ordinaire | créé par le **Portail**, pas par la zone DNS |
| 6.5 | « le site est derrière Cloudflare » | la zone DNS est chez **Stellarix** ; le site est bien derrière Cloudflare, mais sur une autre IP |
| 7.2 | un certificat Let's Encrypt unique, HTTP-01 possible | certificat de `webmail.` **délivré par le Portail** ; notre Apache ne sert qu'en HTTP interne |
| 7.4 | ClamAV prévu | **validé en labo** : 4/4 au test EICAR, le corps n'est jamais scanné |
| 7.4 | (version de Rspamd non précisée) | **Rspamd 4.2.2 depuis le dépôt officiel** (les paquets de la distribution fournissent 2.7, non supporté) — la pile du labo est désormais identique à celle de la production |
| 11 | Partie A = PTR, DNS, MikroTik, matériel | **+ A5** (sous-domaine et certificat via le Portail) et **+ A6** (enregistrement DKIM) |

**La leçon à retenir** : les hypothèses de conception fondées sur une infrastructure décrite de
seconde main (« les ports sont libres ») ont été fausses, et une seule d'entre elles — le 443
déjà pris — a changé l'architecture. **Toute affirmation sur l'infrastructure existante doit être
vérifiée avant d'en dépendre**, a fortiori quand elle est au centre d'un plan.

**Où est la suite ?** Le carnet d'exécution `docs/superpowers/plans/2026-10-14-labo-mail-execution.md`
contient l'état réel du laboratoire (34/34 aux critères de validation, sauvegarde et restauration
validées, open relay 4/4, DKIM signé, antivirus opérationnel), le tableau des divergences
labo/production (D1 à D24) et la checklist de ce qui reste à demander à l'encadrant.