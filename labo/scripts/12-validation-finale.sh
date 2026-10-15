#!/bin/bash
# =============================================================================
# VALIDATION FINALE DU LABO - meteo-test.lan
# Usage : sudo ./12-validation-finale.sh
#
# Rejoue toute la chaine de bout en bout et affiche PASS/FAIL par critere.
# Ce script est le meme qui sera execute sur le serveur de production, avec
# les 5 criteres d'ouverture de la conception (ci-dessous, notes LABO).
# =============================================================================
set -uo pipefail

DOMAINE="${DOMAINE:-meteo-test.lan}"
COFFRE=/root/labo-credentials.txt
MDP_TEST=$(sudo grep '^MDP_TEST=' "${COFFRE}" | tail -1 | cut -d= -f2-)

PASS=0
FAIL=0
CRIT=0

verdict() {
    # $1 = libelle, $2 = 0 (OK) ou 1 (KO)
    CRIT=$((CRIT + 1))
    if [ "$2" -eq 0 ]; then
        printf '  [PASS] %s\n' "$1"
        PASS=$((PASS + 1))
    else
        printf '  [FAIL] %s\n' "$1"
        FAIL=$((FAIL + 1))
    fi
}

echo "############################################################"
echo "# VALIDATION FINALE - labo mail"
echo "# $(date '+%Y-%m-%d %H:%M:%S')"
echo "############################################################"
echo ""

# --- 1. Services -----------------------------------------------------------
echo "[1] Services actifs"
for s in postfix dovecot rspamd apache2 mariadb fail2ban redis-server; do
    systemctl is-active --quiet "$s"
    verdict "$s actif" $?
done
echo ""

# --- 2. Ports ---------------------------------------------------------------
echo "[2] Ports ecoutes"
for p in 25 143 993 4190 587 11332; do
    ss -tln | grep -qE "[:.]${p}[[:space:]]"
    verdict "port $p" $?
done
for p in 443 80; do
    ss -tln | grep -qE "[:.]${p}[[:space:]]"
    verdict "port $p (HTTPS)" $?
done
echo ""

# --- 3. Postfix : sante de la config ---------------------------------------
echo "[3] Postfix"
postfix check > /dev/null 2>&1
verdict "postfix check sans erreur" $?
postconf -h virtual_mailbox_maps 2>/dev/null | grep -q 'postfix_accounts.cf'
verdict "pont fichier plat (pas de SQL)" $?
postconf -h disable_vrfy_command 2>/dev/null | grep -q '^yes$'
verdict "VRFY desactive" $?
rspamc stat 2>/dev/null | grep -q .
verdict "Rspamd joignable" $?
echo ""

# --- 4. Dovecot : sante + auth ---------------------------------------------
echo "[4] Dovecot"
doveconf -n > /dev/null 2>&1
verdict "doveconf valide" $?
doveadm auth test luc.ranaivo@"${DOMAINE}" "${MDP_TEST}" 2>&1 | grep -q 'auth succeeded'
verdict "auth SQL+Argon2id" $?
echo ""

# --- 5. Comptes -------------------------------------------------------------
echo "[5] Comptes"
# Comptage direct en SQL : la CLI postfixadmin n'a pas de tache `list`
# pour `mailbox` ("Error: Unknown task list") et la question est triviale
# a poser a la base, qui est la source de verite.
NB=$(mysql -N -e "SELECT COUNT(*) FROM postfix.mailbox WHERE domain='${DOMAINE}' AND active=1;")
[ "${NB}" -eq 5 ]
verdict "5 comptes actifs dans la base (trouve ${NB})" $?
postmap -q luc.ranaivo@"${DOMAINE}" hash:/etc/postfix/postfix_accounts.cf > /dev/null 2>&1
verdict "compte exporte vers le fichier plat" $?
echo ""

