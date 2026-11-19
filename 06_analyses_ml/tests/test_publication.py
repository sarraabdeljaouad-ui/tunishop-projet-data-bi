# -*- coding: utf-8 -*-
"""Publication dans TuniShop_ANALYTICS (testée sur une base SQLite temporaire)."""
import numpy as np
import pandas as pd
import pytest


def test_noms_de_tables():
    from tunishop_analytics.publication import nom_table
    assert nom_table("Q01_ventes_annuelles")[0] == "eda_q01_ventes_annuelles"
    assert nom_table("DM01_profil_segments")[0] == "dm01_profil_segments"
    assert nom_table("churn_2025_test")[0] == "ml_pred_churn_2025"
    assert nom_table("EDA_hypotheses_02_EDA_Sales") == ("eda_hypotheses", "notebook", "02_EDA_Sales")


def test_types_sql():
    from tunishop_analytics.publication import type_sql
    assert type_sql(pd.Series([1, 2])) == "INT"
    assert type_sql(pd.Series([1.5, None])) == "FLOAT"
    assert type_sql(pd.Series([True, False])) == "BIT"
    assert type_sql(pd.Series(["2025-01-31", None])) == "DATE"
    assert type_sql(pd.Series(["abc"])) == "NVARCHAR(50)"


def test_compatibilite_des_types():
    from tunishop_analytics.publication import _compatible
    assert _compatible("NVARCHAR(255)", "NVARCHAR(50)") and not _compatible("NVARCHAR(50)", "NVARCHAR(255)")
    assert _compatible("FLOAT", "INT") and not _compatible("INT", "FLOAT")


def test_publier_remplace_et_journalise(base_test):
    pub = base_test
    df = pd.DataFrame({"client_sk": [1, 2, 3], "date_observation": pd.to_datetime(["2025-03-31"] * 3), "score": [0.1, np.nan, 0.9]})
    assert pub.publier(df, "segments_rfm", index=False) == 3
    assert pub.publier(df.head(2), "segments_rfm", index=False) == 2          # remplace, n'ajoute pas
    cn = pub.ouvrir_connexion()
    assert cn.execute("SELECT COUNT(*) FROM ana.dm_segments_rfm").fetchone()[0] == 2
    assert len(pub.journal(10)) == 2


def test_table_partagee(base_test):
    pub = base_test
    pub.publier(pd.DataFrame({"question": ["Q1", "Q2"], "verdict": ["Confirmée"] * 2}), "EDA_hypotheses_02_EDA_Sales", index=False)
    pub.publier(pd.DataFrame({"question": ["Q3"], "verdict": ["Nuancée"]}), "EDA_hypotheses_04_EDA_Products", index=False)
    pub.publier(pd.DataFrame({"question": ["Q1"], "verdict": ["Confirmée"]}), "EDA_hypotheses_02_EDA_Sales", index=False)
    cn = pub.ouvrir_connexion()
    assert cn.execute("SELECT COUNT(*) FROM ana.eda_hypotheses").fetchone()[0] == 2   # Q1 (02) + Q3 (04)


def test_doublon_de_cle_refuse(base_test):
    df = pd.DataFrame({"client_sk": [1, 1], "date_observation": pd.to_datetime(["2025-03-31"] * 2)})
    with pytest.raises(ValueError):
        base_test.publier(df, "segments_rfm", index=False)


def test_publication_desactivee(base_test, monkeypatch):
    monkeypatch.setenv("TUNISHOP_PUBLIER_SQL", "0")
    assert base_test.publier(pd.DataFrame({"a": [1]}), "ZZ_test", index=False) is None
