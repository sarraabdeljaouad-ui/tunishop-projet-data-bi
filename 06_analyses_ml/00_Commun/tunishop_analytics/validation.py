# -*- coding: utf-8 -*-
"""
validation.py — contrôles de qualité des données avant toute analyse
=====================================================================

Une analyse n'a de valeur que si ses données sont fiables. Ce module regroupe les 11 contrôles
du cahier d'analyse exploratoire (C01 à C11) :

    controle_inventaire(inv)      C02  les 23 vues ont le nombre de lignes attendu
    verifier_coherence(p)         C03-C07  5 totaux : validé (PV) = calcul SQL = calcul Python
    integrite_referentielle()     C08  chaque clé d'un fait retrouve sa dimension (SQL direct)
    unicite(p)                    C09  aucune clé de fait en double
    membres_techniques(p)         C10  part des clés -1 (inconnu) / -2 (non applicable)
    valeurs_manquantes(p)         C11  part des valeurs vides par colonne
    valeurs_extremes(p)           complément : montants et délais hors normes (règle de Tukey)

Chaque fonction renvoie un tableau pandas avec une colonne « statut » (OK / ÉCART / INFO).
"""
from __future__ import annotations

import pandas as pd

from . import chargement
from .config import LIGNES_ATTENDUES, SCHEMA, VALEURS_VALIDEES

# Les mêmes totaux que le PV, calculés DIRECTEMENT dans SQL Server sur les vues bi
CONTROLES_SQL = {
    "Lignes de vente": "SELECT COUNT(*) FROM bi.v_fact_ventes",
    "Commandes": "SELECT COUNT(*) FROM bi.v_fact_commandes",
    "Livraisons": "SELECT COUNT(*) FROM bi.v_fact_livraisons",
    "CA reconnu TTC (DT)": """
        SELECT SUM(c.montant_total_ttc)
        FROM bi.v_fact_commandes c
        JOIN bi.v_dim_statut_commande s ON s.statut_commande_sk = c.statut_commande_sk
        WHERE s.famille_statut = 'aboutie'""",
    "Clients ayant commandé (hors membre inconnu)":
        "SELECT COUNT(DISTINCT client_sk) FROM bi.v_fact_commandes WHERE client_sk > 0",
}

# Relations fait -> dimension contrôlées (fait, clé dans le fait, dimension)
RELATIONS = [
    ("v_fact_ventes", "produit_sk", "v_dim_produit"),
    ("v_fact_ventes", "date_commande_sk", "v_dim_date"),
    ("v_fact_commandes", "client_sk", "v_dim_client"),
    ("v_fact_commandes", "canal_sk", "v_dim_canal"),
    ("v_fact_commandes", "statut_commande_sk", "v_dim_statut_commande"),
    ("v_fact_commandes", "coupon_sk", "v_dim_coupon"),
    ("v_fact_paiements", "mode_paiement_sk", "v_dim_mode_paiement"),
    ("v_fact_livraisons", "transporteur_sk", "v_dim_transporteur"),
    ("v_fact_livraisons", "geographie_sk", "v_dim_geographie"),
    ("v_fact_livraisons", "entrepot_sk", "v_dim_entrepot"),
    ("v_fact_remboursements", "motif_retour_sk", "v_dim_motif_retour"),
    ("v_fact_avis", "produit_sk", "v_dim_produit"),
    ("v_fact_marketing_quotidien", "campagne_sk", "v_dim_campagne"),
    ("v_fact_achats_fournisseur", "fournisseur_sk", "v_dim_fournisseur"),
    ("v_fact_mouvements_stock", "produit_sk", "v_dim_produit"),
    ("v_fact_stock_mensuel", "entrepot_sk", "v_dim_entrepot"),
]

# Clé unique de chaque table de faits préparée
CLES = {"cmd": "commande_id", "lig": "ligne_id", "liv": "livraison_id", "rmb": "remboursement_id",
        "avis": "avis_id", "pai": "paiement_id"}


def controle_inventaire(inventaire: pd.DataFrame) -> pd.DataFrame:
    """C02 — compare le nombre de lignes de chaque vue (inventaire_vues()) à la valeur attendue."""
    t = inventaire.copy()
    t["lignes_attendues"] = t["vue"].str.replace(f"{SCHEMA}.", "", regex=False).map(LIGNES_ATTENDUES)
    t["ecart"] = t["lignes"] - t["lignes_attendues"]
    t["statut"] = t["ecart"].map(lambda e: "OK" if e == 0 else "ÉCART")
    return t


