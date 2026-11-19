# -*- coding: utf-8 -*-
"""
features.py — tables de variables (features) communes au data mining et au machine learning
============================================================================================

Une « table de variables » = une ligne par individu étudié, une colonne par variable, et
éventuellement une colonne cible. Les 4 tables enregistrées dans 05_Data/features :

    table_clients()       clients.parquet       1 ligne = 1 client actif à une fin de trimestre
                                                -> RFM, clustering, ML churn
    table_commandes()     commandes.parquet     1 ligne = 1 commande (avec la liste de ses articles)
                                                -> règles d'association, comportement d'achat
    table_produits_mois() produits_mois.parquet 1 ligne = 1 produit x 1 mois (ventes, stock, rupture)
                                                -> ML prévision des ventes (agrégée par catégorie)
                                                   et ML prédiction de la demande (par produit)
    table_expeditions()   expeditions.parquet   1 ligne = 1 expédition livrée
                                                -> ML retard de livraison

LA règle pour chaque variable : elle doit être CONNUE au moment où l'on ferait la prédiction.
Sinon c'est une « fuite de données » : le modèle paraît excellent en test et échoue en réalité.
Les colonnes volontairement écartées sont listées dans FUITES_*.

Toutes les tables sont construites à partir des vues bi du DWH (via chargement.charger_donnees),
avec les règles de gestion du dictionnaire des KPI (tunishop_kpi.preparer).
"""
from __future__ import annotations

import os

import numpy as np
import pandas as pd

from . import temporal_split as coupures
from .config import DOSSIER_FEATURES

STATUT_ECHEC_PAIEMENT = "paiement_echoue"   # une commande en échec de paiement n'est pas un achat


# =====================================================================================
# Outils
# =====================================================================================
def _date(sk: pd.Series) -> pd.Series:
    """Clé de date AAAAMMJJ (entier) -> date pandas. Les membres techniques -1 / -2 -> NaT."""
    return pd.to_datetime(sk.where(sk > 0).astype("Int64").astype(str), format="%Y%m%d", errors="coerce")


def commandes_achats(p: dict) -> pd.DataFrame:
    """Commandes qui sont de vrais achats : hors échec de paiement et hors client inconnu (-1).

    On ajoute quelques indicateurs 0/1 par commande, utiles pour décrire les habitudes du client.
    """
    c = p["cmd"]
    c = c[(c["statut_commande"] != STATUT_ECHEC_PAIEMENT) & (c["client_sk"] > 0)].copy()
    c["est_mobile"] = (c["canal"] == "application_mobile").astype(int)
    c["est_paiement_livraison"] = (c["mode_paiement"] == "paiement_a_la_livraison").astype(int)
    c["a_coupon"] = (c["coupon_sk"] > 0).astype(int)
    c["est_annulee"] = (c["statut_commande"] == "annulee").astype(int)
    c["est_aboutie_int"] = c["est_aboutie"].astype(int)
    return c


# =====================================================================================
# Table clients — RFM, clustering, ML churn
# =====================================================================================
# Colonnes du DWH à NE PAS utiliser comme variables du churn
FUITES_CHURN = {
    "segment_fidelite": "attribut calculé par le métier sur tout l'historique, y compris après la date d'observation",
    "date_fin_validite / est_courant": "décrivent l'état final du client, inconnu à la date d'observation",
}


def features_clients(p: dict, date_obs: pd.Timestamp,
                     horizon_j: int = coupures.HORIZON_CHURN_J,
                     fenetre_j: int = coupures.FENETRE_ACTIVITE_J) -> pd.DataFrame:
    """Photo des clients actifs à la date d'observation + cible churn.

    Étapes :
      1. on ne garde que le PASSÉ (commandes jusqu'à date_obs incluse) pour les variables ;
      2. un client est actif s'il a commandé dans les `fenetre_j` derniers jours ;
      3. on calcule ses variables (récence, fréquence, montant, habitudes, expérience vécue) ;
      4. on regarde l'AVENIR (date_obs, date_obs + horizon] uniquement pour la cible.
    """
    c = commandes_achats(p)
    passe = c[c["date"] <= date_obs]
    avenir = c[(c["date"] > date_obs) & (c["date"] <= date_obs + pd.Timedelta(days=horizon_j))]

    # --- 2. Clients actifs
    derniere = passe.groupby("client_sk")["date"].max()
    actifs = derniere[derniere >= date_obs - pd.Timedelta(days=fenetre_j)].index
    passe = passe[passe["client_sk"].isin(actifs)]
    g = passe.groupby("client_sk")

    # --- 3a. RFM et habitudes d'achat
    f = pd.DataFrame({
        "recence_j": (date_obs - g["date"].max()).dt.days,                 # jours depuis la dernière commande
        "anciennete_j": (date_obs - g["date"].min()).dt.days,              # jours depuis la première commande
        "frequence": g.size(),                                              # nombre de commandes
        "montant_reconnu_ttc": g.apply(lambda x: x.loc[x["est_aboutie"], "montant_total_ttc"].sum(),
                                       include_groups=False),               # CA reconnu cumulé
        "panier_moyen_ttc": g["montant_total_ttc"].mean(),
        "nb_articles_moyen": g["nb_articles"].mean(),
        "part_mobile": g["est_mobile"].mean(),                              # part des commandes sur l'appli
        "part_paiement_livraison": g["est_paiement_livraison"].mean(),
        "part_coupon": g["a_coupon"].mean(),
        "taux_annulation": g["est_annulee"].mean(),
        "taux_aboutie": g["est_aboutie_int"].mean(),
    })
    recentes = passe[passe["date"] > date_obs - pd.Timedelta(days=90)]
    f["nb_commandes_90j"] = recentes.groupby("client_sk").size().reindex(f.index, fill_value=0)

    # --- 3b. Diversité des achats (nombre de catégories différentes)
    lig = p["lig"]
    lig_passe = lig[lig["commande_id"].isin(passe["commande_id"])]
    nb_cat = lig_passe.merge(passe[["commande_id", "client_sk"]], on="commande_id", suffixes=("_l", ""))
    f["nb_categories"] = nb_cat.groupby("client_sk")["categorie"].nunique().reindex(f.index, fill_value=0)

    # --- 3c. Expérience vécue : livraisons, retours, avis (seulement ce qui est connu à date_obs)
    liv = p["liv"]
    liv = liv[liv["est_livree"] & liv["client_sk"].isin(actifs)].copy()
    liv["date_liv"] = _date(liv["date_livraison_sk"])
    liv = liv[liv["date_liv"] <= date_obs]
    gl = liv.groupby("client_sk")
    f["nb_livraisons"] = gl.size().reindex(f.index, fill_value=0)
    f["part_livraisons_retard"] = gl["retard_j"].apply(lambda r: (r.fillna(0) > 0).mean()).reindex(f.index)
    f["retard_max_j"] = gl["retard_j"].max().reindex(f.index)

    rmb = p["rmb"]
    rmb = rmb[_date(rmb["date_demande_sk"]) <= date_obs]
    f["nb_demandes_remboursement"] = rmb.groupby("client_sk").size().reindex(f.index, fill_value=0)

    avis = p["avis"]
    avis = avis[_date(avis["date_avis_sk"]) <= date_obs]
    f["note_moyenne"] = avis.groupby("client_sk")["note"].mean().reindex(f.index)
    f["nb_avis"] = avis.groupby("client_sk").size().reindex(f.index, fill_value=0)

    # --- 3d. Profil (attributs stables du client ; segment_fidelite volontairement exclu)
    cli = p["cli"].set_index("client_sk")
    for col in ["region", "type_client", "tranche_age", "genre", "canal_inscription"]:
        f[col] = cli[col].reindex(f.index)

    # --- 4. Cible : 1 = aucune commande dans les `horizon_j` jours qui suivent
    revenus = set(avenir["client_sk"])
    f["churn"] = (~f.index.isin(revenus)).astype(int)

    f.insert(0, "date_observation", date_obs)
    return f.reset_index()


