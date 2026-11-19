# -*- coding: utf-8 -*-
"""
figer_versions.py — enregistre les versions EXACTES des bibliothèques installées sur ce poste
==============================================================================================

Pourquoi ? requirements.txt donne des bornes (pandas>=2.2,<4). Pour pouvoir refaire exactement la même
analyse plus tard, ou sur un autre PC, on fige les versions qui ont produit les résultats validés :

    python 00_Commun/figer_versions.py            -> écrit 00_Commun/requirements-lock.txt
    python -m pip install -r 00_Commun/requirements-lock.txt   (sur un autre poste)

À relancer après chaque mise à jour de bibliothèque, et à joindre aux livrables d'une phase validée.
"""
import datetime as dt
import platform
import re
import sys
from importlib import metadata
from pathlib import Path

ICI = Path(__file__).resolve().parent
noms = []
for fichier in ("requirements.txt", "requirements-dev.txt"):
    for ligne in (ICI / fichier).read_text(encoding="utf-8").splitlines():
        ligne = ligne.split("#")[0].strip()
        if ligne and not ligne.startswith("-r"):
            noms.append(re.split(r"[<>=!~ ]", ligne)[0])

lignes = [f"# Versions figées le {dt.datetime.now():%d/%m/%Y %H:%M} — Python {platform.python_version()} ({sys.platform})"]
manquants = []
for nom in noms:
    try:
        lignes.append(f"{nom}=={metadata.version(nom)}")
    except metadata.PackageNotFoundError:
        manquants.append(nom)
(ICI / "requirements-lock.txt").write_text("\n".join(lignes) + "\n", encoding="utf-8")
print("\n".join(lignes))
if manquants:
    print("Non installés (ignorés) :", ", ".join(manquants))
print(f"-> {ICI / 'requirements-lock.txt'}")
