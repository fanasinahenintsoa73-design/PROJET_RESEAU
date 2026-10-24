---
type: handoff
date: 2026-10-24
status: done
commit: HEAD
deployed: no
---
# A second PC can clone and push the repository

## What changed

Created the bare repo `C:\repos\mail.git` on the Windows PC and made it `origin` of the working clone. Documented the clone command for any other machine, including the `ext::` transport that gets around git's quoting on that host.

## Why it changed

Work alternates between two PCs. Without a shared remote there is no way to hand a branch from one to the other, and a chat session is not a durable record.

## How it was proven

`git ls-remote "ext::ssh snl329v git-upload-pack C:/repos/mail.git"` returned `1d49c83`, the head of `master`. The second PC cloned that URL and `git log` shows both commits. Nothing was deployed.

## What is left

- The VM is still down, so no change can be deployed or checked on the lab.
- The working clone on the Windows PC keeps uncommitted `labo/systemd/*` and `labo/DESIGN-mintlify.md`; they are not part of this change.

## How to undo it

`git remote remove origin` on each clone, then delete `C:\repos\mail.git`. No history is lost: every clone keeps its own objects.
