# -*- coding: utf-8 -*-
"""Régénère intégralement TuniShop : simulation -> contrôles -> exports (couche de référence, couche brute, docs générées).
Usage : python generer_tunishop.py   (sortie dans ./tunishop_dataset, ou chemin donné par la variable TUNISHOP_OUT)"""
import os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
subprocess.run([sys.executable, os.path.join(here, "gen_part3.py")], check=True, cwd=here)
subprocess.run([sys.executable, os.path.join(here, "gen_part5_export.py")], check=True, cwd=here)
print("Terminé.")