def table_clients(p: dict) -> pd.DataFrame:
    """Empile les photos de toutes les dates d'observation (apprentissage puis test).

    Un même client apparaît à plusieurs dates : c'est voulu, chaque photo est une situation
    différente (récence, fréquence… ont changé). La colonne `periode` dit à quel jeu elle appartient.
    """
    morceaux = []
    for jeu, dates in (("apprentissage", coupures.DATES_OBS_APPRENTISSAGE), ("test", coupures.DATES_OBS_TEST)):
        for d in dates:
            t = features_clients(p, d)
            t["periode"] = jeu
            morceaux.append(t)
    return pd.concat(morceaux, ignore_index=True)


# =====================================================================================
# Table expeditions — ML retard de livraison
# =====================================================================================
# Colonnes connues seulement APRÈS l'expédition : interdites comme variables
FUITES_RETARD = {
    "date_livraison_sk / delai_livraison_j / retard_j": "c'est la réponse elle-même",
    "est_livree_a_temps / statut_livraison": "issue de la livraison",
    "nb_tentatives / est_premiere_tentative": "connues pendant la livraison",
    "cout_transport_ht": "facturé après coup (peut dépendre des tentatives)",
}


def table_expeditions(p: dict, vues: dict, en_cours: bool = False) -> pd.DataFrame:
    """1 ligne = 1 expédition LIVRÉE (on ne connaît le retard que si le colis est arrivé).

    en_cours=True : expéditions PARTIES mais pas encore livrées (statut « en_transit ») ; la cible
    en_retard est alors inconnue (vide). Sert au calcul des scores du jour (08_Scoring_Actuel).

    Cible : en_retard = 1 si la livraison est arrivée après la date prévue (retard_j > 0),
    même définition que la mesure « Nb Livrees En Retard » du cube.
    Variables : uniquement ce qui est connu le jour de l'expédition.
    """
    liv = p["liv"]
    if en_cours:
        t = liv[~liv["est_livree"] & (liv["date_expedition_sk"] > 0) & (liv["statut_livraison"] == "en_transit")].copy()
    else:
        t = liv[liv["est_livree"] & (liv["date_expedition_sk"] > 0)].copy()
    t["date_expedition"] = _date(t["date_expedition_sk"])
    t["en_retard"] = np.nan if en_cours else (t["retard_j"].fillna(0) > 0).astype(int)

    # Calendrier du jour d'expédition
    cal = vues["dim_date"][["date_sk", "jour_semaine", "mois", "est_weekend", "est_ramadan", "periode_commerciale"]]
    t = t.merge(cal, left_on="date_expedition_sk", right_on="date_sk", how="left").drop(columns="date_sk")
    for c in ["est_weekend", "est_ramadan"]:
        t[c] = t[c].fillna(False).astype(int)

    # Destination et entrepôt de départ
    geo = vues["dim_geographie"][["geographie_sk", "zone_livraison"]]
    ent = vues["dim_entrepot"][["entrepot_sk", "nom_entrepot"]].rename(columns={"nom_entrepot": "entrepot"})
    t = t.merge(geo, on="geographie_sk", how="left").merge(ent, on="entrepot_sk", how="left")

    # Caractéristiques de la commande (connues avant l'expédition)
    cmd = p["cmd"][["commande_id", "montant_total_ttc", "nb_articles", "mode_paiement", "canal"]]
    t = t.merge(cmd, on="commande_id", how="left")

    t["periode"] = coupures.periode(t["date_expedition"]).astype(str)
    colonnes = ["livraison_id", "commande_id", "date_expedition", "periode", "semestre",
                "transporteur", "region", "zone_livraison", "entrepot",
                "poids_kg", "delai_preparation_h", "montant_total_ttc", "nb_articles", "mode_paiement", "canal",
                "jour_semaine", "mois", "est_weekend", "est_ramadan", "periode_commerciale",
                "en_retard"]
    return t[colonnes]


# =====================================================================================
# Table produits_mois — ML prévision des ventes et prédiction de la demande
# =====================================================================================
def table_produits_mois(p: dict, vues: dict) -> pd.DataFrame:
    """1 ligne = 1 produit x 1 mois, du premier mois de vente du produit à décembre 2025.

    Les mois sans vente sont présents avec 0 (une demande nulle est une information) ;
    `en_rupture` et `stock_fin_mois` viennent de la photo de stock de fin de mois.
    Le CA est rattaché au mois de la COMMANDE (comme le cube), pour les lignes abouties.
    """
    lig = p["lig"]
    lig = lig[lig["est_aboutie"] & (lig["produit_sk"] > 0) & (lig["date_commande_sk"] > 0)].copy()
    lig["mois"] = _date(lig["date_commande_sk"]).dt.to_period("M").dt.to_timestamp()
    ventes = (lig.groupby(["produit_id", "mois"])
              .agg(quantite=("quantite", "sum"), ca_ttc=("montant_ttc", "sum"), ca_ht=("montant_ht", "sum"),
                   marge_ht=("marge_brute_ht", "sum"), nb_commandes=("commande_id", "nunique"))
              .reset_index())

    # Grille complète : chaque produit, de son 1er mois de vente à la fin des données
    mois = pd.date_range(coupures.DEBUT_DONNEES, coupures.FIN_DONNEES, freq="MS")
    premier = ventes.groupby("produit_id")["mois"].min()
    grille = pd.DataFrame([(pid, m) for pid, debut in premier.items() for m in mois if m >= debut],
                          columns=["produit_id", "mois"])
    t = grille.merge(ventes, on=["produit_id", "mois"], how="left")
    for c in ["quantite", "ca_ttc", "ca_ht", "marge_ht", "nb_commandes"]:
        t[c] = t[c].fillna(0)

    # Attributs du produit (version courante)
    prod = vues["dim_produit"]
    prod = prod[prod["produit_sk"] > 0].sort_values("produit_sk").drop_duplicates("produit_id", keep="last")
    t = t.merge(prod[["produit_id", "nom_produit", "categorie", "sous_categorie", "gamme_prix", "marque",
                      "prix_catalogue_ttc"]], on="produit_id", how="left")

    # Stock de fin de mois (tous entrepôts) et rupture
    stk = p["stk"].merge(vues["dim_produit"][["produit_sk", "produit_id"]], on="produit_sk", how="left")
    stk["mois"] = _date(stk["date_sk"]).dt.to_period("M").dt.to_timestamp()
    s = stk.groupby(["produit_id", "mois"]).agg(stock_fin_mois=("stock_fin_mois", "sum"),
                                                en_rupture=("est_rupture", "max")).reset_index()
    t = t.merge(s, on=["produit_id", "mois"], how="left")
    t["en_rupture"] = t["en_rupture"].fillna(False).astype(int)

    # Calendrier du mois : connu à l'avance (v_dim_date), donc utilisable pour prévoir
    t = t.merge(calendrier_mensuel(vues), on="mois", how="left")
    t["periode"] = coupures.periode(t["mois"]).astype(str)
    return t.sort_values(["produit_id", "mois"]).reset_index(drop=True)


PERIODES_COMMERCIALES = ["soldes_hiver", "ramadan", "pre_aid_fitr", "pre_aid_idha", "soldes_ete",
                         "rentree_scolaire", "black_friday", "fin_annee"]


def calendrier_mensuel(vues: dict) -> pd.DataFrame:
    """1 ligne par mois : part des jours du mois dans chaque période commerciale de v_dim_date
    (Ramadan, pré-Aïd, Black Friday, soldes...) et indicateur a_black_friday.

    Ces dates sont connues à l'avance (calendrier lunaire publié), on peut donc les utiliser pour
    prévoir : c'est ce qui permet au modèle de suivre le Ramadan, qui avance d'environ 11 jours par an.
    """
    cal = vues["dim_date"][vues["dim_date"]["date_sk"] > 0].copy()
    cal["mois"] = _date(cal["date_sk"]).dt.to_period("M").dt.to_timestamp()
    parts = pd.crosstab(cal["mois"], cal["periode_commerciale"], normalize="index")
    parts = parts.reindex(columns=PERIODES_COMMERCIALES, fill_value=0.0).add_prefix("part_jours_")
    parts["a_black_friday"] = (parts["part_jours_black_friday"] > 0).astype(int)
    return parts.reset_index()


