# -*- coding: utf-8 -*-
"""
config.py — tous les réglages du projet d'analyse au même endroit
==================================================================

Si quelque chose change (nom du serveur SQL, dossier, couleur d'un graphique), on le change ICI
et tous les notebooks (EDA, data mining, machine learning) en tiennent compte.

Contenu :
    1. Connexion au DWH (serveur, base, schéma, pilotes ODBC) et à la base des résultats TuniShop_ANALYTICS
    2. Dossiers du projet (05_Data, 06_Exports, 04_Livrables)
    3. Valeurs validées (point de départ contrôlé)
    4. Affichage : style des graphiques, formats de nombres, enregistrement des figures et tableaux
"""
from __future__ import annotations

import os
from pathlib import Path

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import pandas as pd
import seaborn as sns

# =====================================================================================
# 1. Connexion au DWH
# =====================================================================================
SERVEUR = "localhost"          # ton SQL Server 2019 Express ; ex. r"localhost\SQLEXPRESS" si instance nommée
BASE = "TuniShop_DWH"
SCHEMA = "bi"                  # schéma des 23 vues de restitution
# Pilotes ODBC essayés dans cet ordre : le premier installé sur le PC est utilisé
PILOTES = ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server", "SQL Server")

# Base des RÉSULTATS de l'analyse (EDA, data mining, ML), sur le même serveur que le DWH.
# Les notebooks y copient chaque tableau qu'ils enregistrent en fichier (module publication.py).
# Création : script 00_Commun/sql/01_Creer_base_TuniShop_ANALYTICS.sql (à lancer une fois dans SSMS).
BASE_ANALYTICS = "TuniShop_ANALYTICS"
SCHEMA_RESULTATS = "ana"       # tables de résultats écrites par Python (les vues pour Power BI sont dans pbi)
PUBLIER_SQL = True             # False = fichiers seulement (ex. tant que la base n'est pas créée)

# =====================================================================================
# 2. Dossiers du projet
# =====================================================================================
# config.py est dans  TuniShop_Etape7_Analyse/00_Commun/tunishop_analytics/
RACINE = Path(__file__).resolve().parents[2]            # TuniShop_Etape7_Analyse/
COMMUN = RACINE / "00_Commun"
DOSSIER_FEATURES = RACINE / "05_Data" / "features"      # tables de variables (.parquet)
DOSSIER_METADATA = RACINE / "05_Data" / "metadata"      # dictionnaire des variables, lignage
DOSSIER_COPIE = RACINE / "05_Data" / "copie_dwh"        # photo CSV facultative du DWH
DOSSIER_FIGURES = RACINE / "06_Exports" / "Figures"
DOSSIER_TABLES = RACINE / "06_Exports" / "Tables"
DOSSIER_MODELES = RACINE / "06_Exports" / "Modeles"
DOSSIER_PREDICTIONS = RACINE / "06_Exports" / "Predictions"
DOSSIER_LIVRABLES = RACINE / "04_Livrables"

# =====================================================================================
# 3. Valeurs validées (PV du DWH du 28/10/2026 et des cubes du 04/11/2026)
# =====================================================================================
VALEURS_VALIDEES = {
    "Lignes de vente": 115_903,
    "Commandes": 66_268,
    "Livraisons": 61_793,
    "CA reconnu TTC (DT)": 15_541_665.655,
    "Clients ayant commandé (hors membre inconnu)": 12_472,
}

# Dates et version des livrables de chaque phase
DATE_LIVRABLES = {"EDA": "12/11/2026", "Data_Mining": "19/11/2026", "Machine_Learning": "26/11/2026"}
VERSION_LIVRABLES = {"EDA": "1.0", "Data_Mining": "1.0", "Machine_Learning": "1.0"}

