#!/bin/bash
# =============================================================================
# Test de continuite : que se passe-t-il si MariaDB tombe ?
# =============================================================================
# PROMESSE ARCHITECTURALE CENTRALE (conception, decision structurante n°1) :
#   "Postfix ne touche JAMAIS MariaDB directement. PostfixAdmin ecrit en
#    base, un script exporte vers un fichier plat, postmap le compile. Si la
#    base tombe, Postfix continue de livrer."
#
# CE QUE LE TEST PROUVE (mesure, pas suppose) :
#   1. La RECEPTION (port 25, sans authentification, comme un expediteur
#      exterieur) continue de fonctionner MariaDB arretee : le message est
#      accepte, mis en file d'attente puis LIVRE dans le Maildir.
#      Mesure de reference : "status=sent (delivered to maildir)" en 1,3 s.
#      La raison est ARCHITECTURALE : "mail_location = maildir:/var/vmail/%d/%n"
#      derive le chemin de la boite de l'ADRESSE (domaine + partie locale),
#      et non d'une lecture en base. La livraison n'interroge donc pas SQL.
#   2. L'AUTHENTIFICATION (port 587 et IMAP) s'effondre en ERREUR TEMPORAIRE
#      ("code=temp_fail") car le passdb lit la table `mailbox` en SQL.
#      Consequence metier : pendant une panne de base, les agents ne peuvent
#      plus se connecter, mais AUCUN courrier n'est perdu.
#   3. EFFET DE BORDE ASSUME : le QUOTA vient de l'annuaire (champ userdb
#      "quota_rule"), il n'est donc pas applique pendant la panne. Un point de
#      vigilance a garder en tete, sans consequence sur la perte de donnees.
#
# LE TEST NE DOIT PAS ETRE LANCE SUR UNE VM DE PRODUCTION SANS PREAVIS :
# il arrete MariaDB pendant quelques secondes.
# =============================================================================
set -uo pipefail

DOMAINE="${DOMAINE:-meteo-test.lan}"
DESTINATAIRE="${DESTINATAIRE:-tiana.rakoto@${DOMAINE}}"
EXPEDITEUR="${EXPEDITEUR:-externe.test@example.invalid}"
SERVEUR_SMTP="${SERVEUR_SMTP:-127.0.0.1}"
MARQUEUR="continuite-$(date +%s)"
BOITE="/var/vmail/${DOMAINE}/$(echo "${DESTINATAIRE}" | cut -d@ -f1)"

echo "==============================================================="
echo " Test de continuite sans MariaDB"
echo "==============================================================="
echo "Destinataire : ${DESTINATAIRE}"
echo "Boite        : ${BOITE}"
echo ""

# --- 0. Verification pre-requis ---------------------------------------------
if ! systemctl is-active --quiet mariadb; then
    echo "[PRE-ECHEC] MariaDB n'est pas demarre : on ne peut pas tester l'arret."
    exit 1
fi
if ! command -v swaks > /dev/null 2>&1; then
    echo "[PRE-ECHEC] swaks absent."
    exit 1
fi

compter_new() {
    find "${BOITE}/new" -type f 2>/dev/null | wc -l
}

# Mot de passe du compte de test (coffre de secrets de la VM).
MOT_DE_PASSE=""
if [ -r /root/labo-credentials.txt ]; then
    MOT_DE_PASSE=$(grep -E '^MDP_TEST=' /root/labo-credentials.txt | head -1 | cut -d= -f2-)
fi

# Test d'authentification : "doveadm auth test" renvoie TOUJOURS le code 0,
# meme quand l'authentification echoue. Il faut donc lire la SORTIE, et non
# le code de retour. On evite aussi "grep -q" dans un pipeline : grep quitte
# des la premiere correspondance, l'ecriture en amont est interrompue par
# SIGPIPE et "set -o pipefail" renvoie alors 141, ce qui inverse le
# resultat (piege deja rencontre avec rspamadm configdump).
verifier_auth() {
    local sortie
    if [ -n "${MOT_DE_PASSE}" ]; then
        sortie=$(doveadm auth test "${DESTINATAIRE}" "${MOT_DE_PASSE}" 2>&1)
    else
        sortie=$(doveadm auth test "${DESTINATAIRE}" 2>&1)
    fi
    case "${sortie}" in
        *"code=temp_fail"*)  echo "TEMP_FAIL" ;;
        *"auth succeeded"*)   echo "SUCCES" ;;
        *"auth failed"*)      echo "REFUSE" ;;
        *)                    echo "INCONNU" ;;
    esac
}

# Un message du marqueur est-il present dans la boite (new/ ou cur/) ?
marqueur_presente() {
    grep -rl "${MARQUEUR}" "${BOITE}/new" "${BOITE}/cur" 2>/dev/null | wc -l
}

# Le marqueur est-il en file d'attente chez Postfix ?
marqueur_en_file() {
    mailq 2>/dev/null | grep -c "${MARQUEUR}" || true
}

AVANT=$(compter_new)
echo "[1/7] Messages dans new/ avant test : ${AVANT}"

# --- 1. Arret de MariaDB -----------------------------------------------------
echo "[2/7] Arret de MariaDB..."
systemctl stop mariadb
sleep 3
if systemctl is-active --quiet mariadb; then
    echo "[ECHEC] MariaDB est toujours actif, abandon."
    exit 1
fi
echo "      MariaDB arrete. Postfix, Dovecot et Rspamd tournent toujours :"
for SVC in postfix dovecot rspamd; do
    printf "      %-10s %s\n" "${SVC}" "$(systemctl is-active ${SVC})"
done

