# -*- coding: utf-8 -*-
"""Registre des modèles : fiche, enregistrement, relecture."""
import pandas as pd


def test_fiche_et_registre(tmp_path, monkeypatch):
    from sklearn.linear_model import LogisticRegression
    from tunishop_analytics import config, modeles
    monkeypatch.setattr(config, "DOSSIER_MODELES", tmp_path)
    monkeypatch.setattr(modeles, "DOSSIER_FICHES", tmp_path / "fiches")
    df = pd.DataFrame({"x": [0, 1, 2, 3], "y": [0, 0, 1, 1]})
    m = LogisticRegression().fit(df[["x"]], df["y"])
    f = modeles.fiche("essai", "test", objet=m, donnees=df, cible="y", variables=["x"], mesures={"AUC": 1.0}, seuil=0.5)
    assert f["lignes_apprentissage"] == 4 and f["taux_cible"] == 0.5 and "LogisticRegression" in f["reglages"]
    assert f["empreinte_donnees"] == modeles.empreinte(df)              # même données -> même empreinte
    modeles.enregistrer({"pipeline": m}, f)
    assert modeles.charger("essai")["fiche"]["nom"] == "essai"
    r = modeles.registre()
    assert r.loc[0, "mesure_AUC"] == 1.0
