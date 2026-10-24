---
type: handoff
date: 2026-10-24
status: done
commit: HEAD
deployed: no
---
# The repository can be handed between the two PCs

## What changed

Added `AGENTS.md`, `HANDOFF.md`, `docs/handoffs/TEMPLATE.md` and this record. No runtime code touched.

## Why it changed

Work alternates between the Windows PC and a second workstation. A chat cannot carry that: the previous session reached 2,705 messages and ended on a provider quota, leaving no readable state on disk. The repository is the shared memory instead, and these four files are its index.

## How it was proven

`git log -1 --stat` shows the four files in one commit. Nothing was deployed, so `deployed: no` is accurate.

## What is left

- Create the bare repository on the Windows PC, add it as `origin`, push `master`. Then clone it on the second PC.
- Bring the VM back up; every deploy and every verification is blocked until then.

## How to undo it

`git revert <sha>`. Nothing outside the repository is touched.
