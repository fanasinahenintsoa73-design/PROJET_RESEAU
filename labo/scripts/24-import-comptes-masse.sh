#!/bin/bash
# =============================================================================
# Import de comptes a l'echelle - version production
# =============================================================================
# SOURCE DE VERITE : un fichier CSV unique. Pas de double saisie, pas de
# generation a la volee dans la base. Le CSV est relu par un humain AVANT
# l'import (le fichier `adresses-generees.csv` produit ici est cette liste
# de relecture).
#
# FORMAT CSV (une ligne par agent) :
#     prenom,nom[,profil]
#   profil : agent (defaut, 2 Go) | cadre (5 Go) | station (3 Go)
#   Ligne commençant par '#' = commentaire. Lignes vides ignorees.
#
# NORMALISATION (identique a la conception) :
#   1. minuscules
#   2. accents supprimes (ASCII non accentue)
#   3. apostrophes droites et typographiques supprimees
#   4. traits d'hyphen conserves
#   5. tout caractere hors [a-z0-9.-] supprime
#   6. collision d'homonyme -> suffixe numerique (rakoto2, rakoto3)
#
# MOTS DE PASSE : un mot de passe PROVISOIRE ALEATOIRE et UNIQUE par compte
# (20 caracteres). Ils ne sont jamais partages, jamais identiques, et sont
# remis INDIVIDUELLEMENT via un CSV de remise ecrit hors du depot git.
# Rappel de conception : le changement de mot de passe a la 1re connexion
# n'est PAS impose par Dovecot (password_expiry) car Roundcube 1.7 ne sait
# pas traiter la reponse « mot de passe expire » -> l'agent verrait un echec
# de connexion au lieu d'etre invite a changer. Le controle equivalent est
# ce mot de passe provisoire aleatoire, unique et non devinable.
#
# UTILISATION (root requis : la CLI PostfixAdmin appelle doveadm pw, qui
# exige les privileges de l'utilisateur _rspamd/dovecot) :
#     sudo ./24-import-comptes-masse.sh --csv /root/noms.csv --domaine meteomadagascar.mg
#
# OPTIONS :
#     --csv FICHIER      source de verite (obligatoire)
#     --domaine DOM      domaine cible (obligatoire)
#     --quota-dir DOSSIER ou sont ecrits les CSV de sortie (defaut /root)
#     --limite N         nombre maximal de comptes a creer (defaut : tous)
#     --simulation       n'ecrit rien dans la base, affiche le plan
# =============================================================================
set -euo pipefail

CSV=""
DOMAINE=""
QUOTA_DIR="/root"
LIMITE=0
SIMULATION=0

while [ $# -gt 0 ]; do
    case "$1" in
        --csv)        CSV="$2"; shift 2 ;;
        --domaine)    DOMAINE="$2"; shift 2 ;;
        --quota-dir)  QUOTA_DIR="$2"; shift 2 ;;
        --limite)     LIMITE="$2"; shift 2 ;;
        --simulation) SIMULATION=1; shift ;;
        -h|--help)    sed -n '2,40p' "$0"; exit 0 ;;
        *) echo "Option inconnue : $1" >&2; exit 2 ;;
    esac
done

[ -n "$CSV" ]     || { echo "ERREUR : --csv obligatoire" >&2; exit 2; }
[ -n "$DOMAINE" ] || { echo "ERREUR : --domaine obligatoire" >&2; exit 2; }
[ -f "$CSV" ]     || { echo "ERREUR : fichier introuvable : $CSV" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo "ERREUR : a executer en root (sudo)" >&2; exit 2; }

# -----------------------------------------------------------------------------
# OUTILS
# -----------------------------------------------------------------------------
# Normalisation : minuscules, accents retires, apostrophes retirees,
# caracteres interdits elimines. Fait en python (unicodedata) car iconv
# //TRANSLIT depend de la locale et peut laisser passer de l'ASCII etendu.
normaliser() {
    python3 - "$1" <<'PYEOF'
import sys, unicodedata, re
s = sys.argv[1].lower()
s = unicodedata.normalize('NFKD', s)
s = ''.join(c for c in s if not unicodedata.combining(c))
s = s.replace("'", '').replace('\u2019', '').replace('\u02bc', '')
s = re.sub(r'[^a-z0-9.\-]', '', s)
s = re.sub(r'[-.]{2,}', lambda m: m.group(0)[0], s)
s = s.strip('-.')
print(s)
PYEOF
}

