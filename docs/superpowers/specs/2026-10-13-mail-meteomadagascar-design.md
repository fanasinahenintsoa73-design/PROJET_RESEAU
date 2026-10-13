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

Le site web étant derrière Cloudflare sur une autre IP, **les ports 80 et 443 de `41.207.49.27`
sont libres**. Il n'y a aucun conflit de port, aucun partage de NAT et aucune raison de toucher
à la configuration du site existant. C'est ce qui rend ce déploiement simple et sans risque
pour la production en place.

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
| **ClamAV** | Analyse des pièces jointes via Rspamd | socket Unix |
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
443/tcp   Roundcube + PostfixAdmin
80/tcp    temporaire : uniquement l'émission du certificat Let's Encrypt (HTTP-01)
```

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
add chain=dstnat action=dst-nat protocol=tcp in-interface=ether1 dst-port=443 to-addresses=<IP_PRIVEE_MAIL>
```

**Note sur le port 80.** Let's Encrypt n'a besoin du port 80 que **pendant l'émission du
certificat** (challenge HTTP-01). Une fois le certificat obtenu, cette redirection peut être
supprimée — c'est une réduction d'attaque gratuite. Deux options au choix :

- **HTTP-01 (recommandé ici)** : ouvrir 80 le temps de l'émission, puis le fermer. Aucun
  mécanisme de renouvellement automatique à maintenir.
- **DNS-01** : 80 reste fermé en permanence, mais le renouvellement exige un accès API à la zone
  DNS. À retenir si le port 80 doit être fermé même temporairement.

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

| Enregistrement | Rôle |
|---|---|
| `autodiscover.meteomadagascar.mg` | Outlook et Thunderbird découvrent le serveur seuls |
| `autoconfig.meteomadagascar.mg` | idem pour les autres clients |
| `webmail.meteomadagascar.mg` | webmail, séparé du serveur pour permettre un durcissement distinct |
| `postfixadmin.meteomadagascar.mg` | console d'administration |

### 6.4 La console d'administration n'est pas publique

`postfixadmin.meteomadagascar.mg` crée les comptes et change les mots de passe. Un intrus qui y
entre prend le contrôle de toute la messagerie.

→ Aucun enregistrement DNS public, ou enregistrement public **et** blocage au niveau du serveur
web qui n'accepte que les adresses du réseau interne de la Météo. L'administrateur y accède depuis
le bureau. Les agents n'y ont jamais accès.

### 6.5 Précaution Cloudflare

Le site est derrière Cloudflare. `mail.meteomadagascar.mg` doit être en **nuage gris (DNS seul)**.
Passé en nuage orange, le trafic SMTP et IMAP ne fonctionnerait pas — le proxy ne relaie pas ces
protocoles. À vérifier avant toute chose.

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

Un certificat Let's Encrypt couvre `mail`, `webmail` et `postfixadmin`. HTTP-01 est possible car
le port 80 est libre.

| Emplacement | Exigence |
|---|---|
| Soumission (587) | STARTTLS obligatoire, sinon refus de l'authentification |
| IMAP (993) | TLS dès la connexion, jamais antérieur à TLS 1.2 |
| SMTP entrant (25) | TLS **optionnel** — imposé par certains Gmail, refusé par d'autres segments antérieurs |
| Webmail / admin (443) | TLS obligatoire |

Le SMTP entrant reste tolérant : refuser les messages sans TLS casserait la réception depuis des
réseaux d'états africains.

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