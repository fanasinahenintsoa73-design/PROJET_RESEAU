---
type: handoff
status: active
updated: 2026-11-03
---
# Passation

Webmail de Météo Madagascar : un skin Roundcube dans `labo/skins/meteo`, déployé sur une VM de labo. Ce fichier porte l'état courant ; `docs/handoffs/` contient un enregistrement par changement majeur.

## Où cela tourne

| Élément | Emplacement |
|---|---|
| Dépôt de référence | https://github.com/fanasinahenintsoa73-design/PROJET_RESEAU (public, branche `main`) |
| Clone de travail (PC Windows) | `C:\MAIL_MESSAGERIE`, remote `origin` = GitHub |
| Miroir sur le poste | dépôt nu `C:\repos\mail.git`, remote `desktop` |
| Source du skin | `labo/skins/meteo/` : `meteo.js`, `styles/meteo.css`, `templates/mail.html` |
| Cible de déploiement | `messagerie@127.0.0.1:2222`, fichiers dans `/var/www/roundcube/skins/meteo/` |
| Clé de déploiement | `C:\Users\WINDOWS 10\.ssh\meteo_labo` — nouvelle clé du 2026-11-03, **pas encore autorisée sur la VM** ; l'ancienne `%TEMP%\opencode\labo_agent` a été effacée par le nettoyage temporaire de Windows |
| URL du labo | https://webmail.meteo-test.lan/ et https://127.0.0.1:8443/ |
| Compte du labo | luc.ranaivo@meteo-test.lan, mot de passe dans le provisionnement du labo |

## Comment le travail circule

GitHub est le stockage et la source des mises à jour. N'importe quelle machine le clone :

    git clone https://github.com/fanasinahenintsoa73-design/PROJET_RESEAU.git C:/MAIL_MESSAGERIE

Le dépôt est public : le clone ne demande aucune clé. Le push demande un compte : HTTPS via l'aide d'identification `gh` déjà configurée sur ce PC (`gh auth status`), ou une clé SSH ajoutée au compte GitHub. `ssh -T git@github.com` échoue ici aujourd'hui, donc utiliser HTTPS.

Tirer avant de travailler, pousser après. Ce PC garde `desktop` (`C:\repos\mail.git`) comme miroir local : `git push origin main && git push desktop main`. Le `HEAD` du dépôt nu pointe sur `main` ; `desktop/master` reste figé à `6b8a8d1` et ne doit pas bouger.

Les changements n'atteignent le serveur météo que par ce PC, le seul à joindre la VM : commit, push vers GitHub, déploiement par `labo/scripts/19-deploy-skin.sh`, puis relecture des md5.

**L'accès est actuellement bloqué.** La clé de déploiement qui vivait dans `%TEMP%` a été supprimée par le nettoyage de Windows entre deux sessions. Une clé de remplacement existe dans `C:\Users\WINDOWS 10\.ssh\meteo_labo`, mais sa clé publique n'a pas encore été ajoutée à `~/.ssh/authorized_keys` sur la VM : tout appel SSH renvoie `Permission denied (publickey,password)`. Tant que cette ligne n'est pas ajoutée, ni le déploiement ni la relecture des md5 ne sont possibles.

## Docker

Un stack conteneurisé est en préparation dans `labo/docker/` (voir le dernier enregistrement de passation). Rien n'a été construit ni lancé : la commande `docker` n'existe pas sur ce PC Windows, et la VM n'a pas encore été inspectée. La direction retenue est un stack **en parallèle** (ports propres, volumes propres, aucun montage de `/var/vmail` ni de la base du système), pour ne jamais toucher aux données du labo.

## Ce qui marche