def ventes_categorie_mois(produits_mois: pd.DataFrame) -> pd.DataFrame:
    """Agrège produits_mois par catégorie x mois (+ une catégorie « Total ») : série du ML de prévision des ventes."""
    agr = {"ca_ttc": "sum", "quantite": "sum", "nb_commandes": "sum"}
    par_cat = produits_mois.groupby(["mois", "categorie"]).agg(agr).reset_index()
    total = produits_mois.groupby("mois").agg(agr).reset_index().assign(categorie="Total")
    s = pd.concat([par_cat, total], ignore_index=True).sort_values(["categorie", "mois"])
    s["periode"] = coupures.periode(s["mois"]).astype(str)
    return s.reset_index(drop=True)


# =====================================================================================
# Table commandes — règles d'association, comportement d'achat
# =====================================================================================
def table_commandes(p: dict) -> pd.DataFrame:
    """1 ligne = 1 commande passée (toutes les commandes, avec leur statut).

    Les listes `categories`, `sous_categories` et `produits` décrivent le contenu du panier
    (utilisées pour les règles d'association). Filtrer `est_aboutie == 1` pour les achats reconnus.
    """
    c = p["cmd"].copy()
    c["date_commande"] = _date(c["date_commande_sk"])
    lig = p["lig"][p["lig"]["produit_sk"] > 0]               # hors produit inconnu (-1)
    contenu = lig.groupby("commande_id").agg(
        categories=("categorie", lambda x: sorted(set(x.dropna()) - {"Inconnu"})),
        sous_categories=("sous_categorie", lambda x: sorted(set(x.dropna()) - {"Inconnu"})),
        produits=("produit_id", lambda x: sorted(set(x))),
        remise_promo_ttc=("montant_remise_promo_ttc", "sum"),
        marge_brute_ht=("marge_brute_ht", "sum"))
    c = c.merge(contenu, on="commande_id", how="left")
    for col in ["categories", "sous_categories", "produits"]:
        c[col] = c[col].apply(lambda x: x if isinstance(x, list) else [])
    c["nb_categories"] = c["categories"].apply(len)
    c["nb_produits_distincts"] = c["produits"].apply(len)
    c["a_coupon"] = (c["coupon_sk"] > 0).astype(int)
    c["a_campagne"] = (c["campagne_sk"] > 0).astype(int)
    c["est_aboutie"] = c["est_aboutie"].astype(int)
    c["est_premiere_commande"] = c["est_premiere_commande"].astype(int)
    c["periode"] = coupures.periode(c["date_commande"].fillna(coupures.DEBUT_DONNEES)).astype(str)
    colonnes = ["commande_id", "client_sk", "client_id", "date_commande", "annee", "periode", "statut_commande",
                "famille_statut", "est_aboutie", "canal", "appareil", "mode_paiement", "region", "gouvernorat",
                "type_client", "est_premiere_commande", "a_coupon", "a_campagne", "nb_lignes", "nb_articles",
                "sous_total_ttc", "remise_coupon_ttc", "remise_promo_ttc", "frais_livraison_ttc", "montant_total_ttc",
                "marge_brute_ht", "nb_tentatives_paiement", "delai_livraison_j", "nb_categories",
                "nb_produits_distincts", "categories", "sous_categories", "produits"]
    return c[colonnes]


def paniers_longs(commandes: pd.DataFrame, niveau: str = "sous_categories") -> pd.DataFrame:
    """Passe la liste des articles de chaque commande en format long : 1 ligne = 1 article d'une commande."""
    t = commandes[["commande_id", "periode", niveau]].explode(niveau).dropna(subset=[niveau])
    return t.rename(columns={niveau: "article"}).reset_index(drop=True)


# =====================================================================================
# Data mining — segmentation RFM (02_Data_Mining/01_Segmentation_RFM) -> variable « segment_rfm » du churn
# =====================================================================================
# Récence, Fréquence, Montant notés de 1 (faible valeur) à 5 (forte valeur).
# R et M : quintiles calculés UNIQUEMENT sur l'apprentissage (puis appliqués tels quels au test),
#          sinon le test influencerait les seuils : ce serait une fuite de données.
# F      : bornes fixes, car la fréquence a trop de valeurs égales (30 % des clients ont 1 commande)
#          pour faire des quintiles propres.
BORNES_F = [0, 1, 2, 3, 6, np.inf]          # 1 | 2 | 3 | 4-6 | 7 et plus  -> scores 1 à 5

# Segments : règles sur les scores R et F (le montant sert à décrire la valeur du segment)
ORDRE_SEGMENTS = ["Champions", "Fidèles", "Fidèles potentiels", "Nouveaux", "À surveiller",
                  "À risque", "Hibernants", "Perdus"]


def seuils_rfm(table: pd.DataFrame) -> dict:
    """Calcule les seuils des scores R et M sur la table fournie (l'apprentissage)."""
    return {
        "recence_j": [float(x) for x in table["recence_j"].quantile([0.2, 0.4, 0.6, 0.8])],
        "montant_reconnu_ttc": [float(x) for x in table["montant_reconnu_ttc"].quantile([0.2, 0.4, 0.6, 0.8])],
        "frequence": [float(x) for x in BORNES_F[1:-1]],
    }


def _segment(r: int, f: int) -> str:
    if r >= 4 and f >= 4:
        return "Champions"
    if r == 3 and f >= 4:
        return "Fidèles"
    if r >= 4 and f in (2, 3):
        return "Fidèles potentiels"
    if r >= 4 and f == 1:
        return "Nouveaux"
    if r == 3:
        return "À surveiller"
    if f >= 4:
        return "À risque"
    if f in (2, 3):
        return "Hibernants"
    return "Perdus"


def scores_rfm(table: pd.DataFrame, seuils: dict) -> pd.DataFrame:
    """Ajoute score_r, score_f, score_m (1 à 5), code_rfm (ex. « 545 ») et segment_rfm.

    Récence : plus elle est PETITE, meilleur est le score (5 = a commandé très récemment).
    """
    t = table.copy()
    bornes_r = [-np.inf] + seuils["recence_j"] + [np.inf]
    bornes_m = [-np.inf] + seuils["montant_reconnu_ttc"] + [np.inf]
    t["score_r"] = 6 - pd.cut(t["recence_j"], bornes_r, labels=False, right=True).astype(int) - 1
    t["score_f"] = pd.cut(t["frequence"], BORNES_F, labels=False, right=True).astype(int) + 1
    t["score_m"] = pd.cut(t["montant_reconnu_ttc"], bornes_m, labels=False, right=True).astype(int) + 1
    t["code_rfm"] = t["score_r"].astype(str) + t["score_f"].astype(str) + t["score_m"].astype(str)
    t["segment_rfm"] = pd.Categorical([_segment(r, f) for r, f in zip(t["score_r"], t["score_f"])],
                                      categories=ORDRE_SEGMENTS, ordered=True)
    return t


def ajouter_segment_rfm(churn: pd.DataFrame, dossier=DOSSIER_FEATURES) -> pd.DataFrame:
    """Ajoute à la table clients les scores et le segment RFM produits par 01_Segmentation_RFM.

    Utilisation dans la phase ML :  clients = features.ajouter_segment_rfm(features.lire("clients"))
    """
    seg = lire("segments_rfm", dossier)[["client_sk", "date_observation", "score_r", "score_f", "score_m", "segment_rfm"]]
    return churn.merge(seg, on=["client_sk", "date_observation"], how="left")


