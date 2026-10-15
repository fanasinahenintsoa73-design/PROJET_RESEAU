#!/usr/bin/env python3
"""Diagnostic : teste la regex fail2ban substituee (<HOST> expanse) contre
une vraie ligne de log Roundcube. Usage : sudo python3 diag-f2b-regex.py
Lit la regex via `fail2ban-client get <jail> failregex` (source de verite).
"""
import re
import subprocess

JAIL = "roundcube-login"
LOG = "/var/www/roundcube/logs/errors.log"

out = subprocess.run(
    ["fail2ban-client", "get", JAIL, "failregex"],
    capture_output=True, text=True, check=True,
).stdout

# Les lignes utiles ressemblent a : `- [0]: ^\[...`
patterns = []
for line in out.splitlines():
    line = line.strip()
    if line.startswith("`- ["):
        # coupe "`- [N]: "
        pat = line.split(":", 1)[1].strip()
        patterns.append(pat)

print(f"{len(patterns)} pattern(s) dans la prison {JAIL}")
with open(LOG) as f:
    lines = [ln.rstrip("\n") for ln in f if ln.strip()]
print(f"{len(lines)} ligne(s) dans {LOG}")

for i, pat in enumerate(patterns):
    try:
        rx = re.compile(pat)
    except re.error as e:
        print(f"[{i}] ERREUR COMPILATION: {e}")
        continue
    hits = [ln for ln in lines if rx.search(ln)]
    print(f"[{i}] compile OK, {len(hits)}/{len(lines)} lignes matchent")
    if hits:
        print(f"    ex: {hits[0][:100]}")
