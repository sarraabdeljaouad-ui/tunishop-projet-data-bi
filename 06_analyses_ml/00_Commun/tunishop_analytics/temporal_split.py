# -*- coding: utf-8 -*-
"""
temporal_split.py — dates de coupure et découpage apprentissage / test
======================================================================

Règle n° 1 du machine learning : on évalue un modèle sur des données qu'il n'a JAMAIS vues,
et qui ressemblent à l'usage réel. Pour des données datées, cela veut dire : apprendre sur le
passé, tester sur une période plus récente. Jamais l'inverse, jamais au hasard.

Pour TuniShop :
    apprentissage = 2023 et 2024   (le modèle apprend)
    test          = 2025           (on mesure sa performance, comme s'il était en production)

Ces dates sont utilisées par l'EDA (pour vérifier que 2025 ressemble à 2023-2024), par le
data mining (RFM calculé à une date donnée) et par les 4 cas de ML (ventes, churn, demande,
retard de livraison). Les changer ici les change partout.
"""
from __future__ import annotations

import pandas as pd

# Période couverte par les données du DWH
DEBUT_DONNEES = pd.Timestamp("2023-01-01")
FIN_DONNEES = pd.Timestamp("2025-12-31")

# Découpage apprentissage / test
FIN_APPRENTISSAGE = pd.Timestamp("2024-12-31")
DEBUT_TEST = pd.Timestamp("2025-01-01")

# --- Churn (cas ML n° 1)
# Un client est « actif » à une date d'observation s'il a passé au moins une commande
# (hors échec de paiement) dans les FENETRE_ACTIVITE_J jours précédents.
# Il est « perdu » (churn = 1) s'il ne repasse AUCUNE commande dans les HORIZON_CHURN_J jours suivants.
FENETRE_ACTIVITE_J = 365
HORIZON_CHURN_J = 90

# --- Retard de livraison (cas ML n° 4), modèle de production (version 1.5)
# Le modèle de production est réappris chaque mois sur les FENETRE_RETARD_PRODUCTION_MOIS derniers mois.
# Choix fait sur le suivi (09_Suivi_Modeles) : rejouée mois par mois sur 2025, la fenêtre de 12 mois
# donne 7 alertes de calibrage sur 48 (transporteur x mois), contre 14 pour tout l'historique, et
# corrige la sous-estimation de SahelLog dès que sa rupture de juillet 2024 sort de la fenêtre.
FENETRE_RETARD_PRODUCTION_MOIS = 12

# Dates d'observation : une photo des clients à chaque fin de trimestre.
# Condition : la fenêtre « avenir » (date + 90 jours) doit rester dans la même période,
# sinon la cible d'apprentissage utiliserait des données de la période de test.
DATES_OBS_APPRENTISSAGE = pd.to_datetime(["2023-06-30", "2023-09-30", "2023-12-31",
                                          "2024-03-31", "2024-06-30", "2024-09-30"])
DATES_OBS_TEST = pd.to_datetime(["2025-03-31", "2025-06-30", "2025-09-30"])


def periode(dates: pd.Series) -> pd.Series:
    """Renvoie 'apprentissage' ou 'test' selon la date (série de dates pandas)."""
    return pd.Series(["apprentissage" if d <= FIN_APPRENTISSAGE else "test" for d in dates],
                     index=dates.index, dtype="category")


def verifier_dates_obs() -> pd.DataFrame:
    """Tableau de contrôle : chaque date d'observation, la fin de sa fenêtre « avenir »,
    et la vérification que cette fenêtre ne déborde pas sur la période suivante."""
    lignes = []
    for jeu, dates, limite in (("apprentissage", DATES_OBS_APPRENTISSAGE, FIN_APPRENTISSAGE),
                               ("test", DATES_OBS_TEST, FIN_DONNEES)):
        for d in dates:
            fin = d + pd.Timedelta(days=HORIZON_CHURN_J)
            lignes.append({"jeu": jeu, "date_observation": d.date(), "fin_fenetre_avenir": fin.date(),
                           "limite": limite.date(), "statut": "OK" if fin <= limite else "DÉBORDE"})
    return pd.DataFrame(lignes)


def separer(df: pd.DataFrame, colonne_date: str) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Coupe une table en (apprentissage, test) selon une colonne de date.

        app, test = temporal_split.separer(expeditions, "date_expedition")
    """
    dates = pd.to_datetime(df[colonne_date])
    return df[dates <= FIN_APPRENTISSAGE].copy(), df[(dates >= DEBUT_TEST) & (dates <= FIN_DONNEES)].copy()