# =====================================================================================
# Data mining — règles d'association (02_Data_Mining/03_Association_Produits) -> recommandation
# =====================================================================================
VARIABLES_CLUSTERING = ["log_recence", "log_frequence", "log_montant", "log_panier", "part_mobile", "part_coupon",
                        "nb_categories", "part_retard"]


def variables_clustering(t: pd.DataFrame) -> pd.DataFrame:
    """Les 8 variables du k-means (02_Clustering_Clients) à partir d'une photo de la table clients.

    Dans le module (et non plus seulement dans le notebook) pour que le scoring du jour
    (08_Scoring_Actuel) affecte les clients aux groupes exactement comme l'apprentissage.
    """
    return pd.DataFrame({
        "log_recence": np.log1p(t["recence_j"]), "log_frequence": np.log1p(t["frequence"]),
        "log_montant": np.log1p(t["montant_reconnu_ttc"]), "log_panier": np.log1p(t["panier_moyen_ttc"]),
        "part_mobile": t["part_mobile"], "part_coupon": t["part_coupon"], "nb_categories": t["nb_categories"],
        "part_retard": t["part_livraisons_retard"].fillna(0)}, index=t.index)


def matrice_paniers(commandes: pd.DataFrame, niveau: str = "sous_categories") -> pd.DataFrame:
    """1 ligne = 1 commande, 1 colonne = 1 article (catégorie, sous-catégorie ou produit),
    valeur VRAI si la commande en contient au moins un. Format attendu par mlxtend."""
    t = paniers_longs(commandes, niveau)
    return pd.crosstab(t["commande_id"], t["article"]).gt(0)


def recommander(panier: list, regles: pd.DataFrame, populaires: list, n: int = 3) -> pd.DataFrame:
    """Propose n articles à ajouter à un panier.

    1. On prend les règles « stables » dont TOUS les antécédents sont dans le panier,
       triées par lift puis confiance ;
    2. si elles ne suffisent pas, on complète avec les articles les plus populaires
       (absents du panier). C'est le comportement attendu quand les règles sont faibles.
    """
    panier = set(panier)
    propositions = []
    if len(regles):
        ok = regles[regles["stable"] & regles["antecedents"].apply(lambda a: set(a.split(" + ")) <= panier)]
        for r in ok.sort_values(["lift", "confidence"], ascending=False).itertuples():
            for article in r.consequents.split(" + "):
                if article not in panier and article not in [x[0] for x in propositions]:
                    propositions.append((article, "règle", round(r.lift, 2), round(r.confidence, 3)))
    for article in populaires:
        if len(propositions) >= n:
            break
        if article not in panier and article not in [x[0] for x in propositions]:
            propositions.append((article, "popularité", None, None))
    return pd.DataFrame(propositions[:n], columns=["article", "source", "lift", "confiance"])


# =====================================================================================
# Sauvegarde et dictionnaire des variables
# =====================================================================================
def sauvegarder(df: pd.DataFrame, nom: str, dossier=DOSSIER_FEATURES) -> str:
    """Enregistre une table en Parquet (types conservés) ; en CSV si pyarrow n'est pas installé."""
    os.makedirs(dossier, exist_ok=True)
    try:
        chemin = os.path.join(dossier, f"{nom}.parquet")
        provisoire = chemin + ".tmp"                                 # écriture complète puis remplacement :
        df.to_parquet(provisoire, index=False)                       # jamais de fichier à moitié écrit
        os.replace(provisoire, chemin)
    except ImportError:
        chemin = os.path.join(dossier, f"{nom}.csv")
        df.to_csv(chemin, index=False, encoding="utf-8-sig")
    print(f"  {nom:<22} {len(df):>8,} lignes x {df.shape[1]:>2} colonnes -> {os.path.basename(chemin)}".replace(",", " "))
    # Résultats du data mining (segments, groupes) : copiés aussi dans la base TuniShop_ANALYTICS
    from . import publication
    if nom in publication.TABLES_PARQUET:
        publication.publier(df, nom, index=False, source=f"05_Data/features/{nom}.parquet")
    return chemin


def lire(nom: str, dossier=DOSSIER_FEATURES) -> pd.DataFrame:
    """Relit une table enregistrée par sauvegarder() (utilisé par les notebooks suivants)."""
    pq, csv = os.path.join(dossier, f"{nom}.parquet"), os.path.join(dossier, f"{nom}.csv")
    if not os.path.exists(pq) and not os.path.exists(csv):
        raise FileNotFoundError(f"Table introuvable : {pq}\n"
                                "Exécute d'abord 01_EDA/01_EDA_Global (ou mets RECONSTRUIRE = True dans ce notebook).")
    if not os.path.exists(pq):
        return pd.read_csv(csv, encoding="utf-8-sig")
    try:
        return pd.read_parquet(pq)
    except Exception as erreur:                                     # fichier abîmé ou écrit par une autre version
        with open(pq, "rb") as f:
            debut = f.read(4)
        raise OSError(
            f"Impossible de lire {pq} ({os.path.getsize(pq)} octets, début du fichier : {debut!r} ; "
            "un fichier Parquet valide commence par b'PAR1').\n"
            "Solution : reconstruis la table depuis le DWH (RECONSTRUIRE = True dans ce notebook, "
            "ou exécute à nouveau 01_EDA/01_EDA_Global), ce qui la réécrit avec ta propre version de pyarrow.\n"
            f"Erreur d'origine : {type(erreur).__name__} : {erreur}") from None