# Nombre de lignes attendu pour chaque vue (DWH validé)
LIGNES_ATTENDUES = {
    "v_dim_date": 1828, "v_dim_client": 16002, "v_dim_produit": 1603, "v_dim_fournisseur": 42,
    "v_dim_geographie": 26, "v_dim_entrepot": 5, "v_dim_transporteur": 6, "v_dim_campagne": 154,
    "v_dim_coupon": 70, "v_dim_canal": 8, "v_dim_mode_paiement": 7, "v_dim_statut_commande": 10,
    "v_dim_motif_retour": 14, "v_fact_ventes": 115903, "v_fact_commandes": 66268, "v_fact_paiements": 64491,
    "v_fact_livraisons": 61793, "v_fact_remboursements": 8815, "v_fact_avis": 9314,
    "v_fact_marketing_quotidien": 3427, "v_fact_achats_fournisseur": 11793,
    "v_fact_mouvements_stock": 140184, "v_fact_stock_mensuel": 56562,
}

# =====================================================================================
# 4. Affichage
# =====================================================================================
BLEU, ORANGE, GRIS, VERT, ROUGE = "#1F4E79", "#E07B39", "#8C8C8C", "#2E8B57", "#C0392B"
PALETTE = [BLEU, ORANGE, VERT, "#7B4F9E", "#2A9D8F", "#D4A017", ROUGE, GRIS, "#5DADE2", "#A0522D"]


def appliquer_style() -> None:
    """Style commun de tous les graphiques et de l'affichage des tableaux (à appeler une fois)."""
    sns.set_theme(style="whitegrid", palette=PALETTE, font="DejaVu Sans")
    plt.rcParams.update({"figure.figsize": (10, 4.5), "axes.titleweight": "bold", "axes.titlesize": 12,
                         "axes.spines.top": False, "axes.spines.right": False, "figure.dpi": 100})
    pd.set_option("display.max_columns", 40)
    pd.set_option("display.float_format", lambda v: f"{v:,.3f}".replace(",", " "))


def format_milliers(ax, axe: str = "y", suffixe: str = "") -> None:
    """Affiche 1 234 567 au lieu de 1.234567e6 sur un axe."""
    f = mticker.FuncFormatter(lambda v, _: f"{v:,.0f}".replace(",", " ") + suffixe)
    (ax.yaxis if axe == "y" else ax.xaxis).set_major_formatter(f)


def format_millions(ax, axe: str = "y") -> None:
    """Affiche 4 500 000 sous la forme 4,5 M."""
    f = mticker.FuncFormatter(lambda v, _: f"{v / 1e6:.1f} M".replace(".", ","))
    (ax.yaxis if axe == "y" else ax.xaxis).set_major_formatter(f)


def format_pourcent(ax, axe: str = "y", decimales: int = 0) -> None:
    """Affiche 0.15 sous la forme 15 %."""
    f = mticker.FuncFormatter(lambda v, _: f"{v * 100:.{decimales}f} %".replace(".", ","))
    (ax.yaxis if axe == "y" else ax.xaxis).set_major_formatter(f)


def nombre(v: float, decimales: int = 0) -> str:
    """Nombre au format français : 1 234 567,89."""
    return f"{v:,.{decimales}f}".replace(",", " ").replace(".", ",")


def sauver_figure(fig, nom: str) -> Path:
    """Enregistre la figure dans 06_Exports/Figures/<nom>.png (réutilisée par les rapports)."""
    DOSSIER_FIGURES.mkdir(parents=True, exist_ok=True)
    chemin = DOSSIER_FIGURES / f"{nom}.png"
    fig.savefig(chemin, dpi=150, bbox_inches="tight")
    return chemin


def exporter_table(df: pd.DataFrame, nom: str, index: bool = True) -> Path:
    """Enregistre un tableau de résultats à DEUX endroits :
    1. 06_Exports/Tables/<nom>.csv (séparateur « ; » pour Excel français), comme avant ;
    2. la table ana.<nom> de TuniShop_ANALYTICS (voir publication.nom_table), si PUBLIER_SQL = True.
    """
    DOSSIER_TABLES.mkdir(parents=True, exist_ok=True)
    chemin = DOSSIER_TABLES / f"{nom}.csv"
    df.to_csv(chemin, index=index, sep=";", decimal=",", encoding="utf-8-sig")
    from . import publication                 # import ici pour éviter une boucle d'imports
    publication.publier(df, nom, index=index, source=f"06_Exports/Tables/{nom}.csv")
    return chemin


