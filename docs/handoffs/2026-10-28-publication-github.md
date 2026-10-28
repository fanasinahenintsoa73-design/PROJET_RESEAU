---
type: handoff
date: 2026-10-28
status: done
commit: 8b7313b
deployed: none
---
# The project is published on GitHub (public, branch `main`) and GitHub is now the storage and update source

## What changed

- Branch `master` renamed to `main`; tip is `6b8a8d1`.
- New remote `origin` = `https://github.com/fanasinahenintsoa73-design/PROJET_RESEAU.git` (public), `main` tracks `origin/main`.
- Former `origin` (bare repo `C:\repos\mail.git`) renamed to `desktop`; it also carries `main`, and its `HEAD` now points to `refs/heads/main` so a fresh clone checks out `main`.
- `HANDOFF.md`: « Where it runs » and « How the two PCs share work » rewritten around GitHub; the deploy target is unchanged.
- `AGENTS.md` §6: GitHub is stated as the storage and update source, the VM as the deploy target.
- `README.md` added so the public repository explains itself; published tip is `8b7313b`.

## Why it changed

The user wants GitHub to hold the project and to be the place updates come from, with the meteo server as the deployment target. A public repository also removes the `ext::ssh` clone workaround the second PC needed to reach the bare repo on this desktop.

## How it was proven

No secrets in the published history — 25 commits scanned for key blocks and provider tokens, plus every revision grepped for password literals:

    $ git rev-list --all | while read c; do git grep -nIE "BEGIN (RSA |OPENSSH |EC |PGP )?PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-|sk-[A-Za-z0-9]{20,}" "$c" -- ; done | sort -u
    SCAN1_DONE
    $ git rev-list --all | while read c; do git grep -nIE "(password|passwd|pwd|mot_de_passe)[[:space:]]*[:=][[:space:]]*['\"][^'\"]{6,}" "$c" -- ; done | sort -u
    labo/scripts/import-comptes-lab.sh:58: password="$MDP_PROVISOIRE" \
    SCAN2_DONE

The only hit is a shell variable. Tracked configs carry placeholders (`__MVPP_POSTFIXADMIN__`, `CHANGEME_roundcube`); the real values live in `/root/labo-credentials.txt` on the VM, never in the repository.

The two lab passwords used during testing do not appear in any revision:

    $ grep -rn "LaboTest2026\|8RDf6lrX649DwH0gx0v3" . --exclude-dir=.git    # no output
    $ git rev-list --all | while read c; do git grep -l "LaboTest2026\|8RDf6lrX649DwH0gx0v3" "$c"; done | sort -u    # no output

GitHub serves the published tip:

    $ git ls-remote origin
    6b8a8d12b2d38e04db9de9a7db2171d0f4cb8f2c	HEAD
    6b8a8d12b2d38e04db9de9a7db2171d0f4cb8f2c	refs/heads/main
    $ gh api repos/fanasinahenintsoa73-design/PROJET_RESEAU/commits/main --jq '.sha[0:7]+" "+.commit.message'
    6b8a8d1 feat(webmail): barre unique, actions en icones et en-tete facon Gmail

    $ gh repo view fanasinahenintsoa73-design/PROJET_RESEAU --json visibility
    {"visibility":"PUBLIC"}

The desktop mirrors the same tip on `main`:

    $ git --git-dir=C:/repos/mail.git branch -v
    * main   6b8a8d1 feat(webmail): barre unique, actions en icones et en-tete facon Gmail
      master 6b8a8d1 feat(webmail): barre unique, actions en icones et en-tete facon Gmail

## What is left

- Nothing was deployed: the published tree is the same content that was already on the VM (`meteo.js` `90e99c34…`, `meteo.css` `7428e685…`, `mail.html` `2292a760…`).
- SSH push (`git@github.com:…`) is not usable from this PC: `ssh -T git@github.com` returns `Permission denied (publickey)`. HTTPS with the `gh` credential helper works; add `~/.ssh/id_ed25519.pub` to the GitHub account if SSH is wanted later.
- `desktop/master` is kept only for the older clone instructions; it must not drift. Push `main`.
- Public visibility exposes the architecture: Tailscale address `100.94.160.92`, the desktop hostname `DESKTOP-SNL329V`, VM paths, the production plan. No credential is exposed, but that map is readable by anyone. Revisit if the encadrant objects.

## How to undo it

    git remote remove origin
    gh repo edit fanasinahenintsoa73-design/PROJET_RESEAU --visibility private
    git branch -m main master

The content stays identical; only the remote and the branch name change.
