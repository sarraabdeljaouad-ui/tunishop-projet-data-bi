# -*- coding: utf-8 -*-
"""
texte.py — analyse des commentaires d'avis clients (text mining par règles)
============================================================================

Auteure : Sarra Abdeljaouad · utilisé par 02_Data_Mining/05_Text_Mining_Avis

Ce module ne contient AUCUN modèle de sentiment. C'est volontaire :
les commentaires du dataset se réduisent à 19 phrases générées, chacune
liée à une plage de notes fixe. Un modèle retrouverait la note à 100 %,
ce qui ne prouverait rien. On fait donc une analyse par règles,
transparente et vérifiable :
    1. nettoyage (HTML, espaces)
    2. détection et traduction du derja écrit en arabizi
    3. découpage en propositions ("Bon produit MAIS emballage abîmé")
    4. thème(s) et polarité par proposition
    5. polarité globale de l'avis et cohérence avec la note

Polarités : « positif », « neutre », « négatif ».
"""
from __future__ import annotations

import html
import re
import unicodedata

import pandas as pd

# ---------------------------------------------------------------------------
# 1. Nettoyage
# ---------------------------------------------------------------------------
_RE_BALISE = re.compile(r"<[^>]+>")
_RE_ESPACES = re.compile(r"\s+")


def nettoyer(texte) -> str | None:
    """Retire les balises HTML, décode les entités (&amp;...) et les espaces en trop.
    Renvoie None si le commentaire est vide."""
    if texte is None or (isinstance(texte, float) and pd.isna(texte)):
        return None
    t = html.unescape(str(texte))
    t = _RE_BALISE.sub(" ", t)
    t = _RE_ESPACES.sub(" ", t).strip()
    return t or None


def normaliser(texte: str) -> str:
    """Minuscules, sans accents. Sert uniquement à la comparaison avec les lexiques."""
    t = unicodedata.normalize("NFKD", texte).encode("ascii", "ignore").decode()
    return t.lower()


# ---------------------------------------------------------------------------
# 2. Derja tunisien en arabizi
#    Les chiffres remplacent des lettres arabes sans équivalent latin :
#    3 = ع (ain), 7 = ح (ha), 9 = ق (qaf), 5 = خ (kha).
# ---------------------------------------------------------------------------
LEXIQUE_DERJA: dict[str, str] = {
    "behi barcha": "très bien",
    "behi": "bien",
    "barcha": "beaucoup",
    "mriguel": "parfait",
    "fi wa9tha": "à temps",
    "khayeb": "mauvais",
    "ma3jebnich": "ne m'a pas plu",
    "3jebni": "m'a plu",
}
# Les expressions longues d'abord, pour que "behi barcha" passe avant "behi".
_DERJA_TRIE = sorted(LEXIQUE_DERJA, key=len, reverse=True)
_RE_ARABIZI = re.compile(r"\b[a-z]*[3579][a-z]+\b")


def detecter_langue(texte: str) -> str:
    """'derja' si le texte contient un mot du lexique ou un mot arabizi (lettres + chiffres 3/5/7/9)."""
    n = normaliser(texte)
    if any(re.search(rf"\b{re.escape(m)}\b", n) for m in LEXIQUE_DERJA) or _RE_ARABIZI.search(n):
        return "derja"
    return "français"


def traduire_derja(texte: str) -> str:
    """Remplace les expressions derja connues par leur sens en français."""
    t = texte
    for mot in _DERJA_TRIE:
        t = re.sub(rf"\b{re.escape(mot)}\b", LEXIQUE_DERJA[mot], t, flags=re.IGNORECASE)
    return t


# ---------------------------------------------------------------------------
# 3. Thèmes et polarité (lexiques sur texte normalisé, sans accents)
# ---------------------------------------------------------------------------
THEMES: dict[str, list[str]] = {
    "Prix": [r"rapport qualite ?/ ?prix", r"\bprix\b"],
    "Livraison": [r"\blivraison", r"\blivreur", r"\bretard", r"\bsuivi\b", r"\ba temps\b"],
    "Emballage": [r"\bemballage"],
    "Service client": [r"\bservice client"],
    "Taille et retours": [r"\btaille\b", r"\bretour"],
    "Fidélité": [r"\bdeuxieme commande", r"\btoujours aussi\b"],
    "Qualité produit": [r"\bqualite\b", r"\bconforme\b", r"\bproduit\b", r"\bphoto\b", r"\bdescription\b"],
}
THEME_PAR_DEFAUT = "Satisfaction générale"

# Ordre de test : négatif, puis neutre, puis positif.
# Ainsi "non conforme" passe avant "conforme", "ne recommande pas" avant "recommande".
POLARITES: list[tuple[str, list[str]]] = [
    ("négatif", [r"non conforme", r"ne recommande pas", r"decevant", r"abime", r"retard",
                 r"aucun suivi", r"jamais", r"injoignable", r"trop petit", r"complique",
                 r"\blongue?\b", r"mauvais", r"ne m'a pas plu"]),
    ("neutre", [r"\bmoyen\b", r"attendais a mieux", r"sans plus", r"\bca va\b", r"\bcorrect\b"]),
    ("positif", [r"satisfait", r"\bconforme\b", r"rapide", r"excellent", r"recommande",
                 r"\bbon(ne)?\b", r"soigne", r"content", r"parfait", r"rien a dire",
                 r"merci", r"tres bien", r"\bbien\b", r"a temps", r"m'a plu"]),
]