# --- 6. Cloisonnement des bases ---------------------------------------------
echo "[6] Cloisonnement MariaDB"
N_RC=$(mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='roundcube';")
[ "${N_RC}" -ge 10 ]
verdict "base roundcube peuplee (${N_RC} tables)" $?
GRANT_RC=$(mysql -N -e "SHOW GRANTS FOR 'roundcube'@'localhost';" | grep -c 'on `postfix`')
[ "${GRANT_RC}" -eq 0 ]
verdict "roundcube n'a AUCUN droit sur la base postfix" $?
GRANT_DV=$(mysql -N -e "SHOW GRANTS FOR 'dovecot'@'localhost';" | grep -c 'SELECT')
GRANT_DV_W=$(mysql -N -e "SHOW GRANTS FOR 'dovecot'@'localhost';" | grep -c 'roundcube')
[ "${GRANT_DV_W}" -eq 0 ]
verdict "dovecot n'a AUCUN droit sur roundcube" $?
echo ""

# --- 7. Securite ------------------------------------------------------------
echo "[7] Securite"
ss -tln | grep -qE '[:.]110[[:space:]]'
[ $? -ne 0 ]
verdict "POP3 (110) NON expose" $?
ss -tln | grep -qE '[:.]465[[:space:]]'
[ $? -ne 0 ]
verdict "SMTPS (465) NON expose" $?
# `doveconf -n` OMET les reglages egaux a leur valeur par defaut, or
# TLSv1.2 EST le defaut de Dovecot 2.3 -> interroger la valeur effective.
# ATTENTION : `doveconf <cle>` renvoie la ligne complete
# ("ssl_min_protocol = TLSv1.2") ; c'est `-h` qui ne sort que la valeur.
[ "$(doveconf -h ssl_min_protocol 2>/dev/null)" = "TLSv1.2" ]
verdict "TLS 1.2 minimum impose" $?
# NB_JAILS : la liste tient sur UNE ligne -> compter les occurrences, pas les
# lignes. La ligne commence par un accent grave (`- ), pas une barre verticale.
NB_JAILS=$(fail2ban-client status 2>/dev/null | grep 'Jail list:' | tr ',' '\n' | wc -l)
[ "${NB_JAILS}" -ge 5 ]
verdict "5 prisons fail2ban (trouve ${NB_JAILS})" $?
echo ""

# --- 8. Web -----------------------------------------------------------------
echo "[8] Webmail + administration"
CODE=$(curl -sk -o /dev/null -w '%{http_code}' https://webmail.meteo-test.lan/ 2>/dev/null)
[ "${CODE}" = "200" ]
verdict "webmail accessible (HTTP ${CODE})" $?
CODE=$(curl -sk -o /dev/null -w '%{http_code}' https://postfixadmin.meteo-test.lan/ 2>/dev/null)
[ "${CODE}" = "302" ] || [ "${CODE}" = "200" ]
verdict "postfixadmin accessible (HTTP ${CODE})" $?
echo ""

# --- 9. Bout-en-bout : envoi + lecture -------------------------------------
echo "[9] Bout-en-bout (SMTP 587 -> Maildir -> IMAP)"
BEFORE=$(find /var/vmail/${DOMAINE}/tiana.rakoto/new -type f 2>/dev/null | wc -l)
swaks --server 127.0.0.1 --port 587 --tls --auth LOGIN \
      --auth-user luc.ranaivo@"${DOMAINE}" --auth-password "${MDP_TEST}" \
      --from luc.ranaivo@"${DOMAINE}" --to tiana.rakoto@"${DOMAINE}" \
      --header "Subject: [VALIDATION] bout-en-bout" \
      --body "Message de validation finale." > /tmp/swaks-validation.log 2>&1
sleep 3
AFTER=$(find /var/vmail/${DOMAINE}/tiana.rakoto/new -type f 2>/dev/null | wc -l)
[ "${AFTER}" -gt "${BEFORE}" ]
verdict "message delivered (${BEFORE} -> ${AFTER})" $?

python3 - <<PYEOF
import imaplib, ssl, sys
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
try:
    m = imaplib.IMAP4_SSL("127.0.0.1", 993, ssl_context=ctx)
    m.login("tiana.rakoto@${DOMAINE}", "${MDP_TEST}")
    m.select("INBOX")
    typ, data = m.search(None, 'SUBJECT', '"[VALIDATION]"')
    n = len(data[0].split()) if data and data[0] else 0
    print("  [PASS] message lisible en IMAP (%d trouve(s))" % n)
    m.logout()
    sys.exit(0 if n > 0 else 1)
except Exception as e:
    print("  [FAIL] IMAP : %s" % e)
    sys.exit(1)
PYEOF
verdict "lecture IMAP du message de validation" $?
echo ""

# --- Verdict ----------------------------------------------------------------
echo "############################################################"
echo "# RESULTAT : ${PASS} PASS / ${FAIL} FAIL  (${CRIT} criteres)"
if [ "${FAIL}" -eq 0 ]; then
    echo "# VERDICT : TOUT EST VERT"
else
    echo "# VERDICT : ${FAIL} CRITERE(S) EN ECHEC"
fi
echo "############################################################"
exit "${FAIL}"