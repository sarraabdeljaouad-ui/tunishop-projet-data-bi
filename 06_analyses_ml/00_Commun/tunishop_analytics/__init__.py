# -*- coding: utf-8 -*-
"""
tunishop_analytics — module commun à l'EDA, au data mining et au machine learning de TuniShop
================================================================================================

Pourquoi un module commun ?
    Tous les notebooks (01_EDA, 02_Data_Mining, 03_Machine_Learning) lisent les MÊMES données,
    avec les MÊMES règles et les MÊMES variables, construites par le MÊME code. Un modèle de ML
    ne peut donc jamais utiliser une variable calculée autrement que ce que montre l'EDA.

Les fichiers principaux :
    config.py          réglages : serveur SQL, dossiers, valeurs validées, style des graphiques
    chargement.py      liaison DIRECTE avec les vues bi du DWH : connexion, requêtes SQL, lecture des vues
    validation.py      contrôles de qualité : totaux validés, intégrité, doublons, vides, valeurs extrêmes
    temporal_split.py  dates de coupure et découpage apprentissage (2023-2024) / test (2025)
    features.py        tables de variables (clients, commandes, produits_mois, expeditions)
                       et outils du data mining (RFM, paniers, recommandation)
    publication.py     copie de chaque résultat (CSV / Parquet) dans la base SQL TuniShop_ANALYTICS
    modeles.py         registre des modèles : fiche d'identité de chaque modèle enregistré
    suivi.py           suivi des modèles de production : rejeu mois par mois, historique des exécutions (v1.5)

Utilisation dans un notebook (le notebook est dans 01_EDA/, 02_Data_Mining/ ou 03_Machine_Learning/) :
    import sys; sys.path.insert(0, "../00_Commun")
    from tunishop_analytics import config, chargement, validation, temporal_split, features
"""
__version__ = "3.2"
