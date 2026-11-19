# -*- coding: utf-8 -*-
"""Découpage dans le temps : aucune information de 2025 ne doit servir à l'apprentissage."""
import pandas as pd

from tunishop_analytics import temporal_split as ts


def test_fenetres_avenir_ne_debordent_pas():
    # la cible churn (90 jours après la photo) d'une photo d'apprentissage reste en 2023-2024
    assert (ts.verifier_dates_obs()["statut"] == "OK").all()


def test_dates_apprentissage_avant_test():
    assert ts.DATES_OBS_APPRENTISSAGE.max() < ts.DEBUT_TEST <= ts.DATES_OBS_TEST.min()


def test_periode_et_separer():
    df = pd.DataFrame({"d": pd.to_datetime(["2024-12-31", "2025-01-01", "2023-05-01"])})
    assert list(ts.periode(df["d"])) == ["apprentissage", "test", "apprentissage"]
    app, test = ts.separer(df, "d")
    assert len(app) == 2 and len(test) == 1
