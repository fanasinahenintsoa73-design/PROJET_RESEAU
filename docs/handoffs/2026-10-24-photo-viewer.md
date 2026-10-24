---
type: handoff
date: 2026-10-24
status: done
commit: this commit
deployed: /var/www/roundcube/skins/meteo (md5 meteo.js be0b254e…, meteo.css 4e50ce78…)
---
# Les photos recues s'ouvrent en grand dans le message, plus de bouton « Afficher » muet

## What changed

- `labo/skins/meteo/meteo.js` : visionneuse photo maison. `showPhoto(url)` crée un calque
  `#meteo-photo` (image plein cadre + bouton Fermer), `hidePhoto()` le referme,
  `hookPhotoLinks(frame)` intercepte les clics sur `.image-attachment a.image-link` et
  `.attachment-links a.open` dans le cadre de lecture, force `_embed=1` et empêche le
  gestionnaire Roundcube de partir dans le vide. Échap ferme aussi la visionneuse (dans la
  page et depuis le cadre).
- `labo/skins/meteo/styles/meteo.css` : bloc `#meteo-photo` (fond sombre translucide,
  z-index 120, image 94vw/88vh, bouton rond) et `.meteo-photo-close`.
- Données du labo : le message « photo » (tiana → luc, pièce jointe
  `1743573864817.jpg`, 642 ko) a été remis dans la INBOX de
  luc.ranaivo@meteo-test.lan (uid 24) par `doveadm save` depuis la copie de Sent.

## Why it changed

L'utilisateur voyait la réponse « Re: photo » sans la photo et écrivait : « sur ce message
il faut qu'il y a de message de photo ou une personne envoye cette photo mais il cache ».

Enquête : la réponse « Re: photo » (INBOX uid 21 et 23) ne contient réellement aucune pièce
jointe (text/plain + text/html seulement). Le message « photo » de tiana existait uniquement
dans son dossier Sent (uid 2, multipart/mixed avec image/jpeg 657459 o) ; `mail.log` ne montre
aucune transaction SMTP pour lui, seulement un APPEND local. Il n'a donc jamais été livré.

Deuxième défaut trouvé en route : quand une photo arrive bien (uid 24), l'aperçu s'affiche,
mais le bouton « Afficher » ne faisait rien dans notre panneau de lecture, car la commande
Roundcube `load-attachment` ne peut pas ouvrir sa visionneuse dans l'iframe.

## How it was proven

    node --check labo/skins/meteo/meteo.js            -> JS_OK
    ssh … "md5sum /var/www/roundcube/skins/meteo/meteo.js …/meteo.css"
      meteo.js   be0b254ebdcf08c0e7f8e09d53c8d4c3
      meteo.css  4e50ce784c429874667d84f8f1f005fa      (identiques au dépôt)

Recette Playwright `recette-photo4.js` sur luc.ranaivo@meteo-test.lan :

    OPEN VIA THUMB: {"exists":true,"hidden":false,"loaded":true,"token":true}
    CLOSE BUTTON:   {"hidden":true,"bodyClass":false}
    ESCAPE:         {"hidden":true}
    SETTINGS:       {"cards":3,"switchOn":false}

Capture : `C:\Users\WINDOWS 10\AppData\Local\Temp\opencode\pw\P7-viewer.png` — photo
affichée en grand sur fond sombre, bouton de fermeture visible.

## What is left

- Vérifier l'envoi réel avec pièce jointe depuis le formulaire (tiana → luc) et confirmer
  qu'une transaction SMTP apparaît dans `mail.log`. Le message d'origine n'a jamais été
  remis ; la cause (envoi interrompu, brouillon, ou simple copie dans Sent) n'est pas établie.
- La VM a dû être redémarrée à froid pendant la séance (réseau invité muet). Surveiller.
- Le commit `93560af` (paramètres simplifiés) n'a pas son enregistrement dans
  `docs/handoffs/` ; à compléter si le dépôt l'exige.

## How to undo it

    git revert <ce commit>
    # et, pour le message de démonstration :
    sudo doveadm expunge -u luc.ranaivo@meteo-test.lan mailbox INBOX uid 24

Puis redéployer le skin avec `labo/scripts/19-deploy-skin.sh`.
