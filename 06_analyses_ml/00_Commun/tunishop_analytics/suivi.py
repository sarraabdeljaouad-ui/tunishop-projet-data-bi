# -*- coding: utf-8 -*-
"""
suivi.py — suivi des modèles de production dans le temps (version 1.5)
======================================================================

Outils pour les notebooks 08_Scoring_Actuel et 09_Suivi_Modeles :

    predictions_glissantes(...)     prédictions ligne par ligne de la production rejouée (v1.5.1 : seuil d'alerte)

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


def predictions_glissantes(t: pd.DataFrame, pipeline, variables: list[str], cible: str, col_date: str,
                           mois_fenetre: int = 12, nb_mois: int = 12) -> pd.DataFrame:
    """Prédictions de la production rejouée, ligne par ligne (version 1.5.1).

    Pour chacun des `nb_mois` derniers mois complets : apprentissage sur les `mois_fenetre` mois qui précèdent,
    prédiction du mois. Chaque ligne n'est donc prédite que par un modèle qui ne l'a pas vue : ces prédictions
    servent à mesurer le calibrage (rejouer_fenetre_glissante) et à choisir le seuil d'alerte de la production.
    Renvoie les lignes de `t` rejouées, avec les colonnes « mois_rejoue », « lignes_apprentissage » et « proba »
    (« mois_rejoue » et non « mois » : le modèle de retard a déjà une variable « mois »).
    """
    d = t.copy()
    rejoue = d[col_date].dt.to_period("M")
    mois_dispo = sorted(rejoue.unique())
    if len(mois_dispo) < 2:
        raise ValueError("Il faut au moins deux mois de données pour rejouer la production.")
    parts = []
    for mois in mois_dispo[-nb_mois:]:
        debut = mois.to_timestamp()
        app = d[(d[col_date] < debut) & (d[col_date] >= debut - pd.DateOffset(months=mois_fenetre))]
        test = d[rejoue == mois]
        if app.empty or app[cible].nunique() < 2 or test.empty:
            continue                      # pas assez d'historique pour apprendre : mois ignoré
        modele = clone(pipeline).fit(app[variables], app[cible])
        parts.append(test.assign(mois_rejoue=str(mois), lignes_apprentissage=len(app),
                                 proba=modele.predict_proba(test[variables])[:, 1]))
    if not parts:
        return d.iloc[0:0].assign(mois_rejoue="", lignes_apprentissage=0, proba=0.0)
    return pd.concat(parts)


def rejouer_fenetre_glissante(t: pd.DataFrame, pipeline, variables: list[str], cible: str, col_date: str,
                              mois_fenetre: int = 12, nb_mois: int = 12, groupe: str = "transporteur",
                              predictions: pd.DataFrame | None = None) -> pd.DataFrame:
    """Rejoue la production sur les `nb_mois` derniers mois complets des données.

    Pour chaque mois M : apprentissage sur les `mois_fenetre` mois avant M (même pipeline, réglages
    identiques), prédiction de M, puis taux prévu et taux réel par `groupe`.
    `predictions` : sortie de predictions_glissantes, pour ne pas réapprendre deux fois.
    Renvoie une ligne par mois et par groupe : mois, groupe, lignes, taux_prevu, taux_reel, ecart.
    """
    p = predictions if predictions is not None else predictions_glissantes(t, pipeline, variables, cible, col_date,
                                                                          mois_fenetre, nb_mois)
    r = (p.groupby(["mois_rejoue", groupe], sort=True)
         .agg(lignes=(cible, "size"), lignes_apprentissage=("lignes_apprentissage", "first"),
              taux_prevu=("proba", "mean"), taux_reel=(cible, "mean"))
         .reset_index().rename(columns={"mois_rejoue": "mois"}))
    r["taux_reel"] = r["taux_reel"].astype(float)
    r["ecart"] = r["taux_prevu"] - r["taux_reel"]
    return r[["mois", groupe, "lignes", "lignes_apprentissage", "taux_prevu", "taux_reel", "ecart"]]


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