def verifier_coherence(p: dict, avec_sql: bool = True) -> pd.DataFrame:
    """C03 à C07 — 5 totaux : valeur validée (PV) / calcul SQL direct sur les vues / calcul Python.

    - SQL = Python : la lecture et la préparation n'ont rien perdu ni dupliqué ;
    - SQL = PV     : le DWH est toujours celui qui a été validé.
    Si une ligne est en ÉCART, on s'arrête et on vérifie la source avant d'aller plus loin.
    """
    cmd = p["cmd"]
    python = {
        "Lignes de vente": len(p["lig"]),
        "Commandes": len(cmd),
        "Livraisons": len(p["liv"]),
        "CA reconnu TTC (DT)": round(cmd.loc[cmd["est_aboutie"], "montant_total_ttc"].sum(), 3),
        "Clients ayant commandé (hors membre inconnu)": cmd.loc[cmd["client_sk"] > 0, "client_sk"].nunique(),
    }
    lignes = []
    for i, (nom, attendu) in enumerate(VALEURS_VALIDEES.items()):
        ligne = {"controle": f"C0{3 + i}", "indicateur": nom, "valide_pv": attendu}
        valeurs = [python[nom]]
        if avec_sql:
            v_sql = round(float(chargement.valeur(CONTROLES_SQL[nom])), 3)
            ligne["sql_vues_bi"] = v_sql
            valeurs.append(v_sql)
        ligne["python_pandas"] = python[nom]
        ligne["statut"] = "OK" if all(abs(v - attendu) < 0.01 for v in valeurs) else "ÉCART"
        lignes.append(ligne)
    return pd.DataFrame(lignes)


def integrite_referentielle(relations: list = RELATIONS) -> pd.DataFrame:
    """C08 — 🔗 SQL direct : lignes de faits dont la clé ne retrouve PAS sa dimension.

    Principe : LEFT JOIN du fait vers la dimension ; si la dimension est vide (IS NULL),
    la ligne est « orpheline ». Attendu : 0 partout (les inconnus pointent vers le membre -1).
    """
    morceaux = []
    for fait, cle, dim in relations:
        cle_dim = "date_sk" if dim == "v_dim_date" else cle
        morceaux.append(f"""
            SELECT '{fait}' AS fait, '{cle}' AS cle, '{dim}' AS dimension, COUNT(*) AS lignes,
                   SUM(CASE WHEN d.{cle_dim} IS NULL THEN 1 ELSE 0 END) AS orphelines
            FROM {SCHEMA}.{fait} f LEFT JOIN {SCHEMA}.{dim} d ON d.{cle_dim} = f.{cle}""")
    t = chargement.requete(" UNION ALL ".join(morceaux))
    t["statut"] = t["orphelines"].map(lambda n: "OK" if n == 0 else "ÉCART")
    return t


def unicite(p: dict) -> pd.DataFrame:
    """C09 — nombre de doublons sur la clé de chaque table de faits (attendu : 0)."""
    lignes = []
    for table, cle in CLES.items():
        doublons = int(p[table][cle].duplicated().sum())
        lignes.append({"table": table, "cle": cle, "lignes": len(p[table]), "doublons": doublons,
                       "statut": "OK" if doublons == 0 else "ÉCART"})
    return pd.DataFrame(lignes)


def membres_techniques(p: dict) -> pd.DataFrame:
    """C10 — part des clés -1 (inconnu) et -2 (non applicable) dans les commandes.

    -1 doit rester rare (une donnée qu'on n'a pas su rattacher) ; -2 est une information métier
    (pas de coupon, pas encore expédiée...) et n'est pas une erreur.
    """
    cmd = p["cmd"]
    colonnes = ["client_sk", "geographie_sk", "canal_sk", "campagne_sk", "coupon_sk", "mode_paiement_sk",
                "date_expedition_sk", "date_livraison_sk"]
    t = pd.DataFrame([{"colonne": c, "inconnu_-1": int((cmd[c] == -1).sum()), "non_applicable_-2": int((cmd[c] == -2).sum()),
                       "part_-1": (cmd[c] == -1).mean(), "part_-2": (cmd[c] == -2).mean()} for c in colonnes])
    t["statut"] = t["part_-1"].map(lambda x: "OK" if x < 0.01 else "ÉCART")
    return t


