#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TuniShop - executer_notebooks.py
=================================
Étape « Analyses et ML » de la chaîne automatisée.

Exécute, dans l'ordre, les notebooks Jupyter de l'étape 7 (EDA, data mining, ML),
sans ouvrir VS Code ni Jupyter. Chaque notebook exécuté est enregistré avec ses
résultats (graphiques, tableaux) dans un dossier daté. Chaque exécution est
journalisée dans TuniShop_ADMIN.audit.execution_notebook.

Utilisé par :
  - SQL Server Agent (mode Windows) : étape « Analyses et ML » du travail
    « TuniShop - Chaine complete » ;
  - SQL Server Agent (mode Airflow) : travail « TuniShop AF - 3 Analyses ML »,
    déclenché par Airflow.

Commandes :
  python executer_notebooks.py lister     -> crée notebooks_a_executer.txt (à relire)
  python executer_notebooks.py tester     -> vérifie la configuration sans rien exécuter
  python executer_notebooks.py executer   -> exécute les notebooks de la liste

Code retour : 0 si tous les notebooks réussissent, 1 sinon. SQL Server Agent
s'appuie sur ce code pour marquer l'étape en succès ou en échec.

Auteure : Sarra Abdeljaouad
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import shutil
import sys
import time
import uuid
from pathlib import Path

# ---------------------------------------------------------------------------
# CONFIGURATION : À ADAPTER À TON PC (ou à passer en variables d'environnement)
# ---------------------------------------------------------------------------
# Dossier racine de l'étape 7 (celui qui contient 00_Commun et les dossiers de notebooks)
RACINE_ANALYSE = Path(os.environ.get("TUNISHOP_RACINE_ANALYSE", r"C:\TuniShop\07_Analyse"))

# Dossier où sont rangés les notebooks exécutés (un sous-dossier daté par exécution)
DOSSIER_SORTIES = Path(os.environ.get("TUNISHOP_SORTIES_NOTEBOOKS", r"C:\TuniShop\08_Automatisation\executions_notebooks"))

# Nombre d'exécutions datées à conserver (les plus anciennes sont supprimées)
NB_EXECUTIONS_CONSERVEES = int(os.environ.get("TUNISHOP_NB_EXECUTIONS", "10"))

# Instance SQL Server qui héberge TuniShop_ADMIN (l'instance Express)
SERVEUR_ADMIN = os.environ.get("TUNISHOP_SERVEUR_ADMIN", "localhost")
BASE_ADMIN = os.environ.get("TUNISHOP_BASE_ADMIN", "TuniShop_ADMIN")

# Noyau Jupyter : « python3 » = le Python qui lance ce script (ton environnement virtuel)
NOYAU = os.environ.get("TUNISHOP_NOYAU", "python3")

# Temps maximum par cellule, en secondes (l'entraînement d'un modèle peut être long)
DELAI_CELLULE = int(os.environ.get("TUNISHOP_DELAI_CELLULE", "3600"))

# Liste ordonnée des notebooks, à côté de ce script
FICHIER_LISTE = Path(__file__).with_name("notebooks_a_executer.txt")

# Sous-dossiers ignorés par la commande « lister »
DOSSIERS_IGNORES = {".ipynb_checkpoints", "_executions", "executions_notebooks", "__pycache__", ".venv", "venv"}


# ---------------------------------------------------------------------------
# Journalisation dans TuniShop_ADMIN
# ---------------------------------------------------------------------------
SQL_TABLE = """
IF SCHEMA_ID(N'audit') IS NULL EXEC(N'CREATE SCHEMA audit');
IF OBJECT_ID(N'audit.execution_notebook', N'U') IS NULL
CREATE TABLE audit.execution_notebook (
    id_ligne        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_execution_notebook PRIMARY KEY,
    id_execution    UNIQUEIDENTIFIER  NOT NULL,
    ordre           INT               NOT NULL,
    notebook        NVARCHAR(400)     NOT NULL,
    date_debut      DATETIME2(0)      NOT NULL,
    date_fin        DATETIME2(0)      NULL,
    duree_secondes  INT               NULL,
    statut          NVARCHAR(20)      NOT NULL,   -- EN_COURS, SUCCES, ECHEC
    message_erreur  NVARCHAR(4000)    NULL,
    notebook_sortie NVARCHAR(600)     NULL,
    lance_par       NVARCHAR(128)     NOT NULL CONSTRAINT DF_execution_notebook_lance_par DEFAULT (SUSER_SNAME())
);
"""


