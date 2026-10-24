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

- `master` at `1d49c83`, handoff contract committed and pushed.
- Settings page reduced to three cards (dark mode, signature, seven-point guide) plus a discreet advanced options link. Bubble conversation view, inline contact directory and trash actions are in place. Deployed and checked by the previous session at 2026-10-24 04:04 UTC; not re-checked since, the VM went down afterwards.

## What is broken

- **The VM is down.** Nothing listens on `127.0.0.1:2222` (checked 2026-10-24 15:40 UTC). No deploy, no login, no verification until it is back.
- Uncommitted on the Windows PC: `labo/systemd/*` modified, `labo/DESIGN-mintlify.md` untracked. Leave them alone until their owner says they are ready.

## Next action

1. Bring the VM up and confirm `ssh -p 2222 messagerie@127.0.0.1 "true"` succeeds.
2. Fix the reported defect: an image sent as an attachment is hidden in the message view. User words: « sur ce message il faut qu'il y a de message de photo ou une personne envoye cette photo mais il cache ».
3. Deploy, then run the md5 check below.

## How to verify

The shipped files must match the source:

    ssh -i "%TEMP%\opencode\labo_agent" -p 2222 -o StrictHostKeyChecking=no messagerie@127.0.0.1 "md5sum /var/www/roundcube/skins/meteo/meteo.js /var/www/roundcube/skins/meteo/styles/meteo.css"

Compare with `Get-FileHash -Algorithm MD5` on the same files under `labo/skins/meteo/`.

## Do not

- Do not resume session `ses_ecf512874ffeITb4u48KiF0D1C` to find context. It ran to 2,705 messages, ended on provider quota, and costs more than it carries. Read this file and the last two handoff records instead.
- Do not commit `labo/systemd/*` or `labo/DESIGN-mintlify.md`.

Checked: 2026-10-24