def valeurs_manquantes(p: dict, tables: tuple = ("cmd", "lig", "liv", "rmb", "avis", "pai", "ach", "mkt")) -> pd.DataFrame:
    """C11 — part des valeurs vides par colonne (seules les colonnes concernées sont listées).

    Le statut est INFO : un vide n'est pas une erreur s'il a une explication métier
    (ex. pas de délai de livraison pour une commande non livrée). L'explication est donnée
    dans la lecture du notebook et dans le Rapport_Qualite_Analytique.
    """
    lignes = []
    for nom in tables:
        m = p[nom].isna().mean()
        for col, part in m[m > 0].items():
            lignes.append({"table": nom, "colonne": col, "lignes": len(p[nom]),
                           "vides": int(p[nom][col].isna().sum()), "part_vide": part, "statut": "INFO"})
    return pd.DataFrame(lignes).sort_values("part_vide", ascending=False).reset_index(drop=True)


def valeurs_extremes(p: dict) -> pd.DataFrame:
    """Complément — valeurs hors normes selon la règle de Tukey (au-delà de Q3 + 3 × écart interquartile).

    On utilise 3 × l'écart (valeurs « très » extrêmes) : sur des montants très asymétriques,
    la règle classique de 1,5 × signalerait trop de valeurs normales. Statut INFO : on les
    garde dans l'analyse, mais les modèles devront être robustes (logarithme, arbres).
    """
    variables = [("cmd", "montant_total_ttc", "Montant d'une commande (DT)"),
                 ("cmd", "nb_articles", "Articles par commande"),
                 ("liv", "delai_livraison_j", "Délai de livraison (j)"),
                 ("liv", "delai_preparation_h", "Préparation (h)"),
                 ("liv", "poids_kg", "Poids du colis (kg)"),
                 ("rmb", "montant_demande_ttc", "Montant demandé en remboursement (DT)"),
                 ("ach", "retard_appro_j", "Retard fournisseur (j)")]
    lignes = []
    for table, col, libelle in variables:
        x = p[table][col].dropna()
        q1, q3 = x.quantile([0.25, 0.75])
        seuil = q3 + 3 * (q3 - q1)
        n = int((x > seuil).sum())
        lignes.append({"table": table, "variable": col, "libelle": libelle, "valeurs": len(x), "mediane": x.median(),
                       "q3": q3, "seuil_haut": seuil, "maximum": x.max(), "nb_extremes": n,
                       "part_extremes": n / len(x) if len(x) else 0, "statut": "INFO"})
    return pd.DataFrame(lignes)


# =====================================================================================
# Synthèse et rapport Excel
# =====================================================================================
_LIBELLES = {
    "inventaire": ("C01-C02", "Connexion et 23 vues complètes"),
    "coherence": ("C03-C07", "5 totaux validés : PV = SQL = Python"),
    "integrite": ("C08", "Intégrité référentielle (relations fait -> dimension)"),
    "unicite": ("C09", "Unicité des clés de faits"),
    "membres": ("C10", "Membres techniques -1 rares"),
    "manquants": ("C11", "Valeurs manquantes (toutes expliquées par le métier)"),
    "extremes": ("—", "Valeurs extrêmes (règle de Tukey, 3 × écart interquartile)"),
}


def synthese_qualite(resultats: dict) -> pd.DataFrame:
    """Une ligne par contrôle : nombre de vérifications, nombre d'OK / ÉCART / INFO, statut global."""
    lignes = []
    for cle, (code, libelle) in _LIBELLES.items():
        t = resultats[cle]
        n_ok, n_ecart, n_info = (int((t["statut"] == s).sum()) for s in ("OK", "ÉCART", "INFO"))
        statut = "ÉCART" if n_ecart else ("INFO" if n_info else "OK")
        lignes.append({"controle": code, "libelle": libelle, "verifications": len(t), "ok": n_ok,
                       "ecart": n_ecart, "info": n_info, "statut": statut})
    return pd.DataFrame(lignes)