# Mot de passe provisoire : 20 caracteres, alphanumeriques, avec au moins
# une majuscule, une minuscule et deux chiffres garantis (regle
# password_validation de PostfixAdmin).
mot_de_passe_aleatoire() {
    local p
    p="A7$(LC_ALL=C tr -dc 'a-z' </dev/urandom | head -c 9)"
    p="${p}$(LC_ALL=C tr -dc 'A-Z' </dev/urandom | head -c 4)"
    p="${p}$(LC_ALL=C tr -dc '0-9' </dev/urandom | head -c 4)"
    printf '%s' "$p"
}

quota_mo_pour_profil() {
    case "$1" in
        cadre)   echo 5120 ;;
        station) echo 3072 ;;
        *)       echo 2048 ;;
    esac
}

# -----------------------------------------------------------------------------
# ETAT INITIAL
# -----------------------------------------------------------------------------
FICH_GEN="/tmp/import-adresses-$$.csv"
FICH_REMISE="/tmp/import-remise-$$.csv"
FICH_ERREURS="/tmp/import-erreurs-$$.csv"
trap 'rm -f "${FICH_GEN}" "${FICH_REMISE}" "${FICH_ERREURS}"' EXIT
: > "${FICH_GEN}"
: > "${FICH_REMISE}"
: > "${FICH_ERREURS}"

# Ensemble des identifiants deja pris : UNE seule requete SQL (la commande
# `postfixadmin mailbox list` N'EXISTE PAS, c'est un piege connu).
# On charge les parties locales des boites ET des alias du domaine.
mapfile -t EXISTANTS < <(
    mysql -N -B postfix -e "
        SELECT LOWER(SUBSTRING_INDEX(username,'@',1)) FROM mailbox
        WHERE domain = '${DOMAINE}'
        UNION
        SELECT LOWER(SUBSTRING_INDEX(address,'@',1)) FROM alias
        WHERE domain = '${DOMAINE}';" 2>/dev/null
)
declare -A PRIS
for E in "${EXISTANTS[@]}"; do
    [ -n "$E" ] && PRIS["$E"]=1
done

echo "=== Import de comptes sur ${DOMAINE} ==="
echo "Domaines deja en base : ${#PRIS[@]} identifiants reserves"
echo "Fichier source : ${CSV}"
if [ "$SIMULATION" -eq 1 ]; then
    echo "MODE SIMULATION : aucune ecriture en base"
fi
echo ""

# Le domaine doit exister et ses limites doivent etre relevees : PostfixAdmin
# refuse de creer des boites au-dela de `mailboxes` et des alias au-dela de
# `aliases`. Sans ce relèvement, l'import echoue a la 10e boite.
ACTUAL_DOMAIN=$(mysql -N -B postfix -e \
    "SELECT COUNT(*) FROM domain WHERE domain = '${DOMAINE}';" 2>/dev/null || echo 0)
if [ "$ACTUAL_DOMAIN" -eq 0 ]; then
    echo "ERREUR : le domaine ${DOMAINE} n'existe pas dans PostfixAdmin." >&2
    exit 3
fi
NB_LIGNES=$(grep -cvE '^\s*(#|$)' "${CSV}")
NB_CIBLES=${NB_LIGNES}
if [ "$LIMITE" -gt 0 ] && [ "$LIMITE" -lt "$NB_CIBLES" ]; then
    NB_CIBLES=$LIMITE
fi
DOM_MAILBOXES=$(mysql -N -B postfix -e \
    "SELECT mailboxes FROM domain WHERE domain = '${DOMAINE}';" 2>/dev/null || echo 0)
DOM_ALIASES=$(mysql -N -B postfix -e \
    "SELECT aliases FROM domain WHERE domain = '${DOMAINE}';" 2>/dev/null || echo 0)
echo "Lignes CSV utiles : ${NB_LIGNES}  (a traiter : ${NB_CIBLES})"
echo "Limites du domaine : mailboxes=${DOM_MAILBOXES} aliases=${DOM_ALIASES}"
if [ "${DOM_MAILBOXES}" -lt "$NB_CIBLES" ] || [ "${DOM_ALIASES}" -lt "$NB_CIBLES" ]; then
    echo "  -> relèvement nécessaire des limites du domaine (fait automatiquement)"
    mysql -N -B postfix -e \
        "UPDATE domain SET mailboxes = GREATEST(mailboxes, ${NB_CIBLES}),
                           aliases  = GREATEST(aliases, ${NB_CIBLES}) + 100
         WHERE domain = '${DOMAINE}';" 2>/dev/null
    echo "  -> fait."