- Le skin est déployé et identique au dépôt : `meteo.js` md5 `90e99c34…`, `meteo.css` md5 `225249c8…`, `mail.html` md5 `2292a760…`.
- Menu de gauche : lignes larges sur écran normal, compact sur fenêtre courte, jamais de barre de défilement ; toutes les sections (dossiers, actions, site, quota) restent visibles dès 1366×500. Depuis le 2026-11-03, le groupe du bas (« Site officiel ») est ancré en bas du panneau avec un filet au-dessus, et « Actions » est plus éloigné des dossiers — **cet espacement est commité mais pas encore déployé**.
- Le projet est publié : dépôt GitHub public, branche `main`, dernier changement de contenu `c20882c` (2026-10-28). GitHub est désormais le stockage et la source des mises à jour ; la VM ne reçoit que les déploiements.
- Boîte de réception : un seul bouton jaune « Écrire » ; « Tous les messages » est un lien discret dans l'en-tête de liste et cherche dans tous les dossiers en AJAX ; les compteurs de non-lus sont dans la colonne des dossiers.
- Lecture d'un message : en-tête façon Gmail/Proton (avatar rond avec initiales, nom de l'expéditeur, adresse, date, « à moi » ou « à … » pour les envois), actions en icônes (répondre, répondre à tous, transférer, imprimer, restaurer/supprimer dans la corbeille), bulles de conversation, citations, liste des pièces jointes, et visionneuse photo plein écran au clic (bouton Fermer, Échap).
- Réglages : trois cartes — mode sombre, signature personnelle (gardée dans le navigateur et insérée dans le composeur), guide utilisateur en sept points — plus un lien discret vers les options avancées.
- Données de démonstration du labo : la boîte de réception de luc, uid 24, contient le message avec photo (`1743573864817.jpg`, 642 ko) qui n'existait que dans les Envoyés de tiana. Il a été placé par `doveadm save` ; ce n'est pas une remise SMTP réelle.
- Dernière vérification le 2026-10-25 par `recette-design.js` (lien tous-les-messages, en-tête Gmail, barre d'icônes, préremplissage de réponse, réglages, mode sombre), `recette-photo4.js` (visionneuse, bulles, réglages) et `design-check.js` (sondes BAR/READ). Captures `pw\N1-inbox.png` à `pw\N4-mobile.png`.

## Ce qui est cassé

- Plus d'accès SSH à la VM : `ssh … messagerie@127.0.0.1` renvoie `Permission denied (publickey,password)` car la nouvelle clé publique n'est pas encore dans `~/.ssh/authorized_keys`. Déploiements et relectures de md5 bloqués jusque-là.
- La remise réelle d'un message avec photo n'a pas été reproduite : le message d'origine de tiana n'a été ajouté qu'aux Envoyés, sans transaction SMTP dans `mail.log`. Cause inconnue (envoi interrompu, brouillon, ou copie manuelle).
- Non commité sur le PC Windows : `labo/systemd/*` modifiés, `labo/DESIGN-mintlify.md` non suivi. Les laisser tranquilles jusqu'à décision de leur propriétaire.
- La VM de labo a déjà figé une fois (échange de bannière SSH interrompu, réseau invité mort) : il a fallu l'éteindre et la relancer avec `VBoxManage startvm server_messagerie --type headless`.

## Prochaine action

1. Rétablir l'accès SSH : sur la VM, ajouter la clé publique de `C:\Users\WINDOWS 10\.ssh\meteo_labo.pub` à `~/.ssh/authorized_keys`, puis vérifier que `ssh -i "$HOME/.ssh/meteo_labo" -p 2222 messagerie@127.0.0.1 "echo OK"` affiche `OK`.
2. Déployer l'espacement du menu en attente (commit du 2026-11-03), vérifier `DEPLOIEMENT DU SKIN OK` et l'égalité du md5 de `meteo.css` avec le dépôt.
3. Relire le squelette Docker dans `labo/docker/`, puis faire l'inventaire serveur en lecture seule avant de lancer le moindre conteneur.
4. Toujours ouvert, indépendant de Docker : reproduire un envoi réel avec pièce jointe de tiana vers luc par le composeur, et confirmer la transaction SMTP dans `/var/log/mail.log`.

## Comment vérifier

Les fichiers livrés doivent correspondre à la source :

    ssh -i "%USERPROFILE%\.ssh\meteo_labo" -p 2222 -o StrictHostKeyChecking=no messagerie@127.0.0.1 "md5sum /var/www/roundcube/skins/meteo/meteo.js /var/www/roundcube/skins/meteo/styles/meteo.css /var/www/roundcube/skins/meteo/templates/mail.html"

Comparer avec `Get-FileHash -Algorithm MD5` sur les mêmes fichiers sous `labo/skins/meteo/`.

Disposition et fonctions, de bout en bout : `C:\Users\WINDOWS 10\AppData\Local\Temp\opencode\pw\recette-design.js` doit afficher sept PASS (lien tous-les-messages, en-tête Gmail, barre d'icônes, préremplissage de réponse, réglages, mode sombre). `recette-photo4.js` prouve la visionneuse photo, les bulles et les réglages ; `design-check.js` affiche les sondes BAR et READ et écrit les captures `N1` à `N4`.

Menu de gauche sans défilement : `pw\probe-tiers.js` doit afficher `over:0` avec un `free` positif aux hauteurs 768, 650, 620, 600 et 500, et `pw\shot-menu.js` doit afficher `over:0` en 1366×768, 1366×600 et 390×844 (tiroir téléphone), en écrivant `MENU-*.png`.

Espacement du menu, avant déploiement : `pw\preview-menu.js` injecte le CSS local dans la page réelle. Il doit afficher `over:0` à 768, 650, 620, 600 et 500, avec `gapTopBottom` (distance entre « Actions » et « Site officiel ») qui grandit avec la hauteur — 328 px à 768, 210 px à 650 — et `free` autour de 8–14 px en bas du panneau. Il écrit `PREV-768.png` et `PREV-650.png`.

Visionneuse photo, de bout en bout : se connecter comme luc, ouvrir le message « photo » (uid 24), cliquer sur l'aperçu — la photo doit remplir l'écran avec un bouton de fermeture rond ; Échap doit la fermer.

## À ne pas faire

- Ne pas reprendre la session `ses_ecf512874ffeITb4u48KiF0D1C` pour retrouver du contexte. Elle a tourné jusqu'à 2 705 messages, s'est arrêtée sur le quota du fournisseur, et coûte plus qu'elle n'apporte. Lire ce fichier et les deux derniers enregistrements de passation.
- Ne pas commiter `labo/systemd/*` ni `labo/DESIGN-mintlify.md`.

Vérifié : 2026-11-03