_RE_DECOUPE = re.compile(r"\bmais\b|[,.;!?]")
_RE_PRIX = re.compile(r"rapport qualite ?/ ?prix")


def _polarite(proposition: str) -> str | None:
    for pol, motifs in POLARITES:
        if any(re.search(m, proposition) for m in motifs):
            return pol
    return None


def _themes(proposition: str) -> list[str]:
    trouves = []
    if _RE_PRIX.search(proposition):
        trouves.append("Prix")
        proposition = _RE_PRIX.sub(" ", proposition)  # "qualité" de "qualité/prix" ne compte pas
    for theme, motifs in THEMES.items():
        if theme == "Prix":
            continue
        if any(re.search(m, proposition) for m in motifs):
            trouves.append(theme)
    return trouves


def analyser(commentaire) -> dict:
    """Analyse un commentaire. Renvoie :
    {texte_nettoye, langue, texte_fr, themes: [(theme, polarite), ...]}"""
    t = nettoyer(commentaire)
    if t is None:
        return {"texte_nettoye": None, "langue": None, "texte_fr": None, "themes": []}

    langue = detecter_langue(t)
    texte_fr = traduire_derja(t) if langue == "derja" else t
    propositions = [p.strip() for p in _RE_DECOUPE.split(normaliser(texte_fr)) if p.strip()]

    analyse = [(_themes(p), _polarite(p)) for p in propositions]
    # Polarité d'ensemble : la première trouvée, en donnant la priorité au négatif.
    pols = [pol for _, pol in analyse if pol]
    pol_globale = next((p for p in ("négatif", "neutre", "positif") if p in pols), None)

    # Un thème = une seule polarité. S'il apparaît deux fois, on garde la plus défavorable.
    rang = {"négatif": 0, "neutre": 1, "positif": 2}
    par_theme: dict[str, str] = {}
    for themes, pol in analyse:
        if not themes and not pol:
            continue
        for theme in themes or [THEME_PAR_DEFAUT]:
            p = pol or pol_globale or "neutre"
            if theme not in par_theme or rang[p] < rang[par_theme[theme]]:
                par_theme[theme] = p
    resultat = list(par_theme.items())
    return {"texte_nettoye": t, "langue": langue, "texte_fr": texte_fr, "themes": resultat}


def analyser_avis(df: pd.DataFrame, col_texte: str = "commentaire") -> pd.DataFrame:
    """Prend un DataFrame d'avis (avec avis_id et la colonne texte) et renvoie
    une ligne par (avis, thème) : prêt à écrire dans TuniShop_ANALYTICS.

    Les phrases étant très répétées, on analyse chaque phrase distincte une seule fois."""
    avis = df.copy()
    avis["texte_nettoye"] = avis[col_texte].map(nettoyer)
    avis = avis[avis["texte_nettoye"].notna()]

    cache = {t: analyser(t) for t in avis["texte_nettoye"].unique()}
    avis["langue"] = avis["texte_nettoye"].map(lambda t: cache[t]["langue"])
    avis["texte_fr"] = avis["texte_nettoye"].map(lambda t: cache[t]["texte_fr"])
    avis["couples"] = avis["texte_nettoye"].map(lambda t: cache[t]["themes"])

    long = avis.explode("couples").dropna(subset=["couples"])
    long["theme"] = long["couples"].map(lambda c: c[0])
    long["polarite"] = long["couples"].map(lambda c: c[1])
    return long.drop(columns=["couples"]).reset_index(drop=True)


# ---------------------------------------------------------------------------
# 4. Polarité globale d'un avis et cohérence avec la note
# ---------------------------------------------------------------------------
def polarite_globale(themes: list[tuple[str, str]]) -> str | None:
    """Résume les polarités par thème en une polarité d'avis :
    - « positif » : au moins un thème positif et aucun négatif ;
    - « négatif » : au moins un thème négatif et aucun positif ;
    - « neutre »  : thèmes seulement neutres, ou avis mixte (« Bon produit mais emballage abîmé »).
    None si l'avis n'a aucun thème."""
    pols = {p for _, p in themes}
    if not pols:
        return None
    if "positif" in pols and "négatif" not in pols:
        return "positif"
    if "négatif" in pols and "positif" not in pols:
        return "négatif"
    return "neutre"


def coherence(note, polarite: str | None) -> str:
    """Compare le texte à la note (échelle 1 à 5).
    « texte positif, note basse » : texte positif et note de 1 ou 2 ;
    « texte négatif, note haute » : texte négatif et note de 4 ou 5 ;
    « cohérent » sinon ; « non évaluable » sans polarité ou sans note valide."""
    if polarite is None or note is None or pd.isna(note) or not 1 <= note <= 5:
        return "non évaluable"
    if polarite == "positif" and note <= 2:
        return "texte positif, note basse"
    if polarite == "négatif" and note >= 4:
        return "texte négatif, note haute"
    return "cohérent"
