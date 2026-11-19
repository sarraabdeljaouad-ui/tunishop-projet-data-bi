"""Tests du module texte.py (text mining des avis). Lancer : python -m pytest -q tests"""
import pytest

from tunishop_analytics.texte import (analyser, analyser_avis, coherence, detecter_langue, nettoyer,
                                     polarite_globale, traduire_derja)


def test_nettoyage_html_et_espaces():
    assert nettoyer("<p>  Service client   injoignable. </p>") == "Service client injoignable."


def test_nettoyage_entites_html():
    assert nettoyer("Rapport qualit&eacute;/prix") == "Rapport qualité/prix"


@pytest.mark.parametrize("vide", [None, "", "   ", "<br>"])
def test_nettoyage_vide_renvoie_none(vide):
    assert nettoyer(vide) is None


@pytest.mark.parametrize("texte", ["Khayeb, ma3jebnich.", "Behi barcha, livraison fi wa9tha.", "Mriguel, merci TuniShop."])
def test_derja_detecte(texte):
    assert detecter_langue(texte) == "derja"


def test_francais_detecte():
    assert detecter_langue("Rien à dire, parfait !") == "français"


def test_traduction_derja():
    assert traduire_derja("Khayeb, ma3jebnich.") == "mauvais, ne m'a pas plu."
    # l'expression longue passe avant le mot seul
    assert traduire_derja("Behi barcha") == "très bien"


# Les 19 phrases réelles du dataset et le résultat attendu
ATTENDUS = {
    "Behi barcha, livraison fi wa9tha.": {"Satisfaction générale": "positif", "Livraison": "positif"},
    "Bon produit mais emballage abîmé.": {"Qualité produit": "positif", "Emballage": "négatif"},
    "Conforme à la photo, très contente.": {"Qualité produit": "positif", "Satisfaction générale": "positif"},
    "Deuxième commande, toujours aussi satisfait.": {"Fidélité": "positif"},
    "Excellent rapport qualité/prix, je recommande.": {"Prix": "positif", "Satisfaction générale": "positif"},
    "Khayeb, ma3jebnich.": {"Satisfaction générale": "négatif"},
    "Le livreur n'a jamais appelé.": {"Livraison": "négatif"},
    "Livraison très en retard, aucun suivi.": {"Livraison": "négatif"},
    "Moyen, je m'attendais à mieux.": {"Satisfaction générale": "neutre"},
    "Mriguel, merci TuniShop.": {"Satisfaction générale": "positif"},
    "Produit correct mais livraison un peu longue.": {"Qualité produit": "neutre", "Livraison": "négatif"},
    "Produit de bonne qualité, emballage soigné.": {"Qualité produit": "positif", "Emballage": "positif"},
    "Produit non conforme à la description.": {"Qualité produit": "négatif"},
    "Qualité décevante, je ne recommande pas.": {"Qualité produit": "négatif", "Satisfaction générale": "négatif"},
    "Rien à dire, parfait !": {"Satisfaction générale": "positif"},
    "Service client injoignable.": {"Service client": "négatif"},
    "Taille trop petite, retour compliqué.": {"Taille et retours": "négatif"},
    "Très satisfait, produit conforme et livraison rapide.":
        {"Satisfaction générale": "positif", "Livraison": "positif", "Qualité produit": "positif"},
    "Ça va, sans plus.": {"Satisfaction générale": "neutre"},
}


@pytest.mark.parametrize("phrase,attendu", ATTENDUS.items())
def test_themes_et_polarites_des_19_phrases(phrase, attendu):
    assert dict(analyser(phrase)["themes"]) == attendu


def test_analyser_avis_une_ligne_par_theme():
    import pandas as pd
    df = pd.DataFrame({"avis_id": ["A1", "A2", "A3"],
                       "commentaire": ["Bon produit mais emballage abîmé.", None, "<b>Rien à dire, parfait !</b>"]})
    res = analyser_avis(df)
    assert set(res["avis_id"]) == {"A1", "A3"}          # l'avis sans commentaire est écarté
    assert len(res[res["avis_id"] == "A1"]) == 2         # 2 thèmes pour A1


@pytest.mark.parametrize("phrase,attendu", [
    ("Rien à dire, parfait !", "positif"),
    ("Service client injoignable.", "négatif"),
    ("Bon produit mais emballage abîmé.", "neutre"),     # avis mixte
    ("Ça va, sans plus.", "neutre"),
])
def test_polarite_globale(phrase, attendu):
    assert polarite_globale(analyser(phrase)["themes"]) == attendu


def test_polarite_globale_sans_theme():
    assert polarite_globale([]) is None


@pytest.mark.parametrize("note,polarite,attendu", [
    (1, "positif", "texte positif, note basse"),
    (5, "négatif", "texte négatif, note haute"),
    (3, "négatif", "cohérent"),
    (4, "positif", "cohérent"),
    (6, "positif", "non évaluable"),      # note hors échelle
    (None, "positif", "non évaluable"),
    (2, None, "non évaluable"),
])
def test_coherence(note, polarite, attendu):
    assert coherence(note, polarite) == attendu
