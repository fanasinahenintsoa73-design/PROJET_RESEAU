#!/bin/bash
# =============================================================================
# TEST D'OPEN RELAY - critere d'ouverture n° 3
# Usage : sudo ./17-test-open-relay.sh
#
# Un serveur de messagerie mal configure sert de relais a quiconque
# veut envoyer du spam. Les victimes ne sont alors plus les agents de la
# meteo mais les destinataires du monde entier, et c'est l'ADRESSE IP de
# la DGM qui se fait blacklister. C'est le risque le plus cher du projet.
#
# 4 scenarios. On utilise example.invalid (RFC 2606, reserve et non
# routable) : rien ne part reellement, on teste uniquement la reponse
# du serveur a l'etape RCPT.
# =============================================================================
set -uo pipefail

DOMAINE="${DOMAINE:-meteo-test.lan}"
SERVEUR=127.0.0.1
COMPTE="tiana.rakoto@${DOMAINE}"
# Le mot de passe vient du coffre de la VM, jamais du depot git.
MDP="${MDP_TEST:-$(grep '^MDP_TEST=' /root/labo-credentials.txt 2>/dev/null | cut -d= -f2-)}"
[ -n "${MDP}" ] || { echo "ERREUR : MDP_TEST absent du coffre" >&2; exit 1; }
EXTERNE="victime@example.invalid"

PASS=0
FAIL=0

# Rend le code de reponse du serveur a l'etape RCPT.
# swaks ecrit les lignes du serveur comme :
#    -> RCPT TO:<destinataire>
#   <-  250 2.1.5 Ok
# La reponse est donc la ligne IMMEDIATEMENT apres « RCPT TO: ».
# (Ne pas chercher de marqueur « *** » : swaks n'en emet pas.)
code_reponse() {
    grep -A1 'RCPT TO:' "$1" 2>/dev/null | tail -1 | grep -oE '[0-9]{3}' | head -1
}

test_case() {
    local nom="$1" attendus="$2" description="$3" log="$4"
    local code
    code=$(code_reponse "${log}")
    # Postfix refuse un relais avec 550 (commande rejetee) OU 554
    # (transaction echouee). Les deux sont des refus : on accepte
    # l'un ou l'autre plutot que d'exiger un code unique.
    if echo ",${attendus}," | grep -q ",${code},"; then
        echo "  [PASS] ${nom}"
        echo "         ${description}"
        PASS=$((PASS+1))
    else
        echo "  [FAIL] ${nom}"
        echo "         ${description}"
        echo "         attendu ${attendus}, obtenu ${code:-aucun}"
        grep -E '<--|--> ' "${log}" | tail -4 | sed 's/^/         | /'
        FAIL=$((FAIL+1))
    fi
}

echo "########################################################"
echo "# TEST D'OPEN RELAY"
echo "# $(date '+%Y-%m-%d %H:%M:%S')"
echo "########################################################"
echo

# ---------------------------------------------------------------------------
# PREPARATION : simuler un attaquant situe sur Internet
# ---------------------------------------------------------------------------
# Piege majeur : connecte depuis 127.0.0.1, le serveur fait confiance a
# la machine locale (permit_mynetworks) et ACCEPTE le relais. Un test
# fait ainsi ne teste rien : il donne un faux sentiment de securite.
#
# Pour reproduire les conditions reelles, on retire temporairement toute
# adresse locale de mynetworks : la seule IP encore declaree de confiance
# est 127.0.0.1, et les tests se font depuis l'adresse de la VM, comme si
# la connexion venait d'Internet.
#
# La restauration est garantie, meme en cas d'interruption (trap).
# ---------------------------------------------------------------------------
IP_LOCAL=$(hostname -I | awk '{print $1}')
MYNETWORKS_AVANT=$(postconf -h mynetworks)

restaurer() {
    postconf -e "mynetworks = ${MYNETWORKS_AVANT}"
    postfix reload > /dev/null 2>&1
    echo
    echo "  mynetworks restaure : ${MYNETWORKS_AVANT}"
}
trap restaurer EXIT INT TERM

