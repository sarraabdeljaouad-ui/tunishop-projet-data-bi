# -*- coding: utf-8 -*-
"""Tests du module suivi.py (version 1.5) : rejeu de la production mois par mois et historique du suivi."""
import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import OneHotEncoder

from tunishop_analytics import suivi


def _suivi(valeur=0.1, statut="OK"):
    return pd.DataFrame([
        {"cas": "retard", "objet": "SahelLog", "periode": "2025-01", "indicateur": "écart", "valeur": valeur, "seuil": 0.05, "statut": statut},
        {"cas": "ventes", "objet": "total", "periode": "2025-01", "indicateur": "erreur", "valeur": 0.02, "seuil": 0.2, "statut": "OK"},
    ])


# ---------------------------------------------------------------- historiser
def test_premiere_execution_cree_l_historique():
    h = suivi.historiser(_suivi(), None, "2025-12-31", "2026-11-19 10:00:00")
    assert list(h.columns) == suivi.COLONNES_HISTORIQUE
    assert len(h) == 2 and set(h["date_donnees"]) == {"2025-12-31"}


def test_relancer_sur_les_memes_donnees_remplace_sans_doublon():
    h1 = suivi.historiser(_suivi(0.1, "ALERTE"), None, "2025-12-31", "2026-11-19 10:00:00")
    h2 = suivi.historiser(_suivi(0.01, "OK"), h1, "2025-12-31", "2026-11-19 11:00:00")
    assert len(h2) == 2
    ligne = h2[h2["cas"] == "retard"].iloc[0]
    assert ligne["valeur"] == 0.01 and ligne["statut"] == "OK" and ligne["calcule_le"] == "2026-11-19 11:00:00"


def test_nouvelles_donnees_ajoutent_des_lignes_et_gardent_les_anciennes():
    h1 = suivi.historiser(_suivi(), None, "2025-12-31", "2026-11-19 10:00:00")
    h2 = suivi.historiser(_suivi(), h1, "2026-01-31", "2026-02-02 08:00:00")
    assert len(h2) == 4
    assert h2.groupby("date_donnees").size().to_dict() == {"2025-12-31": 2, "2026-01-31": 2}


def test_suivi_incomplet_ou_en_double_refuse():
    with pytest.raises(ValueError):
        suivi.historiser(_suivi().drop(columns="statut"), None, "2025-12-31", "2026-11-19")
    double = pd.concat([_suivi(), _suivi().iloc[:1]])
    with pytest.raises(ValueError):
        suivi.historiser(double, None, "2025-12-31", "2026-11-19")


def test_historique_relu_depuis_le_csv(tmp_path):
    h1 = suivi.historiser(_suivi(), None, "2025-12-31", "2026-11-19 10:00:00")
    chemin = tmp_path / "ML_suivi_historique.csv"
    h1.to_csv(chemin, index=False, sep=";", decimal=",", encoding="utf-8-sig")      # format de config.exporter_table
    relu = suivi.lire_historique(chemin)
    assert relu["valeur"].tolist() == pytest.approx(h1["valeur"].tolist())
    h2 = suivi.historiser(_suivi(), relu, "2026-01-31", "2026-02-02 08:00:00")
    assert len(h2) == 4
    assert suivi.lire_historique(tmp_path / "absent.csv") is None


# ---------------------------------------------------------------- rejeu de la production
def _expeditions(n_mois=30, rupture=12, par_mois=400, graine=0):
    """Deux transporteurs ; B passe de 5 % à 40 % de retard au mois `rupture`."""
    rng = np.random.default_rng(graine)
    lignes = []
    for m in range(n_mois):
        debut = pd.Timestamp("2023-01-01") + pd.DateOffset(months=m)
        for tr in ("A", "B"):
            taux = 0.10 if tr == "A" else (0.05 if m < rupture else 0.40)
            jours = rng.integers(0, 28, par_mois)
            lignes.append(pd.DataFrame({"date_expedition": debut + pd.to_timedelta(jours, unit="D"), "transporteur": tr,
                                        "en_retard": (rng.random(par_mois) < taux).astype(int)}))
    return pd.concat(lignes, ignore_index=True)


def _pipeline():
    return make_pipeline(OneHotEncoder(handle_unknown="ignore"), LogisticRegression(max_iter=1000))


def test_rejeu_un_resultat_par_mois_et_par_transporteur():
    t = _expeditions()
    r = suivi.rejouer_fenetre_glissante(t, _pipeline(), ["transporteur"], "en_retard", "date_expedition",
                                        mois_fenetre=12, nb_mois=6)
    assert r["mois"].nunique() == 6 and len(r) == 12
    assert r["mois"].max() == "2025-06"
    assert (r["lignes_apprentissage"] <= 12 * 2 * 400).all()     # jamais plus que 12 mois d'historique


def test_fenetre_recente_corrige_la_rupture_et_tout_l_historique_non():
    t = _expeditions()
    court = suivi.rejouer_fenetre_glissante(t, _pipeline(), ["transporteur"], "en_retard", "date_expedition",
                                            mois_fenetre=12, nb_mois=3)
    long = suivi.rejouer_fenetre_glissante(t, _pipeline(), ["transporteur"], "en_retard", "date_expedition",
                                           mois_fenetre=1000, nb_mois=3)
    b_court = court[court["transporteur"] == "B"]["ecart"].abs().mean()
    b_long = long[long["transporteur"] == "B"]["ecart"].abs().mean()
    assert b_court < 0.05 < b_long                               # 12 mois après la rupture : fenêtre calibrée


def test_mois_sans_historique_ignore_et_donnees_insuffisantes_refusees():
    t = _expeditions(n_mois=3)
    r = suivi.rejouer_fenetre_glissante(t, _pipeline(), ["transporteur"], "en_retard", "date_expedition", nb_mois=3)
    assert "2023-01" not in set(r["mois"])                        # premier mois : rien avant pour apprendre
    with pytest.raises(ValueError):
        suivi.rejouer_fenetre_glissante(_expeditions(n_mois=1), _pipeline(), ["transporteur"], "en_retard",
                                        "date_expedition")


def test_predictions_glissantes_jamais_sur_des_lignes_vues():
    """Chaque mois est prédit par un modèle appris uniquement sur les mois d'avant (v1.5.1 : seuil d'alerte)."""
    t = _expeditions()
    p = suivi.predictions_glissantes(t, _pipeline(), ["transporteur"], "en_retard", "date_expedition",
                                     mois_fenetre=12, nb_mois=4)
    assert sorted(p["mois_rejoue"].unique()) == ["2025-03", "2025-04", "2025-05", "2025-06"]
    assert len(p) == 4 * 2 * 400 and p["proba"].between(0, 1).all()
    assert (p["lignes_apprentissage"] == 12 * 2 * 400).all()                  # exactement les 12 mois d'avant
    r = suivi.rejouer_fenetre_glissante(t, _pipeline(), ["transporteur"], "en_retard", "date_expedition",
                                        mois_fenetre=12, nb_mois=4, predictions=p)
    assert len(r) == 8 and list(r["mois"].unique()) == ["2025-03", "2025-04", "2025-05", "2025-06"]


# ---------------------------------------------------------------- publication
def test_historique_publie_avec_sa_cle(base_test):
    h = suivi.historiser(_suivi(), None, "2025-12-31", "2026-11-19 10:00:00")
    assert base_test.publier(h, "ML_suivi_historique", index=False) == 2
    with pytest.raises(ValueError):                               # clé en double : publication refusée
        base_test.publier(pd.concat([h, h.iloc[:1]]), "ML_suivi_historique", index=False)
