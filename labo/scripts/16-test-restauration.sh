#!/bin/bash
# =============================================================================
# TEST DE RESTAURATION - le plus important de tous
# Usage : sudo ./16-test-restauration.sh [compte]
#        defaut : tiana.rakoto
#
# "Une sauvegarde jamais restauree n'est pas une sauvegarde."
# Ce script ne verifie pas que le backup a reussi : il verifie qu'on peut
# en revenir. Concretement il :
#   1. releve l'etat de reference d'une boite (nombre de messages,
#      date d reception de chacun, dossier, taille)
#   2. DETRUIT cette boite (comme si le serveur avait ete perdu)
#   3. restaure depuis le depot
#   4. compare etat avant / etat apres
#
# C'est le critere d'ouverture n° 5 de la conception :
#   "restauration d'une boite a l'identique, dates comprises".
# =============================================================================
set -euo pipefail

[ -f /etc/default/meteo-backup ] || { echo "ERREUR : lancer 13-backup-init.sh d'abord" >&2; exit 1; }
# shellcheck disable=SC1091
. /etc/default/meteo-backup

REPO="${BACKUP_ROOT}/restic-repo"
COMPTE="${1:-tiana.rakoto}"
BOITE="/var/vmail/${DOMAINE}/${COMPTE}"
export RESTIC_PASSWORD_FILE=/root/.restic-password

echo "########################################################"
echo "# TEST DE RESTAURATION"
echo "# Compte   : ${COMPTE}"
echo "# $(date '+%Y-%m-%d %H:%M:%S')"
echo "########################################################"

