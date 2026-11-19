# -*- coding: utf-8 -*-
"""
tunishop_kpi.py — Calcul de référence des KPI TuniShop (phase BI / analyse)
==========================================================================

Un seul endroit où chaque KPI est défini et calculé en Python.
Les notebooks d'analyse (EDA, segmentation, classification, association)
importent ce module : les chiffres sont donc identiques d'un bout à
l'autre du projet, et identiques à ceux de Power BI / Tableau (recette).

Source des données : les vues bi.v_* de TuniShop_DWH (jamais les tables dw.*).

Utilisation type (dans un notebook) :
    import tunishop_kpi as tk
    cn = tk.connecter(serveur="localhost")          # authentification Windows
    vues = tk.charger_vues(cn)                      # 23 vues -> DataFrames
    p = tk.preparer(vues)                           # tables enrichies
    resultats = tk.calculer_kpi(p)                  # tous les KPI (global + années + détails)
    controles = tk.controler_coherence(p)           # tendances attendues
    tk.exporter_excel(resultats, controles, "kpi_reference.xlsx")
"""
from __future__ import annotations

import os
import warnings
from dataclasses import dataclass, field
from decimal import Decimal
from typing import Callable

import numpy as np
import pandas as pd

# ---------------------------------------------------------------------------
# 1. Connexion et chargement des vues
# ---------------------------------------------------------------------------
VUES = [
    "v_dim_date", "v_dim_client", "v_dim_produit", "v_dim_fournisseur", "v_dim_geographie",
    "v_dim_entrepot", "v_dim_transporteur", "v_dim_campagne", "v_dim_coupon", "v_dim_canal",
    "v_dim_mode_paiement", "v_dim_statut_commande", "v_dim_motif_retour",
    "v_fact_ventes", "v_fact_commandes", "v_fact_paiements", "v_fact_livraisons",
    "v_fact_remboursements", "v_fact_avis", "v_fact_marketing_quotidien",
    "v_fact_achats_fournisseur", "v_fact_mouvements_stock", "v_fact_stock_mensuel",
]


def connecter(serveur: str = "localhost", base: str = "TuniShop_DWH", auth: str = "windows",
              utilisateur: str | None = None, pilote: str = "ODBC Driver 17 for SQL Server"):
    """Ouvre une connexion pyodbc vers le DWH.
    auth = "windows" (Trusted_Connection) ou "sql" (mot de passe lu dans la
    variable d'environnement TUNISHOP_MDP : jamais de mot de passe dans le code)."""
    import pyodbc
    cs = f"DRIVER={{{pilote}}};SERVER={serveur};DATABASE={base};"
    if auth == "windows":
        cs += "Trusted_Connection=yes;"
    else:
        mdp = os.environ.get("TUNISHOP_MDP")
        if not utilisateur or not mdp:
            raise ValueError("Authentification SQL : renseigner utilisateur et la variable TUNISHOP_MDP.")
        cs += f"UID={utilisateur};PWD={mdp};"
    return pyodbc.connect(cs)


def _convertir_types(df: pd.DataFrame) -> pd.DataFrame:
    """pyodbc renvoie les DECIMAL en objets Decimal : on les convertit en float."""
    for col in df.columns:
        if df[col].dtype == object:
            echantillon = df[col].dropna().head(50)
            if len(echantillon) and all(isinstance(v, Decimal) for v in echantillon):
                df[col] = df[col].astype(float)
    return df


def charger_vues(cn, vues: list[str] = VUES) -> dict[str, pd.DataFrame]:
    """Lit chaque vue bi.v_* dans un DataFrame (clé = nom de la vue sans 'v_')."""
    resultat = {}
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)   # avertissement pandas « SQLAlchemy »
        for v in vues:
            df = pd.read_sql(f"SELECT * FROM bi.[{v}]", cn)
            resultat[v[2:]] = _convertir_types(df)
            print(f"  {v:<30} {len(df):>8,} lignes".replace(",", " "))
    return resultat


def exporter_vues(vues: dict[str, pd.DataFrame], dossier: str) -> None:
    """Sauvegarde les vues chargées en CSV (une copie figée du DWH : les notebooks suivants
    peuvent travailler sans SQL Server, et toujours sur la même photo des données)."""
    os.makedirs(dossier, exist_ok=True)
    for nom, df in vues.items():
        df.to_csv(os.path.join(dossier, f"v_{nom}.csv"), index=False, encoding="utf-8-sig")


def charger_vues_dossier(dossier: str, vues: list[str] = VUES) -> dict[str, pd.DataFrame]:
    """Relit une copie figée créée par exporter_vues()."""
    resultat = {}
    for v in vues:
        df = pd.read_csv(os.path.join(dossier, f"{v}.csv"), encoding="utf-8-sig", low_memory=False)
        resultat[v[2:]] = df
        print(f"  {v:<30} {len(df):>8,} lignes".replace(",", " "))
    return resultat


# ---------------------------------------------------------------------------
# 2. Préparation : tables enrichies prêtes pour les calculs
# ---------------------------------------------------------------------------
FAMILLE_ABOUTIE = "aboutie"          # livree, partiellement_retournee, retournee
DATE_BASCULE_SAHELLOG = 20240701     # scénario transporteur (contrôle de cohérence)