def rapport_qualite_excel(resultats: dict, chemin) -> str:
    """Écrit Rapport_Qualite_Analytique.xlsx : une synthèse + une feuille par contrôle."""
    import datetime as dt
    from .config import DATE_LIVRABLES, VERSION_LIVRABLES, exporter_excel
    quand = (f"Livrable EDA v{VERSION_LIVRABLES['EDA']} du {DATE_LIVRABLES['EDA']} · Sarra Abdeljaouad · "
             f"lecture directe de TuniShop_DWH (vues bi) le {dt.datetime.now():%d/%m/%Y à %H:%M}")
    feuilles = {"00_Synthese": ("Rapport de qualité analytique — TuniShop_DWH", quand, synthese_qualite(resultats))}
    titres = {
        "inventaire": ("01_Inventaire", "C01-C02 — Inventaire des 23 vues bi", "Lignes lues dans SQL Server contre lignes du DWH validé"),
        "coherence": ("02_Totaux_valides", "C03-C07 — Point de départ contrôlé", "Valeur du PV, calcul SQL direct sur les vues, calcul Python"),
        "integrite": ("03_Integrite", "C08 — Intégrité référentielle", "Lignes de faits dont la clé ne retrouve pas sa dimension (SQL : LEFT JOIN ... IS NULL)"),
        "unicite": ("04_Unicite", "C09 — Unicité des clés", "Doublons sur la clé de chaque table de faits"),
        "membres": ("05_Membres_techniques", "C10 — Membres techniques des commandes", "-1 = inconnu (défaut de qualité si fréquent) ; -2 = non applicable (information métier)"),
        "manquants": ("06_Valeurs_manquantes", "C11 — Valeurs manquantes", "Part des valeurs vides ; explication métier dans la colonne « explication »"),
        "extremes": ("07_Valeurs_extremes", "Valeurs extrêmes", "Au-delà de Q3 + 3 × (Q3 - Q1) ; conservées dans l'analyse"),
    }
    manquants = resultats["manquants"].copy()
    manquants["explication"] = manquants["colonne"].map(EXPLICATIONS_VIDES).fillna("")
    resultats = {**resultats, "manquants": manquants}
    for cle, (feuille, titre, sous_titre) in titres.items():
        feuilles[feuille] = (titre, sous_titre, resultats[cle])
    return exporter_excel(feuilles, chemin, "Rapport de qualité analytique — TuniShop")


# Explication métier de chaque colonne vide (utilisée dans le rapport Excel)
EXPLICATIONS_VIDES = {
    "code_erreur": "Rempli seulement pour les paiements échoués",
    "delai_reversement_j": "Concerne seulement le paiement à la livraison (argent reversé par le transporteur)",
    "commentaire": "Commentaire facultatif dans un avis",
    "etat_article": "Sans objet pour les annulations et gestes commerciaux (pas d'article retourné)",
    "quantite": "Sans objet pour les annulations et gestes commerciaux",
    "delai_livraison_j": "Commande ou colis non livré",
    "est_livree_a_temps": "Commande non livrée",
    "cout_transport_ht": "Commande jamais expédiée (annulée, échec de paiement)",
    "delai_traitement_j": "Demande en cours ou refusée (+ 15 remboursements sans délai, écart connu de la recette des cubes)",
    "retard_j": "Colis non livré (échec, en transit, en préparation)",
    "retard_appro_j": "Bon fournisseur pas encore reçu",
    "delai_appro_reel_j": "Bon fournisseur pas encore reçu",
    "quantite_recue": "Bon fournisseur pas encore reçu",
    "impressions": "Jours de campagne sans impressions renseignées par la plateforme",
    "nb_tentatives": "Colis pas encore remis au transporteur",
    "note": "Avis sans note",
    "sentiment": "Avis sans note (le sentiment est déduit de la note)",
    "delai_preparation_h": "Colis pas encore préparé",
    "annee": "Colis pas encore expédié (pas de date d'expédition)",
    "semestre": "Colis pas encore expédié (pas de date d'expédition)",
}