# =====================================================================================
# Dictionnaire des variables et lignage (05_Data/metadata)
# =====================================================================================
_V_CMD = "v_fact_commandes"
_ACHATS = "commandes hors échec de paiement et hors client inconnu, jusqu'à la date d'observation"
# table -> liste de (variable, description, vues bi sources, règle de calcul, connue à)
DICTIONNAIRE = {
    "clients": [
        ("client_sk", "Clé du client dans le DWH", "v_dim_client", "clé de la version du client", "toujours"),
        ("date_observation", "Fin de trimestre à laquelle le client est photographié", "—", "dates de temporal_split", "—"),
        ("recence_j", "Jours depuis la dernière commande", _V_CMD, "date_observation - date de la dernière commande (" + _ACHATS + ")", "date d'observation"),
        ("anciennete_j", "Jours depuis la première commande", _V_CMD, "date_observation - date de la première commande", "date d'observation"),
        ("frequence", "Nombre de commandes passées", _V_CMD, "nombre de commandes (" + _ACHATS + ")", "date d'observation"),
        ("montant_reconnu_ttc", "CA reconnu TTC cumulé du client", _V_CMD + ", v_dim_statut_commande", "somme de montant_total_ttc des commandes abouties", "date d'observation"),
        ("panier_moyen_ttc", "Montant moyen d'une commande", _V_CMD, "moyenne de montant_total_ttc", "date d'observation"),
        ("nb_articles_moyen", "Nombre moyen d'articles par commande", _V_CMD, "moyenne de nb_articles", "date d'observation"),
        ("part_mobile", "Part des commandes passées sur l'application mobile", _V_CMD + ", v_dim_canal", "commandes canal = application_mobile / commandes", "date d'observation"),
        ("part_paiement_livraison", "Part des commandes payées à la livraison", _V_CMD + ", v_dim_mode_paiement", "commandes paiement_a_la_livraison / commandes", "date d'observation"),
        ("part_coupon", "Part des commandes avec coupon", _V_CMD, "commandes coupon_sk > 0 / commandes", "date d'observation"),
        ("taux_annulation", "Part des commandes annulées", _V_CMD + ", v_dim_statut_commande", "commandes statut annulee / commandes", "date d'observation"),
        ("taux_aboutie", "Part des commandes abouties", _V_CMD + ", v_dim_statut_commande", "commandes famille aboutie / commandes", "date d'observation"),
        ("nb_commandes_90j", "Commandes des 90 derniers jours", _V_CMD, "commandes entre date_observation - 90 j et date_observation", "date d'observation"),
        ("nb_categories", "Nombre de catégories différentes achetées", "v_fact_ventes, v_dim_produit", "nombre de catégories distinctes des lignes", "date d'observation"),
        ("nb_livraisons", "Livraisons reçues", "v_fact_livraisons", "livraisons livrées avant la date d'observation", "date d'observation"),
        ("part_livraisons_retard", "Part des livraisons reçues en retard", "v_fact_livraisons", "livraisons retard_j > 0 / livraisons reçues", "date d'observation"),
        ("retard_max_j", "Pire retard subi (jours)", "v_fact_livraisons", "maximum de retard_j", "date d'observation"),
        ("nb_demandes_remboursement", "Demandes de remboursement ou de retour", "v_fact_remboursements", "demandes datées avant la date d'observation", "date d'observation"),
        ("note_moyenne", "Note moyenne donnée dans les avis (vide si aucun avis)", "v_fact_avis", "moyenne de note", "date d'observation"),
        ("nb_avis", "Nombre d'avis déposés", "v_fact_avis", "nombre d'avis", "date d'observation"),
        ("region", "Région du client", "v_dim_client", "attribut de la version courante", "toujours"),
        ("type_client", "Particulier ou professionnel", "v_dim_client", "attribut de la version courante", "toujours"),
        ("tranche_age", "Tranche d'âge (vide pour les professionnels)", "v_dim_client", "attribut de la version courante", "toujours"),
        ("genre", "Genre", "v_dim_client", "attribut de la version courante", "toujours"),
        ("canal_inscription", "Canal par lequel le client s'est inscrit", "v_dim_client", "attribut de la version courante", "toujours"),
        ("churn", "CIBLE du churn : 1 si aucune commande dans les 90 jours suivants", _V_CMD, "aucune commande (hors échec de paiement) dans ]date_observation ; date_observation + 90 j]", "90 jours après"),
        ("periode", "apprentissage (2023-2024) ou test (2025)", "—", "temporal_split.periode(date_observation)", "—"),
    ],
    "commandes": [
        ("commande_id", "Identifiant de la commande", _V_CMD, "clé métier", "commande"),
        ("client_sk / client_id", "Client (clé et identifiant métier)", _V_CMD + ", v_dim_client", "jointure sur client_sk", "commande"),
        ("date_commande / annee / periode", "Date, année et période de la commande", _V_CMD + ", v_dim_date", "date_commande_sk -> date", "commande"),
        ("statut_commande / famille_statut / est_aboutie", "Statut final de la commande ; 1 si aboutie (CA reconnu)", _V_CMD + ", v_dim_statut_commande", "famille_statut = aboutie", "après livraison"),
        ("canal / appareil", "Canal de vente et appareil", _V_CMD + ", v_dim_canal", "jointure sur canal_sk", "commande"),
        ("mode_paiement", "Mode de paiement choisi", _V_CMD + ", v_dim_mode_paiement", "jointure sur mode_paiement_sk", "commande"),
        ("region / gouvernorat", "Lieu de livraison", _V_CMD + ", v_dim_geographie", "jointure sur geographie_sk", "commande"),
        ("type_client", "Particulier ou professionnel", "v_dim_client", "jointure sur client_sk", "commande"),
        ("est_premiere_commande", "1 si première commande du client", _V_CMD, "colonne du DWH", "commande"),
        ("a_coupon / a_campagne", "1 si coupon utilisé / commande attribuée à une campagne", _V_CMD, "coupon_sk > 0 / campagne_sk > 0", "commande"),
        ("nb_lignes / nb_articles", "Lignes et articles de la commande", _V_CMD, "colonnes du DWH", "commande"),
        ("sous_total_ttc / remise_coupon_ttc / frais_livraison_ttc / montant_total_ttc", "Montants de la commande", _V_CMD, "colonnes du DWH", "commande"),
        ("remise_promo_ttc / marge_brute_ht", "Remises promotionnelles et marge brute des lignes", "v_fact_ventes", "somme sur les lignes de la commande", "commande"),
        ("nb_tentatives_paiement", "Tentatives de paiement", _V_CMD, "colonne du DWH", "paiement"),
        ("delai_livraison_j", "Délai de livraison (vide si non livrée)", _V_CMD, "colonne du DWH", "après livraison"),
        ("nb_categories / nb_produits_distincts", "Diversité du panier", "v_fact_ventes, v_dim_produit", "nombre de valeurs distinctes", "commande"),
        ("categories / sous_categories / produits", "Listes des articles du panier (hors inconnu)", "v_fact_ventes, v_dim_produit", "liste triée des valeurs distinctes", "commande"),
    ],
    "produits_mois": [
        ("produit_id / mois", "Produit et mois (de son 1er mois de vente à 12/2025)", "v_fact_ventes, v_dim_produit, v_dim_date", "grille complète produit x mois", "—"),
        ("quantite / ca_ttc / ca_ht / marge_ht / nb_commandes", "Ventes abouties du mois (0 si aucune vente)", "v_fact_ventes, v_dim_statut_commande", "somme des lignes abouties par mois de commande", "fin du mois"),
        ("nom_produit / categorie / sous_categorie / gamme_prix / marque / prix_catalogue_ttc", "Attributs du produit (version courante)", "v_dim_produit", "dernière version du produit", "toujours"),
        ("stock_fin_mois / en_rupture", "Stock de fin de mois (tous entrepôts) ; 1 si rupture dans au moins un entrepôt", "v_fact_stock_mensuel", "somme / maximum par produit et mois", "fin du mois"),
        (" / ".join(f"part_jours_{x}" for x in PERIODES_COMMERCIALES) + " / a_black_friday", "Calendrier du mois : part des jours dans chaque période commerciale", "v_dim_date", "part des jours du mois par periode_commerciale", "connu à l'avance"),
        ("periode", "apprentissage (2023-2024) ou test (2025)", "—", "temporal_split.periode(mois)", "—"),
    ],
    "expeditions": [
        ("livraison_id / commande_id", "Identifiants", "v_fact_livraisons", "clés", "expédition"),
        ("date_expedition / periode / semestre", "Date d'expédition et période", "v_fact_livraisons, v_dim_date", "date_expedition_sk -> date", "expédition"),
        ("transporteur", "Transporteur", "v_fact_livraisons, v_dim_transporteur", "jointure sur transporteur_sk", "expédition"),
        ("region / zone_livraison", "Destination", "v_fact_livraisons, v_dim_geographie", "jointure sur geographie_sk", "expédition"),
        ("entrepot", "Entrepôt de départ", "v_fact_livraisons, v_dim_entrepot", "jointure sur entrepot_sk", "expédition"),
        ("poids_kg / delai_preparation_h", "Poids du colis, temps de préparation", "v_fact_livraisons", "colonnes du DWH", "expédition"),
        ("montant_total_ttc / nb_articles / mode_paiement / canal", "Caractéristiques de la commande", "v_fact_commandes", "jointure sur commande_id", "expédition"),
        ("jour_semaine / mois / est_weekend / est_ramadan / periode_commerciale", "Calendrier du jour d'expédition", "v_dim_date", "jointure sur date_expedition_sk", "expédition"),
        ("en_retard", "CIBLE du retard : 1 si livrée après la date prévue", "v_fact_livraisons", "retard_j > 0 (expéditions livrées)", "après la livraison"),
    ],
}

# Utilisation prévue de chaque table
USAGES = {
    "clients": "02_Data_Mining (RFM, clustering) ; 03_Machine_Learning (churn)",
    "commandes": "02_Data_Mining (association, comportement d'achat)",
    "produits_mois": "03_Machine_Learning (prévision des ventes par catégorie, prédiction de la demande par produit)",
    "expeditions": "03_Machine_Learning (retard de livraison, notebook ajouté 06_Prediction_Retard_Livraison)",
}


