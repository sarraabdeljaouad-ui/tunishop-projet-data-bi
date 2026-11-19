# -*- coding: utf-8 -*-
"""
modeles.py — registre des modèles : chaque modèle enregistré est accompagné de sa FICHE D'IDENTITÉ
==================================================================================================

Pourquoi ?
    Un fichier .joblib seul ne dit pas QUAND il a été appris, SUR QUELLES DONNÉES, avec QUELS
    réglages ni avec QUELLE performance. Six mois plus tard, on ne sait plus quel modèle a produit
    quelle prédiction. Ce module enregistre donc, à côté de chaque modèle :

        06_Exports/Modeles/<nom>.joblib            le modèle (comme avant)
        06_Exports/Modeles/fiches/<nom>.json       sa fiche (version, période, variables, mesures…)
        TuniShop_ANALYTICS.ana.ml_registre_modeles toutes les fiches, lisibles dans SSMS et Power BI

Utilisation (notebook 03_Machine_Learning/08_Scoring_Actuel) :
    fiche = modeles.fiche("churn_production", cas="churn", objet=pipe, donnees=table, cible="churn", ...)
    modeles.enregistrer(objet, fiche)
    modeles.publier_registre()
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import platform
from pathlib import Path

import joblib
import pandas as pd

from . import config

DOSSIER_FICHES = config.DOSSIER_MODELES / "fiches"


def empreinte(df: pd.DataFrame) -> str:
    """Empreinte (SHA-256, 16 caractères) des données d'apprentissage : deux apprentissages sur les
    mêmes lignes ont la même empreinte ; si le DWH change, l'empreinte change."""
    h = pd.util.hash_pandas_object(df.reset_index(drop=True), index=False).values
    return hashlib.sha256(h.tobytes()).hexdigest()[:16]


def _reglages(objet) -> str:
    """Réglages du dernier estimateur d'un pipeline scikit-learn (texte court), ou description libre."""
    est = getattr(objet, "steps", [[None, objet]])[-1][1]
    if hasattr(est, "get_params"):
        p = {k: v for k, v in est.get_params().items() if isinstance(v, (int, float, str, bool)) and v is not None}
        return f"{type(est).__name__}({', '.join(f'{k}={v}' for k, v in sorted(p.items()))})"
    return str(objet)[:300]


def fiche(nom: str, cas: str, objet=None, donnees: pd.DataFrame | None = None, cible: str | None = None,
          periode: str = "", variables: list | None = None, mesures: dict | None = None, seuil: float | None = None,
          role: str = "production", notes: str = "", reglages: str | None = None) -> dict:
    """Construit la fiche d'identité d'un modèle (dictionnaire sérialisable en JSON)."""
    import sklearn
    maintenant = dt.datetime.now().replace(microsecond=0)
    f = {
        "nom": nom, "cas": cas, "role": role,
        "version": maintenant.strftime("%Y.%m.%d.%H%M"),
        "appris_le": maintenant.isoformat(sep=" "),
        "periode_apprentissage": periode,
        "lignes_apprentissage": int(len(donnees)) if donnees is not None else None,
        "taux_cible": float(donnees[cible].mean()) if (donnees is not None and cible in donnees) else None,
        "empreinte_donnees": empreinte(donnees) if donnees is not None else None,
        "variables": list(variables or []),
        "nb_variables": len(variables or []),
        "reglages": reglages if reglages is not None else (_reglages(objet) if objet is not None else ""),
        "seuil": seuil,
        "mesures": mesures or {},
        "versions": {"python": platform.python_version(), "scikit-learn": sklearn.__version__, "pandas": pd.__version__},
        "source": "TEST (miroir SQLite)" if __import__("os").environ.get("TUNISHOP_BASE_TEST") else "TuniShop_DWH",
        "fichier": f"06_Exports/Modeles/{nom}.joblib" if objet is not None else "",
        "notes": notes,
    }
    return f


def enregistrer(objet, f: dict) -> Path:
    """Enregistre le modèle (.joblib, avec sa fiche à l'intérieur) et la fiche seule (.json)."""
    DOSSIER_FICHES.mkdir(parents=True, exist_ok=True)
    if objet is not None:
        contenu = objet if isinstance(objet, dict) else {"modele": objet}
        contenu = {**contenu, "fiche": f}
        joblib.dump(contenu, config.DOSSIER_MODELES / f"{f['nom']}.joblib")
    chemin = DOSSIER_FICHES / f"{f['nom']}.json"
    chemin.write_text(json.dumps(f, ensure_ascii=False, indent=1, default=str), encoding="utf-8")
    print(f"  fiche {f['nom']:<28} version {f['version']}  ({f['role']})")
    return chemin


def registre() -> pd.DataFrame:
    """Toutes les fiches, une ligne par modèle (mesures à plat : mesure_AUC, mesure_WAPE…)."""
    lignes = []
    for p in sorted(DOSSIER_FICHES.glob("*.json")):
        f = json.loads(p.read_text(encoding="utf-8"))
        ligne = {k: v for k, v in f.items() if k not in ("mesures", "variables", "versions")}
        ligne["variables"] = ", ".join(f.get("variables", []))
        ligne.update({f"mesure_{k}": v for k, v in f.get("mesures", {}).items()})
        ligne.update({f"version_{k}": v for k, v in f.get("versions", {}).items()})
        lignes.append(ligne)
    return pd.DataFrame(lignes)


def publier_registre() -> pd.DataFrame:
    """Écrit le registre en CSV (06_Exports/Tables/ML_registre_modeles.csv) et dans ana.ml_registre_modeles."""
    r = registre()
    config.exporter_table(r, "ML_registre_modeles", index=False)
    return r


def charger(nom: str) -> dict:
    """Relit un modèle enregistré par enregistrer() : {"modele" ou "pipeline": ..., "fiche": {...}, ...}."""
    return joblib.load(config.DOSSIER_MODELES / f"{nom}.joblib")
