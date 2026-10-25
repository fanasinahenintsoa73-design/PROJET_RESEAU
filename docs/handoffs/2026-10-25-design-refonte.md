---
type: handoff
date: 2026-10-25
status: done
commit: this commit
deployed: /var/www/roundcube/skins/meteo (md5 meteo.js 90e99c34…, meteo.css 7428e685…, mail.html 2292a760…)
---
# La boite n'a plus qu'un bouton Écrire, et le message se lit comme dans Gmail

## What changed

- `labo/skins/meteo/templates/mail.html`
  - `#meteo-actions` ne garde qu'un bouton compact « Ecrire » (crayon, jaune, casse
    normale). Les trois cartes « Boite de reception », « Envoyes » et « Tous les
    messages » sont supprimees : les deux premieres font doublon avec la liste des
    boites, la troisieme devient un lien discret.
  - `#messagelist-header` recoit `.meteo-all-link` « Tous les messages » (recherche
    multifolder inchangee, interceptee en JavaScript).
  - Barre de lecture refaite : fond clair, fleche de retour, puis boutons-icones
    (Répondre, Répondre à tous, Transférer, Imprimer, Restaurer, Supprimer) avec
    `title` et `aria-label`. Le titre du message n'est plus repete dans la barre :
    l'objet reste dans le message.
  - Barre de redaction refaite dans le meme vocabulaire (titre + bouton-icone Fermer).
- `labo/skins/meteo/styles/meteo.css`
  - Suppression des tuiles et de tous les traits verts decoratifs : plus de
    `border-left: 3px` sur les cartes ni de `inset 3px` sur le dossier selectionne.
    Les cartes de parametres n'ont plus ni barre ni effet de soulvement.
  - Suppression des majuscules et du letter-spacing sur les boutons, les titres de
    liste et de panneau.
  - `.btn` redevient neutre (surface + bordure) ; seul `.btn-primary` reste jaune.
    Cela supprime le carre jaune que Roundcube imposait aux `<button>` de nos barres.
  - Nouveaux `.meteo-iconbtn`, `.meteo-all-link`, barres claires, bouton flottant de
    Roundcube masque (il doublait « Ecrire » sur telephone).
  - En-tete de message facon Gmail/Proton : avatar rond a initiales, nom, adresse,
    date a droite, « a moi » (ou « a … » depuis les envoyes), lien « Ajouter aux
    contacts ». Les liens Détails / En-têtes / Texte brut passent en texte simple.
  - Piece jointe image : plus de carte bleue ; l'image (rayon 12) puis une legende
    discrete (fichier, taille, Afficher, Télécharger).
- `labo/skins/meteo/meteo.js`
  - `styleMessageHeader(doc)` construit l'en-tete ci-dessus a l'ouverture du message ;
    `agentDisplayName()` s'appuie sur `window.METEO_AGENTS` (annuaire du deploiement)
    avec repli sur l'adresse ; `initialsOf()` produit les initiales.
  - `tidyAttachments(doc)` masque la ligne de pieces jointes du haut quand chaque
    piece jointe a deja son apercu dans le corps (doublon supprime).
  - `window.__meteoReadMbox` retient la boite du message ouvert (pour « a … »).
  - `interceptAllMail()` accepte le nouveau lien `.meteo-all-link` en plus de
    l'ancienne classe `.meteo-tile-all`.
  - `loadAgents()` est appele au demarrage de la page mail pour disposer des noms.

## Why it changed

Demande de l'utilisateur : « utilise le skill impeccable aislop;enlève les redondances
du bouton et les design pour que connaitre que c est IA (par exemple le petit bout vert
de bouton et les 3 bouton au dessus (les 3 cartes sauf ecrire message car ces 3 bouton
existe en bas) ;;;;;;faire le recherche sur internet le gmail et protonmail et applique
le design comme structure de message et de fonctionnalité necessaire pour le projet
comme les icônes transferer structure de message ou de conversation ».

Recherche Gmail/Proton : barre d'outils avec retour et actions en icones, chrome clair,
avatar + expediteur + date sur une ligne, reponse/reponse a tous/transfert en icones
(support.google.com/mail/answer/2473038, proton.me/support/sender-images,
proton.me/support/check-email-headers). Le skill `impeccable` (mode Operate, distill)
interdit les bordures colorees decoratives, les majuscules de bouton et les cartes
imbriquees.

## How it was proven

    node --check labo/skins/meteo/meteo.js        -> JS_OK
    accolades CSS                                 -> 279 / 279, BALANCED

Deploiement : `DEPLOIEMENT DU SKIN OK`. Les fichiers servis sont identiques au depot :

    meteo.js    90e99c34786b9d3bbb6c79c696da04bd  (depot et VM)
    meteo.css   7428e6854622cc2ae7d916eacadd5964  (depot et VM)
    mail.html   2292a760803e6fa4f22a6743a10a89e2  (depot et VM)

`pw\design-check.js` sur luc.ranaivo@meteo-test.lan :

    BAR:  {"actions":["meteo-compose-btn","meteo-search-mobile"],"tiles":0,"compose":"Ecrire","allLink":"Tous les messages"}
    READ: {"head":true,"avatar":"TR","name":"Tiana Rakoto","addr":"tiana.rakoto@meteo-test.lan",
           "date":"2026-10-16 11:00","to":"a moiAjouter aux contacts","subjectSize":"18.9px",
           "oldPhotoVisible":false,"attachmentsHidden":true,"barLight":"rgb(255, 255, 255)","iconBtns":7}

`pw\recette-design.js` (non-regression fonctionnelle) :

    PASS tous-les-messages: lignes visibles
    PASS tous-les-messages: portee all/recherche
    PASS lecture: en-tete Gmail
    PASS lecture: boutons-icones
    PASS repondre: destinataire pre-rempli
    PASS parametres: 3 cartes
    PASS parametres: mode sombre bascule

`pw\recette-photo4.js` (visionneuse) reste vert :

    OPEN VIA THUMB: {"exists":true,"hidden":false,"loaded":true,"token":true}
    CLOSE BUTTON:   {"hidden":true,"bodyClass":false}
    ESCAPE:         {"hidden":true}
    BUBBLES:        {"replyPart":false,"incoming":true,"sent":false}
    SETTINGS:       {"cards":3,"switchOn":false}

Detecteur impeccable (`scripts/detect.mjs --json`) : 0 erreur, 7 avertissements —
6 « overused-font » (Open Sans, police de marque imposee par le site) et 1
« broken-image » faux positif (`<img alt="Photo">` construit par la visionneuse, src
posee au clic).

Captures : `pw\N1-inbox.png`, `pw\N2-read.png`, `pw\N3-compose.png`, `pw\N4-mobile.png`.

## What is left

- Reproduire un envoi reel avec piece jointe tiana -> luc et confirmer la transaction
  SMTP dans `mail.log` (inchange depuis le handoff precedent).
- La VM a deja du etre redemarree une fois ; surveiller.
- Le projet n'a pas de `PRODUCT.md` ; le skill impeccable suggere `$impeccable init`
  pour fixer le contexte produit (non bloquant).

## How to undo it

    git revert <ce commit>
    # puis redeployer
    bash labo/scripts/19-deploy-skin.sh

Aucune donnee n'a ete modifiee en base ; le retour au skin precedent suffit.