def dictionnaire_variables() -> pd.DataFrame:
    """Une ligne par variable (ou groupe de variables) des 4 tables."""
    lignes = [{"table": t, "variable": v, "description": d, "vues_bi_sources": s, "regle_de_calcul": r,
               "connue_a": c, "utilisee_par": USAGES[t]} for t, liste in DICTIONNAIRE.items() for v, d, s, r, c in liste]
    return pd.DataFrame(lignes)


# Chaîne complète des données, des fichiers sources aux livrables (Data_Lineage.xlsx)
CHAINE = [
    ("1", "Sources", "Fichiers CSV / Excel de l'activité TuniShop", "—", "—", "Phase BI"),
    ("2", "Staging", "STG_RAW -> STG_CLEAN -> STG_INTEGRATED", "Python (1-tunishop_pipeline.py)", "audit TuniShop_ADMIN (22 tâches par couche)", "Phase BI"),
    ("3", "Entrepôt", "TuniShop_DWH, tables dw.* (13 dimensions, 10 faits)", "SSIS DWH_01 / DWH_02", "PV de validation du DWH (28/10/2026)", "Phase BI"),
    ("4", "Restitution", "23 vues bi.v_*", "SQL Server (vues)", "PV DWH ; cubes SSAS validés (04/11/2026)", "Phase BI"),
    ("5", "Lecture directe", "vues bi -> DataFrames pandas", "tunishop_analytics.chargement (pyodbc)", "validation : C01 à C11", "01_EDA_Global"),
    ("6", "Préparation", "tables cmd, lig, liv, rmb, avis, pai, mkt, stk, mvt, ach, cli", "tunishop_kpi.preparer (règles du dictionnaire des KPI)", "5 totaux validés (SQL = Python = PV)", "01_EDA_Global"),
    ("7", "Variables", "clients, commandes, produits_mois, expeditions (05_Data/features)", "tunishop_analytics.features", "Dictionnaire_Variables.xlsx", "01_EDA_Global"),
    ("8", "Analyse", "EDA thématique, data mining, machine learning", "notebooks 01_EDA, 02_Data_Mining, 03_Machine_Learning", "verdicts des hypothèses, métriques des modèles", "phases EDA, DM, ML"),
    ("9", "Restitution de l'analyse", "figures, tableaux, modèles, prédictions, rapports", "06_Exports, 04_Livrables", "relecture des livrables", "phases EDA, DM, ML"),
    ("10", "Scores et suivi", "scores du jour (churn, colis en transit), registre et suivi des modèles", "notebooks 08_Scoring_Actuel, 09_Suivi_Modeles ; tunishop_analytics.modeles", "contrôles SQL des scores ; alertes du suivi", "03_Machine_Learning"),
    ("11", "Publication", "tables ana.* de TuniShop_ANALYTICS (copie de chaque résultat) et journal ctl.journal_publication", "tunishop_analytics.publication (pyodbc)", "ctl.usp_controler_publication : L1-L7, N1, P1", "tous les notebooks ; 07_Publication_Resultats"),
    ("12", "Vues Power BI", "vues pbi.* reliant les tables ana aux vues bi du DWH", "00_Commun/sql/03_Vues_pbi_Power_BI.sql", "0 clé orpheline (L1-L7)", "SSMS"),
    ("13", "Tableau de bord", "rapport Power BI TuniShop_Analyse_ML (5 pages)", "07_PowerBI (projet .pbip, mode Importer)", "recette : 33 valeurs, 44 visuels", "Power BI Desktop"),
]

# Table préparée (tunishop_kpi) d'où vient chaque table de variables
PREPAREES = {"clients": "cmd, lig, liv, rmb, avis, cli", "commandes": "cmd, lig",
             "produits_mois": "lig, stk + vues dim_produit, dim_date", "expeditions": "liv, cmd + vues dim_date, dim_geographie, dim_entrepot"}

# Notebooks de l'EDA thématique et leurs questions (Plan_Analyse_EDA)
NOTEBOOKS_EDA = {
    "02_EDA_Sales": ["Q1", "Q2", "Q9"],
    "03_EDA_Customers": ["Q5", "Q6", "Q7", "Q8", "Q15", "Q18"],
    "04_EDA_Products": ["Q3", "Q4", "Q16"],
    "05_EDA_Stock_Logistics": ["Q13", "Q14", "Q19", "Q20", "Q21"],
    "06_EDA_Marketing_Finance": ["Q10", "Q11", "Q12", "Q17"],
}

# Notebooks qui lisent chaque table de variables
CONSOMMATEURS = {
    "clients": ["02_Data_Mining/01_Segmentation_RFM", "02_Data_Mining/02_Clustering_Clients",
                "03_Machine_Learning/01_Preparation_Datasets_ML", "03_Machine_Learning/03_Prediction_Churn"],
    "commandes": ["02_Data_Mining/03_Association_Produits", "02_Data_Mining/04_Analyse_Comportement_Achat"],
    "produits_mois": ["03_Machine_Learning/01_Preparation_Datasets_ML", "03_Machine_Learning/02_Prevision_Ventes",
                      "03_Machine_Learning/04_Prediction_Demande"],
    "expeditions": ["03_Machine_Learning/01_Preparation_Datasets_ML", "03_Machine_Learning/06_Prediction_Retard_Livraison"],
}


# Sorties du data mining réutilisées par le ML (Data_Lineage.xlsx)
SORTIES_DATA_MINING = [
    ("02_Data_Mining/01_Segmentation_RFM", "05_Data/features/segments_rfm.parquet", "scores R, F, M et segment_rfm par client et date d'observation", "03_Prediction_Churn (features.ajouter_segment_rfm)"),
    ("02_Data_Mining/01_Segmentation_RFM", "06_Exports/Modeles/rfm_seuils.json", "seuils des scores appris sur 2023-2024", "toute nouvelle photo de clients"),
    ("02_Data_Mining/02_Clustering_Clients", "05_Data/features/clusters_clients.parquet", "groupe k-means par client et date d'observation", "03_Prediction_Churn"),
    ("02_Data_Mining/02_Clustering_Clients", "06_Exports/Modeles/clustering_kmeans.joblib", "échelle + modèle k-means + noms des groupes", "affectation de nouveaux clients"),
    ("02_Data_Mining/03_Association_Produits", "06_Exports/Modeles/regles_association.parquet", "règles apprises sur 2023-2024 avec leur validation 2025 (colonne stable)", "features.recommander"),
    ("02_Data_Mining/03_Association_Produits", "06_Exports/Modeles/articles_populaires.json", "articles les plus achetés par niveau", "features.recommander"),
    ("02_Data_Mining/04_Analyse_Comportement_Achat", "06_Exports/Tables/DM04_*.csv", "facteurs de rachat à 90 jours, rythme d'achat", "choix des variables du churn"),
]


