---
type: handoff
date: 2026-10-28
status: done
commit: this commit
deployed: /var/www/roundcube/skins/meteo (meteo.css 225249c802487946ab1b6e076c7f08e0)
---
# Le menu latéral tient dans la fenêtre, sans barre de défilement et sans rétrécir

## What changed

`labo/skins/meteo/styles/meteo.css` seulement.

- `.meteo-side-scroll` : `scrollbar-width: none`, `-ms-overflow-style: none`, `::-webkit-scrollbar { width:0; height:0 }` — plus aucune barre visible. Padding de base `.5rem .7rem .6rem`.
- `#meteo-folders li > a` : `padding .36rem .5rem`, `font-size .88rem`, `line-height: 1.4` explicite (l'héritage du skin parent imposait `35px`, soit 47,6 px par ligne).
- `.meteo-side-actions a`, `.meteo-side-services a` : mêmes valeurs compactes.
- `.meteo-side-title` : marge `.75rem .2rem .25rem`, `line-height: 1.3`.
- Media query `@media screen and (min-height: 620px)` : sur les écrans courants, le menu retrouve de l'ampleur — padding `.72rem .6rem`, `font-size .95rem`, marges de titres `1.05rem`, icônes d'action `1.15rem`, padding du panneau `.85rem .8rem 1rem`.

Deux régimes, donc :

| Hauteur de fenêtre | Ligne de menu | Taille du texte |
|---|---|---|
| ≥ 620 px (portable, bureau) | 38,8 px | 13,3 px |
| < 620 px (fenêtre courte) | 27,3 px | 12,3 px |

## Why it changed

Sur un portable (1366×768, barre du navigateur comprise), le menu dépassait la hauteur du panneau : barre de défilement visible et « Déconnexion » hors écran. Première correction trop serrée : le menu tenait, mais paraissait petit. La version finale garde l'aisance d'avant sur les écrans normaux et ne se compacte que lorsque la hauteur l'exige.

## How it was proven

Avant toute correction, à 1366×600 : `scrollHeight 518` pour `clientHeight 493` (25 px en trop), 125 px en trop à 1366×500.

Après déploiement (`probe-tiers.js`, `1366` de large) :

    H=768 {"over":0,"row":38.8,"fs":"13.3px","free":168}
    H=680 {"over":0,"row":38.8,"fs":"13.3px","free":80}
    H=650 {"over":0,"row":38.8,"fs":"13.3px","free":50}
    H=620 {"over":0,"row":38.8,"fs":"13.3px","free":20}
    H=610 {"over":0,"row":27.3,"fs":"12.32px","free":149}
    H=600 {"over":0,"row":27.3,"fs":"12.32px","free":139}
    H=500 {"over":0,"row":27.3,"fs":"12.32px","free":39}

`over:0` et `free` positif partout : le contenu ne dépasse jamais et il reste de la place sous « Site Meteo Madagascar ».

Tiroir téléphone (390×844, ouvert) : `{"sh":844,"ch":844,"over":0}` (`shot-menu.js`).

Fichier déployé identique à la source :

    $ md5sum labo/skins/meteo/styles/meteo.css
    225249c802487946ab1b6e076c7f08e0
    $ ssh … "md5sum /var/www/roundcube/skins/meteo/styles/meteo.css"
    225249c802487946ab1b6e076c7f08e0

`meteo.js` (`90e99c34…`) et `mail.html` (`2292a760…`) sont inchangés.

Non-régression :

    $ node recette-design.js
    PASS tous-les-messages: lignes visibles
    PASS tous-les-messages: portee all/recherche
    PASS lecture: en-tete Gmail
    PASS lecture: boutons-icones
    PASS repondre: destinataire pre-rempli
    PASS parametres: 3 cartes
    PASS parametres: mode sombre bascule

    $ node recette-photo4.js
    OPEN VIA THUMB: {"exists":true,"hidden":false,"loaded":true,"token":true}
    CLOSE BUTTON: {"hidden":true,"bodyClass":false}
    ESCAPE: {"hidden":true}
    BUBBLES: {"replyPart":false,"incoming":true,"sent":false}
    SETTINGS: {"cards":3,"switchOn":false}

Captures : `pw\MENU-1366x768.png`, `pw\MENU-1366x600.png`, `pw\MENU-390x844.png`, `pw\TIER-650.png`, `pw\TIER-610.png`.

## What is left

- Un compte avec beaucoup de dossiers personnalisés (>10) dépassera encore : la molette fonctionne, mais sans barre visible. À traiter si des dossiers s'ajoutent.
- Le tiroir téléphone n'a pas de bouton de fermeture explicite ; il se referme par le bouton ☰ du bandeau. Hors du cadre de cette demande.

## How to undo it

    git revert <commit>
    # puis redéployer : scp du skin + sudo bash /tmp/19-deploy-skin.sh

Le retour remet la barre de défilement et les espacements précédents ; aucun changement de gabarit ni de JavaScript.
