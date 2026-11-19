# -*- coding: utf-8 -*-
"""
documentation.py — met à jour le lignage et le dictionnaire jusqu'à Power BI
=============================================================================

Data_Lineage.xlsx et Dictionnaire_Variables.xlsx (05_Data/metadata) sont écrits par 01_EDA_Global
pour les tables de variables. Cette fonction AJOUTE (ou remplace) les feuilles qui décrivent la suite
de la chaîne, en relisant les objets réels du projet (rien n'est recopié à la main) :

    Data_Lineage.xlsx
        07_Fichiers_vers_ANALYTICS   fichier de résultats -> notebook -> table ana.* -> vues pbi.*
        08_Vues_vers_PowerBI         vue pbi.* -> tables sources (ana.*, TuniShop_DWH.bi.*) -> visuels Power BI
    Dictionnaire_Variables.xlsx
        10_Tables_ANALYTICS          chaque colonne de chaque table ana.* (type SQL, clé, source)
        11_Vues_PowerBI              chaque colonne des vues pbi.* telle que Power BI la charge (type)
        12_Mesures_DAX               chaque mesure du tableau de bord (formule, format, dossier)

Sources relues : 05_Data/metadata/Schema_Base_Analytics.json (tables publiées), 00_Commun/sql/03_Vues_pbi_Power_BI.sql
(vues), 07_PowerBI (modèle et visuels du rapport). Appelée à la fin de 07_Publication_Resultats.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import pandas as pd

from . import config, publication

NOTEBOOK_DE = {"Q01": "02_EDA_Sales", "Q02": "02_EDA_Sales", "Q09": "02_EDA_Sales", "Q05": "03_EDA_Customers",
               "Q06": "03_EDA_Customers", "Q07": "03_EDA_Customers", "Q08": "03_EDA_Customers", "Q15": "03_EDA_Customers",
               "Q18": "03_EDA_Customers", "Q03": "04_EDA_Products", "Q04": "04_EDA_Products", "Q16": "04_EDA_Products",
               "Q13": "05_EDA_Stock_Logistics", "Q14": "05_EDA_Stock_Logistics", "Q19": "05_EDA_Stock_Logistics",
               "Q20": "05_EDA_Stock_Logistics", "Q21": "05_EDA_Stock_Logistics", "Q10": "06_EDA_Marketing_Finance",
               "Q11": "06_EDA_Marketing_Finance", "Q12": "06_EDA_Marketing_Finance", "Q17": "06_EDA_Marketing_Finance",
               "G03": "01_EDA_Global", "G04": "01_EDA_Global", "EDA00": "01_EDA_Global", "EDA": "02 à 06 (01_EDA)",
               "DM01": "01_Segmentation_RFM", "DM02": "02_Clustering_Clients", "DM03": "03_Association_Produits",
               "DM04": "04_Analyse_Comportement_Achat", "ML01": "01_Preparation_Datasets_ML", "ML02": "02_Prevision_Ventes",
               "ML03": "03_Prediction_Churn", "ML04": "04_Prediction_Demande", "ML06": "06_Prediction_Retard_Livraison",
               "ML08": "08_Scoring_Actuel", "segments_rfm": "01_Segmentation_RFM", "clusters_clients": "02_Clustering_Clients",
               "regles_association": "03_Association_Produits", "ventes": "02_Prevision_Ventes", "churn": "03_Prediction_Churn",
               "demande": "04_Prediction_Demande", "retard": "06_Prediction_Retard_Livraison",
               "ML_metriques_ventes": "02_Prevision_Ventes", "ML_metriques_churn": "03_Prediction_Churn",
               "ML_metriques_demande": "04_Prediction_Demande", "ML_metriques_retard": "06_Prediction_Retard_Livraison",
               "ML_registre_modeles": "08_Scoring_Actuel", "ML_suivi": "09_Suivi_Modeles"}
FICHIER_SQL = config.COMMUN / "sql" / "03_Vues_pbi_Power_BI.sql"
DOSSIER_PBI = config.RACINE / "07_PowerBI"


def _notebook(source: str) -> str:
    nom = Path(source).stem
    for cle in (nom, nom.split("_")[0], nom.replace("_2025_test", "").replace("_scores_actuels", "").replace("_scores_en_cours", "")):
        if cle in NOTEBOOK_DE:
            return NOTEBOOK_DE[cle]
    if nom in ("churn_scores_actuels", "retard_scores_en_cours"):
        return "08_Scoring_Actuel"
    return NOTEBOOK_DE.get(nom.split("_")[0], "")


def vues_pbi() -> dict:
    """Vues du script 03 : {vue: {"sources": [...], "description": "..."}} (lecture du SQL)."""
    texte = FICHIER_SQL.read_text(encoding="utf-8")
    vues = {}
    for bloc in re.split(r"^\s*GO\s*$", texte, flags=re.M):
        m = re.search(r"CREATE OR ALTER VIEW\s+(pbi\.\w+)", bloc)
        if not m:
            continue
        avant = bloc[:m.start()].strip().splitlines()
        description = " ".join(l.strip("- ").strip() for l in avant if l.strip().startswith("--") and "*/" not in l)
        sources = sorted(set(re.findall(r"(?:FROM|JOIN)\s+((?:TuniShop_DWH\.)?(?:ana|bi|ctl)\.\w+)", bloc)))
        vues[m.group(1)] = {"sources": sources, "description": description}
    return vues


def visuels_powerbi() -> pd.DataFrame:
    """Visuels du rapport Power BI (07_PowerBI) : page, titre, champs utilisés (table.champ)."""
    lignes = []
    for page_json in sorted(DOSSIER_PBI.glob("*.Report/definition/pages/*/page.json")):
        page = json.loads(page_json.read_text(encoding="utf-8"))["displayName"]
        for vj in sorted(page_json.parent.glob("visuals/*/visual.json")):
            v = json.loads(vj.read_text(encoding="utf-8"))["visual"]
            titre = v.get("visualContainerObjects", {}).get("title", [{}])[0].get("properties", {}).get("text", {}) \
                     .get("expr", {}).get("Literal", {}).get("Value", "''")[1:-1].replace("''", "'")
            for ps in v["query"]["queryState"].values():
                for pr in ps["projections"]:
                    lignes.append({"page": page, "visuel": vj.parent.name, "type": v["visualType"], "titre": titre,
                                   "table": pr["queryRef"].split(".")[0], "champ": pr["nativeQueryRef"]})
    return pd.DataFrame(lignes)


def modele_powerbi() -> dict:
    bim = next(DOSSIER_PBI.glob("*.SemanticModel/model.bim"), None)
    return json.loads(bim.read_text(encoding="utf-8")) if bim else {"model": {"tables": []}}


def documenter() -> None:
    """Ajoute les feuilles ANALYTICS et Power BI au lignage et au dictionnaire (05_Data/metadata)."""
    import openpyxl
    schema = json.loads((config.DOSSIER_METADATA / "Schema_Base_Analytics.json").read_text(encoding="utf-8"))
    vues, visuels, bim = vues_pbi(), visuels_powerbi(), modele_powerbi()
    mesures = [(t["name"], m) for t in bim["model"]["tables"] for m in t.get("measures", [])]

    # Lignage 07 : fichier -> notebook -> table -> vues
    l7 = []
    for table, info in schema.items():
        lues_par = [v for v, d in vues.items() if f"ana.{table}" in d["sources"]]
        for source in info["sources"]:
            l7.append({"fichier_resultat": source, "notebook": _notebook(source), "table_analytics": f"ana.{table}",
                       "lignes": info["lignes"], "vues_pbi": ", ".join(lues_par) or "—"})
    l7 = pd.DataFrame(l7).drop_duplicates(subset=["fichier_resultat", "table_analytics"])
    # Lignage 08 : vue -> sources -> visuels
    l8 = []
    for vue, d in vues.items():
        nom = vue.split(".")[1]
        vis = visuels[visuels["table"] == nom] if len(visuels) else visuels
        l8.append({"vue_pbi": vue, "sources": ", ".join(d["sources"]), "description": d["description"][:200],
                   "pages_power_bi": ", ".join(sorted(vis["page"].unique())) if len(vis) else "—",
                   "visuels": len(vis["visuel"].unique()) if len(vis) else 0})
    l8 = pd.DataFrame(l8)
    # Dictionnaire 10 : colonnes des tables ana
    d10 = pd.DataFrame([{"table": f"ana.{t}", "colonne": c, "type_sql": ty, "null_autorise": "oui" if nul else "non",
                         "cle": "oui" if c in info.get("cle", []) else "", "lignes_table": info["lignes"],
                         "source": "; ".join(info["sources"])[:150]}
                        for t, info in schema.items() for c, ty, nul in info["colonnes"]])
    # Dictionnaire 11 : colonnes des vues telles que Power BI les charge
    d11 = pd.DataFrame([{"vue_pbi": f"pbi.{t['name']}", "colonne": c["name"], "type_power_bi": c["dataType"],
                         "format": c.get("formatString", ""), "masquee": "oui" if c.get("isHidden") else "",
                         "description_table": t.get("description", "")}
                        for t in bim["model"]["tables"] if t["name"] != "Mesures" for c in t["columns"]])
    # Dictionnaire 12 : mesures DAX
    d12 = pd.DataFrame([{"dossier": m.get("displayFolder", ""), "mesure": m["name"], "formule_dax": m["expression"],
                         "format": m.get("formatString", ""),
                         "visuels": int((visuels["champ"] == m["name"]).sum()) if len(visuels) else 0} for _, m in mesures])

    def remplacer(chemin, feuilles):
        wb = openpyxl.load_workbook(chemin)
        for nom in feuilles:
            if nom in wb.sheetnames:
                del wb[nom]
        wb.save(chemin)
        tmp = chemin.with_name("_tmp_" + chemin.name)
        config.exporter_excel(feuilles, tmp, "")
        source = openpyxl.load_workbook(tmp)
        wb = openpyxl.load_workbook(chemin)
        for nom in feuilles:                              # copie cellule par cellule (valeurs + styles)
            ws_s, ws = source[nom], wb.create_sheet(nom[:31])
            for ligne in ws_s.iter_rows():
                for c in ligne:
                    n = ws.cell(c.row, c.column, c.value)
                    if c.has_style:
                        n._style = c._style
            for col, dim in ws_s.column_dimensions.items():
                ws.column_dimensions[col].width = dim.width
            ws.freeze_panes = ws_s.freeze_panes
            ws.sheet_view.showGridLines = False
            ws.conditional_formatting = ws_s.conditional_formatting
        wb.save(chemin)
        tmp.unlink()

    lig = config.DOSSIER_METADATA / "Data_Lineage.xlsx"
    dic = config.DOSSIER_METADATA / "Dictionnaire_Variables.xlsx"
    remplacer(lig, {
        "07_Fichiers_vers_ANALYTICS": ("Fichiers de résultats -> TuniShop_ANALYTICS -> vues Power BI",
                                       "Chaque résultat est écrit en fichier ET dans une table ana (module publication)", l7),
        "08_Vues_vers_PowerBI": ("Vues pbi -> sources -> rapport Power BI",
                                 "Sources lues dans 03_Vues_pbi_Power_BI.sql ; visuels lus dans 07_PowerBI", l8)})
    remplacer(dic, {
        "10_Tables_ANALYTICS": (f"Colonnes des {len(schema)} tables ana de TuniShop_ANALYTICS",
                                "Structure réelle des tables publiées (Schema_Base_Analytics.json)", d10),
        "11_Vues_PowerBI": ("Colonnes des vues pbi chargées par Power BI", "Modèle TuniShop_Analyse_ML (model.bim)", d11),
        "12_Mesures_DAX": (f"Les {len(d12)} mesures DAX du tableau de bord", "Table « Mesures » du modèle Power BI", d12)})
    print(f"Lignage et dictionnaire mis à jour : {len(l7)} fichiers -> tables, {len(l8)} vues, "
          f"{len(d10)} colonnes ana, {len(d11)} colonnes Power BI, {len(d12)} mesures")