# Sorties du machine learning (Data_Lineage.xlsx)
SORTIES_ML = [
    ("03_Machine_Learning/01_Preparation_Datasets_ML", "05_Data/features/ml_ventes|ml_churn|ml_demande|ml_retard.parquet", "jeux de données des 4 cas (colonne periode)", "notebooks 02, 03, 04, 06"),
    ("03_Machine_Learning/02_Prevision_Ventes", "06_Exports/Modeles/prevision_ventes_ridge*.joblib ; 06_Exports/Predictions/ventes_2025_test.parquet", "Ridge « calendrier » (retenu)", "05_Evaluation_Modeles, prévision 2026"),
    ("03_Machine_Learning/03_Prediction_Churn", "06_Exports/Modeles/churn_modele.joblib ; 06_Exports/Predictions/churn_2025_test.parquet", "gradient boosting + seuil (retenu)", "05_Evaluation_Modeles, ciblage fidélisation"),
    ("03_Machine_Learning/04_Prediction_Demande", "06_Exports/Modeles/demande_modele.joblib ; 06_Exports/Predictions/demande_2025_test.parquet", "version 2 « catégorie × part produit » retenue (colonne prevision_retenue) ; meilleur gradient boosting enregistré", "05_Evaluation_Modeles, approvisionnement"),
    ("03_Machine_Learning/06_Prediction_Retard_Livraison", "06_Exports/Modeles/retard_modele.joblib ; 06_Exports/Predictions/retard_2025_test.parquet", "régression logistique + seuil (retenue)", "05_Evaluation_Modeles, alertes livraison"),
    ("03_Machine_Learning/05_Evaluation_Modeles", "04_Livrables/Machine_Learning/Comparaison_Modeles.xlsx", "comparaison et robustesse des modèles", "Rapport_Modelisation"),
    ("03_Machine_Learning/08_Scoring_Actuel", "06_Exports/Modeles/churn_production.joblib, retard_production.joblib ; 06_Exports/Modeles/fiches/*.json", "modèles de production (réappris sur 2023-2025) et fiches d'identité", "scores du jour ; ana.ml_registre_modeles"),
    ("03_Machine_Learning/08_Scoring_Actuel", "06_Exports/Predictions/churn_scores_actuels.parquet ; retard_scores_en_cours.parquet", "probabilité de churn des clients actifs, de retard des colis en transit", "marketing, logistique ; pbi.v_ml_scores_churn, pbi.v_ml_scores_retard"),
    ("03_Machine_Learning/09_Suivi_Modeles", "06_Exports/Tables/ML_suivi.csv", "indicateurs par période et alertes", "pbi.v_ml_suivi ; décision de réapprentissage"),
]


def _description_colonne(table: str, colonne: str):
    """Retrouve la ligne du dictionnaire qui décrit une colonne (les variables sont parfois groupées « a / b »)."""
    for v, d, s, r, c in DICTIONNAIRE[table]:
        if colonne in [x.strip() for x in v.split("/")]:
            return d, s, r, c
    return "", "", "", ""


def exporter_metadonnees(tables: dict, dossier) -> None:
    """Écrit Dictionnaire_Variables.xlsx et Data_Lineage.xlsx dans 05_Data/metadata.

    Le dictionnaire décrit CHAQUE colonne réellement présente dans les tables (type, exemple,
    part de vides) : il reste juste même si une variable est ajoutée plus tard.
    """
    from .config import exporter_excel
    from pathlib import Path
    dossier = Path(dossier)

    # --- Dictionnaire
    resume, feuilles = [], {}
    for nom, t in tables.items():
        lignes = []
        for col in t.columns:
            d, s, r, c = _description_colonne(nom, col)
            exemple = t[col].dropna().iloc[0] if t[col].notna().any() else None
            lignes.append({"variable": col, "type": str(t[col].dtype), "exemple": str(exemple)[:60],
                           "part_vide": float(t[col].isna().mean()) if not isinstance(exemple, (list, tuple)) else 0.0,
                           "description": d, "vues_bi_sources": s, "regle_de_calcul": r, "connue_a": c})
        df = pd.DataFrame(lignes)
        feuilles[f"{len(feuilles) + 1:02d}_{nom}"] = (f"Table {nom}.parquet — {len(t):,} lignes x {t.shape[1]} colonnes".replace(",", " "),
                                                     f"Utilisée par : {USAGES[nom]}", df)
        resume.append({"table": nom, "fichier": f"05_Data/features/{nom}.parquet", "lignes": len(t), "colonnes": t.shape[1],
                       "grain": {"clients": "1 client actif x 1 fin de trimestre", "commandes": "1 commande",
                                 "produits_mois": "1 produit x 1 mois", "expeditions": "1 expédition livrée"}[nom],
                       "utilisee_par": USAGES[nom]})
    feuilles = {"00_Tables": ("Dictionnaire des variables — TuniShop", "Tables de variables construites à partir des vues bi du DWH",
                              pd.DataFrame(resume)), **feuilles}
    exporter_excel(feuilles, dossier / "Dictionnaire_Variables.xlsx", "Dictionnaire des variables — TuniShop")

    # --- Lignage
    chaine = pd.DataFrame(CHAINE, columns=["etape", "couche", "objet", "outil", "controle", "ou"])
    vers_tables = pd.DataFrame([{"table_variables": nom, "vues_bi_sources": ", ".join(sorted({v.strip() for _, _, s, _, _ in DICTIONNAIRE[nom]
                                                                                               for v in s.split(",") if v.strip() not in ("—", "")})),
                                 "tables_preparees_tunishop_kpi": PREPAREES[nom], "fonction": f"features.table_{nom}()",
                                 "fichier": f"05_Data/features/{nom}.parquet"} for nom in tables])
    vers_notebooks = pd.DataFrame([{"table_variables": nom, "notebook": nb} for nom, l in CONSOMMATEURS.items() for nb in l])
    eda = pd.DataFrame([{"notebook": nb, "questions": ", ".join(qs)} for nb, qs in NOTEBOOKS_EDA.items()])
    exporter_excel({
        "01_Chaine": ("Lignage des données — de la source aux livrables", "Chaque étape, l'outil qui la réalise et le contrôle associé", chaine),
        "02_Vues_vers_tables": ("Vues bi -> tables de variables", "D'où vient chaque table de 05_Data/features", vers_tables),
        "03_Tables_vers_notebooks": ("Tables de variables -> notebooks", "Qui lit chaque table", vers_notebooks),
        "04_Notebooks_EDA": ("Notebooks de l'EDA thématique", "Questions du Plan_Analyse_EDA traitées dans chaque notebook (lecture directe des vues bi)", eda),
        "05_Sorties_data_mining": ("Sorties du data mining", "Fichiers produits par 02_Data_Mining et leur utilisation",
                                   pd.DataFrame(SORTIES_DATA_MINING, columns=["notebook", "fichier", "contenu", "utilise_par"])),
        "06_Sorties_machine_learning": ("Sorties du machine learning", "Fichiers produits par 03_Machine_Learning et leur utilisation",
                                        pd.DataFrame(SORTIES_ML, columns=["notebook", "fichier", "contenu", "utilise_par"])),
    }, dossier / "Data_Lineage.xlsx", "Lignage des données — TuniShop")


# =====================================================================================
# Jeux de données du machine learning (03_Machine_Learning/01_Preparation_Datasets_ML)
# =====================================================================================
# Pour chaque cas : la cible, les variables numériques et catégorielles retenues, et les colonnes
# écartées (identifiants, fuites). Tous les notebooks de modélisation utilisent ces listes.
CALENDRIER = [f"part_jours_{x}" for x in PERIODES_COMMERCIALES]

CAS_ML = {
    "ventes": {
        "titre": "Prévision des ventes (CA TTC mensuel par catégorie)", "type": "régression (série temporelle)",
        "cible": "ca_ttc", "grain": "1 catégorie x 1 mois",
        "numeriques": ["t"] + CALENDRIER, "categorielles": ["categorie"],
        "ecartees": {"quantite / nb_commandes": "mesurés en même temps que la cible (fuite)"},
    },
    "churn": {
        "titre": "Prédiction du churn à 90 jours", "type": "classification binaire",
        "cible": "churn", "grain": "1 client actif x 1 fin de trimestre",
        "numeriques": ["recence_j", "anciennete_j", "frequence", "montant_reconnu_ttc", "panier_moyen_ttc",
                       "nb_articles_moyen", "part_mobile", "part_paiement_livraison", "part_coupon", "taux_annulation",
                       "taux_aboutie", "nb_commandes_90j", "nb_categories", "nb_livraisons", "part_livraisons_retard",
                       "retard_max_j", "nb_demandes_remboursement", "note_moyenne", "a_donne_avis", "nb_avis",
                       "score_r", "score_f", "score_m"],
        "categorielles": ["region", "type_client", "tranche_age", "genre", "canal_inscription", "segment_rfm", "cluster"],
        "ecartees": {**FUITES_CHURN, "client_sk / date_observation": "identifiants (pas des comportements)"},
    },
    "demande": {
        "titre": "Prédiction de la demande (quantité mensuelle par produit)", "type": "régression (comptage)",
        "cible": "quantite", "grain": "1 produit x 1 mois",
        "numeriques": ["moy_annee_prec", "moy_3_derniers_mois", "mois_vendus_annee_prec", "meme_mois_annee_prec",
                       "moy_categorie_annee_prec", "part_rupture_annee_prec", "nouveau_produit", "prix_catalogue_ttc",
                       "mois_num"] + CALENDRIER,
        "categorielles": ["categorie", "gamme_prix"],
        "ecartees": {"ca_ttc / ca_ht / marge_ht / nb_commandes": "mesurés en même temps que la cible (fuite)",
                     "stock_fin_mois / en_rupture du mois": "connus seulement à la fin du mois prévu (fuite)"},
    },
    "retard": {
        "titre": "Prédiction du retard de livraison", "type": "classification binaire",
        "cible": "en_retard", "grain": "1 expédition livrée",
        "numeriques": ["poids_kg", "delai_preparation_h", "montant_total_ttc", "nb_articles", "jour_semaine", "mois",
                       "est_weekend", "est_ramadan"],
        "categorielles": ["transporteur", "region", "zone_livraison", "entrepot", "mode_paiement", "canal", "periode_commerciale"],
        "ecartees": {**FUITES_RETARD, "livraison_id / commande_id": "identifiants"},
    },
}


