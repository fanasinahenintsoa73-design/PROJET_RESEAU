#!/bin/bash
# =============================================================================
# Test bout-en-bout de la prison roundcube-login
# Usage : sudo ./10-test-fail2ban-e2e.sh
#
# But : prouver que la prison SE DECLENCHE vraiment. Une regex qui matche sur
# fail2ban-regex ne garantit rien : il faut voir l'IP bannie dans fail2ban-client.
#
# Contrainte : en labo toutes les requetes viennent de 127.0.0.1, qui est dans
# ignoreip. On le retire TEMPORAIREMENT, on teste, puis on restaure.
# Idempotent : restaure ignoreip meme en cas d'echec (trap EXIT).
# =============================================================================
set -uo pipefail

JAIL=roundcube-login
JAILCONF=/etc/fail2ban/jail.local
WEBMAIL=https://webmail.meteo-test.lan
JAR=$(mktemp)
N_TENTATIVES=6

restore() {
    echo ""
    echo "=== RESTAURATION ==="
    fail2ban-client set "$JAIL" ignoreip "127.0.0.1/8 ::1 10.0.2.0/24" >/dev/null 2>&1
    fail2ban-client unban --all >/dev/null 2>&1
    echo "ignoreip restaure : 127.0.0.1/8 ::1 10.0.2.0/24"
    fail2ban-client status "$JAIL" | head -5
    rm -f "$JAR"
}
trap restore EXIT

echo "=== 1. Retrait temporaire de 127.0.0.1 de ignoreip ==="
fail2ban-client set "$JAIL" ignoreip "10.0.2.0/24" >/dev/null 2>&1
fail2ban-client status "$JAIL" | grep -i "Currently banned\|Currently failed"

echo ""
echo "=== 2. Generation de $N_TENTATIVES logins RoundcubeRates (mauvais mdp) ==="
for i in $(seq 1 "$N_TENTATIVES"); do
    TOKEN=$(curl -sk -c "$JAR" "$WEBMAIL/" \
        | grep -o 'name="_token" value="[^"]*"' \
        | head -1 | sed 's/.*value="//; s/"//')
    curl -sk -b "$JAR" -o /dev/null \
        -d "_token=$TOKEN" \
        -d "_task=login" \
        -d "_action=login" \
        -d "_user=tiana.rakoto@meteo-test.lan" \
        -d "_pass=MotDePasseFaux$i" \
        "$WEBMAIL/?_task=login&_action=login"
    echo "  tentative $i/$N_TENTATIVES envoyee"
    sleep 1
done

echo ""
echo "=== 3. Attente du traitement (3 s) ==="
sleep 3

echo ""
echo "=== 4. ETAT DE LA PRISON ==="
fail2ban-client status "$JAIL"

echo ""
echo "=== 5. VERDICT ==="
BANNI=$(fail2ban-client status "$JAIL" | grep -c "127.0.0.1")
if [ "$BANNI" -gt 0 ]; then
    echo "SUCCES : la prison a bien banni l'IP (filtre operationnel)"
    exit 0
else
    echo "ECHEC : aucune IP bannie. Le filtre ne se declenche pas."
    echo "Diagnostic : tail -20 /var/www/roundcube/logs/errors.log"
    exit 1
fi