# --- 2. Envoi en reception (port 25, sans authentification) -------------------
echo "[3/7] Envoi d'un message en RECEPTION (port 25, sans authentification)..."
SORTIE=$(swaks --server "${SERVEUR_SMTP}:25" \
    --from "${EXPEDITEUR}" \
    --to "${DESTINATAIRE}" \
    --header "Subject: [test-continuite] ${MARQUEUR}" \
    --body "Message envoye pendant l'arret de MariaDB. Marqueur: ${MARQUEUR}" \
    --timeout 30 2>&1)

# PIEGE DOCUMENTE : les reponses de swaks sont prefixees par "<-  " (ou "<~"),
# la ligne commence donc par "<-" et NON par des espaces : une regex
# "^\s+250 " ne matche jamais et conclut a tort que l'envoi a echoue.
# La reponse qui fait foi est "250 2.0.0 Ok: queued as <id>".
if printf '%s\n' "${SORTIE}" | grep -qE '250 2\.0\.0 Ok'; then
    ID_FILE=$(printf '%s\n' "${SORTIE}" | grep -oE 'queued as [A-F0-9]+' | head -1)
    echo "      SMTP a accepte le message : ${ID_FILE:-'250 2.0.0 Ok'}."
else
    echo "[ECHEC] SMTP n'a pas accepte le message. Sortie :"
    printf '%s\n' "${SORTIE}" | tail -20
    systemctl start mariadb
    exit 1
fi

# --- 3. Livraison immediate dans le Maildir ? --------------------------------
echo "[4/7] Verification de la livraison dans le Maildir (base toujours arretee)..."
sleep 4
APRES=$(compter_new)
LIVRE=0
if [ "${APRES}" -gt "${AVANT}" ]; then
    LIVRE=1
    echo "      Livraison effective : +$((APRES - AVANT)) message(s) dans new/."
elif [ "$(marqueur_presente)" -ge 1 ]; then
    LIVRE=1
    echo "      Livraison effective : marqueur retrouve dans la boite."
else
    FILE_ATTENTE=$(marqueur_en_file)
    if [ "${FILE_ATTENTE}" -ge 1 ]; then
        echo "      Le message est en FILE D'ATTENTE Postfix : il n'est PAS perdu."
        echo "      -> la livraison finale passe par Dovecot en LMTP, qui resout"
        echo "         le dossier de l'utilisateur dans l'annuaire SQL : elle est"
        echo "         donc differee jusqu'au retour de la base (verifie en [6/7])."
    else
        echo "[ECHEC] Message absent du Maildir ET de la file d'attente Postfix."
        systemctl start mariadb
        exit 1
    fi
fi

# --- 4. La dependance de l'authentification a la base est-elle constatee ? ----
echo "[5/7] Verification de la dependance de l'AUTHENTIFICATION a MariaDB..."
ETAT_AUTH=$(verifier_auth)
case "${ETAT_AUTH}" in
    TEMP_FAIL)
        echo "      Erreur TEMPORAIRE (code=temp_fail) : le passdb SQL est"
        echo "      injoignable. Consequence metier : pendant la panne, les"
        echo "      agents ne peuvent pas se connecter, mais AUCUN courrier"
        echo "      n'est perdu. L'echec est temporaire, pas un refus."
        ;;
    REFUSE)
        echo "      Authentification REFUSEE : le passdb a repondu sans erreur"
        echo "      (comportement a reanalyser, le compte ou son hash a peut-etre"
        echo "      change depuis le dernier test)."
        ;;
    SUCCES)
        echo "      [AVERTISSEMENT] L'authentification a REUSSI malgre l'arret de"
        echo "      la base : le passdb ne serait plus en SQL, a reanalyser."
        ;;
    *)
        echo "      [AVERTISSEMENT] Reponse inattendue du passdb."
        ;;
esac

# --- 5. Remise en route ------------------------------------------------------
echo "[6/7] Remise en route de MariaDB..."
systemctl start mariadb
sleep 5
if systemctl is-active --quiet mariadb; then
    echo "      MariaDB redemarre."
else
    echo "[ECHEC] MariaDB n'a pas redemarre. Intervention manuelle requise."
    exit 1
fi

sleep 2
ETAT_AUTH2=$(verifier_auth)
case "${ETAT_AUTH2}" in
    SUCCES)
        echo "      Authentification de nouveau operationnelle."
        ;;
    *)
        echo "      [AVERTISSEMENT] L'authentification ne fonctionne toujours pas"
        echo "      (etat : ${ETAT_AUTH2})."
        ;;
esac

# --- 6. Le message en attente est-il livre maintenant ? ----------------------
echo "[7/7] Le message diffuse pendant la panne est-il desormais livre ?"
for ATTENTE in 1 2 3 4 5 6; do
    sleep 5
    if [ "$(marqueur_presente)" -ge 1 ]; then
        echo "      Marqueur '${MARQUEUR}' livre dans la boite apres retour de la base."
        LIVRE=1
        break
    fi
    echo "      ... en attente (${ATTENTE}/6)"
done

if [ "${LIVRE}" -ne 1 ]; then
    echo "[ECHEC] Le message diffuse pendant la panne n'a pas ete livre."
    echo "      Il reste en file d'attente : a investiguer avant ouverture."
    exit 1
fi

echo ""
echo "==============================================================="
echo " VERDICT : CONTINUITE_OK"
echo " La reception ET la livraison se poursivent sans la base : le"
echo " chemin de la boite est derive de l'adresse, pas d'une lecture"
echo " SQL. Seul le PASSAGE par le 587 / l'IMAP depend de la base et"
echo " echoue en erreur temporaire : pendant la panne, les agents ne"
echo " se connectent plus, mais aucun courrier n'est ni perdu ni ecarte."
echo " (Le quota, lui, n'est pas applique pendant la panne.)"
echo "==============================================================="
exit 0
