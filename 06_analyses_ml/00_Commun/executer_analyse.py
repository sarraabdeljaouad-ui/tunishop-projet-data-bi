# -*- coding: utf-8 -*-
"""
executer_analyse.py — exécute les notebooks de l'analyse dans l'ordre, sans ouvrir Jupyter
=========================================================================================

Utilisé par l'étape « Analyse et publication » du job SQL Server Agent (script
00_Commun/sql/07_Etape_job_Agent.sql), ou à la main dans un terminal :

    python executer_analyse.py                 # tout : EDA, data mining, ML, publication
    python executer_analyse.py ml publication  # seulement le ML puis la publication

Chaque notebook est exécuté sur place (ses résultats et graphiques sont enregistrés dedans),
il lit le DWH et écrit ses résultats en fichiers ET dans TuniShop_ANALYTICS.
Au premier notebook en erreur, le script s'arrête avec le code 1 : le job SQL Agent passe
alors en échec et la publication suivante n'a pas lieu.

Journal (v1.3) : chaque exécution est tracée
  - dans 06_Exports/Journaux/execution_AAAAMMJJ_HHMM.log (détail, dont l'erreur complète) ;
  - dans 06_Exports/Journaux/journal_executions.csv (une ligne par notebook : date, statut, durée) ;
  - dans la table ctl.journal_execution de TuniShop_ANALYTICS (script sql/08), lue depuis
    TuniShop_ADMIN par la vue audit.v_execution_analytics (script sql/06).
  Le journal SQL est « au mieux » : s'il est indisponible, l'exécution continue et le message
  est écrit dans le .log. Les fichiers restent la trace de secours.
"""
import csv
import datetime as dt
import os
import platform
import subprocess
import sys
import time
from pathlib import Path

COMMUN = Path(__file__).resolve().parent              # 00_Commun/
RACINE = COMMUN.parent                                # TuniShop_Etape7_Analyse/
sys.path.insert(0, str(COMMUN))                       # chemin absolu : marche quel que soit le dossier courant
JOURNAUX = RACINE / "06_Exports" / "Journaux"
DEBUT = dt.datetime.now()
JOURNAUX.mkdir(parents=True, exist_ok=True)
FICHIER_LOG = JOURNAUX / f"execution_{DEBUT:%Y%m%d_%H%M}.log"
FICHIER_CSV = JOURNAUX / "journal_executions.csv"
ID_EXECUTION = f"{DEBUT:%Y%m%d_%H%M%S}"               # regroupe les lignes d'un même lancement
_connexion_sql = None                                 # connexion au journal SQL (ouverte au 1er besoin)
_sql_indisponible = False                             # True après un échec : on n'essaie plus


def ecrire(texte: str) -> None:
    """Affiche le texte et l'ajoute au fichier .log de l'exécution."""
    print(texte, flush=True)
    with open(FICHIER_LOG, "a", encoding="utf-8") as f:
        f.write(texte + "\n")


def _connexion_journal():
    """Connexion à TuniShop_ANALYTICS pour le journal (authentification Windows), ou None.

    Renvoie None, sans lever d'erreur, si la publication SQL est coupée (config.PUBLIER_SQL,
    TUNISHOP_PUBLIER_SQL=0), en mode test (TUNISHOP_BASE_TEST) ou si la connexion échoue.
    """
    global _connexion_sql, _sql_indisponible
    if _connexion_sql is not None or _sql_indisponible:
        return _connexion_sql
    try:
        from tunishop_analytics import config
        if (not config.PUBLIER_SQL or os.environ.get("TUNISHOP_PUBLIER_SQL", "1") == "0"
                or os.environ.get("TUNISHOP_BASE_TEST")):
            _sql_indisponible = True
            return None
        import pyodbc
        installes = pyodbc.drivers()
        pilote = next((p for p in config.PILOTES if p in installes), None)
        if pilote is None:
            raise RuntimeError("aucun pilote ODBC SQL Server installé")
        cs = (f"DRIVER={{{pilote}}};SERVER={config.SERVEUR};DATABASE={config.BASE_ANALYTICS};"
              "Trusted_Connection=yes;")
        if pilote.startswith("ODBC Driver 18"):
            cs += "Encrypt=yes;TrustServerCertificate=yes;"
        _connexion_sql = pyodbc.connect(cs, timeout=15, autocommit=True)
    except Exception as e:                            # le journal ne doit jamais bloquer l'analyse
        _sql_indisponible = True
        ecrire(f"ATTENTION journal SQL indisponible (fichiers seulement) : {e}")
    return _connexion_sql


