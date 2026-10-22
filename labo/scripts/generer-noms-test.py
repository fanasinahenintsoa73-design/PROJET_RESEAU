#!/usr/bin/env python3
# =============================================================================
# Generateur d'echantillon de test pour l'import de comptes a l'echelle
# =============================================================================
# Produit un CSV `prenom,nom,profil` avec des cas REALISTES qui cassent les
# scripts d'import naifs :
#   - homonymes exacts (meme prenom + meme nom)      -> suffixe numerique
#   - meme nom de famille, prenoms differents       -> pas de collision
#   - prenoms accentues                              -> normalisation ASCII
#   - prenoms avec apostrophe (N'andry, N'aina)      -> apostrophe supprimee
#   - prenoms composes avec trait d'union            -> trait conserve
#   - profils cadres / stations -> quotas differents
#
# Les noms sont des prenoms et noms de famille MALGACHES courants, choisis
# pour reproduire la realite du recensement (Rakoto, Rasoa, Ramanana,
# Andrianina sont parmi les plus frequents -> homonymes garantis).
# Aucune personne reelle n'est concernee : les combinaisons sont inventees.
#
# Usage : python3 generer-noms-test.py 400 > /root/noms.csv
# =============================================================================
import sys
import random

PRENOMS_SIMPLE = [
    "Jean", "Rakoto", "Rasoa", "Ramanana", "Andrianina", "Hery", "Naina",
    "Tiana", "Faniry", "Nirina", "Mamy", "Onja", "Fanja", "Lova", "Tojoa",
    "Sitraka", "Toky", "Fandresena", "Haja", "Miora", "Soa", "Vola",
    "Anjara", "Rado", "Ravaka", "Lala", "Rivo", "Fetra", "Domoina", "Sambo",
    "Georgio", "Honore", "Marcellin", "Basile", "Pascal", "Prosper",
    "Griselda", "Victa", "Bako", "Faniry", "Miora", "Zo", "Tojoa", "Lova",
]

PRENOMS_ACCENTUES = [
    "Helene", "Emile", "Arsene", "Noel", "Felicite", "Desire", "Benedicte",
    "Gregoire", "Eloi", "Michael", "Jerome", "Therese", "Agnes", "Innocent",
]

PRENOMS_APOSTROPHE = [
    "N'andry", "N'aina", "N'jaka", "N'ivo", "N'aina", "N'andrianina",
    "N'nah", "N'gery", "N'elisa", "N'o",
]

PRENOMS_HYPHEN = [
    "Jean-Claude", "Marie-Christine", "Jean-Baptiste", "Jean-Pierre",
    "Andriamalala", "Nirina-Andrianina",
]

NOMS = [
    "Rakoto", "Rasoa", "Ramanana", "Andrianina", "Rakotomalala", "Ranaivo",
    "Rasolofomanana", "Randrianasolo", "Razafindrakoto", "Ravelojaona",
    "Rakotondrabe", "Andriamalala", "Rasoamanarivo", "Ramaroson",
    "Rasoanaivo", "Ratsimbazafy", "Randriamanana", "Razanamparany",
    "Andriantsitohaina", "Rafanomezantsoa", "Rakotobe", "Rasoamanana",
    "Rafaralahy", "Ramiliarisoa", "Ranaivoson", "Rabe", "Raminosoa",
    "Rajaonarison", "Ranjohanirina", "Rasolofo", "Rasoanaivo",
    "Randriamampionona", "Razafimahatratra", "Andriamanana", "Rasoalahady",
    "Rabemananjara", "Razanamparany", "Rakotondrasoa", "Randrianirina",
    "Rasolofoniaina", "Razafindrakoto", "Ramanantsoa", "Rasolomanana",
    "Ravalomanana", "Rasoamanarivo", "Randriamiarana", "Rasoanirina",
]

PROFILS = ["agent", "agent", "agent", "agent", "agent", "agent", "agent",
           "cadre", "station"]


def main() -> int:
    nombre = int(sys.argv[1]) if len(sys.argv) > 1 else 400
    graine = int(sys.argv[2]) if len(sys.argv) > 2 else 20261021
    alea = random.Random(graine)

    lignes = []
    # 1. Les homonymes exacts : 12 paires repetees (Rakoto et Rasoa sont les
    #    noms les plus frequents -> on en met beaucoup).
    for _ in range(12):
        prenom = alea.choice(PRENOMS_SIMPLE)
        nom = alea.choice(["Rakoto", "Rasoa", "Ramanana", "Andrianina"])
        for _ in range(alea.randint(2, 4)):
            lignes.append((prenom, nom, alea.choice(PROFILS)))

    # 2. Le reste : noms varies, dont accentues, apostrophes, traits d'union.
    while len(lignes) < nombre:
        tirage = alea.random()
        if tirage < 0.12:
            prenom = alea.choice(PRENOMS_ACCENTUES)
        elif tirage < 0.22:
            prenom = alea.choice(PRENOMS_APOSTROPHE)
        elif tirage < 0.30:
            prenom = alea.choice(PRENOMS_HYPHEN)
        else:
            prenom = alea.choice(PRENOMS_SIMPLE)
        nom = alea.choice(NOMS)
        lignes.append((prenom, nom, alea.choice(PROFILS)))

    lignes = lignes[:nombre]
    alea.shuffle(lignes)

    print("# Echantillon genere par generer-noms-test.py "
          f"({nombre} lignes, graine {graine})")
    print("# Format : prenom,nom,profil  (agent | cadre | station)")
    for prenom, nom, profil in lignes:
        print(f"{prenom},{nom},{profil}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
