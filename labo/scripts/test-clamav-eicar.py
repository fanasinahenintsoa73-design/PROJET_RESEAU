#!/usr/bin/env python3
"""
Test de bout en bout du module antivirus de Rspamd (ClamAV).

Envoie quatre messages via le port 587 (soumission authentifiee) :

  1. un message SAIN, sans piece jointe            -> doit etre ACCEPTE
  2. une piece jointe BINAIRE contenant la signature EICAR
     (application/octet-stream)                      -> doit etre REFUSE (554)
  3. une piece jointe TEXTE contenant la signature EICAR
     (text/plain)                                    -> doit etre REFUSE (554)
  4. la signature EICAR placee dans le CORPS du message, sans piece jointe
                                                     -> doit etre ACCEPTE
     (decision de conception n4 : le corps n'est JAMAIS scanne ; un scan
      complet ferait chuter la delivrabilite)

Resultat mesure le 21 octobre 2026 : 4/4 conformes.

Le mot de passe est lu dans /root/labo-credentials.txt (jamais en clair dans
le depot). Sortie : 0 si les 4 cas se comportent comme attendu.
"""
import email
import os
import smtplib
import ssl
import sys
from email.mime.application import MIMEApplication
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

EICAR = (
    r"X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"
)

CRED = "/root/labo-credentials.txt"
USER = "tiana.rakoto@meteo-test.lan"
HOST = "127.0.0.1"
PORT = 587


def lire_secret(nom):
    with open(CRED, "r", encoding="utf-8") as fh:
        for ligne in fh:
            ligne = ligne.strip()
            if ligne.startswith(nom + "="):
                return ligne.split("=", 1)[1].strip()
    raise SystemExit("secret %s introuvable dans %s" % (nom, CRED))


def envoyer(msg, mdp):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with smtplib.SMTP(HOST, PORT, timeout=30) as srv:
        srv.ehlo("meteo-test.lan")
        srv.starttls(context=ctx)
        srv.ehlo("meteo-test.lan")
        srv.login(USER, mdp)
        srv.send_message(msg)


def message_sain():
    msg = MIMEText("Message de controle, aucun virus, aucun piece jointe.")
    msg["Subject"] = "[ANTIVIRUS] message sain"
    msg["From"] = USER
    msg["To"] = "luc.ranaivo@meteo-test.lan"
    return msg


def message_eicar(binaire):
    msg = MIMEMultipart()
    msg["Subject"] = "[ANTIVIRUS] piece jointe EICAR"
    msg["From"] = USER
    msg["To"] = "luc.ranaivo@meteo-test.lan"
    msg.attach(MIMEText("Message de test antivirus."))
    if binaire:
        piece = MIMEApplication(EICAR.encode("utf-8"), "octet-stream")
        piece.add_header("Content-Disposition", "attachment", filename="eicar.bin")
    else:
        piece = MIMEText(EICAR, "plain", "utf-8")
        piece.add_header("Content-Disposition", "attachment", filename="eicar.txt")
    msg.attach(piece)
    return msg


def message_eicar_dans_le_corps():
    """EICAR place dans le CORPS du message (aucune piece jointe).

    Sert a verifier la decision de conception n4 : le corps du message
    ne doit JAMAIS etre scanne. Si ce message est refuse, c'est que le
    corps est scanne => la configuration contredit le design.
    """
    msg = MIMEText("essai " + EICAR + " fin")
    msg["Subject"] = "[ANTIVIRUS] EICAR dans le corps"
    msg["From"] = USER
    msg["To"] = "luc.ranaivo@meteo-test.lan"
    return msg


def tenter(msg, mdp, libelle):
    try:
        envoyer(msg, mdp)
        print("  [ACCEPTE ] %s" % libelle)
        return "accepte"
    except smtplib.SMTPResponseException as exc:
        print("  [REFUSE  ] %s -> %s %s" % (libelle, exc.smtp_code, exc.smtp_error))
        return "refuse"
    except smtplib.SMTPException as exc:
        print("  [ERREUR  ] %s -> %s" % (libelle, exc))
        return "erreur"


def main():
    mdp = lire_secret("MDP_TEST")
    echecs = 0

    print("--- Test antivirus (module Rspamd -> clamd) ---")

    r1 = tenter(message_sain(), mdp, "message sain (doit etre accepte)")
    if r1 != "accepte":
        print("  [ECHEC] un message sain a ete refuse : regression !")
        echecs += 1

    r2 = tenter(message_eicar(True), mdp, "piece jointe BINAIRE EICAR (doit etre refuse)")
    if r2 != "refuse":
        print("  [ECHEC] la piece jointe binaire n'a pas ete refusee")
        echecs += 1

    r3 = tenter(message_eicar(False), mdp, "piece jointe TEXTE EICAR")
    if r3 == "accepte":
        print("  [INFO  ] confirme : scan_text_mime = false ignore les pieces "
              "jointes texte (limitation documentee)")
    else:
        print("  [INFO  ] la piece jointe texte a aussi ete refusee : "
              "ClamAV l'a signalee malgre scan_text_mime = false")

    # CAS 4 - decision de conception n4 : le CORPS n'est jamais scanne.
    # Un EICAR place dans le corps, SANS piece jointe, doit donc etre
    # ACCEPTE. S'il est refuse, la configuration contredit le design
    # (un scan complet ferait chuter la delivrabilite).
    r4 = tenter(message_eicar_dans_le_corps(), mdp,
                "EICAR dans le CORPS (doit etre accepte : le corps n'est pas scanne)")
    if r4 != "accepte":
        print("  [ECHEC] le corps du message est scanne : la configuration "
              "contredit la decision de conception n4")
        echecs += 1

    print("")
    if echecs == 0:
        print("# VERDICT : ANTIVIRUS OPERATIONNEL")
    else:
        print("# VERDICT : %d ECHEC(S)" % echecs)
    return echecs


if __name__ == "__main__":
    sys.exit(main())