def _annee(sk: pd.Series) -> pd.Series:
    """date_sk au format AAAAMMJJ -> année ; membres -1 / -2 -> NaN."""
    return np.where(sk > 0, sk // 10000, np.nan)


def _date(sk: pd.Series) -> pd.Series:
    return pd.to_datetime(sk.where(sk > 0).astype("Int64").astype(str), format="%Y%m%d", errors="coerce")


def _bool(s: pd.Series) -> pd.Series:
    """BIT SQL -> booléen pandas (NULL -> False)."""
    return s.fillna(False).astype(bool)


def preparer(v: dict[str, pd.DataFrame]) -> dict[str, pd.DataFrame]:
    """Joint les faits à leurs dimensions et ajoute les colonnes d'analyse
    (annee, famille de statut, catégorie, transporteur...)."""
    d = {k: x.copy() for k, x in v.items()}
    statut = d["dim_statut_commande"][["statut_commande_sk", "statut_commande", "famille_statut"]]
    canal = d["dim_canal"][["canal_sk", "canal", "appareil"]]
    mode = d["dim_mode_paiement"][["mode_paiement_sk", "mode_paiement"]]
    client = d["dim_client"][["client_sk", "client_id", "segment_fidelite", "type_client"]]
    geo = d["dim_geographie"][["geographie_sk", "region", "gouvernorat"]]
    produit = d["dim_produit"][["produit_sk", "produit_id", "categorie", "sous_categorie", "fournisseur_id"]]
    transp = d["dim_transporteur"][["transporteur_sk", "nom_transporteur"]].rename(columns={"nom_transporteur": "transporteur"})
    campagne = d["dim_campagne"][["campagne_sk", "canal_media"]]
    motif = d["dim_motif_retour"][["motif_retour_sk", "type_remboursement", "motif"]]
    fourn = d["dim_fournisseur"][["fournisseur_sk", "fournisseur_id", "nom_fournisseur"]]

    # --- Commandes (grain : commande)
    cmd = (d["fact_commandes"].merge(statut, on="statut_commande_sk", how="left")
           .merge(canal, on="canal_sk", how="left").merge(mode, on="mode_paiement_sk", how="left")
           .merge(client, on="client_sk", how="left").merge(geo, on="geographie_sk", how="left"))
    cmd["annee"] = _annee(cmd["date_commande_sk"])
    cmd["date"] = _date(cmd["date_commande_sk"])
    cmd["est_aboutie"] = cmd["famille_statut"].eq(FAMILLE_ABOUTIE)
    cmd["est_premiere_commande"] = _bool(cmd["est_premiere_commande"])

    # --- Remboursements (grain : demande de remboursement)
    rmb = (d["fact_remboursements"].merge(motif, on="motif_retour_sk", how="left")
           .merge(produit[["produit_sk", "produit_id", "categorie"]], on="produit_sk", how="left"))
    rmb["annee"] = _annee(rmb["date_demande_sk"])
    rmb["est_rembourse"] = rmb["statut"].eq("rembourse")

    # Lignes retournées : retour accepté ou en cours (statut <> refuse), relié par commande + produit
    retours = rmb[rmb["type_remboursement"].eq("retour") & rmb["statut"].ne("refuse") & rmb["produit_id"].notna()]
    cles_retour = set(zip(retours["commande_id"], retours["produit_id"]))

    # --- Lignes de commande (grain : ligne)
    lig = (d["fact_ventes"].merge(statut, on="statut_commande_sk", how="left")
           .merge(produit, on="produit_sk", how="left"))
    lig["annee"] = _annee(lig["date_commande_sk"])
    lig["est_aboutie"] = lig["famille_statut"].eq(FAMILLE_ABOUTIE)
    lig["est_retournee"] = [(c, p) in cles_retour for c, p in zip(lig["commande_id"], lig["produit_id"])]

    # --- Livraisons (grain : livraison)
    liv = (d["fact_livraisons"].merge(transp, on="transporteur_sk", how="left")
           .merge(geo, on="geographie_sk", how="left"))
    liv["annee"] = _annee(liv["date_expedition_sk"])
    liv["semestre"] = np.where(liv["date_expedition_sk"] > 0,
                               (liv["date_expedition_sk"] // 10000).astype(str) + "-S"
                               + np.where((liv["date_expedition_sk"] // 100) % 100 <= 6, "1", "2"), None)
    for c in ["est_livree", "est_livree_a_temps", "est_premiere_tentative"]:
        liv[c] = _bool(liv[c])

    # --- Avis (grain : avis) + retard de la livraison de la commande
    retard_cmd = liv[liv["est_livree"]].groupby("commande_id")["retard_j"].max()
    avis = d["fact_avis"].merge(produit[["produit_sk", "categorie"]], on="produit_sk", how="left")
    avis["annee"] = _annee(avis["date_avis_sk"])
    r = avis["commande_id"].map(retard_cmd)
    avis["tranche_retard"] = np.select([r.isna(), r.eq(0), r.le(2)], ["non livrée", "0 j", "1-2 j"], "3 j et +")

    # --- Marketing (grain : campagne x jour)
    mkt = d["fact_marketing_quotidien"].merge(campagne, on="campagne_sk", how="left")
    mkt["annee"] = _annee(mkt["date_sk"])

    # --- Stock mensuel (snapshot) et mouvements
    stk = d["fact_stock_mensuel"].merge(produit[["produit_sk", "categorie"]], on="produit_sk", how="left")
    stk["annee"] = _annee(stk["date_sk"])
    stk["est_rupture"] = _bool(stk["est_rupture"])
    mvt = d["fact_mouvements_stock"].merge(produit[["produit_sk", "categorie"]], on="produit_sk", how="left")
    mvt["annee"] = _annee(mvt["date_sk"])
    mvt["date"] = _date(mvt["date_sk"])

    # --- Achats fournisseurs (grain : ligne de bon de commande)
    ach = d["fact_achats_fournisseur"].merge(fourn, on="fournisseur_sk", how="left")
    ach["annee"] = _annee(ach["date_commande_sk"])
    ach["trimestre"] = np.where(ach["date_commande_sk"] > 0,
                                (ach["date_commande_sk"] // 10000).astype(str) + "-T"
                                + (((ach["date_commande_sk"] // 100) % 100 - 1) // 3 + 1).astype(str), None)

    # --- Paiements (grain : tentative)
    pai = d["fact_paiements"].merge(mode, on="mode_paiement_sk", how="left")
    pai["annee"] = _annee(pai["date_paiement_sk"])
    pai["est_reussi"] = _bool(pai["est_reussi"])

    # --- Clients (version courante, hors membres techniques)
    cli = d["dim_client"]
    cli = cli[(cli["client_sk"] > 0) & _bool(cli["est_courant"]) & ~_bool(cli["est_supprime"])].copy()

    return {"cmd": cmd, "lig": lig, "liv": liv, "rmb": rmb, "avis": avis, "mkt": mkt,
            "stk": stk, "mvt": mvt, "ach": ach, "pai": pai, "cli": cli}


# ---------------------------------------------------------------------------
# 3. Catalogue des KPI (source unique du dictionnaire des KPI)
# ---------------------------------------------------------------------------
def _div(a, b):
    return float(a) / float(b) if b not in (0, None) and not pd.isna(b) else np.nan


@dataclass
class KPI:
    code: str
    domaine: str
    nom: str
    definition: str
    regle: str                    # règle de gestion (filtres, exclusions)
    source: str                   # vues bi.v_* utilisées
    unite: str                    # DT, %, j, nb, ratio
    sens: str                     # ↑ = plus c'est haut mieux c'est
    page: str                     # page du tableau de bord
    tables: list[str]             # tables préparées utilisées par le calcul
    calcul: Callable[[dict], float]
    pandas: str                   # formule lisible (pour le dictionnaire)
    dax: str
    axes: list[str] = field(default_factory=list)   # axes de détail en plus de global / année
    tolerance: float = 0.0        # tolérance de recette (en unité du KPI ; % exprimé en fraction)


def _aboutie(d, t="cmd"):
    return d[t][d[t]["est_aboutie"]]


def _couverture(d):
    stk, mvt = d["stk"], d["mvt"]
    if stk.empty:
        return np.nan
    dern = stk["date_sk"].max()
    stock_qte = stk.loc[stk["date_sk"].eq(dern), "stock_fin_mois"].sum()
    fin = pd.to_datetime(str(int(dern)), format="%Y%m%d")
    v = mvt[mvt["type_mouvement"].eq("vente") & mvt["date"].between(fin - pd.Timedelta(days=89), fin)]
    ventes_jour = v["quantite"].abs().sum() / 90
    return _div(stock_qte, ventes_jour)


def _rotation(d):
    stk, mvt = d["stk"], d["mvt"]
    v = mvt[mvt["type_mouvement"].eq("vente")]
    if v.empty or stk.empty:
        return np.nan
    jours = (v["date"].max() - v["date"].min()).days + 1
    cout_ventes_an = v["valeur_ht"].abs().sum() / jours * 365
    stock_moyen = stk.groupby("date_sk")["valeur_stock_ht"].sum().mean()
    return _div(cout_ventes_an, stock_moyen)


def _cf_recues(d):
    a = d["ach"]
    return a[a["date_reception_sk"] > 0]


def _clients_actifs(d):
    c = d["cmd"]
    return c[c["statut_commande"].ne("paiement_echoue")]


F_ABOUTIE = 'v_dim_statut_commande[famille_statut] = "aboutie"'

CATALOGUE: list[KPI] = [
    # ---------------- VENTES
    KPI("V01", "Ventes", "CA commandé TTC", "Montant TTC de toutes les commandes passées (prise de commande).",
        "Toutes les commandes, quel que soit le statut (y compris annulées et échecs).",
        "bi.v_fact_commandes", "DT", "↑", "Direction",
        ["cmd"], lambda d: d["cmd"]["montant_total_ttc"].sum(),
        "cmd.montant_total_ttc.sum()",
        "CA commandé TTC = SUM ( v_fact_commandes[montant_total_ttc] )",
        ["canal", "region"], 1.0),
    KPI("V02", "Ventes", "Commandes passées", "Nombre de commandes passées.",
        "Toutes les commandes, quel que soit le statut.", "bi.v_fact_commandes", "nb", "↑", "Direction",
        ["cmd"], lambda d: len(d["cmd"]), "len(cmd)",
        "Commandes passées = COUNTROWS ( v_fact_commandes )", ["canal", "region"]),
    KPI("V03", "Ventes", "CA reconnu TTC", "Montant TTC des commandes abouties (livrées, même si retournées ensuite).",
        "famille_statut = 'aboutie' (livree, partiellement_retournee, retournee). Exclut annulée, échec de paiement, "
        "livraison échouée, en préparation, expédiée (CA pas encore acquis).",
        "bi.v_fact_commandes + v_dim_statut_commande", "DT", "↑", "Direction / Ventes",
        ["cmd"], lambda d: _aboutie(d)["montant_total_ttc"].sum(),
        "cmd[cmd.est_aboutie].montant_total_ttc.sum()",
        f"CA reconnu TTC = CALCULATE ( SUM ( v_fact_commandes[montant_total_ttc] ), {F_ABOUTIE} )",
        ["canal", "region", "mode_paiement"], 1.0),
    KPI("V04", "Ventes", "Commandes reconnues", "Nombre de commandes abouties.", "famille_statut = 'aboutie'.",
        "bi.v_fact_commandes + v_dim_statut_commande", "nb", "↑", "Direction / Ventes",
        ["cmd"], lambda d: len(_aboutie(d)), "len(cmd[cmd.est_aboutie])",
        f"Commandes reconnues = CALCULATE ( COUNTROWS ( v_fact_commandes ), {F_ABOUTIE} )", ["canal", "region"]),
    KPI("V05", "Ventes", "Remboursé TTC (sur CA reconnu)", "Montant effectivement remboursé sur les commandes abouties.",
        "Remboursements au statut 'rembourse' uniquement (déjà agrégés par commande dans montant_rembourse_ttc) ; "
        "daté par la date de la commande.", "bi.v_fact_commandes", "DT", "↓", "Direction / SAV",
        ["cmd"], lambda d: _aboutie(d)["montant_rembourse_ttc"].sum(),
        "cmd[cmd.est_aboutie].montant_rembourse_ttc.sum()",
        f"Remboursé TTC = CALCULATE ( SUM ( v_fact_commandes[montant_rembourse_ttc] ), {F_ABOUTIE} )", [], 1.0),
    KPI("V06", "Ventes", "CA net TTC", "CA reconnu après remboursements.", "V03 − V05.",
        "bi.v_fact_commandes", "DT", "↑", "Direction",
        ["cmd"], lambda d: _aboutie(d)["montant_total_ttc"].sum() - _aboutie(d)["montant_rembourse_ttc"].sum(),
        "V03 - V05", "CA net TTC = [CA reconnu TTC] - [Remboursé TTC]", ["canal", "region"], 1.0),
    KPI("V07", "Ventes", "CA HT (produits)", "Chiffre d'affaires HT des lignes de produits des commandes abouties.",
        "Grain ligne ; hors frais de livraison et hors remise coupon (portée par la commande).",
        "bi.v_fact_ventes + v_dim_statut_commande", "DT", "↑", "Ventes & produits",
        ["lig"], lambda d: _aboutie(d, "lig")["montant_ht"].sum(), "lig[lig.est_aboutie].montant_ht.sum()",
        f"CA HT = CALCULATE ( SUM ( v_fact_ventes[montant_ht] ), {F_ABOUTIE} )", ["categorie"], 1.0),
    KPI("V08", "Ventes", "Marge brute HT", "CA HT − coût d'achat HT des articles vendus.",
        "Lignes des commandes abouties ; coût d'achat au prix de la période (dim_produit versionnée).",
        "bi.v_fact_ventes", "DT", "↑", "Direction / Ventes",
        ["lig"], lambda d: _aboutie(d, "lig")["marge_brute_ht"].sum(), "lig[lig.est_aboutie].marge_brute_ht.sum()",
        f"Marge brute HT = CALCULATE ( SUM ( v_fact_ventes[marge_brute_ht] ), {F_ABOUTIE} )", ["categorie"], 1.0),
    KPI("V09", "Ventes", "Taux de marge brute", "Marge brute HT / CA HT.", "Mêmes lignes que V07 et V08.",
        "bi.v_fact_ventes", "%", "↑", "Ventes & produits",
        ["lig"], lambda d: _div(_aboutie(d, "lig")["marge_brute_ht"].sum(), _aboutie(d, "lig")["montant_ht"].sum()),
        "V08 / V07", "Taux de marge = DIVIDE ( [Marge brute HT], [CA HT] )", ["categorie"], 0.0005),
    KPI("V10", "Ventes", "Panier moyen TTC", "CA reconnu TTC / commandes reconnues.", "Commandes abouties.",
        "bi.v_fact_commandes", "DT", "↑", "Direction / Ventes",
        ["cmd"], lambda d: _aboutie(d)["montant_total_ttc"].mean(), "V03 / V04",
        "Panier moyen TTC = DIVIDE ( [CA reconnu TTC], [Commandes reconnues] )", ["canal", "mode_paiement"], 0.01),
    KPI("V11", "Ventes", "Articles par commande", "Nombre moyen d'articles par commande aboutie.",
        "Somme de nb_articles / commandes abouties.", "bi.v_fact_commandes", "nb", "↑", "Ventes & produits",
        ["cmd"], lambda d: _aboutie(d)["nb_articles"].mean(), "cmd[cmd.est_aboutie].nb_articles.mean()",
        f"Articles par commande = CALCULATE ( AVERAGE ( v_fact_commandes[nb_articles] ), {F_ABOUTIE} )", ["canal"], 0.001),
    KPI("V12", "Ventes", "Taux de remise produit", "Remises promo / montant brut au prix catalogue.",
        "Lignes des commandes abouties ; hors coupon.", "bi.v_fact_ventes", "%", "↓", "Ventes & produits",
        ["lig"], lambda d: _div(_aboutie(d, "lig")["montant_remise_promo_ttc"].sum(), _aboutie(d, "lig")["montant_brut_ttc"].sum()),
        "remise_promo.sum() / montant_brut.sum()",
        f"Taux de remise = DIVIDE ( CALCULATE ( SUM ( v_fact_ventes[montant_remise_promo_ttc] ), {F_ABOUTIE} ), "
        f"CALCULATE ( SUM ( v_fact_ventes[montant_brut_ttc] ), {F_ABOUTIE} ) )", ["categorie"], 0.0005),
    KPI("V13", "Ventes", "Part de l'application mobile", "Part des commandes passées via l'application.",
        "canal = 'application_mobile' / toutes les commandes passées.", "bi.v_fact_commandes + v_dim_canal", "%", "↑",
        "Direction / Marketing",
        ["cmd"], lambda d: d["cmd"]["canal"].eq("application_mobile").mean(), "(cmd.canal == 'application_mobile').mean()",
        'Part app = DIVIDE ( CALCULATE ( COUNTROWS ( v_fact_commandes ), v_dim_canal[canal] = "application_mobile" ), [Commandes passées] )',
        [], 0.0005),
    KPI("V14", "Ventes", "Part du paiement à la livraison", "Part des commandes payées à la livraison (COD).",
        "mode_paiement = 'paiement_a_la_livraison' / toutes les commandes passées.",
        "bi.v_fact_commandes + v_dim_mode_paiement", "%", "↓", "Direction",
        ["cmd"], lambda d: d["cmd"]["mode_paiement"].eq("paiement_a_la_livraison").mean(),
        "(cmd.mode_paiement == 'paiement_a_la_livraison').mean()",
        'Part COD = DIVIDE ( CALCULATE ( COUNTROWS ( v_fact_commandes ), v_dim_mode_paiement[mode_paiement] = "paiement_a_la_livraison" ), [Commandes passées] )',
        [], 0.0005),
    # ---------------- OPÉRATIONS
    KPI("O01", "Opérations", "Taux d'annulation", "Commandes annulées / commandes passées.", "statut_commande = 'annulee'.",
        "bi.v_fact_commandes + v_dim_statut_commande", "%", "↓", "Direction",
        ["cmd"], lambda d: d["cmd"]["statut_commande"].eq("annulee").mean(), "(cmd.statut_commande == 'annulee').mean()",
        'Taux d\'annulation = DIVIDE ( CALCULATE ( COUNTROWS ( v_fact_commandes ), v_dim_statut_commande[statut_commande] = "annulee" ), [Commandes passées] )',
        ["canal", "mode_paiement"], 0.0005),
    KPI("O02", "Opérations", "Taux d'échec de paiement", "Tentatives de paiement échouées / tentatives.",
        "Grain tentative (une commande peut avoir plusieurs tentatives).", "bi.v_fact_paiements", "%", "↓", "Direction",
        ["pai"], lambda d: 1 - d["pai"]["est_reussi"].mean(), "1 - pai.est_reussi.mean()",
        "Taux d'échec de paiement = 1 - DIVIDE ( CALCULATE ( COUNTROWS ( v_fact_paiements ), v_fact_paiements[est_reussi] = TRUE () ), COUNTROWS ( v_fact_paiements ) )",
        ["mode_paiement"], 0.0005),
    KPI("O03", "Opérations", "Taux de refus de colis", "Livraisons échouées (colis refusé / retour expéditeur) / commandes arrivées au bout de la livraison.",
        "Numérateur : statut 'livraison_echouee'. Dénominateur : commandes abouties + livraisons échouées.",
        "bi.v_fact_commandes + v_dim_statut_commande", "%", "↓", "Logistique",
        ["cmd"], lambda d: _div(d["cmd"]["statut_commande"].eq("livraison_echouee").sum(),
                                (d["cmd"]["est_aboutie"] | d["cmd"]["statut_commande"].eq("livraison_echouee")).sum()),
        "échouées / (abouties + échouées)",
        'Taux de refus = DIVIDE ( CALCULATE ( COUNTROWS ( v_fact_commandes ), v_dim_statut_commande[statut_commande] = "livraison_echouee" ), '
        'CALCULATE ( COUNTROWS ( v_fact_commandes ), v_dim_statut_commande[famille_statut] = "aboutie" || v_dim_statut_commande[statut_commande] = "livraison_echouee" ) )',
        ["mode_paiement", "region"], 0.0005),
    KPI("O04", "Opérations", "Taux de rupture (stock)", "Part des couples produit × entrepôt en rupture en fin de mois.",
        "stock_fin_mois = 0 (est_rupture) ; moyenne sur les inventaires mensuels de la période.",
        "bi.v_fact_stock_mensuel", "%", "↓", "Stock & achats",
        ["stk"], lambda d: d["stk"]["est_rupture"].mean(), "stk.est_rupture.mean()",
        "Taux de rupture = DIVIDE ( CALCULATE ( COUNTROWS ( v_fact_stock_mensuel ), v_fact_stock_mensuel[est_rupture] = TRUE () ), COUNTROWS ( v_fact_stock_mensuel ) )",
        ["categorie"], 0.0005),
    # ---------------- LOGISTIQUE
    KPI("L01", "Logistique", "Délai moyen de livraison (j)", "Durée moyenne entre la commande et la livraison réelle.",
        "Livraisons au statut 'livree' ; délai en jours décimaux (delai_livraison_j).", "bi.v_fact_livraisons", "j", "↓",
        "Logistique",
        ["liv"], lambda d: d["liv"].loc[d["liv"]["est_livree"], "delai_livraison_j"].mean(),
        "liv[liv.est_livree].delai_livraison_j.mean()",
        "Délai moyen de livraison = CALCULATE ( AVERAGE ( v_fact_livraisons[delai_livraison_j] ), v_fact_livraisons[est_livree] = TRUE () )",
        ["transporteur", "region"], 0.01),
    KPI("L02", "Logistique", "Taux de livraison à l'heure (OTD)", "Livraisons arrivées au plus tard à la date prévue / livraisons livrées.",
        "Livraisons au statut 'livree' uniquement (les échecs ne comptent ni au numérateur ni au dénominateur).",
        "bi.v_fact_livraisons", "%", "↑", "Logistique",
        ["liv"], lambda d: d["liv"].loc[d["liv"]["est_livree"], "est_livree_a_temps"].mean(),
        "liv[liv.est_livree].est_livree_a_temps.mean()",
        "OTD = DIVIDE ( CALCULATE ( COUNTROWS ( v_fact_livraisons ), v_fact_livraisons[est_livree_a_temps] = TRUE () ), "
        "CALCULATE ( COUNTROWS ( v_fact_livraisons ), v_fact_livraisons[est_livree] = TRUE () ) )",
        ["transporteur", "region", "semestre"], 0.0005),
    KPI("L03", "Logistique", "Taux de retard", "Livraisons en retard / livraisons livrées (= 1 − OTD).", "Livraisons 'livree'.",
        "bi.v_fact_livraisons", "%", "↓", "Logistique",
        ["liv"], lambda d: 1 - d["liv"].loc[d["liv"]["est_livree"], "est_livree_a_temps"].mean(), "1 - OTD",
        "Taux de retard = 1 - [OTD]", ["transporteur", "semestre"], 0.0005),
    KPI("L04", "Logistique", "Retard moyen (j)", "Retard moyen des livraisons arrivées en retard.",
        "Livraisons 'livree' avec retard_j > 0.", "bi.v_fact_livraisons", "j", "↓", "Logistique",
        ["liv"], lambda d: d["liv"].loc[d["liv"]["est_livree"] & d["liv"]["retard_j"].gt(0), "retard_j"].mean(),
        "liv[liv.est_livree & (liv.retard_j > 0)].retard_j.mean()",
        "Retard moyen = CALCULATE ( AVERAGE ( v_fact_livraisons[retard_j] ), v_fact_livraisons[est_livree] = TRUE (), v_fact_livraisons[retard_j] > 0 )",
        ["transporteur"], 0.01),
    KPI("L05", "Logistique", "Coût de transport moyen HT", "Coût de transport HT moyen par livraison.",
        "Toutes les livraisons expédiées.", "bi.v_fact_livraisons", "DT", "↓", "Logistique",
        ["liv"], lambda d: d["liv"]["cout_transport_ht"].mean(), "liv.cout_transport_ht.mean()",
        "Coût transport moyen = AVERAGE ( v_fact_livraisons[cout_transport_ht] )", ["transporteur", "region"], 0.01),
    KPI("L06", "Logistique", "Livraison au 1er passage", "Livraisons réussies dès la première tentative / livraisons livrées.",
        "Livraisons 'livree'.", "bi.v_fact_livraisons", "%", "↑", "Logistique",
        ["liv"], lambda d: d["liv"].loc[d["liv"]["est_livree"], "est_premiere_tentative"].mean(),
        "liv[liv.est_livree].est_premiere_tentative.mean()",
        "1er passage = DIVIDE ( CALCULATE ( COUNTROWS ( v_fact_livraisons ), v_fact_livraisons[est_premiere_tentative] = TRUE () ), "
        "CALCULATE ( COUNTROWS ( v_fact_livraisons ), v_fact_livraisons[est_livree] = TRUE () ) )",
        ["transporteur"], 0.0005),
    # ---------------- SAV
    KPI("S01", "SAV", "Taux de retour (lignes)", "Lignes retournées / lignes des commandes abouties.",
        "Retour = remboursement de type 'retour' au statut différent de 'refuse', relié à la ligne (commande + produit). "
        "Daté par la date de commande.", "bi.v_fact_ventes + v_fact_remboursements", "%", "↓", "SAV",
        ["lig"], lambda d: _aboutie(d, "lig")["est_retournee"].mean(), "lig[lig.est_aboutie].est_retournee.mean()",
        'Taux de retour = DIVIDE ( CALCULATE ( COUNTROWS ( v_fact_remboursements ), v_dim_motif_retour[type_remboursement] = "retour", '
        f'v_fact_remboursements[statut] <> "refuse" ), CALCULATE ( COUNTROWS ( v_fact_ventes ), {F_ABOUTIE} ) )'
        "   -- numérateur daté par la date de demande : petit écart possible par année, comparer surtout le global et les catégories",
        ["categorie"], 0.003),
    KPI("S02", "SAV", "Taux de retour (valeur)", "Montant TTC des lignes retournées / montant TTC des lignes abouties.",
        "Mêmes lignes que S01.", "bi.v_fact_ventes + v_fact_remboursements", "%", "↓", "SAV",
        ["lig"], lambda d: _div(_aboutie(d, "lig").loc[lambda x: x["est_retournee"], "montant_ttc"].sum(),
                                _aboutie(d, "lig")["montant_ttc"].sum()),
        "lig_ret.montant_ttc.sum() / lig_aboutie.montant_ttc.sum()",
        "Calcul en Python uniquement (nécessite le lien ligne ↔ retour) ; en Power BI, afficher S03 par type et catégorie.",
        ["categorie"], 0.003),
    KPI("S03", "SAV", "Montant remboursé TTC", "Montant effectivement remboursé, par date de demande.",
        "Statut 'rembourse' ; tous types (retour, annulation, geste commercial).", "bi.v_fact_remboursements", "DT", "↓", "SAV",
        ["rmb"], lambda d: d["rmb"].loc[d["rmb"]["est_rembourse"], "montant_rembourse_ttc"].sum(),
        "rmb[rmb.statut == 'rembourse'].montant_rembourse_ttc.sum()",
        'Montant remboursé = CALCULATE ( SUM ( v_fact_remboursements[montant_rembourse_ttc] ), v_fact_remboursements[statut] = "rembourse" )',
        ["type_remboursement", "categorie"], 1.0),
    KPI("S04", "SAV", "Délai moyen de remboursement (j)", "Durée moyenne entre la demande et le remboursement.",
        "Statut 'rembourse'.", "bi.v_fact_remboursements", "j", "↓", "SAV",
        ["rmb"], lambda d: d["rmb"].loc[d["rmb"]["est_rembourse"], "delai_traitement_j"].mean(),
        "rmb[rmb.statut == 'rembourse'].delai_traitement_j.mean()",
        'Délai remboursement = CALCULATE ( AVERAGE ( v_fact_remboursements[delai_traitement_j] ), v_fact_remboursements[statut] = "rembourse" )',
        ["type_remboursement"], 0.01),
    KPI("S05", "SAV", "Note moyenne des avis", "Moyenne des notes (1 à 5).", "Tous les avis notés.", "bi.v_fact_avis",
        "note", "↑", "SAV / Logistique",
        ["avis"], lambda d: d["avis"]["note"].mean(), "avis.note.mean()",
        "Note moyenne = AVERAGE ( v_fact_avis[note] )", ["tranche_retard", "categorie"], 0.001),
    KPI("S06", "SAV", "Part d'avis négatifs", "Avis notés 1 ou 2 / avis.", "note <= 2 (sentiment 'negatif').", "bi.v_fact_avis",
        "%", "↓", "SAV",
        ["avis"], lambda d: d["avis"]["note"].le(2).mean(), "(avis.note <= 2).mean()",
        'Part avis négatifs = DIVIDE ( CALCULATE ( COUNTROWS ( v_fact_avis ), v_fact_avis[sentiment] = "negatif" ), COUNTROWS ( v_fact_avis ) )',
        ["tranche_retard"], 0.0005),
    # ---------------- STOCK & ACHATS
    KPI("K01", "Stock & achats", "Valeur du stock HT (fin de période)", "Valeur du stock au dernier inventaire mensuel de la période.",
        "Somme de valeur_stock_ht au dernier date_sk de la période (un snapshot ne s'additionne pas dans le temps).",
        "bi.v_fact_stock_mensuel", "DT", "≈", "Stock & achats",
        ["stk"], lambda d: d["stk"].loc[d["stk"]["date_sk"].eq(d["stk"]["date_sk"].max()), "valeur_stock_ht"].sum()
        if len(d["stk"]) else np.nan,
        "stk[stk.date_sk == stk.date_sk.max()].valeur_stock_ht.sum()",
        "Valeur stock = CALCULATE ( SUM ( v_fact_stock_mensuel[valeur_stock_ht] ), LASTDATE ( v_dim_date[date] ) )   "
        "-- relation sur date_sk ; avec un filtre par année, LASTDATE donne le 31/12",
        ["categorie"], 1.0),
    KPI("K02", "Stock & achats", "Couverture de stock (j)", "Nombre de jours de ventes couverts par le stock de fin de période.",
        "Stock (quantité) au dernier inventaire / ventes moyennes journalières (quantité) des 90 derniers jours.",
        "bi.v_fact_stock_mensuel + v_fact_mouvements_stock", "j", "≈", "Stock & achats",
        ["stk", "mvt"], _couverture, "stock_fin / (ventes_90j / 90)",
        "Calcul en Python (fenêtre glissante de 90 j) ; en Power BI : DIVIDE ( [Stock fin qté], [Ventes qté 90 j] / 90 ) avec DATESINPERIOD.",
        ["categorie"], 0.5),
    KPI("K03", "Stock & achats", "Rotation du stock (fois/an)", "Coût des ventes annualisé / valeur moyenne du stock.",
        "Coût des ventes = valeur des mouvements de type 'vente' ; stock moyen = moyenne des inventaires mensuels.",
        "bi.v_fact_mouvements_stock + v_fact_stock_mensuel", "ratio", "↑", "Stock & achats",
        ["stk", "mvt"], _rotation, "cout_ventes_annualise / stock_moyen", "Calcul en Python (annualisation).",
        ["categorie"], 0.01),
    KPI("K04", "Stock & achats", "Retard fournisseur moyen (j)", "Retard moyen de réception des bons de commande fournisseurs.",
        "Bons réceptionnés (date de réception connue) ; un bon compté une fois ; retard_appro_j (0 si à l'heure).",
        "bi.v_fact_achats_fournisseur", "j", "↓", "Stock & achats",
        ["ach"], lambda d: _cf_recues(d).drop_duplicates("commande_fournisseur_id")["retard_appro_j"].mean(),
        "ach_recues.drop_duplicates('commande_fournisseur_id').retard_appro_j.mean()",
        "Retard fournisseur = AVERAGEX ( SUMMARIZE ( FILTER ( v_fact_achats_fournisseur, v_fact_achats_fournisseur[date_reception_sk] > 0 ), "
        "v_fact_achats_fournisseur[commande_fournisseur_id], v_fact_achats_fournisseur[retard_appro_j] ), v_fact_achats_fournisseur[retard_appro_j] )",
        ["nom_fournisseur"], 0.01),
    KPI("K05", "Stock & achats", "Taux de rupture fournisseur", "Lignes de bon reçues incomplètes / lignes reçues.",
        "quantite_recue < quantite_commandee, sur les lignes réceptionnées.", "bi.v_fact_achats_fournisseur", "%", "↓",
        "Stock & achats",
        ["ach"], lambda d: (_cf_recues(d)["quantite_recue"] < _cf_recues(d)["quantite_commandee"]).mean(),
        "(recues.quantite_recue < recues.quantite_commandee).mean()",
        "Rupture fournisseur = DIVIDE ( COUNTROWS ( FILTER ( v_fact_achats_fournisseur, v_fact_achats_fournisseur[date_reception_sk] > 0 && "
        "v_fact_achats_fournisseur[quantite_recue] < v_fact_achats_fournisseur[quantite_commandee] ) ), "
        "COUNTROWS ( FILTER ( v_fact_achats_fournisseur, v_fact_achats_fournisseur[date_reception_sk] > 0 ) ) )",
        ["nom_fournisseur"], 0.0005),
    KPI("K06", "Stock & achats", "Taux de service fournisseur", "Quantités reçues / quantités commandées.", "Lignes réceptionnées.",
        "bi.v_fact_achats_fournisseur", "%", "↑", "Stock & achats",
        ["ach"], lambda d: _div(_cf_recues(d)["quantite_recue"].sum(), _cf_recues(d)["quantite_commandee"].sum()),
        "recues.quantite_recue.sum() / recues.quantite_commandee.sum()",
        "Taux de service = DIVIDE ( CALCULATE ( SUM ( v_fact_achats_fournisseur[quantite_recue] ), v_fact_achats_fournisseur[date_reception_sk] > 0 ), "
        "CALCULATE ( SUM ( v_fact_achats_fournisseur[quantite_commandee] ), v_fact_achats_fournisseur[date_reception_sk] > 0 ) )",
        ["nom_fournisseur"], 0.0005),
    # ---------------- MARKETING
    KPI("M01", "Marketing", "Dépense marketing HT", "Somme des dépenses médias.", "Toutes campagnes.",
        "bi.v_fact_marketing_quotidien", "DT", "≈", "Marketing",
        ["mkt"], lambda d: d["mkt"]["depense_ht"].sum(), "mkt.depense_ht.sum()",
        "Dépense HT = SUM ( v_fact_marketing_quotidien[depense_ht] )", ["canal_media"], 1.0),
    KPI("M02", "Marketing", "CPC", "Coût par clic = dépense / clics.", "", "bi.v_fact_marketing_quotidien", "DT", "↓", "Marketing",
        ["mkt"], lambda d: _div(d["mkt"]["depense_ht"].sum(), d["mkt"]["clics"].sum()), "depense.sum() / clics.sum()",
        "CPC = DIVIDE ( [Dépense HT], SUM ( v_fact_marketing_quotidien[clics] ) )", ["canal_media"], 0.001),
    KPI("M03", "Marketing", "CPM", "Coût pour mille impressions.", "", "bi.v_fact_marketing_quotidien", "DT", "↓", "Marketing",
        ["mkt"], lambda d: _div(d["mkt"]["depense_ht"].sum() * 1000, d["mkt"]["impressions"].sum()),
        "depense.sum() * 1000 / impressions.sum()",
        "CPM = DIVIDE ( [Dépense HT] * 1000, SUM ( v_fact_marketing_quotidien[impressions] ) )", ["canal_media"], 0.01),
    KPI("M04", "Marketing", "Taux de clic (CTR)", "Clics / impressions.", "", "bi.v_fact_marketing_quotidien", "%", "↑", "Marketing",
        ["mkt"], lambda d: _div(d["mkt"]["clics"].sum(), d["mkt"]["impressions"].sum()), "clics.sum() / impressions.sum()",
        "CTR = DIVIDE ( SUM ( v_fact_marketing_quotidien[clics] ), SUM ( v_fact_marketing_quotidien[impressions] ) )",
        ["canal_media"], 0.00005),
    KPI("M05", "Marketing", "Taux de conversion", "Commandes attribuées / clics.", "Attribution fournie par la source (dernier clic).",
        "bi.v_fact_marketing_quotidien", "%", "↑", "Marketing",
        ["mkt"], lambda d: _div(d["mkt"]["commandes_attribuees"].sum(), d["mkt"]["clics"].sum()),
        "commandes_attribuees.sum() / clics.sum()",
        "Conversion = DIVIDE ( SUM ( v_fact_marketing_quotidien[commandes_attribuees] ), SUM ( v_fact_marketing_quotidien[clics] ) )",
        ["canal_media"], 0.0005),
    KPI("M06", "Marketing", "Coût d'acquisition client (CAC)", "Dépense / nouveaux clients attribués.", "",
        "bi.v_fact_marketing_quotidien", "DT", "↓", "Marketing",
        ["mkt"], lambda d: _div(d["mkt"]["depense_ht"].sum(), d["mkt"]["nouveaux_clients_attribues"].sum()),
        "depense.sum() / nouveaux_clients_attribues.sum()",
        "CAC = DIVIDE ( [Dépense HT], SUM ( v_fact_marketing_quotidien[nouveaux_clients_attribues] ) )", ["canal_media"], 0.01),
    KPI("M07", "Marketing", "ROAS", "CA attribué TTC / dépense HT.", "Attribution fournie par la source.",
        "bi.v_fact_marketing_quotidien", "ratio", "↑", "Marketing",
        ["mkt"], lambda d: _div(d["mkt"]["ca_attribue_ttc"].sum(), d["mkt"]["depense_ht"].sum()),
        "ca_attribue_ttc.sum() / depense_ht.sum()",
        "ROAS = DIVIDE ( SUM ( v_fact_marketing_quotidien[ca_attribue_ttc] ), [Dépense HT] )", ["canal_media"], 0.001),
    # ---------------- CLIENTS
    KPI("C01", "Clients", "Nouveaux clients", "Clients ayant passé leur première commande sur la période.",
        "est_premiere_commande = 1 ; clients distincts (client_id).", "bi.v_fact_commandes + v_dim_client", "nb", "↑",
        "Direction / Marketing",
        ["cmd"], lambda d: d["cmd"].loc[d["cmd"]["est_premiere_commande"], "client_id"].nunique(),
        "cmd[cmd.est_premiere_commande].client_id.nunique()",
        "Nouveaux clients = CALCULATE ( DISTINCTCOUNT ( v_dim_client[client_id] ), v_fact_commandes[est_premiere_commande] = TRUE () )",
        ["canal"]),
    KPI("C02", "Clients", "Clients actifs", "Clients distincts ayant passé au moins une commande sur la période.",
        "Hors commandes en échec de paiement.", "bi.v_fact_commandes + v_dim_client", "nb", "↑", "Direction",
        ["cmd"], lambda d: _clients_actifs(d)["client_id"].nunique(), "cmd[cmd.statut != 'paiement_echoue'].client_id.nunique()",
        'Clients actifs = CALCULATE ( DISTINCTCOUNT ( v_dim_client[client_id] ), v_dim_statut_commande[statut_commande] <> "paiement_echoue" )',
        ["segment_fidelite", "region"]),
    KPI("C03", "Clients", "Taux de réachat", "Clients actifs ayant passé au moins 2 commandes sur la période / clients actifs.",
        "Hors commandes en échec de paiement.", "bi.v_fact_commandes + v_dim_client", "%", "↑", "Direction / Marketing",
        ["cmd"], lambda d: _clients_actifs(d).groupby("client_id").size().ge(2).mean() if len(_clients_actifs(d)) else np.nan,
        "cmd_actives.groupby('client_id').size().ge(2).mean()",
        'Taux de réachat = DIVIDE ( COUNTROWS ( FILTER ( VALUES ( v_dim_client[client_id] ), CALCULATE ( COUNTROWS ( v_fact_commandes ), '
        'v_dim_statut_commande[statut_commande] <> "paiement_echoue" ) >= 2 ) ), [Clients actifs] )',
        ["segment_fidelite"], 0.0005),
    KPI("C04", "Clients", "CA reconnu par client actif", "CA reconnu TTC / clients actifs.", "", "bi.v_fact_commandes", "DT", "↑",
        "Direction",
        ["cmd"], lambda d: _div(_aboutie(d)["montant_total_ttc"].sum(), _clients_actifs(d)["client_id"].nunique()),
        "V03 / C02", "CA par client = DIVIDE ( [CA reconnu TTC], [Clients actifs] )", ["segment_fidelite"], 0.01),
    KPI("C05", "Clients", "Comptes sans commande", "Clients inscrits n'ayant jamais passé de commande.",
        "Version courante de dim_client, hors membres techniques ; aucune commande dans fact_commandes. Indicateur global (sans axe année).",
        "bi.v_dim_client + v_fact_commandes", "nb", "↓", "Marketing",
        ["cli", "cmd"], lambda d: (~d["cli"]["client_id"].isin(d["cmd"]["client_id"])).sum(),
        "(~cli.client_id.isin(cmd.client_id)).sum()",
        "Sans commande = COUNTROWS ( FILTER ( v_dim_client, v_dim_client[est_courant] = TRUE () && "
        "ISEMPTY ( RELATEDTABLE ( v_fact_commandes ) ) ) )   -- approx. : ne voit que les commandes de la version courante",
        [], 0),
]
KPI_PAR_CODE = {k.code: k for k in CATALOGUE}
KPI_SANS_ANNEE = {"C05"}   # indicateurs globaux uniquement


def _filtrer(p: dict, tables: list[str], col: str, val) -> dict:
    """Filtre les tables utilisées par un KPI sur une modalité d'axe (si la colonne existe)."""
    d = {}
    for t in tables:
        df = p[t]
        d[t] = df[df[col] == val] if col in df.columns and t != "cli" else df
    return d


def calculer_kpi(p: dict, kpis: list[KPI] = CATALOGUE, details: bool = True) -> pd.DataFrame:
    """Calcule chaque KPI en global, par année, et (si details) sur ses axes de détail.
    Renvoie un tableau long : code, domaine, kpi, unite, axe, modalite, valeur."""
    lignes = []
    for k in kpis:
        d = {t: p[t] for t in k.tables}
        lignes.append((k.code, k.domaine, k.nom, k.unite, "global", "Total", k.calcul(d)))
        axes = ([] if k.code in KPI_SANS_ANNEE else ["annee"]) + (k.axes if details else [])
        for ax in axes:
            base = next((p[t] for t in k.tables if ax in p[t].columns), None)
            if base is None:
                continue
            for val in sorted(base[ax].dropna().unique(), key=str):
                v = k.calcul(_filtrer(p, k.tables, ax, val))
                mod = str(int(val)) if ax == "annee" else str(val)
                lignes.append((k.code, k.domaine, k.nom, k.unite, ax, mod, v))
    res = pd.DataFrame(lignes, columns=["code", "domaine", "kpi", "unite", "axe", "modalite", "valeur"])
    res["valeur"] = pd.to_numeric(res["valeur"], errors="coerce")
    return res


def synthese(res: pd.DataFrame) -> pd.DataFrame:
    """Vue « tableau de bord » : une ligne par KPI, colonnes Total / 2023 / 2024 / 2025."""
    s = res[res["axe"].isin(["global", "annee"])].pivot_table(
        index=["code", "domaine", "kpi", "unite"], columns="modalite", values="valeur", aggfunc="first", sort=False)
    s = s.reindex(columns=[c for c in ["Total", "2023", "2024", "2025"] if c in s.columns])
    return s.reset_index()


# ---------------------------------------------------------------------------
# 4. Contrôles de cohérence : tendances attendues du jeu de données
#    (solutions/scenarios_caches.md) — vérifient que les KPI « racontent »
#    ce que le jeu de données a simulé. Ordres de grandeur, avec tolérance.
# ---------------------------------------------------------------------------
@dataclass
class Controle:
    code: str
    description: str
    calcul: Callable[[dict], float]
    attendu: float
    tolerance: float
    unite: str


def _val(p, code, axe="global", modalite="Total"):
    k = KPI_PAR_CODE[code]
    if axe == "global":
        return k.calcul({t: p[t] for t in k.tables})
    return k.calcul(_filtrer(p, k.tables, axe, modalite))


def _retard_sahellog(p, avant: bool):
    liv = p["liv"]
    m = liv["transporteur"].eq("SahelLog") & liv["est_livree"]
    m &= liv["date_expedition_sk"].lt(DATE_BASCULE_SAHELLOG) if avant else liv["date_expedition_sk"].ge(DATE_BASCULE_SAHELLOG)
    return 1 - liv.loc[m, "est_livree_a_temps"].mean()


def _retard_frn025_t2_2024(p):
    a = _cf_recues(p)
    a = a[a["fournisseur_id"].eq("FRN025") & a["trimestre"].eq("2024-T2")]
    return a.drop_duplicates("commande_fournisseur_id")["retard_appro_j"].mean()


def _roas_canal(p, canal):
    return _val(p, "M07", "canal_media", canal)


def _canal_roas_min(p):
    m = p["mkt"].groupby("canal_media")[["ca_attribue_ttc", "depense_ht"]].sum()
    return float((m["ca_attribue_ttc"] / m["depense_ht"]).idxmin() == "tiktok_ads")


def _meilleur_jour(p):
    c = p["cmd"].groupby("date_commande_sk")["montant_total_ttc"].sum()
    return float(c.idxmax() == 20251128)


CONTROLES: list[Controle] = [
    Controle("CC01", "Commandes passées 2023 ≈ 15 100", lambda p: _val(p, "V02", "annee", 2023), 15100, 300, "nb"),
    Controle("CC02", "Commandes passées 2024 ≈ 21 200", lambda p: _val(p, "V02", "annee", 2024), 21200, 300, "nb"),
    Controle("CC03", "Commandes passées 2025 ≈ 30 000", lambda p: _val(p, "V02", "annee", 2025), 30000, 300, "nb"),
    Controle("CC04", "CA commandé TTC 2023 ≈ 4,0 M DT", lambda p: _val(p, "V01", "annee", 2023) / 1e6, 4.0, 0.15, "M DT"),
    Controle("CC05", "CA commandé TTC 2024 ≈ 5,9 M DT", lambda p: _val(p, "V01", "annee", 2024) / 1e6, 5.9, 0.15, "M DT"),
    Controle("CC06", "CA commandé TTC 2025 ≈ 8,4 M DT", lambda p: _val(p, "V01", "annee", 2025) / 1e6, 8.4, 0.15, "M DT"),
    Controle("CC07", "Part application mobile 2023 ≈ 33 %", lambda p: _val(p, "V13", "annee", 2023), 0.33, 0.02, "%"),
    Controle("CC08", "Part application mobile 2025 ≈ 47 %", lambda p: _val(p, "V13", "annee", 2025), 0.47, 0.02, "%"),
    Controle("CC09", "Paiement à la livraison 2023 ≈ 53 %", lambda p: _val(p, "V14", "annee", 2023), 0.53, 0.02, "%"),
    Controle("CC10", "Paiement à la livraison 2025 ≈ 47 %", lambda p: _val(p, "V14", "annee", 2025), 0.47, 0.02, "%"),
    Controle("CC11", "SahelLog : retards ≈ 7 % avant le 01/07/2024", lambda p: _retard_sahellog(p, True), 0.07, 0.03, "%"),
    Controle("CC12", "SahelLog : retards ≈ 37 % après le 01/07/2024", lambda p: _retard_sahellog(p, False), 0.37, 0.04, "%"),
    Controle("CC13", "Poste Colis Plus : retards ≈ 18 %", lambda p: _val(p, "L03", "transporteur", "Poste Colis Plus"), 0.18, 0.03, "%"),
    Controle("CC14", "Retours Mode ≈ 15 % des lignes livrées", lambda p: _val(p, "S01", "categorie", "Mode"), 0.15, 0.02, "%"),
    Controle("CC15", "Retours Épicerie fine < 1 %", lambda p: _val(p, "S01", "categorie", "Épicerie fine"), 0.005, 0.005, "%"),
    Controle("CC16", "FRN025 : retard moyen ≈ 34 j sur les bons du T2 2024", _retard_frn025_t2_2024, 34, 6, "j"),
    Controle("CC17", "ROAS emailing ≈ 5,9 (le meilleur)", lambda p: _roas_canal(p, "emailing"), 5.9, 0.5, "ratio"),
    Controle("CC18", "TikTok a le ROAS le plus faible (1 = vrai)", _canal_roas_min, 1, 0, "booléen"),
    Controle("CC19", "Note moyenne sans retard ≈ 4,1", lambda p: _val(p, "S05", "tranche_retard", "0 j"), 4.1, 0.2, "note"),
    Controle("CC20", "Note moyenne avec retard ≥ 3 j ≈ 2,6", lambda p: _val(p, "S05", "tranche_retard", "3 j et +"), 2.6, 0.3, "note"),
    Controle("CC21", "Comptes sans commande ≈ 3 500", lambda p: _val(p, "C05"), 3500, 250, "nb"),
    Controle("CC22", "Jour le plus fort = Black Friday 28/11/2025 (1 = vrai)", _meilleur_jour, 1, 0, "booléen"),
]


MODALITES_ATTENDUES = {
    ("cmd", "famille_statut"): ["aboutie"],
    ("cmd", "statut_commande"): ["annulee", "livraison_echouee", "paiement_echoue"],
    ("cmd", "canal"): ["application_mobile"],
    ("cmd", "mode_paiement"): ["paiement_a_la_livraison"],
    ("liv", "transporteur"): ["SahelLog", "Poste Colis Plus"],
    ("lig", "categorie"): ["Mode", "Épicerie fine"],
    ("rmb", "type_remboursement"): ["retour"],
    ("rmb", "statut"): ["rembourse", "refuse"],
    ("mkt", "canal_media"): ["emailing", "tiktok_ads"],
    ("ach", "fournisseur_id"): ["FRN025"],
}


def verifier_modalites(p: dict) -> pd.DataFrame:
    """Vérifie que les codes utilisés dans les règles de gestion existent bien dans les vues.
    Une valeur absente = un KPI calculé à 0 ou vide : à corriger avant toute recette."""
    lignes = []
    for (t, col), valeurs in MODALITES_ATTENDUES.items():
        presentes = set(p[t][col].dropna().unique()) if col in p[t].columns else set()
        for val in valeurs:
            lignes.append((t, col, val, "OK" if val in presentes else "ABSENTE"))
    return pd.DataFrame(lignes, columns=["table", "colonne", "valeur attendue", "statut"])


def controler_coherence(p: dict, controles: list[Controle] = CONTROLES) -> pd.DataFrame:
    lignes = []
    for c in controles:
        try:
            v = float(c.calcul(p))
        except Exception as e:                      # un contrôle ne doit pas bloquer les autres
            lignes.append((c.code, c.description, np.nan, c.attendu, c.tolerance, c.unite, f"ERREUR : {e}"))
            continue
        ok = abs(v - c.attendu) <= c.tolerance + 1e-12
        lignes.append((c.code, c.description, v, c.attendu, c.tolerance, c.unite, "CONFORME" if ok else "ÉCART"))
    return pd.DataFrame(lignes, columns=["code", "controle", "valeur", "attendu", "tolerance", "unite", "resultat"])


def recette_dwh(res: pd.DataFrame, chemin_attendus: str, seuil_relatif: float = 0.001) -> pd.DataFrame:
    """Recette niveau 1 : KPI calculés sur le DWH  ↔  mêmes KPI calculés sur donnees_reference.
    OK si l'écart relatif est ≤ seuil (0,1 % par défaut) ; sinon « À EXPLIQUER »."""
    att = pd.read_csv(chemin_attendus, dtype={"modalite": str}, encoding="utf-8-sig")
    r = res.merge(att[["code", "axe", "modalite", "valeur_attendue"]], on=["code", "axe", "modalite"], how="outer")
    r["kpi"] = r["kpi"].fillna(r["code"].map(lambda c: KPI_PAR_CODE[c].nom if c in KPI_PAR_CODE else c))
    r["ecart"] = r["valeur"] - r["valeur_attendue"]
    r["ecart_relatif"] = np.where(r["valeur_attendue"].abs() > 0, r["ecart"] / r["valeur_attendue"].abs(),
                                  np.where(r["ecart"].abs() > 0, np.inf, 0))

    def statut(x):
        if pd.isna(x["valeur"]) and pd.isna(x["valeur_attendue"]):
            return "OK"
        if pd.isna(x["valeur"]) or pd.isna(x["valeur_attendue"]):
            return "ABSENT"
        return "OK" if abs(x["ecart_relatif"]) <= seuil_relatif else "À EXPLIQUER"

    r["statut"] = r.apply(statut, axis=1)
    ordre = {k.code: i for i, k in enumerate(CATALOGUE)}
    r["_o"] = r["code"].map(ordre)
    r["_a"] = r["axe"].map({"global": 0, "annee": 1}).fillna(2)
    r = r.sort_values(["_o", "_a", "axe", "modalite"], kind="stable")
    return r[["code", "kpi", "axe", "modalite", "valeur", "valeur_attendue", "ecart", "ecart_relatif", "statut"]]


# ---------------------------------------------------------------------------
# 5. Export Excel : chiffres de référence + feuilles de recette
# ---------------------------------------------------------------------------
def exporter_excel(res: pd.DataFrame, controles: pd.DataFrame, chemin: str = "kpi_reference.xlsx",
                   rec_dwh: pd.DataFrame | None = None, infos: dict | None = None) -> str:
    """Écrit kpi_reference.xlsx : Synthese, Detail, Controles, Recette (avec formules d'écart)."""
    from openpyxl import Workbook
    from openpyxl.formatting.rule import FormulaRule
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
    from openpyxl.utils import get_column_letter
    from openpyxl.worksheet.datavalidation import DataValidation

    BLEU, GRIS = "1F4E79", "F2F2F2"
    entete = Font(bold=True, color="FFFFFF", name="Arial", size=10)
    fond = PatternFill("solid", fgColor=BLEU)
    saisie = PatternFill("solid", fgColor="FFF2CC")
    normal = Font(name="Arial", size=10)
    fin = Side(style="thin", color="BFBFBF")
    bord = Border(left=fin, right=fin, top=fin, bottom=fin)
    fmt = {"DT": "#,##0.00", "%": "0.00%", "j": "0.00", "nb": "#,##0", "ratio": "0.000", "note": "0.000",
           "M DT": "0.000", "booléen": "0"}

    def ecrire(ws, df, largeurs, ligne0=1):
        for j, c in enumerate(df.columns, 1):
            x = ws.cell(row=ligne0, column=j, value=c)
            x.font, x.fill, x.border = entete, fond, bord
            x.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        for i, row in enumerate(df.itertuples(index=False), ligne0 + 1):
            for j, v in enumerate(row, 1):
                if isinstance(v, float) and np.isnan(v):
                    v = None
                x = ws.cell(row=i, column=j, value=v)
                x.font, x.border = normal, bord
        for j, w in enumerate(largeurs, 1):
            ws.column_dimensions[get_column_letter(j)].width = w
        ws.freeze_panes = ws.cell(row=ligne0 + 1, column=1)

    wb = Workbook()
    # --- Synthèse
    ws = wb.active
    ws.title = "Synthese"
    s = synthese(res)
    ecrire(ws, s, [7, 15, 36, 7] + [16] * (s.shape[1] - 4))
    for i, u in enumerate(s["unite"], 2):
        for j in range(5, s.shape[1] + 1):
            ws.cell(row=i, column=j).number_format = fmt.get(u, "0.00")
    # --- Détail (tous les axes)
    ws = wb.create_sheet("Detail")
    ecrire(ws, res, [7, 15, 36, 7, 18, 26, 16])
    for i, u in enumerate(res["unite"], 2):
        ws.cell(row=i, column=7).number_format = fmt.get(u, "0.00")
    ws.auto_filter.ref = f"A1:G{len(res) + 1}"
    # --- Contrôles de cohérence
    ws = wb.create_sheet("Controles")
    ecrire(ws, controles, [7, 52, 14, 12, 12, 9, 14])
    for i, u in enumerate(controles["unite"], 2):
        for j in (3, 4, 5):
            ws.cell(row=i, column=j).number_format = fmt.get(u, "0.00")
    vert, rouge = PatternFill("solid", fgColor="C6EFCE"), PatternFill("solid", fgColor="FFC7CE")
    plage = f"G2:G{len(controles) + 1}"
    ws.conditional_formatting.add(plage, FormulaRule(formula=['G2="CONFORME"'], fill=vert))
    ws.conditional_formatting.add(plage, FormulaRule(formula=['G2<>"CONFORME"'], fill=rouge))
    # --- Recette niveau 1 : DWH vs donnees_reference
    if rec_dwh is not None:
        ws = wb.create_sheet("Recette_DWH")
        r1 = rec_dwh.replace([np.inf, -np.inf], np.nan)
        ecrire(ws, r1, [7, 34, 18, 26, 16, 16, 13, 12, 14])
        unites = r1["code"].map(lambda c: KPI_PAR_CODE[c].unite if c in KPI_PAR_CODE else "")
        for i, u in enumerate(unites, 2):
            for j in (5, 6, 7):
                ws.cell(row=i, column=j).number_format = fmt.get(u, "0.00")
            ws.cell(row=i, column=8).number_format = "0.000%"
        plage = f"I2:I{len(r1) + 1}"
        ws.conditional_formatting.add(plage, FormulaRule(formula=['I2="OK"'], fill=vert))
        ws.conditional_formatting.add(plage, FormulaRule(formula=['I2<>"OK"'], fill=rouge))
        ws.auto_filter.ref = f"A1:I{len(r1) + 1}"
    # --- Recette niveau 3 : Python (référence) vs Power BI vs Tableau
    ws = wb.create_sheet("Recette")
    rec = res[res["axe"].isin(["global", "annee"])][["code", "kpi", "unite", "axe", "modalite", "valeur"]].copy()
    rec["tolerance"] = rec["code"].map(lambda c: KPI_PAR_CODE[c].tolerance)
    cols = ["Code", "KPI", "Unité", "Axe", "Modalité", "Python (référence)", "Tolérance",
            "Power BI", "Écart Power BI", "Statut Power BI", "Tableau", "Écart Tableau", "Statut Tableau", "Commentaire"]
    for j, c in enumerate(cols, 1):
        x = ws.cell(row=1, column=j, value=c)
        x.font, x.fill, x.border = entete, fond, bord
        x.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    for i, r in enumerate(rec.itertuples(index=False), 2):
        vals = [r.code, r.kpi, r.unite, r.axe, r.modalite, None if pd.isna(r.valeur) else float(r.valeur), float(r.tolerance)]
        for j, v in enumerate(vals, 1):
            ws.cell(row=i, column=j, value=v)
        ws.cell(row=i, column=9, value=f'=IF(H{i}="","",H{i}-F{i})')
        ws.cell(row=i, column=10, value=f'=IF(H{i}="","À saisir",IF(ABS(H{i}-F{i})<=G{i},"OK","ÉCART"))')
        ws.cell(row=i, column=12, value=f'=IF(K{i}="","",K{i}-F{i})')
        ws.cell(row=i, column=13, value=f'=IF(K{i}="","À saisir",IF(ABS(K{i}-F{i})<=G{i},"OK","ÉCART"))')
        f = fmt.get(r.unite, "0.00")
        for j in (6, 7, 8, 9, 11, 12):
            ws.cell(row=i, column=j).number_format = f
        for j in range(1, 15):
            ws.cell(row=i, column=j).font = normal
            ws.cell(row=i, column=j).border = bord
        for j in (8, 11, 14):
            ws.cell(row=i, column=j).fill = saisie
    n = len(rec) + 1
    for col in ("J", "M"):
        ws.conditional_formatting.add(f"{col}2:{col}{n}", FormulaRule(formula=[f'{col}2="OK"'], fill=vert))
        ws.conditional_formatting.add(f"{col}2:{col}{n}", FormulaRule(formula=[f'{col}2="ÉCART"'], fill=rouge))
    for j, w in enumerate([7, 34, 7, 8, 10, 17, 11, 15, 13, 14, 15, 13, 14, 30], 1):
        ws.column_dimensions[get_column_letter(j)].width = w
    ws.freeze_panes = "F2"
    ws.auto_filter.ref = f"A1:N{n}"
    # Bilan de recette en bas de feuille
    b = n + 2
    ws.cell(row=b, column=2, value="Bilan Power BI").font = Font(bold=True, name="Arial")
    ws.cell(row=b, column=6, value=f'=COUNTIF(J2:J{n},"OK")&" OK / "&COUNTIF(J2:J{n},"ÉCART")&" écarts / "&COUNTIF(J2:J{n},"À saisir")&" à saisir"')
    ws.cell(row=b + 1, column=2, value="Bilan Tableau").font = Font(bold=True, name="Arial")
    ws.cell(row=b + 1, column=6, value=f'=COUNTIF(M2:M{n},"OK")&" OK / "&COUNTIF(M2:M{n},"ÉCART")&" écarts / "&COUNTIF(M2:M{n},"À saisir")&" à saisir"')
    # --- Informations d'exécution
    ws = wb.create_sheet("Infos")
    infos = infos or {}
    for i, (k, v) in enumerate({"Généré le": pd.Timestamp.now().strftime("%d/%m/%Y %H:%M"), **infos}.items(), 1):
        ws.cell(row=i, column=1, value=k).font = Font(bold=True, name="Arial")
        ws.cell(row=i, column=2, value=str(v)).font = normal
    ws.column_dimensions["A"].width, ws.column_dimensions["B"].width = 24, 60
    wb.save(chemin)
    return chemin


def catalogue_dataframe() -> pd.DataFrame:
    """Le catalogue sous forme de tableau (sert à générer le dictionnaire des KPI)."""
    return pd.DataFrame([{
        "Code": k.code, "Domaine": k.domaine, "KPI": k.nom, "Définition": k.definition, "Règle de gestion": k.regle,
        "Source (vues bi)": k.source, "Unité": k.unite, "Sens": k.sens, "Page du tableau de bord": k.page,
        "Axes d'analyse": ", ".join((["année"] if k.code not in KPI_SANS_ANNEE else []) + k.axes),
        "Formule Python (pandas)": k.pandas, "Mesure DAX (Power BI)": k.dax, "Tolérance de recette": k.tolerance,
    } for k in CATALOGUE])
