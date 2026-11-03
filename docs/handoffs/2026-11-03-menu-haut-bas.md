---
type: handoff
date: 2026-11-03
status: in-progress
commit: this commit
deployed: none (SSH access to the VM is blocked, see below)
---
# Le menu du haut et le menu du bas sont séparés, « Site officiel » ancré en bas du panneau

## What changed

`labo/skins/meteo/styles/meteo.css` seulement, trois règles ajoutées au bloc du menu latéral.

- `.meteo-side-scroll` devient une colonne flex (`display:flex`, `flex-direction:column`) ; ses enfants gardent leur hauteur naturelle (`.meteo-side-scroll > * { flex: 0 0 auto }`).
- Deuxième groupe (« Actions ») : `margin-top: 1.4rem` au lieu de `1.05rem`, pour l'éloigner des boîtes.
- Dernier groupe (« Site officiel ») : `margin-top: auto`, `padding-top: .7rem` et un filet `border-top: 1px solid var(--meteo-hairline)`. La marge élastique absorbe la place libre : le groupe descend en bas du panneau, et c'est lui qui crée la distance entre le menu haut et le menu bas.

Aucun changement de gabarit, de JavaScript, ni de la structure HTML : les titres sont déjà les seuls `h2` du panneau, donc `:nth-of-type(2)` et `:last-of-type` les ciblent sans toucher au balisage.

## Why it changed

Demande : « faire les menu à gauche un peu etaler ; un peu à distancer le menu haut avec le menu bas ». Les deux groupes étaient empilés avec la même marge de `1.05rem`, et le bas du panneau restait vide sous « Déconnexion » alors que « Site officiel » flottait au milieu.

## How it was proven

Pas encore déployé : la clé SSH de déploiement a disparu du dossier temporaire entre deux sessions (nettoyage Windows), et la nouvelle clé n'est pas autorisée sur la VM. La preuve ci-dessous est donc un **aperçu** : le CSS local est injecté dans la page réelle servie par la VM (`page.addStyleTag`), ce qui reproduit exactement le rendu sans écrire sur le serveur.

`pw/preview-menu.js`, largeur 1366 :

    H=768 {"over":0,"row":38.8,"siteTop":686,"actionsTop":358,"gapTopBottom":328,"free":14}
    H=650 {"over":0,"row":38.8,"siteTop":568,"actionsTop":358,"gapTopBottom":210,"free":14}
    H=620 {"over":0,"row":38.8,"siteTop":538,"actionsTop":358,"gapTopBottom":180,"free":14}
    H=600 {"over":0,"row":27.3,"siteTop":539,"actionsTop":292,"gapTopBottom":247,"free":8}
    H=500 {"over":0,"row":27.3,"siteTop":439,"actionsTop":292,"gapTopBottom":147,"free":8}

`over:0` partout : aucune barre de défilement, y compris à 500 px de haut. L'écart entre « Actions » et « Site officiel » passe de 50 px environ (avant) à 210 px en 1366×650 et 328 px en 1366×768 : c'est la distance demandée entre le menu haut et le menu bas.

Captures : `pw/PREV-650.png`, `pw/PREV-768.png`.

## What is left

1. Rétablir l'accès SSH : autoriser la clé publique de `C:\Users\WINDOWS 10\.ssh\meteo_labo.pub` dans `~/.ssh/authorized_keys` du compte `messagerie` sur la VM.
2. Déployer, puis vérifier `DEPLOIEMENT DU SKIN OK` et l'égalité des md5 dépôt/VM.
3. Rejouer les recettes de non-régression (lecture, pièce jointe, réglages, mode sombre).

## How to undo it

    git revert <commit>
    # puis redéployer le skin et vider le cache du navigateur

Le retour remet l'empilement précédent ; aucun changement de données.
