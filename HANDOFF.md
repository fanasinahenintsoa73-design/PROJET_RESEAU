---
type: handoff
status: active
updated: 2026-10-28
---
# Handoff

Webmail for Météo Madagascar: a Roundcube skin in `labo/skins/meteo`, deployed to a lab VM. This file holds the current state; `docs/handoffs/` holds one record per major change.

## Where it runs

| Piece | Location |
|---|---|
| Canonical repository | https://github.com/fanasinahenintsoa73-design/PROJET_RESEAU (public, branch `main`) |
| Working clone (Windows PC) | `C:\MAIL_MESSAGERIE`, remote `origin` = GitHub |
| Mirror on the desktop | bare repo `C:\repos\mail.git`, remote `desktop` on this PC |
| Skin source | `labo/skins/meteo/`: `meteo.js`, `styles/meteo.css`, `templates/mail.html` |
| Deploy target | `messagerie@127.0.0.1:2222`, files in `/var/www/roundcube/skins/meteo/` |
| Deploy key | `C:\Users\WINDOWS 10\AppData\Local\Temp\opencode\labo_agent` |
| Lab URL | https://webmail.meteo-test.lan/ and https://127.0.0.1:8443/ |
| Lab account | luc.ranaivo@meteo-test.lan, password in the lab provisioning |

## How work moves

GitHub is the storage and the source of updates. Any machine clones it:

    git clone https://github.com/fanasinahenintsoa73-design/PROJET_RESEAU.git C:/MAIL_MESSAGERIE

The repository is public, so cloning needs no key. Pushing needs an account: HTTPS through the `gh` credential helper already configured on this PC (`gh auth status`), or an SSH key added to the GitHub account. `ssh -T git@github.com` fails here today, so use HTTPS.

Pull before work, push after. This PC keeps `desktop` (`C:\repos\mail.git`) as a local mirror: `git push origin main && git push desktop main`. The bare repo's `HEAD` points at `main`; `desktop/master` is left at `6b8a8d1` and must not drift.

Changes reach the meteo server only through this PC, which is the only one that can reach the VM: commit, push to GitHub, deploy from `labo/scripts/19-deploy-skin.sh`, then read back the md5.

## What works now

- The skin is deployed and matches the repository: `meteo.js` md5 `90e99c34…`, `meteo.css` md5 `e895e437…`, `mail.html` md5 `2292a760…`.
- Left menu: compact rows, no scrollbar; all sections (folders, actions, site, quota) fit at 1366×500, 1366×600 and 1366×768 and in the phone drawer.
- The project is published: public GitHub repository, branch `main`, last content change `6b8a8d1` (2026-10-28). GitHub is now the storage and the source of updates; the VM only receives deployments.
- Inbox: a single yellow « Ecrire » button; « Tous les messages » is a quiet link in the list header and searches across folders in AJAX; unread counts sit in the folder sidebar.
- Message reading: Gmail/Proton-style header (round initials avatar, sender name, address, date, « à moi » or « à … » for sent mail), actions as icon buttons (reply, reply all, forward, print, restore/delete in trash), conversation bubbles, quoted replies, attachment list, and a full-screen photo viewer when a photo is clicked (button Fermer, Échap).
- Settings: three cards — dark mode, personal signature (kept in the browser and inserted into the composer), seven-point user guide — plus a discreet advanced options link.
- Lab demonstration data: luc INBOX uid 24 holds the photo message (`1743573864817.jpg`, 642 ko) that was only in tiana's Sent folder. `doveadm save` was used to put it there; it is not a real SMTP delivery.
- Last verified 2026-10-25 by `recette-design.js` (all-mail link, Gmail header, icon bar, reply prefill, settings, dark mode), `recette-photo4.js` (viewer, bubbles, settings) and `design-check.js` (BAR/READ probes). Screenshots `pw\N1-inbox.png` to `pw\N4-mobile.png`.

## What is broken

- Real delivery of a mail with a photo attachment has not been reproduced: the original message from tiana was only appended to Sent, with no SMTP transaction in `mail.log`. Cause unknown (interrupted send, draft, or manual copy).
- Uncommitted on the Windows PC: `labo/systemd/*` modified, `labo/DESIGN-mintlify.md` untracked. Leave them alone until their owner says they are ready.
- The lab VM hung once (SSH banner exchange aborted, guest network dead) and had to be powered off and restarted with `VBoxManage startvm server_messagerie --type headless`.

## Next action

1. Reproduce a real send with an attachment from tiana to luc through the composer, then confirm the SMTP transaction in `sudo tail /var/log/mail.log` and the arrival in luc's INBOX.
2. If it fails, read the composer's send error (Roundcube log `/var/www/roundcube/logs/errors.log`, Postfix `mail.log`) and fix the send path — not the reading side.

## How to verify

The shipped files must match the source:

    ssh -i "%TEMP%\opencode\labo_agent" -p 2222 -o StrictHostKeyChecking=no messagerie@127.0.0.1 "md5sum /var/www/roundcube/skins/meteo/meteo.js /var/www/roundcube/skins/meteo/styles/meteo.css /var/www/roundcube/skins/meteo/templates/mail.html"

Compare with `Get-FileHash -Algorithm MD5` on the same files under `labo/skins/meteo/`.

Layout and features, end to end: `C:\Users\WINDOWS 10\AppData\Local\Temp\opencode\pw\recette-design.js` must print seven PASS (all-mail link, Gmail header, icon bar, reply prefill, settings, dark mode). `recette-photo4.js` proves the photo viewer, bubbles and settings; `design-check.js` prints the BAR and READ probes and writes `N1`–`N4` screenshots.

Left menu without scrolling: `pw\shot-menu.js` must print `over:0` at 1366×768, 1366×600 and 390×844 (phone drawer), and write `MENU-*.png`. `pw\probe-menu2.js` does the same measurement across mail, settings and contacts.

Photo viewer, end to end: log in as luc, open the "photo" message (uid 24), click the preview — the photo must fill the screen with a round close button; Échap must close it.

## Do not

- Do not resume session `ses_ecf512874ffeITb4u48KiF0D1C` to find context. It ran to 2,705 messages, ended on provider quota, and costs more than it carries. Read this file and the last two handoff records instead.
- Do not commit `labo/systemd/*` or `labo/DESIGN-mintlify.md`.

Checked: 2026-10-28
