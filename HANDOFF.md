---
type: handoff
status: active
updated: 2026-10-24
---
# Handoff

Webmail for Météo Madagascar: a Roundcube skin in `labo/skins/meteo`, deployed to a lab VM. This file holds the current state; `docs/handoffs/` holds one record per major change.

## Where it runs

| Piece | Location |
|---|---|
| Canonical repository | bare repo `C:\repos\mail.git` on desktop-snl329v (100.94.160.92) |
| Working clone (Windows PC) | `C:\MAIL_MESSAGERIE` |
| Skin source | `labo/skins/meteo/`: `meteo.js`, `styles/meteo.css`, `templates/mail.html` |
| Deploy target | `messagerie@127.0.0.1:2222`, files in `/var/www/roundcube/skins/meteo/` |
| Deploy key | `C:\Users\WINDOWS 10\AppData\Local\Temp\opencode\labo_agent` |
| Lab URL | https://webmail.meteo-test.lan/ and https://127.0.0.1:8443/ |
| Lab account | luc.ranaivo@meteo-test.lan, password in the lab provisioning |

## How the two PCs share work

`origin` is the bare repo on the Windows PC. Any other machine clones it and works in its own checkout.

    git -c protocol.ext.allow=always clone "ext::ssh snl329v git-upload-pack C:/repos/mail.git" C:/MAIL_MESSAGERIE
    cd C:/MAIL_MESSAGERIE
    git config protocol.ext.allow always
    git config remote.origin.pushurl "ext::ssh snl329v git-receive-pack C:/repos/mail.git"

The `ext::` form exists because git quotes the remote path for a POSIX shell and cmd.exe keeps those quotes, which makes a plain `ssh://` URL fail on that host. `snl329v` is the SSH alias: `HostName 100.94.160.92`, `User "windows 10"`.

Pull before work, push after. The Windows PC's own `origin` is the local path `C:\repos\mail.git`.

## What works now

- The skin is deployed and matches the repository: `meteo.js` md5 `be0b254e…`, `meteo.css` md5 `4e50ce78…`.
- Message reading: conversation bubbles (sender on the left, the user's green on the right, reversed for sent mail), quoted replies, attachment list, photo preview card, and now a full-screen photo viewer when a photo is clicked (button Fermer, Échap).
- Settings: three cards — dark mode, personal signature (kept in the browser and inserted into the composer), seven-point user guide — plus a discreet advanced options link.
- Inbox: "Tous les messages" searches across folders in AJAX; unread badge; contact directory with "Écrire".
- Lab demonstration data: luc INBOX uid 24 holds the photo message (`1743573864817.jpg`, 642 ko) that was only in tiana's Sent folder. `doveadm save` was used to put it there; it is not a real SMTP delivery.
- Last verified 2026-10-24 by `recette-photo4.js`: viewer opens and loads, close button and Échap work, settings still has three cards. Screenshot `pw\P7-viewer.png`.

## What is broken

- Real delivery of a mail with a photo attachment has not been reproduced: the original message from tiana was only appended to Sent, with no SMTP transaction in `mail.log`. Cause unknown (interrupted send, draft, or manual copy).
- Uncommitted on the Windows PC: `labo/systemd/*` modified, `labo/DESIGN-mintlify.md` untracked. Leave them alone until their owner says they are ready.
- The lab VM hung once (SSH banner exchange aborted, guest network dead) and had to be powered off and restarted with `VBoxManage startvm server_messagerie --type headless`.

## Next action

1. Reproduce a real send with an attachment from tiana to luc through the composer, then confirm the SMTP transaction in `sudo tail /var/log/mail.log` and the arrival in luc's INBOX.
2. If it fails, read the composer's send error (Roundcube log `/var/www/roundcube/logs/errors.log`, Postfix `mail.log`) and fix the send path — not the reading side.

## How to verify

The shipped files must match the source:

    ssh -i "%TEMP%\opencode\labo_agent" -p 2222 -o StrictHostKeyChecking=no messagerie@127.0.0.1 "md5sum /var/www/roundcube/skins/meteo/meteo.js /var/www/roundcube/skins/meteo/styles/meteo.css"

Compare with `Get-FileHash -Algorithm MD5` on the same files under `labo/skins/meteo/`.

Photo viewer, end to end: log in as luc, open the "photo" message (uid 24), click the preview — the photo must fill the screen with a round close button; Échap must close it. The script that proved it is `C:\Users\WINDOWS 10\AppData\Local\Temp\opencode\pw\recette-photo4.js`.

## Do not

- Do not resume session `ses_ecf512874ffeITb4u48KiF0D1C` to find context. It ran to 2,705 messages, ended on provider quota, and costs more than it carries. Read this file and the last two handoff records instead.
- Do not commit `labo/systemd/*` or `labo/DESIGN-mintlify.md`.

Checked: 2026-10-24