class Journal:
    """Écrit dans audit.execution_notebook. Si la base est injoignable, on continue
    (les notebooks comptent plus que le journal) mais on le signale dans la console."""

    def __init__(self) -> None:
        self.cnx = None
        try:
            import pyodbc  # noqa: WPS433
            pilotes = [p for p in pyodbc.drivers() if "SQL Server" in p]
            pilote = next((p for p in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server") if p in pilotes),
                          pilotes[-1] if pilotes else None)
            if pilote is None:
                raise RuntimeError("aucun pilote ODBC SQL Server installé")
            chaine = (f"DRIVER={{{pilote}}};SERVER={SERVEUR_ADMIN};DATABASE={BASE_ADMIN};"
                      "Trusted_Connection=yes;TrustServerCertificate=yes;")
            self.cnx = pyodbc.connect(chaine, autocommit=True)
            self.cnx.cursor().execute(SQL_TABLE)
        except Exception as exc:  # noqa: BLE001
            print(f"[AVERTISSEMENT] Journal SQL indisponible ({exc}). Exécution sans journal.")
            self.cnx = None

    def debut(self, id_exec: str, ordre: int, notebook: str) -> int | None:
        if not self.cnx:
            return None
        cur = self.cnx.cursor()
        cur.execute("INSERT INTO audit.execution_notebook (id_execution, ordre, notebook, date_debut, statut) "
                    "OUTPUT INSERTED.id_ligne VALUES (?, ?, ?, SYSDATETIME(), N'EN_COURS');",
                    id_exec, ordre, notebook)
        return int(cur.fetchone()[0])

    def fin(self, id_ligne: int | None, statut: str, duree: int, message: str | None, sortie: str | None) -> None:
        if not self.cnx or id_ligne is None:
            return
        self.cnx.cursor().execute(
            "UPDATE audit.execution_notebook SET date_fin = SYSDATETIME(), duree_secondes = ?, statut = ?, "
            "message_erreur = ?, notebook_sortie = ? WHERE id_ligne = ?;",
            duree, statut, (message or "")[:4000] or None, sortie, id_ligne)


# ---------------------------------------------------------------------------
# Liste des notebooks
# ---------------------------------------------------------------------------
def trouver_notebooks() -> list[Path]:
    """Tous les .ipynb sous RACINE_ANALYSE, triés par chemin (les préfixes 01_, 02_... donnent l'ordre)."""
    resultat = []
    for chemin in sorted(RACINE_ANALYSE.rglob("*.ipynb")):
        if any(partie in DOSSIERS_IGNORES for partie in chemin.relative_to(RACINE_ANALYSE).parts):
            continue
        resultat.append(chemin)
    return resultat


def lire_liste() -> list[Path]:
    if not FICHIER_LISTE.exists():
        raise SystemExit(f"Liste absente : {FICHIER_LISTE}. Lance d'abord : python {Path(__file__).name} lister")
    notebooks = []
    for numero, ligne in enumerate(FICHIER_LISTE.read_text(encoding="utf-8").splitlines(), start=1):
        ligne = ligne.strip()
        if not ligne or ligne.startswith("#"):
            continue
        chemin = (RACINE_ANALYSE / ligne).resolve()
        if not chemin.exists():
            raise SystemExit(f"Ligne {numero} de {FICHIER_LISTE.name} : notebook introuvable -> {chemin}")
        notebooks.append(chemin)
    if not notebooks:
        raise SystemExit(f"{FICHIER_LISTE.name} ne contient aucun notebook actif.")
    return notebooks


def commande_lister() -> int:
    if not RACINE_ANALYSE.exists():
        print(f"[ERREUR] Dossier introuvable : {RACINE_ANALYSE}. Corrige RACINE_ANALYSE en haut du script.")
        return 1
    notebooks = trouver_notebooks()
    lignes = [
        "# TuniShop - notebooks exécutés par la chaîne automatisée, dans cet ordre.",
        f"# Chemins relatifs à : {RACINE_ANALYSE}",
        "# Une ligne par notebook. Mets un # devant une ligne pour la désactiver.",
        "# Relis l'ordre : la préparation des données doit passer avant les modèles.",
        "",
    ] + [str(p.relative_to(RACINE_ANALYSE)) for p in notebooks]
    FICHIER_LISTE.write_text("\n".join(lignes) + "\n", encoding="utf-8")
    print(f"{len(notebooks)} notebooks trouvés. Liste écrite dans : {FICHIER_LISTE}")
    for p in notebooks:
        print("  -", p.relative_to(RACINE_ANALYSE))
    return 0


# ---------------------------------------------------------------------------
# Exécution
# ---------------------------------------------------------------------------
def nettoyer_anciennes_executions() -> None:
    if not DOSSIER_SORTIES.exists():
        return
    dossiers = sorted([d for d in DOSSIER_SORTIES.iterdir() if d.is_dir()], reverse=True)
    for ancien in dossiers[NB_EXECUTIONS_CONSERVEES:]:
        shutil.rmtree(ancien, ignore_errors=True)


def commande_tester() -> int:
    ok = True
    print(f"Python utilisé        : {sys.executable}")
    print(f"Racine de l'analyse   : {RACINE_ANALYSE} -> {'OK' if RACINE_ANALYSE.exists() else 'INTROUVABLE'}")
    ok &= RACINE_ANALYSE.exists()
    try:
        import papermill  # noqa: F401
        print("papermill             : OK")
    except ImportError:
        print("papermill             : ABSENT -> pip install papermill ipykernel")
        ok = False
    try:
        from jupyter_client.kernelspec import KernelSpecManager
        noyaux = KernelSpecManager().find_kernel_specs()
        print(f"Noyau « {NOYAU} »      : {'OK' if NOYAU in noyaux else 'ABSENT'} (noyaux vus : {', '.join(noyaux) or 'aucun'})")
        ok &= NOYAU in noyaux
    except Exception as exc:  # noqa: BLE001
        print(f"Noyaux Jupyter        : erreur ({exc})")
        ok = False
    journal = Journal()
    print(f"Journal TuniShop_ADMIN: {'OK' if journal.cnx else 'INDISPONIBLE'}")
    if FICHIER_LISTE.exists():
        try:
            print(f"Liste des notebooks   : {len(lire_liste())} notebooks actifs")
        except SystemExit as exc:
            print(f"Liste des notebooks   : {exc}")
            ok = False
    else:
        print("Liste des notebooks   : absente -> lance « lister »")
        ok = False
    print("\nRÉSULTAT :", "PRÊT" if ok else "À CORRIGER")
    return 0 if ok else 1


def commande_executer(arreter_au_premier_echec: bool) -> int:
    import papermill as pm

    notebooks = lire_liste()
    id_exec = str(uuid.uuid4())
    horodatage = dt.datetime.now().strftime("%Y-%m-%d_%H%M%S")
    dossier = DOSSIER_SORTIES / horodatage
    dossier.mkdir(parents=True, exist_ok=True)
    journal = Journal()

    print(f"Exécution {id_exec} - {len(notebooks)} notebooks - sorties : {dossier}")
    echecs = 0
    for ordre, notebook in enumerate(notebooks, start=1):
        relatif = str(notebook.relative_to(RACINE_ANALYSE))
        sortie = dossier / relatif
        sortie.parent.mkdir(parents=True, exist_ok=True)
        print(f"[{ordre}/{len(notebooks)}] {relatif} ...", flush=True)
        id_ligne = journal.debut(id_exec, ordre, relatif)
        debut = time.monotonic()
        try:
            pm.execute_notebook(
                input_path=str(notebook),
                output_path=str(sortie),
                kernel_name=NOYAU,
                cwd=str(notebook.parent),          # les imports relatifs (00_Commun) restent valides
                execution_timeout=DELAI_CELLULE,
                progress_bar=False,
                log_output=False,
            )
            duree = int(time.monotonic() - debut)
            journal.fin(id_ligne, "SUCCES", duree, None, str(sortie))
            print(f"    SUCCES ({duree} s)")
        except Exception as exc:  # noqa: BLE001
            duree = int(time.monotonic() - debut)
            message = f"{type(exc).__name__}: {exc}"
            journal.fin(id_ligne, "ECHEC", duree, message, str(sortie))
            print(f"    ECHEC ({duree} s) : {message[:1500]}")
            echecs += 1
            if arreter_au_premier_echec:
                print("Arrêt : les notebooks suivants dépendent peut-être de celui-ci.")
                break

    nettoyer_anciennes_executions()
    print(f"\nBILAN : {len(notebooks)} notebooks prévus, {echecs} en échec.")
    return 1 if echecs else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="TuniShop - exécution automatique des notebooks d'analyse et de ML")
    parser.add_argument("commande", choices=["lister", "tester", "executer"])
    parser.add_argument("--continuer-si-echec", action="store_true",
                        help="exécute les notebooks suivants même si l'un échoue (par défaut : arrêt)")
    args = parser.parse_args()
    if args.commande == "lister":
        return commande_lister()
    if args.commande == "tester":
        return commande_tester()
    return commande_executer(arreter_au_premier_echec=not args.continuer_si_echec)


if __name__ == "__main__":
    sys.exit(main())