[ -d "${BOITE}" ] || { echo "ERREUR : boite absente ${BOITE}" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Releve de reference
# ---------------------------------------------------------------------------
# On note pour chaque message : sa date d reception (en-tete Date, celle
# que voit l'agent) ET son horodatage de fichier sur disque (celui qu'on
# restore). Les deux doivent survivre, sinon l'agent voit ses messages
# reordonnes ou dates du jour de la restauration.
relever() {
    find "${BOITE}" -type f -path '*/cur/*' -o -type f -path '*/new/*' 2>/dev/null | sort | while read -r f; do
        printf '%s|%s|%s|%s\n' \
            "$(echo "${f}" | sed "s|${BOITE}/||")" \
            "$(grep -m1 -a '^Date:' "${f}" 2>/dev/null | tr -d '\r')" \
            "$(stat -c%s "${f}")" \
            "$(stat -c%Y "${f}")"
    done
}

echo
echo "[1/5] Releve de l'etat courant de la boite"
AVANT_FILE=$(mktemp)
relever > "${AVANT_FILE}"
NB_AVANT=$(wc -l < "${AVANT_FILE}")
VOL_AVANT=$(du -sb "${BOITE}" | cut -f1)
echo "  Messages : ${NB_AVANT}"
echo "  Volume   : ${VOL_AVANT} octets"
if [ "${NB_AVANT}" -eq 0 ]; then
    echo "ERREUR : boite vide, le test ne prouverait rien" >&2
    exit 1
fi
echo "  Echantillon :"
head -2 "${AVANT_FILE}" | sed 's/^/    /'

# ---------------------------------------------------------------------------
# 2. Sauvegarde la plus recente
# ---------------------------------------------------------------------------
echo
echo "[2/5] Selection du snapshot"
# PIEGE MAJEUR : `restic snapshots --latest 1` ne renvoie PAS "le plus
# recent". La doc precise "for each host and path" : des snapshots dont
# le jeu de chemins differ forme des groupes distincts, et l'option en
# renvoie donc UN PAR GROUPE. Or notre perimetre varie (ex. la cle DKIM
# fait apparaitre /var/lib/rspamd/dkim : 13 chemins -> 14).
# Consequence : le premier element du tableau n'est pas forcement le plus
# recent, et l'on restaurerait un instantane perime en croyant restaurer
# le dernier.
# On selectionne donc par horodatage reel, sans se fier a l'ordre ni a
# --latest.
SNAP=$(restic -r "${REPO}" snapshots --tag meteo --json 2>/dev/null | python3 -c '
import json, sys
snaps = json.load(sys.stdin)
if not snaps:
    sys.exit(1)
print(max(snaps, key=lambda s: s["time"])["short_id"])
')
if [ -z "${SNAP}" ]; then
    echo "ERREUR : aucun snapshot exploitable" >&2
    restic -r "${REPO}" snapshots 2>&1 | tail -5 >&2
    exit 1
fi
NB_TOTAL=$(restic -r "${REPO}" snapshots --tag meteo --json 2>/dev/null | grep -o '"short_id"' | wc -l)
echo "  ${NB_TOTAL} snapshot(s) disponible(s), retenu : ${SNAP}"

# ---------------------------------------------------------------------------
# 3. Simulation de perte
# ---------------------------------------------------------------------------
# On deplace la boite plutot que de la supprimer : si la restauration
# echoue, la donnee est encore la et on peut diagnostiquer. En prod, apres
# verification du test, ce deplacement est remplace par une suppression.
echo
echo "[3/5] Simulation de la perte de la boite"
mv "${BOITE}" "${BOITE}.SAVEGARDE-TEST"
if [ -d "${BOITE}" ]; then
    echo "ERREUR : la boite existe toujours, abandon" >&2
    exit 1
fi
echo "  Boite deplacee. Elle n'existe plus :"
ls -d "${BOITE}" 2>/dev/null || echo "    ${BOITE} : absent (comme apres un disque perdu)"

# ---------------------------------------------------------------------------
# 4. Restauration
# ---------------------------------------------------------------------------
echo
echo "[4/5] Restauration depuis le snapshot ${SNAP}"
restic -r "${REPO}" restore "${SNAP}" \
        --target / \
        --include "/var/vmail/${DOMAINE}/${COMPTE}" 2>&1 | tail -3

if [ ! -d "${BOITE}" ]; then
    echo "ERREUR : la restauration n'a pas recree la boite" >&2
    echo "--- Contenu disponible pour ce chemin ---" >&2
    restic -r "${REPO}" ls "${SNAP}" 2>/dev/null | grep "${DOMAINE}" | head -10 >&2
    exit 1
fi
# restic restaure avec les droits du snapshot : on les reapplique au cas
# ou (le snapshot est fait en root, donc lisible, mais on ne suppose pas).
chown -R vmail:vmail "${BOITE}"
find "${BOITE}" -type d -exec chmod 700 {} +

# ---------------------------------------------------------------------------
# 5. Comparaison avant / apres
# ---------------------------------------------------------------------------
echo
echo "[5/5] Comparaison avant / apres"
APRES_FILE=$(mktemp)
relever > "${APRES_FILE}"
NB_APRES=$(wc -l < "${APRES_FILE}")

echo "  Messages : ${NB_AVANT} avant -> ${NB_APRES} apres"

if [ "${NB_AVANT}" -eq "${NB_APRES}" ] && diff -q "${AVANT_FILE}" "${APRES_FILE}" > /dev/null; then
    echo "  [PASS] La boite restauree est IDENTIQUE a l'originale"
    echo "         (chemin, en-tete Date, taille et horodatage compris)"
    IDENTIQUE=1
else
    echo "  [FAIL] Divergences detectees :"
    diff "${AVANT_FILE}" "${APRES_FILE}" | head -20 | sed 's/^/    /'
    IDENTIQUE=0
fi

# Verification complementaire : la boite est-elle de nouveau exploitable
# par Dovecot ? Une restauration de fichiers qui ne rend pas la boite
# lisible ne vaut rien.
echo
echo "  Test de lisibilite par le serveur IMAP :"
# `set -e` tuerait le script sur le code de sortie de python avant qu'on
# puisse le capturer : on le desactive le temps du test.
set +e
python3 - <<PYEOF
import imaplib, ssl, sys
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
pw = open("/root/labo-credentials.txt").read()
mdp = [l.split("=",1)[1].strip() for l in pw.splitlines() if l.startswith("MDP_TEST=")][0]

def aplatir(d):
    """imaplib imbrique la reponse : d[0] est un TUPLE
    (entete, litteral), d[1] est le ')' de fin. Aplatir en ignorant
    les non-bytes, sinon on ne recupere que la parenthese fermante."""
    out = b""
    for part in d:
        if isinstance(part, tuple):
            out += b"".join(x for x in part if isinstance(x, bytes))
        elif isinstance(part, bytes):
            out += part
    return out

try:
    m = imaplib.IMAP4_SSL("127.0.0.1", 993, ssl_context=ctx)
    m.login("${COMPTE}@${DOMAINE}", mdp)
    m.select("INBOX")
    typ, data = m.search(None, "ALL")
    ids = data[0].split()
    print("    [PASS] IMAP : %d message(s) visible(s) dans INBOX" % len(ids))
    for i in ids[:3]:
        t, d = m.fetch(i, "(RFC822.HEADER)")
        brut = aplatir(d).decode(errors="replace")
        for ligne in brut.splitlines():
            if ligne.lower().startswith("date:"):
                print("            %s" % ligne.strip()[:60])
                break
    m.logout()
    sys.exit(0)
except Exception as e:
    print("    [FAIL] IMAP : %s" % e)
    sys.exit(1)
PYEOF
IMAP_OK=$?
set -e

# Nettoyage : la copie de securite n'est supprimee que si la
# restauration a reussi. En cas d'ECHEC on la conserve : c'est la seule
# copie restante des messages d'origine, la supprimer en cas d'erreur
# reviendrait a detruire definitivement les donnees qu'on cherchait a
# proteger.
if [ "${IDENTIQUE}" -eq 1 ] && [ "${IMAP_OK}" -eq 0 ]; then
    rm -rf "${BOITE}.SAVEGARDE-TEST"
    echo
    echo "Copie de securite supprimee (restauration reussie)."
else
    echo
    echo "*** ECHEC : la copie de securite est CONSERVEE ***"
    echo "*** ${BOITE}.SAVEGARDE-TEST contient les messages d'origine ***"
    echo "*** Ne pas l'effacer avant d'avoir diagnostique.           ***"
fi

echo
echo "########################################################"
if [ "${IDENTIQUE}" -eq 1 ] && [ "${IMAP_OK}" -eq 0 ]; then
    echo "# VERDICT : RESTAURATION VALIDEE"
    echo "#"
    echo "# Une boite restauree a l'identique, dates comprises, et"
    echo "# de nouveau lisible en IMAP. Le critere d'ouverture n° 5"
    echo "# est satisfait sur cette boite."
else
    echo "# VERDICT : RESTAURATION NON CONFORME"
fi
echo "########################################################"

[ "${IDENTIQUE}" -eq 1 ] && [ "${IMAP_OK}" -eq 0 ] && exit 0 || exit 1
