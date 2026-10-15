#!/bin/bash
# =============================================================================
# Import de comptes de test - LABO meteo-test.lan
# =============================================================================
# REGLE DE NORMALISATION (identite avec la prod) :
#   1. tout en minuscules
#   2. accents supprimes (ASCII non accentue)
#   3. apostrophes supprimees
#   4. traits d'hyphen conserves
#   5. collision d'homonyme -> suffixe numerique automatique (rakoto2, rakoto3)
#
# En prod : remplacer les mots de passe provisoires, changer le domaine,
#           changer le nombre de comptes. Le reste du script est identique.
# =============================================================================
set -euo pipefail

DOMAINE="${DOMAINE:-meteo-test.lan}"
MDP_PROVISOIRE="${MDP_PROVISOIRE:-LaboMeteo2026!}"

# 5 comptes fictifs : prenoms/noms malgaches realistes mais inventes
COMPTES=(
    "tiana.rakoto"
    "luc.ranaivo"
    "fara.andrianina"
    "naina.rasoanaivo"
    "tojoa.rakotomalala"
)

echo "=== Import de ${#COMPTES[@]} comptes sur $DOMAINE ==="
echo ""

# 1. Creation du domaine
echo "--- Domaine ---"
sudo postfixadmin domain add "$DOMAINE" || echo "(domaine deja present)"
sudo postfixadmin domain set "$DOMAINE" description="Domaine labo - fictif"

# 2. Comptes
for ADDRTE in "${COMPTES[@]}"; do
    # Normalisation : minuscules + suppression accents + apostrophes
    NORMALISE=$(echo "$ADDRTE" \
        | tr 'A-Z' 'a-z' \
        | sed "s/'//g" \
        | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
        || echo "$ADDRTE")

    # Detection de collision d'homonyme
    SUFFIXE=""
    CANDIDAT="$NORMALISE"
    COMPTE=2
    while sudo postfixadmin mailbox list "$DOMAINE" 2>/dev/null | grep -q "^$CANDIDAT@"; do
        CANDIDAT="${NORMALISE}${COMPTE}"
        COMPTE=$((COMPTE + 1))
    done
    [ "$CANDIDAT" != "$NORMALISE" ] && echo "  collision detectee : $NORMALISE -> $CANDIDAT"

    echo "--- $CANDIDAT@$DOMAINE ---"
    sudo postfixadmin mailbox add "$CANDIDAT@$DOMAINE" \
        password="$MDP_PROVISOIRE" \
        quota="2097152" \
        active=1 \
        name="$CANDIDAT"

    # Mot de passe provisoire impose : l'utilisateur DOIT le changer a la
    # premiere connexion (flag UPDATEPASSWORD gere par PostfixAdmin).
    sudo postfixadmin mailbox set "$CANDIDAT@$DOMAINE" update_password=1
done

# 3. Verification : comptage + affichage
echo ""
echo "=== VERIFICATION ==="
echo "Nombre de comptes : $(sudo postfixadmin mailbox list "$DOMAINE" | wc -l)"
sudo postfixadmin mailbox list "$DOMAINE"
echo ""
echo "Quotas : 2 Go par boite (aligne sur la prod, agent standard)"
echo "Mot de passe provisoire commun : $MDP_PROVISOIRE"
echo "IMPORTANT : a changer avant toute mise en service reelle."