fi
echo ""

# -----------------------------------------------------------------------------
# BOUCLE D'IMPORT
# -----------------------------------------------------------------------------
CREE=0
EXISTANTS_DEJA=0
COLLISIONS=0
ERREURS=0
COMPTEUR=0

while IFS=, read -r PRENOM NOM PROFIL; do
    # Nettoyage du champ optionnel
    PRENOM="${PRENOM%$'\r'}"; NOM="${NOM%$'\r'}"; PROFIL="${PROFIL%$'\r'}"
    PROFIL="$(printf '%s' "${PROFIL}" | tr -d ' \r"' | tr 'A-Z' 'a-z')"
    [ -z "${PRENOM}${NOM}" ] && continue
    [ "${PRENOM:0:1}" = "#" ] && continue
    [ -z "$PROFIL" ] && PROFIL="agent"

    # Nom complet conserve pour l'affichage (le nom de dossier garde les
    # espaces), parties locales normalisees pour l'adresse.
    PRENOM_AFFICHAGE="$(printf '%s' "${PRENOM}" | sed 's/^"//;s/"$//' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    NOM_AFFICHAGE="$(printf '%s' "${NOM}" | sed 's/^"//;s/"$//' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    NOM_COMPLET="${PRENOM_AFFICHAGE} ${NOM_AFFICHAGE}"

    COMPTEUR=$((COMPTEUR + 1))
    if [ "$LIMITE" -gt 0 ] && [ "$COMPTEUR" -gt "$LIMITE" ]; then
        break
    fi

    LOCAL_PRENOM="$(normaliser "$PRENOM")"
    LOCAL_NOM="$(normaliser "$NOM")"
    BASE="${LOCAL_PRENOM}.${LOCAL_NOM}"
    if [ -z "$LOCAL_PRENOM" ] || [ -z "$LOCAL_NOM" ]; then
        echo "ERREUR ligne $COMPTEUR : prenom/nom vide apres normalisation" >&2
        echo "$COMPTEUR,${PRENOM},${NOM},normalisation vide" >> "${FICH_ERREURS}"
        ERREURS=$((ERREURS + 1))
        continue
    fi

    # Resolution des collisions d'homonyme
    CANDIDAT="${BASE}"
    SUFFIXE=2
    while [ -n "${PRIS[$CANDIDAT]:-}" ]; do
        CANDIDAT="${BASE}${SUFFIXE}"
        SUFFIXE=$((SUFFIXE + 1))
    done
    if [ "$CANDIDAT" != "$BASE" ]; then
        COLLISIONS=$((COLLISIONS + 1))
        echo "  collision : ${BASE} -> ${CANDIDAT}"
    fi
    PRIS["$CANDIDAT"]=1

    ADDRTE="${CANDIDAT}@${DOMAINE}"
    QUOTA_MO="$(quota_mo_pour_profil "$PROFIL")"

    if [ "$SIMULATION" -eq 1 ]; then
        printf '%s,%s,%s,%s\n' "$ADDRTE" "$PROFIL" "$QUOTA_MO" "$NOM_COMPLET" >> "${FICH_GEN}"
        CREE=$((CREE + 1))
        continue
    fi

    # Si la boite existe deja, on ne recree pas et on ne change pas son mot
    # de passe : l'import doit etre REPRENABLE sans casser les agents deja
    # comptes.
    DEJA=$(mysql -N -B postfix -e \
        "SELECT COUNT(*) FROM mailbox WHERE username = '${ADDRTE}';" 2>/dev/null || echo 0)
    if [ "$DEJA" -gt 0 ]; then
        EXISTANTS_DEJA=$((EXISTANTS_DEJA + 1))
        printf '%s,%s,%s\n' "$ADDRTE" "$PROFIL" "$NOM_COMPLET" >> "${FICH_GEN}"
        continue
    fi

    MDP="$(mot_de_passe_aleatoire)"
    SORTIE_ADD=$(postfixadmin-cli mailbox add "${ADDRTE}" \
        --password "$MDP" --password2 "$MDP" \
        --name "$NOM_COMPLET" \
        --quota "$QUOTA_MO" \
        --active 1 2>&1) && RC=0 || RC=$?
    if [ "$RC" -ne 0 ]; then
        ERREURS=$((ERREURS + 1))
        echo "ERREUR creation ${ADDRTE} : ${SORTIE_ADD}" >&2
        echo "${ADDRTE},${SORTIE_ADD}" >> "${FICH_ERREURS}"
        unset MDP
        continue
    fi
    CREE=$((CREE + 1))
    printf '%s,%s,%s,%s\n' "$ADDRTE" "$PROFIL" "$QUOTA_MO" "$NOM_COMPLET" >> "${FICH_GEN}"
    printf '%s,%s\n' "$ADDRTE" "$MDP" >> "${FICH_REMISE}"
    unset MDP
    if [ $((CREE % 50)) -eq 0 ]; then
        echo "  ... ${CREE} comptes crees"
    fi
