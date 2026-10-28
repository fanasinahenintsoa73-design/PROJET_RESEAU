---
type: handoff
date: 2026-10-28
status: done
commit: this commit
deployed: /var/www/roundcube/skins/meteo (meteo.css e895e4371557bcea134fca16b7dc83cf)
---
# Le menu latéral tient dans la fenêtre : plus de barre de défilement

## What changed

- `labo/skins/meteo/styles/meteo.css` : le panneau latéral est compacté et sa barre de défilement disparaît.
  - `.meteo-side-scroll` : `padding` réduit (`.5rem .7rem .6rem`), `scrollbar-width: none`, `-ms-overflow-style: none`, `::-webkit-scrollbar { width:0; height:0 }`.
  - `.meteo-side-title` : marge haute `1rem` → `.75rem`, marge basse `.4rem` → `.25rem`.
  - `#meteo-folders li > a` : `padding` `.45rem .55rem` → `.32rem .5rem`, `line-height: 1.35` explicite.
  - `.meteo-side-actions a`, `.meteo-side-services a` : `padding` `.45rem .55rem` → `.36rem .5rem`, `line-height: 1.35`.
  - Nouvelle media query `@media screen and (min-height: 700px)` qui rend l'aisance d'origine sur les fenêtres hautes, sans jamais dépasser la hauteur disponible ailleurs.

## Why it changed

Sur un portable courant (1366×768, barre du navigateur comprise), le menu des dossiers dépassait la hauteur du panneau : une barre de défilement apparaissait et « Déconnexion » sortait de l'écran. Cause mesurée : `line-height: 35px` hérité de la feuille du skin parent (`elastic`) sur les entrées de liste, soit 47,6 px par dossier au lieu de 28.

## How it was proven

Avant, à 1366×600 : `scrollHeight 518` pour `clientHeight 493` (25 px en trop), et 125 px en trop à 1366×500.

Après déploiement, mesure dans le navigateur (`probe-menu2.js` puis `shot-menu.js`) :

    1366x768 {"sh":661,"ch":661,"over":0}
    1366x600 {"sh":493,"ch":493,"over":0}
    390x844  {"sh":844,"ch":844,"over":0}     (tiroir téléphone ouvert)

`over:0` sur les trois tailles : le contenu du menu ne dépasse plus la hauteur disponible.

Le fichier déployé est identique à la source :

    $ md5sum labo/skins/meteo/styles/meteo.css
    e895e4371557bcea134fca16b7dc83cf
    $ ssh … "md5sum /var/www/roundcube/skins/meteo/styles/meteo.css"
    e895e4371557bcea134fca16b7dc83cf

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

Captures : `pw\MENU-1366x768.png`, `pw\MENU-1366x600.png`, `pw\MENU-390x844.png`.

## What is left

- Un compte avec beaucoup de dossiers personnalisés (>10) dépassera encore la hauteur : la molette fonctionne, mais sans barre visible. À traiter si des dossiers s'ajoutent.
- Le tiroir téléphone n'a pas de bouton de fermeture explicite ; il se referme par le bouton ☰ du bandeau. Hors du cadre de cette demande.

## How to undo it

    git revert <commit>
    # puis redéployer : scp du skin + sudo bash /tmp/19-deploy-skin.sh

Le retour remet la barre de défilement et les espacements précédents ; aucun changement de gabarit ni de JavaScript.
