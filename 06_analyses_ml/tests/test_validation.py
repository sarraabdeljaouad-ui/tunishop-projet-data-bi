# -*- coding: utf-8 -*-
"""Mesures de performance et indice de dérive (PSI)."""
import numpy as np
import pandas as pd
import pytest

from tunishop_analytics import validation


def test_metriques_regression_valeurs_connues():
    m = validation.metriques_regression([10, 20, 30], [12, 18, 30])
    assert m["MAE"] == pytest.approx(4 / 3)
    assert m["WAPE"] == pytest.approx(4 / 60)
    assert m["biais"] == pytest.approx(0)


def test_auc_parfaite_et_hasard():
    y = np.array([0, 0, 1, 1])
    assert validation.metriques_classification(y, np.array([0.1, 0.2, 0.8, 0.9]))["AUC"] == pytest.approx(1)
    assert validation.metriques_classification(y, np.array([0.5, 0.5, 0.5, 0.5]))["AUC"] == pytest.approx(0.5)


def test_psi_stable_et_derive():
    rng = np.random.default_rng(0)
    a = pd.Series(rng.normal(0, 1, 5000))
    assert validation.psi(a, pd.Series(rng.normal(0, 1, 5000))) < 0.10      # même distribution
    assert validation.psi(a, pd.Series(rng.normal(1.5, 1, 5000))) > 0.25    # forte dérive


def test_meilleur_seuil_dans_l_intervalle():
    y = np.array([0, 0, 1, 1, 1, 0])
    s = validation.meilleur_seuil(y, np.array([0.1, 0.3, 0.7, 0.8, 0.6, 0.4]))
    assert 0 < s < 1
