#!/bin/bash
# =============================================================================
# Postfix : anti-VRFY/ETRN + service submission 587 — LABO
# Usage : sudo ./07-submission-antivrfy.sh
# Idempotent.
# =============================================================================
set -euo pipefail

SRC="${SRC:-/tmp/labo-postfix}"

echo "=== 1. Anti-recensement (main.cf) ==="
# REPARATION : si un postconf -e anterieur a colle au dernier parametre
# (template sans saut de ligne final), on separe avant d'appliquer.
if grep -q 'yesdisable_vrfy_command' /etc/postfix/main.cf; then
    sed -i 's/^smtpd_tls_received_header = yesdisable_vrfy_command = yes$/smtpd_tls_received_header = yes\ndisable_vrfy_command = yes/' /etc/postfix/main.cf
    echo "ligne 90 concatenee reparee"
fi
postconf -e disable_vrfy_command=yes
postconf -e 'smtpd_discard_ehlo_keywords=silent-discard, etrn'
postconf disable_vrfy_command smtpd_discard_ehlo_keywords

echo "=== 2. Service submission 587 (master.cf, idempotent) ==="
if grep -q '^submission inet' /etc/postfix/master.cf; then
    echo "submission deja present, on le remplace par la version versionnee"
    python3 - "$SRC/master.cf.submission.labo" <<'EOF'
import sys, re
src = open(sys.argv[1]).read()
cur = open('/etc/postfix/master.cf').read()
block = [l for l in src.splitlines() if l.strip() and not l.startswith('#')]
newblock = '\n'.join(block) + '\n'
pat = re.compile(r'^submission inet.*(?:\n[ \t]+-o.*)*', re.M)
cur2, n = pat.subn(newblock.rstrip('\n'), cur, count=1)
open('/etc/postfix/master.cf','w').write(cur2)
print(f"bloc submission {'remplace' if n else 'NON TROUVE (ajout)'}")
if not n:
    open('/etc/postfix/master.cf','a').write('\n' + newblock)
EOF
else
    grep -v '^#' "$SRC/master.cf.submission.labo" | grep -v '^$' >> /etc/postfix/master.cf
    echo "bloc submission ajoute"
fi

echo "=== 3. Reload + verification ==="
postfix reload
sleep 2
echo "--- EHLO (ETRN et VRFY doivent etre ABSENTS) ---"
swaks --server 127.0.0.1 --port 25 --quit-after EHLO --protocol ESMTP 2>/dev/null | grep -iE '250[ -](ETRN|VRFY)' && echo "!! ETRN/VRFY ENCORE ANNONCES" || echo "OK : ni ETRN ni VRFY annonces"
echo "--- VRFY refusee ? (test brut, ce swaks n'a pas d'option --vrfy) ---"
python3 -c "
import socket
s = socket.create_connection(('127.0.0.1', 25), timeout=10)
print('BANN:', s.recv(200).decode().strip())
s.sendall(b'EHLO labo-test\r\n'); s.recv(2000)
s.sendall(b'VRFY tiana.rakoto@meteo-test.lan\r\n')
print('VRFY:', s.recv(200).decode().strip())
s.sendall(b'QUIT\r\n'); s.close()
" || true
echo "--- Submission 587 avec auth (STARTTLS+LOGIN) ---"
# Mot de passe lu dans le coffre : aucun secret en clair dans le depot git.
MDP_TEST=$(sudo grep '^MDP_TEST=' /root/labo-credentials.txt | tail -1 | cut -d= -f2-)
if [ -z "${MDP_TEST}" ]; then
    echo "MDP_TEST introuvable dans /root/labo-credentials.txt (a y ajouter)" >&2
    exit 1
fi
swaks --server 127.0.0.1 --port 587 --tls --auth LOGIN --auth-user luc.ranaivo@meteo-test.lan --auth-password "${MDP_TEST}" --from luc.ranaivo@meteo-test.lan --to tiana.rakoto@meteo-test.lan --header "Subject: [LABO-587] test submission" --body "Envoi via le port 587 authentifie." --quit-after DOT 2>&1 | grep -E '235|250 Ok|ERROR' | head -3 || true