def exporter_resultat(df: pd.DataFrame, chemin) -> Path:
    """Enregistre un résultat en Parquet (prédictions, règles) puis le copie dans TuniShop_ANALYTICS.

    Remplace df.to_parquet(chemin, index=False) dans les notebooks : même fichier, plus la table SQL.
    """
    chemin = Path(chemin)
    chemin.parent.mkdir(parents=True, exist_ok=True)
    provisoire = chemin.with_suffix(".parquet.tmp")
    df.to_parquet(provisoire, index=False)          # écriture complète puis remplacement
    os.replace(provisoire, chemin)
    from . import publication
    publication.publier(df, chemin.stem, index=False, source=str(chemin.relative_to(RACINE)).replace("\\", "/"))
    return chemin


def exporter_excel(feuilles: dict, chemin, titre_classeur: str = "", auteur: str = "Sarra Abdeljaouad") -> Path:
    """Écrit un classeur Excel mis en forme : une feuille par tableau.

    feuilles = {"nom_feuille": (titre, sous_titre, DataFrame), ...}
    - en-têtes bleus, lignes alternées, colonnes ajustées, volets figés, filtre ;
    - une colonne « statut » est colorée : OK en vert, ÉCART en rouge, INFO en bleu clair.
    """
    from openpyxl import Workbook
    from openpyxl.formatting.rule import FormulaRule
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
    from openpyxl.utils import get_column_letter

    chemin = Path(chemin)
    chemin.parent.mkdir(parents=True, exist_ok=True)
    wb = Workbook()
    wb.remove(wb.active)
    fin = Side(style="thin", color="BFBFBF")
    bord = Border(left=fin, right=fin, top=fin, bottom=fin)
    for nom, (titre, sous_titre, df) in feuilles.items():
        ws = wb.create_sheet(nom[:31])
        ws.sheet_view.showGridLines = False
        ws["A1"] = titre
        ws["A1"].font = Font(name="Arial", size=13, bold=True, color="1F4E79")
        ws["A2"] = sous_titre
        ws["A2"].font = Font(name="Arial", size=9, italic=True, color="5B6B7C")
        df = df.reset_index() if df.index.name else df
        for j, col in enumerate(df.columns, 1):
            c = ws.cell(4, j, str(col))
            c.font = Font(name="Arial", size=10, bold=True, color="FFFFFF")
            c.fill = PatternFill("solid", fgColor="1F4E79")
            c.alignment = Alignment(wrap_text=True, vertical="center")
            c.border = bord
            largeur = max([len(str(col))] + [len(str(v)) for v in df[col].head(200)]) + 2
            ws.column_dimensions[get_column_letter(j)].width = min(max(largeur, 9), 60)
        for i, ligne in enumerate(df.itertuples(index=False), 5):
            for j, v in enumerate(ligne, 1):
                if isinstance(v, (list, tuple)):
                    v = ", ".join(map(str, v))
                elif hasattr(v, "item"):
                    v = v.item()
                if isinstance(v, float) and v != v:
                    v = None
                c = ws.cell(i, j, v)
                c.font = Font(name="Arial", size=10)
                c.border = bord
                c.alignment = Alignment(vertical="top", wrap_text=isinstance(v, str) and len(v) > 50)
                if isinstance(v, float):
                    c.number_format = "0.0%" if str(df.columns[j - 1]).startswith(("part", "taux")) else "#,##0.000"
                elif isinstance(v, int) and not isinstance(v, bool):
                    c.number_format = "#,##0"
                if i % 2 == 0:
                    c.fill = PatternFill("solid", fgColor="F2F6FA")
        if "statut" in df.columns and len(df):
            col = get_column_letter(list(df.columns).index("statut") + 1)
            plage = f"{col}5:{col}{4 + len(df)}"
            for txt, couleur in (("OK", "C6EFCE"), ("ÉCART", "FFC7CE"), ("INFO", "DDEBF7")):
                ws.conditional_formatting.add(plage, FormulaRule(formula=[f'${col}5="{txt}"'],
                                                                 fill=PatternFill("solid", fgColor=couleur)))
        ws.freeze_panes = "A5"
        if len(df):
            ws.auto_filter.ref = f"A4:{get_column_letter(len(df.columns))}{4 + len(df)}"
    wb.properties.creator = auteur
    wb.properties.title = titre_classeur
    wb.save(chemin)
    print("Classeur enregistré :", chemin.relative_to(RACINE))
    return chemin
