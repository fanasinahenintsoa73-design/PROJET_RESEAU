# Rules for agents

**Read this file before touching the repository.** It applies to every agent, on every machine.

## 1. Before work

    git pull --rebase
    read HANDOFF.md

`HANDOFF.md` is the current state of the system, not a log. If it disagrees with git, git is right and you correct the file.

Start a new session for the work. Do not resume an old conversation to recover context: `HANDOFF.md` and the last two files in `docs/handoffs/` carry it.

## 2. What counts as a major change

One of:

- anything under `labo/skins/` or `labo/systemd/`
- deploy, mail or web server configuration
- anything a mailbox user can see
- a decision that would be expensive to undo

A typo, a comment or a local experiment is not major.

## 3. Before you stop

In the same commit as the change:

1. Write `docs/handoffs/YYYY-MM-DD-<slug>.md` from `docs/handoffs/TEMPLATE.md`.
2. Overwrite `HANDOFF.md`: state, next action, how to verify. Do not append.
3. Commit and push:

       git commit -m "type(scope): summary" -m "Handoff: docs/handoffs/<file>"

A change that works but has no handoff is unfinished.

## 4. Claims

Every "done" names the check that proves it: a command with its output, an md5, an HTTP response, a file on the deployed host. "Tested" and "should work" are not claims.

## 5. Secrets

No passwords, tokens, private keys or real user addresses in committed files.

## 6. The lab

The target VM and the deploy path are described in `HANDOFF.md`. Deploy only from the Windows PC that can reach it.