# =====================================================================================
# Dérive des données entre l'apprentissage et le test
# =====================================================================================
def psi(apprentissage: pd.Series, test: pd.Series, classes: int = 10) -> float:
    """Indice de stabilité de population (PSI) d'une variable entre l'apprentissage et le test.

    Lecture usuelle : < 0,10 stable ; 0,10 à 0,25 dérive modérée ; > 0,25 forte dérive.
    Variable numérique : découpée en déciles de l'apprentissage. Catégorielle : une classe par modalité.
    """
    import numpy as np
    a, b = apprentissage.dropna(), test.dropna()
    if len(a) == 0 or len(b) == 0:
        return float("nan")
    if pd.api.types.is_numeric_dtype(a) and a.nunique() > classes:
        bornes = np.unique(np.quantile(a, np.linspace(0, 1, classes + 1)))
        bornes[0], bornes[-1] = -np.inf, np.inf
        pa = pd.cut(a, bornes).value_counts(normalize=True, sort=False)
        pb = pd.cut(b, bornes).value_counts(normalize=True, sort=False)
    else:
        pa, pb = a.astype(str).value_counts(normalize=True), b.astype(str).value_counts(normalize=True)
        pa, pb = pa.align(pb, fill_value=0)
    pa, pb = pa.clip(lower=1e-4), pb.clip(lower=1e-4)
    return float(((pb - pa) * np.log(pb / pa)).sum())


def derive(apprentissage: pd.DataFrame, test: pd.DataFrame, colonnes: list) -> pd.DataFrame:
    """PSI de chaque variable, trié de la plus forte dérive à la plus faible, avec un niveau lisible."""
    t = pd.DataFrame({"variable": colonnes, "psi": [psi(apprentissage[c], test[c]) for c in colonnes]})
    t["niveau"] = pd.cut(t["psi"], [-1, 0.10, 0.25, 99], labels=["stable", "dérive modérée", "forte dérive"])
    t["statut"] = t["niveau"].map({"stable": "OK", "dérive modérée": "INFO", "forte dérive": "ÉCART"}).astype(str)
    return t.sort_values("psi", ascending=False).reset_index(drop=True)


# =====================================================================================
# Mesures de performance des modèles (03_Machine_Learning)
# =====================================================================================
def metriques_regression(reel, prevu) -> dict:
    """MAE, WAPE, MAPE (si pas de zéro) et biais d'une prévision."""
    import numpy as np
    reel, prevu = np.asarray(reel, dtype=float), np.asarray(prevu, dtype=float)
    ecart = prevu - reel
    sortie = {"MAE": float(np.abs(ecart).mean()),
              "WAPE": float(np.abs(ecart).sum() / np.abs(reel).sum()),          # erreur absolue / volume réel
              "biais": float(prevu.sum() / reel.sum() - 1)}                      # > 0 : surestime
    sortie["MAPE"] = float((np.abs(ecart) / reel).mean()) if (reel > 0).all() else float("nan")
    return sortie


def metriques_classification(y, proba, seuil: float = 0.5, part_ciblee: float = 0.2) -> dict:
    """AUC, précision moyenne, et au seuil choisi : précision, rappel, F1 ; plus le « gain » du top 20 %.

    - AUC : probabilité qu'un cas positif ait un score plus haut qu'un négatif (0,5 = hasard, 1 = parfait) ;
    - précision : parmi les cas annoncés positifs, part de vrais positifs ; rappel : part des positifs retrouvés ;
    - capture_top : part des positifs trouvés en ciblant les `part_ciblee` x 100 % de scores les plus hauts ;
    - taux_positifs_top : taux de positifs parmi ces clients ciblés (à comparer au taux moyen).
    """
    import numpy as np
    from sklearn.metrics import average_precision_score, f1_score, precision_score, recall_score, roc_auc_score
    y, proba = np.asarray(y), np.asarray(proba)
    pred = (proba >= seuil).astype(int)
    n_top = int(len(y) * part_ciblee)
    top = np.argsort(-proba)[:n_top]
    return {"AUC": float(roc_auc_score(y, proba)), "precision_moyenne": float(average_precision_score(y, proba)),
            "precision": float(precision_score(y, pred, zero_division=0)), "rappel": float(recall_score(y, pred)),
            "F1": float(f1_score(y, pred)), "seuil": float(seuil), "taux_reel": float(y.mean()), "taux_prevu": float(proba.mean()),
            f"capture_top_{int(part_ciblee * 100)}": float(y[top].sum() / y.sum()),     # part des positifs trouvés
            f"taux_positifs_top_{int(part_ciblee * 100)}": float(y[top].mean())}         # précision du ciblage


def meilleur_seuil(y, proba) -> float:
    """Seuil qui maximise le F1 (à choisir sur la validation, jamais sur le test)."""
    import numpy as np
    from sklearn.metrics import f1_score
    seuils = np.linspace(0.05, 0.95, 91)
    return float(seuils[int(np.argmax([f1_score(y, (proba >= s).astype(int)) for s in seuils]))])