def dataset_ventes(produits_mois: pd.DataFrame) -> pd.DataFrame:
    """1 ligne = 1 catégorie x 1 mois : CA TTC, tendance t (mois depuis janvier 2023) et calendrier."""
    s = ventes_categorie_mois(produits_mois)
    s = s[s["categorie"] != "Total"]
    cal = produits_mois.drop_duplicates("mois").set_index("mois")[CALENDRIER]
    s = s.join(cal, on="mois")
    s["t"] = (s["mois"].dt.year - coupures.DEBUT_DONNEES.year) * 12 + s["mois"].dt.month - 1
    return s.reset_index(drop=True)


def dataset_churn(clients: pd.DataFrame, dossier=DOSSIER_FEATURES) -> pd.DataFrame:
    """Table clients + variables du data mining (segment RFM, cluster) + indicateur « a donné un avis »."""
    t = ajouter_segment_rfm(clients, dossier)
    t = t.merge(lire("clusters_clients", dossier)[["client_sk", "date_observation", "cluster"]],
                on=["client_sk", "date_observation"], how="left")
    t["a_donne_avis"] = t["note_moyenne"].notna().astype(int)
    return t


def dataset_demande(produits_mois: pd.DataFrame) -> pd.DataFrame:
    """Variables de la demande d'un mois, calculées UNIQUEMENT avec l'année civile précédente.

    Chaque mois d'une année est prévu depuis le 31 décembre de l'année précédente (horizon 1 à 12 mois) :
    les variables « historique » ne regardent donc que l'année d'avant. Les lignes de 2023 n'ont pas
    d'année précédente : elles ne servent qu'à calculer les variables de 2024.
    """
    pm = produits_mois.copy()
    pm["annee"] = pm["mois"].dt.year
    pm["mois_num"] = pm["mois"].dt.month
    morceaux = []
    for annee in sorted(pm["annee"].unique())[1:]:
        lignes = pm[pm["annee"] == annee].copy()
        prec = pm[pm["annee"] == annee - 1]
        g = prec.groupby("produit_id")
        lignes["moy_annee_prec"] = lignes["produit_id"].map(g["quantite"].mean())
        lignes["moy_3_derniers_mois"] = lignes["produit_id"].map(prec[prec["mois_num"] >= 10].groupby("produit_id")["quantite"].mean())
        lignes["mois_vendus_annee_prec"] = lignes["produit_id"].map(g.size()).fillna(0)
        meme = prec[["produit_id", "mois_num", "quantite"]].rename(columns={"quantite": "meme_mois_annee_prec"})
        lignes = lignes.merge(meme, on=["produit_id", "mois_num"], how="left")
        lignes["moy_categorie_annee_prec"] = lignes["categorie"].map(prec.groupby("categorie")["quantite"].mean())
        lignes["part_rupture_annee_prec"] = lignes["produit_id"].map(g["en_rupture"].mean())
        lignes["nouveau_produit"] = lignes["moy_annee_prec"].isna().astype(int)
        morceaux.append(lignes)
    return pd.concat(morceaux, ignore_index=True)


def prevision_demande_v2(lignes: pd.DataFrame, produits_mois: pd.DataFrame) -> pd.Series:
    """Demande « version 2 » : prévision par catégorie, puis répartition par produit.

    Pour chaque ligne (produit x mois d'une année A), avec UNIQUEMENT l'année A-1 :
      1. saisonnalité : quantité de la catégorie le même mois de A-1 ;
      2. croissance  : rythme du dernier trimestre de A-1 rapporté à la moyenne mensuelle de A-1
                       (bornée entre 0,8 et 1,6 pour éviter les emballements) ;
      3. répartition : part du produit dans la quantité annuelle de sa catégorie en A-1 ;
      4. nouveau produit (pas d'historique) : moitié de la moyenne mensuelle d'un produit de sa catégorie.
    """
    pm = produits_mois.assign(annee=produits_mois["mois"].dt.year, mois_num=produits_mois["mois"].dt.month)
    resultat = pd.Series(np.nan, index=lignes.index, dtype=float)
    annees = lignes["mois"].dt.year if "mois" in lignes else lignes["annee"]
    for annee in sorted(annees.unique()):
        idx = lignes.index[annees == annee]
        L, prec = lignes.loc[idx], pm[pm["annee"] == annee - 1]
        if prec.empty:
            continue
        cat_mois = prec.groupby(["categorie", "mois_num"])["quantite"].sum()
        cat_an = prec.groupby("categorie")["quantite"].sum()
        croissance = (prec[prec["mois_num"] >= 10].groupby("categorie")["quantite"].sum() / 3 / (cat_an / 12)).clip(0.8, 1.6)
        part = prec.groupby("produit_id")["quantite"].sum() / prec.groupby("produit_id")["categorie"].first().map(cat_an)
        mois_num = L["mois"].dt.month if "mois" in L else L["mois_num"]
        base = pd.Series([cat_mois.get((c, m), np.nan) for c, m in zip(L["categorie"], mois_num)], index=idx)
        p = base * L["categorie"].map(croissance) * L["produit_id"].map(part)
        resultat.loc[idx] = p.fillna(L["moy_categorie_annee_prec"] * 0.5)
    return resultat.clip(lower=0)


def colonnes_ml(cas: str) -> list:
    """Variables explicatives (numériques puis catégorielles) d'un cas de ML."""
    return CAS_ML[cas]["numeriques"] + CAS_ML[cas]["categorielles"]


def preprocesseur(cas: str, echelle: bool = True):
    """Préparation des variables pour scikit-learn, identique dans tous les notebooks :
    - numériques : valeur vide -> médiane de l'APPRENTISSAGE, puis mise à l'échelle (si echelle=True) ;
    - catégorielles : valeur vide -> « inconnu », puis une colonne 0/1 par modalité (une modalité
      nouvelle en 2025 est simplement ignorée, sans erreur).
    Toutes ces règles sont apprises au moment du .fit() sur l'apprentissage uniquement (pas de fuite).
    """
    from sklearn.compose import ColumnTransformer
    from sklearn.impute import SimpleImputer
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import OneHotEncoder, StandardScaler
    etapes_num = [SimpleImputer(strategy="median")] + ([StandardScaler()] if echelle else [])
    return ColumnTransformer([
        ("numeriques", make_pipeline(*etapes_num), CAS_ML[cas]["numeriques"]),
        ("categorielles", make_pipeline(SimpleImputer(strategy="constant", fill_value="inconnu"),
                                        OneHotEncoder(handle_unknown="ignore")), CAS_ML[cas]["categorielles"]),
    ], sparse_threshold=0)                      # sortie dense : acceptée par tous les modèles
