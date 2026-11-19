# -*- coding: utf-8 -*-
"""Variables : segments RFM, variables du clustering, demande v2, absence de fuite."""
import numpy as np
import pandas as pd
import pytest

from tunishop_analytics import features


@pytest.mark.parametrize("r,f,attendu", [(5, 5, "Champions"), (3, 4, "Fidèles"), (4, 2, "Fidèles potentiels"),
                                         (5, 1, "Nouveaux"), (3, 1, "À surveiller"), (2, 4, "À risque"),
                                         (1, 3, "Hibernants"), (1, 1, "Perdus")])
def test_regles_des_segments(r, f, attendu):
    assert features._segment(r, f) == attendu


def test_scores_rfm_bornes():
    t = pd.DataFrame({"recence_j": [1, 50, 100, 200, 400], "frequence": [10, 5, 3, 2, 1],
                      "montant_reconnu_ttc": [5000, 900, 400, 100, 20]})
    s = features.scores_rfm(t, features.seuils_rfm(t))
    assert s[["score_r", "score_f", "score_m"]].isin(range(1, 6)).all().all()
    assert s.loc[0, "score_r"] == 5 and s.loc[4, "score_r"] == 1      # récence courte = meilleur score
    assert s.loc[0, "segment_rfm"] == "Champions"


def test_variables_clustering():
    t = pd.DataFrame({"recence_j": [0, 9], "frequence": [1, 3], "montant_reconnu_ttc": [0, 99], "panier_moyen_ttc": [10, 33],
                      "part_mobile": [0.5, 1], "part_coupon": [0, 0.2], "nb_categories": [1, 2], "part_livraisons_retard": [np.nan, 0.5]})
    x = features.variables_clustering(t)
    assert list(x.columns) == features.VARIABLES_CLUSTERING
    assert x["part_retard"].iloc[0] == 0 and x["log_recence"].iloc[1] == pytest.approx(np.log(10))


def test_aucune_fuite_dans_les_variables():
    for cas, d in features.CAS_ML.items():
        variables = set(features.colonnes_ml(cas))
        interdites = {c.strip() for cle in d["ecartees"] for c in cle.split("/")}
        assert not variables & interdites, (cas, variables & interdites)
        assert d["cible"] not in variables


def test_demande_v2_calcul_a_la_main():
    # Année 2024 : catégorie A, produit P1 = 75 % et P2 = 25 % ; 10 unités chaque mois sauf 40 au T4
    mois = pd.date_range("2024-01-01", periods=12, freq="MS")
    q = [10] * 9 + [40] * 3
    pm = pd.concat([pd.DataFrame({"produit_id": "P1", "categorie": "A", "mois": mois, "quantite": np.array(q) * 0.75}),
                    pd.DataFrame({"produit_id": "P2", "categorie": "A", "mois": mois, "quantite": np.array(q) * 0.25})])
    lignes = pd.DataFrame({"produit_id": ["P1", "P2"], "categorie": ["A", "A"], "mois": pd.to_datetime(["2025-01-01"] * 2),
                           "moy_categorie_annee_prec": [np.nan, np.nan]})
    p = features.prevision_demande_v2(lignes, pm)
    # même mois N-1 = 10 ; croissance = (120/3) / (210/12) = 2,29 bornée à 1,6 ; parts 0,75 / 0,25
    assert p.tolist() == pytest.approx([10 * 1.6 * 0.75, 10 * 1.6 * 0.25])


def test_preprocesseur_tolere_une_modalite_nouvelle():
    from sklearn.linear_model import LinearRegression
    from sklearn.pipeline import make_pipeline
    cols = features.colonnes_ml("retard")
    n = 20
    x = pd.DataFrame({c: np.arange(n, dtype=float) for c in features.CAS_ML["retard"]["numeriques"]})
    for c in features.CAS_ML["retard"]["categorielles"]:
        x[c] = ["a", "b"] * (n // 2)
    pipe = make_pipeline(features.preprocesseur("retard"), LinearRegression()).fit(x[cols], np.arange(n))
    x2 = x.head(2).copy(); x2["transporteur"] = "nouveau transporteur"
    assert len(pipe.predict(x2[cols])) == 2
