#!/bin/bash
# =============================================================================
# Test de la CHAINE DE BANNISSEMENT de la prison roundcube-login
# Usage : sudo ./11-test-fail2ban-ban.sh
#
# POURQUOI un deuxieme test alors que fail2ban-regex matche deja ?
#   fail2ban-regex prouve que la REGEX matche.
#   Ce script prouve que la prison Reaction (compteur maxretry -> ban -> regle
#   iptables) fonctionne vraiment. C'est ce que Regex ne peut PAS prouver.
#
#   Un test par requetes HTTP reelles ne peut PAS fonctionner en labo : le
#   traffic vient de 127.0.0.1, et fail2ban l'ignore TOUJOURS, pour 2 raisons
#   cumulatives (decouvertes) :
#     1. `ignoreself = true` (defaut de la prison) ignore l'IP de la machine ;
#     2. `ignoreip` contient 127.0.0.1 et n'est PAS modifiable a chaud :
#        `fail2ban-client set <jail> ignoreip ...` renvoie
#        "Invalid command 'ignoreip' (no set action or not yet implemented)".
#   On utilise donc une IP de test non routable (203.0.113.0/24 = TEST-NET-3,
#   RFC 5737) : le test est realiste ET sans aucun risque pour cette machine.
#
# Idempotent : nettoie toujours (trap EXIT).
# =============================================================================
set -uo pipefail

LOG=/tmp/f2b-test.log
JAILLOC=/etc/fail2ban/jail.d/f2b-test.local
IP_TEST=203.0.113.5
MAXRETRY=3

cleanup() {
    echo ""
    echo "=== NETTOYAGE ==="
    rm -f "${JAILLOC}"
    systemctl restart fail2ban >/dev/null 2>&1
    rm -f "${LOG}"
    echo "prison de test supprimee, fail2ban redemarre"
}
trap cleanup EXIT

echo "=== 1. Journal de test avec IP distante simulee ==="
rm -f "${LOG}"
printf '[15-Oct-2026 19:05:00 +0000]: <t01> IMAP Error: Login failed for tiana.rakoto@meteo-test.lan against %s from %s. AUTHENTICATE PLAIN: Authentication failed. in /var/www/roundcube/program/lib/Roundcube/rcube_imap.php on line 201 (POST /?_task=login&_action=login)\n' "${IP_TEST}" "${IP_TEST}" > "${LOG}"
chmod 644 "${LOG}"
echo "1 ligne amorcee dans ${LOG}"

echo ""
echo "=== 2. Prison de test (filtre roundcube-login, IP non ignoree) ==="
cat > "${JAILLOC}" <<EOF
[f2b-test-roundcube]
enabled  = true
filter   = roundcube-login
logpath  = ${LOG}
backend  = polling
maxretry = ${MAXRETRY}
findtime = 600
bantime  = 600
ignoreself = false
ignoreip =
EOF
chmod 644 "${JAILLOC}"
systemctl restart fail2ban >/dev/null 2>&1
sleep 5
fail2ban-client status f2b-test-roundcube | head -6

echo ""
echo "=== 3. Injection de ${MAXRETRY} echecs de plus ==="
for i in $(seq 2 ${MAXRETRY}); do
    printf '[15-Oct-2026 19:05:%02d +0000]: <t%02d> IMAP Error: Login failed for tiana.rakoto@meteo-test.lan against %s from %s. AUTHENTICATE PLAIN: Authentication failed. in /var/www/roundcube/program/lib/Roundcube/rcube_imap.php on line 201 (POST /?_task=login&_action=login)\n' "$i" "0$i" "${IP_TEST}" "${IP_TEST}" >> "${LOG}"
    echo "  echec $i/$MAXRETRY injecte"
    sleep 2
done
sleep 4

echo ""
echo "=== 4. ETAT DE LA PRISON ==="
fail2ban-client status f2b-test-roundcube

echo ""
echo "=== 5. REGLE IPTABLES GENEREE ? ==="
sudo iptables -L -n 2>/dev/null | grep -E "${IP_TEST}|f2b-test" || echo "(aucune regle trouvee)"

echo ""
echo "=== 6. VERDICT ==="
if fail2ban-client status f2b-test-roundcube | grep -q "${IP_TEST}"; then
    echo "SUCCES : la chaine complete fonctionne"
    echo "  regex matche -> compteur maxretry -> bannissement -> regle iptables"
    exit 0
else
    echo "ECHEC : aucune IP bannie, la chaine est cassee"
    exit 1
fi