echo "[0/4] Simulation d'un attaquant situe sur Internet"
echo "  mynetworks avant   : ${MYNETWORKS_AVANT}"
postconf -e "mynetworks = 127.0.0.1/32"
postfix reload
sleep 2
echo "  mynetworks pendant : $(postconf -h mynetworks)"
echo "  source des tests   : ${IP_LOCAL} (hors mynetworks => traitee comme exterieure)"
echo

# --- Test 1 : livraison locale sans authentification -> doit aboutir ------
echo "[1/4] Livraison locale sans authentification (doit aboutir)"
LOG=/tmp/relay-1.log
swaks --server "${IP_LOCAL}" --from "${COMPTE}" \
      --to "luc.ranaivo@${DOMAINE}" \
      --quit-after RCPT --timeout 25 > "${LOG}" 2>&1
test_case "Livraison interne acceptee" "250" \
          "Un agent peut envoyer a un collegue sans s'authentifier" "${LOG}"
echo

# --- Test 2 : relais vers un domaine externe sans auth -> doit ECHOUER ----
echo "[2/4] Relais vers un domaine externe sans authentification (doit echouer)"
LOG=/tmp/relay-2.log
swaks --server "${IP_LOCAL}" --from "${COMPTE}" \
      --to "${EXTERNE}" \
      --quit-after RCPT --timeout 25 > "${LOG}" 2>&1
test_case "Relais externe REFUSE" "550,554,501" \
          "C'est LE test anti-relais : le serveur ne doit pas transmettre" "${LOG}"
echo

# --- Test 3 : relais externe AVEC authentification -> doit aboutir --------
# ATTENTION : ce test passe par le port 587 (soumission), PAS par le 25.
# Le port 25 est le port de RECEPTION des serveurs distants : il
# n'accepte volontairement aucune authentification. C'est meme une
# protection : un attaquant ne peut pas utiliser le port 25 pour s'authentifier.
echo "[3/4] Relais externe avec authentification sur le port 587 (doit aboutir)"
LOG=/tmp/relay-3.log
# --tls obligatoire : Postfix n'annonce AUTH qu'APRÈS STARTTLS, pour ne
# jamais faire circuler les identifiants en clair. Sans --tls, swaks
# echoue avec « Host did not advertise authentication ».
swaks --server "${IP_LOCAL}" --port 587 --tls --from "${COMPTE}" \
      --to "${EXTERNE}" \
      --auth LOGIN --auth-user "${COMPTE}" --auth-password "${MDP}" \
      --quit-after RCPT --timeout 25 > "${LOG}" 2>&1
test_case "Envoi externe authentifie accepte" "250" \
          "Un agent identifie DOIT pouvoir ecrire a l'exterieur, sinon la messagerie est inexploitable" "${LOG}"
echo

# --- Test 4 : contournement par adresse IP brute -> doit ECHOUER ---------
echo "[4/4] Tentative de relais via une adresse IP brute (contournement)"
LOG=/tmp/relay-4.log
# 203.0.113.5 = TEST-NET-3 (RFC 5737), reserve et non routable.
swaks --server "${IP_LOCAL}" --from "${COMPTE}" \
      --to "victime@[203.0.113.5]" \
      --quit-after RCPT --timeout 25 > "${LOG}" 2>&1
test_case "Contournement par IP brute REFUSE" "550,554,501" \
          "Ecrire directement a une IP plutot qu'a un nom contourne parfois le filtrage" "${LOG}"
echo

echo "########################################################"
echo "# RESULTAT : ${PASS} reussis, ${FAIL} echecs sur 4"
if [ "${FAIL}" -eq 0 ]; then
    echo "#"
    echo "# Le critere d'ouverture n° 3 est satisfait."
    echo "# Le serveur ne peut pas etre utilise comme relais de spam."
else
    echo "#"
    echo "# ECHEC : NE PAS OUVRIR LA MESSAGERIE."
    echo "# Une IP utilisee comme relais se fait blacklister, et il"
    echo "# faut alors obtenir une nouvelle adresse aupres de l'hebergeur."
fi
echo "########################################################"

[ "${FAIL}" -eq 0 ] && exit 0 || exit 1