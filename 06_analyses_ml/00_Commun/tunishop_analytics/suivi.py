# -*- coding: utf-8 -*-
"""
suivi.py — suivi des modèles de production dans le temps (version 1.5)
======================================================================

Deux outils pour le notebook 09_Suivi_Modeles :

    rejouer_fenetre_glissante(...)  rejoue la production mois par mois : pour chaque mois, le modèle est
                                    réappris sur les N mois qui précèdent, puis il prédit ce mois.
                                    On mesure ainsi le modèle tel qu'il tourne vraiment (réappris chaque
                                    mois), et non un modèle figé appris une fois pour toutes.

    historiser(...)                 ajoute les indicateurs d'une exécution à l'historique des exécutions.
                                    Une exécution est repérée par la date des dernières données : relancer
                                    le suivi sur les mêmes données remplace ses lignes, de nouvelles
                                    données ajoutent des lignes. Rien d'autre n'est effacé.

Pourquoi ? En version 1.4, ana.ml_suivi était entièrement remplacée à chaque exécution : on ne voyait
que le dernier état, jamais l'évolution. Et le suivi mesurait le modèle de test (appris sur 2023-2024),
pas le modèle de production réappris.
"""
from __future__ import annotations

import pandas as pd
from sklearn.base import clone

COLONNES_SUIVI = ["cas", "objet", "periode", "indicateur", "valeur", "seuil", "statut"]
COLONNES_HISTORIQUE = ["date_donnees", "calcule_le"] + COLONNES_SUIVI
CLE_HISTORIQUE = ["date_donnees", "cas", "objet", "periode", "indicateur"]


def rejouer_fenetre_glissante(t: pd.DataFrame, pipeline, variables: list[str], cible: str, col_date: str,
                              mois_fenetre: int = 12, nb_mois: int = 12, groupe: str = "transporteur") -> pd.DataFrame:
    """Rejoue la production sur les `nb_mois` derniers mois complets des données.

    Pour chaque mois M : apprentissage sur les `mois_fenetre` mois avant M (même pipeline, réglages
    identiques), prédiction de M, puis taux prévu et taux réel par `groupe`.
    Renvoie une ligne par mois et par groupe : mois, groupe, lignes, taux_prevu, taux_reel, ecart.
    """
    d = t.copy()
    d["_mois"] = d[col_date].dt.to_period("M")
    mois_dispo = sorted(d["_mois"].unique())
    if len(mois_dispo) < 2:
        raise ValueError("Il faut au moins deux mois de données pour rejouer la production.")
    a_rejouer = mois_dispo[-nb_mois:]
    lignes = []
    for mois in a_rejouer:
        debut = mois.to_timestamp()
        app = d[(d[col_date] < debut) & (d[col_date] >= debut - pd.DateOffset(months=mois_fenetre))]
        test = d[d["_mois"] == mois]
        if app.empty or app[cible].nunique() < 2 or test.empty:
            continue                      # pas assez d'historique pour apprendre : mois ignoré
        modele = clone(pipeline).fit(app[variables], app[cible])
        p = pd.Series(modele.predict_proba(test[variables])[:, 1], index=test.index)
        for valeur, g in test.groupby(groupe):
            prevu, reel = float(p.loc[g.index].mean()), float(g[cible].mean())
            lignes.append({"mois": str(mois), groupe: valeur, "lignes": len(g), "lignes_apprentissage": len(app),
                           "taux_prevu": prevu, "taux_reel": reel, "ecart": prevu - reel})
    return pd.DataFrame(lignes)


def historiser(courant: pd.DataFrame, historique: pd.DataFrame | None, date_donnees, calcule_le) -> pd.DataFrame:
    """Ajoute le suivi `courant` (colonnes COLONNES_SUIVI) à `historique` (colonnes COLONNES_HISTORIQUE).

    date_donnees : date des dernières données utilisées (repère de l'exécution)
    calcule_le   : date et heure du calcul
    Les lignes de l'historique qui ont la même date_donnees sont remplacées ; les autres sont gardées.
    """
    manquantes = [c for c in COLONNES_SUIVI if c not in courant.columns]
    if manquantes:
        raise ValueError(f"Colonnes absentes du suivi : {manquantes}")
    repere = pd.Timestamp(date_donnees).strftime("%Y-%m-%d")
    nouveau = courant[COLONNES_SUIVI].copy()
    nouveau.insert(0, "calcule_le", pd.Timestamp(calcule_le).strftime("%Y-%m-%d %H:%M:%S"))
    nouveau.insert(0, "date_donnees", repere)
    nouveau["periode"] = nouveau["periode"].astype(str)
    if nouveau.duplicated(subset=CLE_HISTORIQUE).any():
        raise ValueError("Le suivi courant contient deux fois le même indicateur pour la même période.")
    if historique is None or historique.empty:
        gardees = pd.DataFrame(columns=COLONNES_HISTORIQUE)
    else:
        h = historique[COLONNES_HISTORIQUE].copy()
        h["date_donnees"] = h["date_donnees"].astype(str)
        h["periode"] = h["periode"].astype(str)
        gardees = h[h["date_donnees"] != repere]
    resultat = pd.concat([gardees, nouveau], ignore_index=True) if len(gardees) else nouveau
    return resultat.sort_values(CLE_HISTORIQUE).reset_index(drop=True)


def lire_historique(chemin) -> pd.DataFrame | None:
    """Relit l'historique enregistré (CSV « ; » et décimale « , », comme les autres tables) ; None s'il n'existe pas."""
    from pathlib import Path
    chemin = Path(chemin)
    if not chemin.exists():
        return None
    h = pd.read_csv(chemin, sep=";", decimal=",", encoding="utf-8-sig",
                    dtype={"date_donnees": str, "calcule_le": str, "periode": str, "objet": str})
    return h