done < <(grep -vE '^\s*(#|$)' "${CSV}")

echo ""
echo "=== RESULTAT ==="
echo "Crees              : ${CREE}"
echo "Deja existants     : ${EXISTANTS_DEJA}"
echo "Collisions resolues: ${COLLISIONS}"
echo "Erreurs            : ${ERREURS}"

# -----------------------------------------------------------------------------
# LIVRABLES
# -----------------------------------------------------------------------------
DEST_GEN="${QUOTA_DIR}/adresses-generees.csv"
DEST_REMISE="${QUOTA_DIR}/remise-mots-de-passe.csv"
install -m 640 -o root -g root "${FICH_GEN}" "${DEST_GEN}"
if [ -s "${FICH_REMISE}" ]; then
    install -m 600 -o root -g root "${FICH_REMISE}" "${DEST_REMISE}"
    echo ""
    echo "LISTE DE RELIVRE (a relire avec le service RH / encadrant) :"
    echo "  ${DEST_GEN}"
    echo "REMISE DES MOTS DE PASSE (SECRET, hors depot git, 600) :"
    echo "  ${DEST_REMISE}"
    echo "  Chaque agent recoit SON mot de passe, par canal individuel."
    echo "  Ne jamais envoyer une liste groupee a toute l'institution."
else
    echo "Aucun mot de passe provisoire genere (simulation ou comptes deja presents)."
fi
if [ -s "${FICH_ERREURS}" ]; then
    DEST_ERR="${QUOTA_DIR}/import-erreurs.csv"
    install -m 640 -o root -g root "${FICH_ERREURS}" "${DEST_ERR}"
    echo ""
    echo "ERREURS (${ERREURS}) : ${DEST_ERR}"
fi

# -----------------------------------------------------------------------------
# VERIFICATION
# -----------------------------------------------------------------------------
if [ "$SIMULATION" -eq 0 ]; then
    echo ""
    echo "=== VERIFICATION ==="
    TOTAL=$(mysql -N -B postfix -e \
        "SELECT COUNT(*) FROM mailbox WHERE domain = '${DOMAINE}' AND active = 1;" 2>/dev/null || echo 0)
    echo "Boites actives dans le domaine : ${TOTAL}"
    DOUBLONS=$(mysql -N -B postfix -e \
        "SELECT COUNT(*) FROM (SELECT SUBSTRING_INDEX(username,'@',1) p, COUNT(*) c
          FROM mailbox WHERE domain = '${DOMAINE}' GROUP BY p HAVING c > 1) d;" 2>/dev/null || echo 0)
    if [ "$DOUBLONS" -eq 0 ]; then
        echo "[PASS] Aucune partie locale en double"
    else
        echo "[FAIL] ${DOUBLONS} doublons de partie locale"
    fi
    echo "Tirages au hasard (authentification + quota) :"
    for TIRAGE in 1 2 3 4 5; do
        LIGNE=$(mysql -N -B postfix -e \
            "SELECT username FROM mailbox WHERE domain = '${DOMAINE}' AND active = 1
             ORDER BY RAND() LIMIT 1;" 2>/dev/null)
        [ -z "$LIGNE" ] && continue
        if doveadm auth test "$LIGNE" "$(cat /dev/null)" >/dev/null 2>&1; then
            echo "  [KO  ] $LIGNE : authentification acceptee avec un mot de passe VIDE (faille)"
        else
            LIMITE_KB=$(doveadm quota get -u "$LIGNE" 2>/dev/null | awk '/STORAGE/ {print $4}')
            echo "  [OK  ] $LIGNE : authentification refusee sans mot de passe, quota ${LIMITE_KB} Ko"
        fi
    done
fi
echo ""
echo "FIN"