def tracer_sql(phase: str, notebook: str, statut: str, debut: dt.datetime, duree: float,
               message: str | None) -> None:
    """Ajoute une ligne à ctl.journal_execution (au mieux : une erreur est notée dans le .log)."""
    global _sql_indisponible
    cn = _connexion_journal()
    if cn is None:
        return
    try:
        cn.cursor().execute(
            "INSERT INTO ctl.journal_execution (id_execution, phase, notebook, statut, debut, fin, "
            "duree_s, message, machine) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [ID_EXECUTION, phase, notebook, statut, debut.replace(microsecond=0),
             dt.datetime.now().replace(microsecond=0), round(duree),
             message[-4000:] if message else None, platform.node()])
    except Exception as e:
        _sql_indisponible = True
        ecrire(f"ATTENTION écriture du journal SQL impossible (script sql/08 lancé ?) : {e}")


def tracer(phase: str, notebook: str, statut: str, debut: dt.datetime, duree: float,
           message: str | None = None) -> None:
    """Trace un notebook : journal CSV (séparateur « ; » pour Excel) puis table SQL."""
    nouveau = not FICHIER_CSV.exists()
    with open(FICHIER_CSV, "a", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f, delimiter=";")
        if nouveau:
            w.writerow(["execution", "notebook", "statut", "duree_s", "fin"])
        w.writerow([f"{DEBUT:%Y-%m-%d %H:%M}", notebook, statut, round(duree), f"{dt.datetime.now():%Y-%m-%d %H:%M:%S}"])
    tracer_sql(phase, notebook, statut, debut, duree, message)

PHASES = {
    "eda": ["01_EDA/01_EDA_Global", "01_EDA/02_EDA_Sales", "01_EDA/03_EDA_Customers", "01_EDA/04_EDA_Products",
            "01_EDA/05_EDA_Stock_Logistics", "01_EDA/06_EDA_Marketing_Finance"],
    "dm": ["02_Data_Mining/01_Segmentation_RFM", "02_Data_Mining/02_Clustering_Clients",
           "02_Data_Mining/03_Association_Produits", "02_Data_Mining/04_Analyse_Comportement_Achat",
           "02_Data_Mining/05_Text_Mining_Avis"],
    "ml": ["03_Machine_Learning/01_Preparation_Datasets_ML", "03_Machine_Learning/02_Prevision_Ventes",
           "03_Machine_Learning/03_Prediction_Churn", "03_Machine_Learning/04_Prediction_Demande",
           "03_Machine_Learning/06_Prediction_Retard_Livraison", "03_Machine_Learning/05_Evaluation_Modeles",
           "03_Machine_Learning/08_Scoring_Actuel", "03_Machine_Learning/09_Suivi_Modeles"],
    "publication": ["03_Machine_Learning/07_Publication_Resultats"],
}


def executer(phase: str, notebook: str) -> bool:
    chemin = RACINE / f"{notebook}.ipynb"
    horodatage = dt.datetime.now()
    debut = time.time()
    # jupyter nbconvert : exécute toutes les cellules ; le dossier de travail est celui du notebook
    commande = [sys.executable, "-m", "jupyter", "nbconvert", "--to", "notebook", "--execute", "--inplace",
                "--ExecutePreprocessor.timeout=1800", str(chemin)]
    resultat = subprocess.run(commande, cwd=chemin.parent, capture_output=True, text=True)
    duree = time.time() - debut
    if resultat.returncode == 0:
        ecrire(f"OK      {notebook}  ({duree:.0f} s)")
        tracer(phase, notebook, "OK", horodatage, duree)
        return True
    ecrire(f"ERREUR  {notebook}  ({duree:.0f} s)\n{resultat.stderr[-3000:]}")
    tracer(phase, notebook, "ERREUR", horodatage, duree, resultat.stderr)
    return False


def main(arguments: list[str]) -> int:
    phases = [a.lower() for a in arguments] or list(PHASES)
    inconnues = [p for p in phases if p not in PHASES]
    if inconnues:
        print("Phases inconnues :", inconnues, "— choix possibles :", list(PHASES))
        return 2
    ecrire(f"Analyse TuniShop — {time.strftime('%d/%m/%Y %H:%M')} — phases : {', '.join(phases)}")
    for phase in phases:
        for notebook in PHASES[phase]:
            if not executer(phase, notebook):
                ecrire(f"Arrêt : voir le détail dans {FICHIER_LOG.relative_to(RACINE)}")
                return 1
    ecrire("Terminé : résultats publiés dans TuniShop_ANALYTICS.")
    if _connexion_sql is not None:
        _connexion_sql.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
