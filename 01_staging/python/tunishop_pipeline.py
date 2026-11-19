#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TuniShop — tunishop_pipeline.py
================================
Alimente les trois bases de staging SQL Server à partir des fichiers bruts :

    donnees_brutes/  --(Python)-->  TuniShop_STG_RAW  --(procédures SQL)-->  TuniShop_STG_CLEAN  -->  TuniShop_STG_INTEGRATED

Python lit les 92 fichiers (CSV « , » et « ; », 72 fichiers mensuels, JSON Lines), les charge tels quels
dans STG_RAW, puis déclenche les procédures stockées qui nettoient (CLEAN) et intègrent (INTEGRATED).
Chaque exécution est un « lot » (id_chargement) tracé dans la base de contrôle TuniShop_ADMIN (schéma audit).

Chargement INCRÉMENTAL : STG_RAW est rechargé en entier (zone d'atterrissage), mais STG_CLEAN et
STG_INTEGRATED ne sont jamais vidés. Les procédures fusionnent (MERGE) chaque ligne :
    clé absente        → INSERT
    empreinte modifiée → UPDATE
    rien n'a changé    → ligne non touchée
    clé disparue       → selon --suppression : marquer (est_supprime = 1, défaut) | supprimer | ignorer

Prérequis (dans SSMS, dans cet ordre) :
    sql/01_Creation_Bases.sql
    sql/02_Audit_Logs.sql
    sql/03_Procedures_CLEAN_INTEGRATED.sql
    (ou :  python tunishop_pipeline.py deployer --sql ../sql)

Utilisation :
    python tunishop_pipeline.py tester                     # connexion + présence des bases
    python tunishop_pipeline.py tout   --dossier <donnees_brutes>   # RAW + CLEAN + INTEGRATED + bilan
    python tunishop_pipeline.py raw    --dossier <donnees_brutes>   # étape par étape
    python tunishop_pipeline.py clean  --lot 1
    python tunishop_pipeline.py integ  --lot 1
    python tunishop_pipeline.py bilan  --lot 1
    python tunishop_pipeline.py reference --dossier-ref <donnees_reference>   # copie la référence dans TuniShop_ADMIN.ref
    python tunishop_pipeline.py valider                    # rapports de validation et décision de fin de phase
    python tunishop_pipeline.py raw    --dossier <donnees_brutes> --simulation   # lecture seule, sans SQL

Connexion : --serveur (défaut localhost), authentification Windows par défaut,
            ou --auth sql --utilisateur sa  (mot de passe dans la variable d'environnement TUNISHOP_MDP).

Dépendances : pip install pandas pyodbc      +  pilote « ODBC Driver 17 ou 18 for SQL Server »
"""
from __future__ import annotations

import argparse
import glob
import hashlib
import logging
import os
import re
import sys
import time
from dataclasses import dataclass

import pandas as pd

# ---------------------------------------------------------------------------
# Paramètres
# ---------------------------------------------------------------------------
DB_RAW, DB_CLEAN, DB_INTEG, DB_DWH = "TuniShop_STG_RAW", "TuniShop_STG_CLEAN", "TuniShop_STG_INTEGRATED", "TuniShop_DWH"
DB_ADMIN = "TuniShop_ADMIN"   # base de contrôle : schéma audit (lots, tâches, erreurs) ; base de connexion du script
TAILLE_LOT = 5_000          # lignes par envoi (fast_executemany)
MODES_SUPPRESSION = ("marquer", "supprimer", "ignorer")

@dataclass(frozen=True)
class Source:
    table: str          # table cible raw.<table>
    motif: str          # chemin (glob) relatif au dossier donnees_brutes
    format: str = "csv" # csv | jsonl

SOURCES = [
    Source("categories", "catalogue/categories.csv"),
    Source("fournisseurs", "catalogue/fournisseurs.csv"),
    Source("produits", "catalogue/produits.csv"),
    Source("produits_prix_historique", "catalogue/produits_prix_historique.csv"),
    Source("clients", "crm/clients.csv"),
    Source("entrepots", "logistique/entrepots.csv"),
    Source("transporteurs", "logistique/transporteurs.csv"),
    Source("livraisons", "logistique/livraisons.csv"),
    Source("campagnes_marketing", "marketing/campagnes_marketing.csv"),
    Source("coupons", "marketing/coupons.csv"),
    Source("marketing_depenses_quotidiennes", "marketing/marketing_depenses_quotidiennes.csv"),
    Source("dim_calendrier", "referentiels/dim_calendrier.csv"),
    Source("ref_gouvernorats", "referentiels/ref_gouvernorats.csv"),
    Source("remboursements", "sav/remboursements.csv"),
    Source("mouvements_stock", "stocks/mouvements_stock.csv"),
    Source("stocks_mensuels", "stocks/stocks_mensuels.csv"),
    Source("commandes_fournisseurs", "achats/commandes_fournisseurs.csv"),
    Source("lignes_commande_fournisseur", "achats/lignes_commande_fournisseur.csv"),
    Source("avis_clients", "avis/avis_clients.csv"),
    Source("commandes", "ventes/commandes/commandes_*.csv"),
    Source("lignes_commande", "ventes/lignes_commande/lignes_commande_*.csv"),
    Source("paiements_api", "paiements_api/paiements.jsonl", "jsonl"),
]

# Ordre d'appel des procédures clean.usp_charger_<table> (produits_prix_historique avant produits : règle QR18)
ORDRE_CLEAN = ["categories", "fournisseurs", "produits_prix_historique", "produits", "ref_gouvernorats", "entrepots",
               "transporteurs", "dim_calendrier", "clients", "campagnes_marketing", "coupons", "marketing_depenses_quotidiennes",
               "commandes", "lignes_commande", "paiements", "livraisons", "remboursements", "avis_clients",
               "commandes_fournisseurs", "lignes_commande_fournisseur", "mouvements_stock", "stocks_mensuels"]

# Volumes attendus, mesurés sur le jeu donnees_brutes lors de la conception (contrôle de bon sens)
ATTENDUS = {
 "raw": {"categories": 19, "fournisseurs": 40, "produits": 596, "produits_prix_historique": 1601, "clients": 16150, "entrepots": 3,
         "transporteurs": 4, "livraisons": 61793, "campagnes_marketing": 152, "coupons": 68, "marketing_depenses_quotidiennes": 3427,
         "dim_calendrier": 1096, "ref_gouvernorats": 24, "remboursements": 8815, "mouvements_stock": 140284, "stocks_mensuels": 56562,
         "commandes_fournisseurs": 10370, "lignes_commande_fournisseur": 11793, "avis_clients": 9344, "commandes": 66568,
         "lignes_commande": 116023, "paiements_api": 65137},
 "clean": {"categories": 19, "fournisseurs": 40, "produits": 596, "produits_prix_historique": 1601, "clients": 16150, "entrepots": 3,
           "transporteurs": 4, "livraisons": 61793, "campagnes_marketing": 152, "coupons": 68, "marketing_depenses_quotidiennes": 3427,
           "dim_calendrier": 1461, "ref_gouvernorats": 24, "remboursements": 8815, "mouvements_stock": 140184, "stocks_mensuels": 56562,
           "commandes_fournisseurs": 10370, "lignes_commande_fournisseur": 11793, "avis_clients": 9314, "commandes": 66268,
           "lignes_commande": 115903, "paiements": 64493},
 "integ": {"calendrier": 1461, "geographie": 24, "entrepot": 3, "transporteur": 4, "fournisseur": 40, "coupon": 68, "campagne": 152,
           "client_correspondance": 16150, "client": 16000, "produit": 596, "produit_version_prix": 1601, "depense_marketing": 3427,
           "commande": 66268, "ligne_commande": 115903, "paiement": 64491, "livraison": 61793, "remboursement": 8815, "avis": 9314,
           "commande_fournisseur": 10370, "ligne_commande_fournisseur": 11793, "mouvement_stock": 140184, "stock_mensuel": 56562},
}

log = logging.getLogger("tunishop")


# ---------------------------------------------------------------------------
# Lecture des fichiers (aucune transformation : RAW = copie fidèle, tout en texte)
# ---------------------------------------------------------------------------
def fichiers(dossier: str, src: Source) -> list[str]:
    fs = sorted(glob.glob(os.path.join(dossier, src.motif)))
    if not fs:
        raise FileNotFoundError(f"Aucun fichier pour raw.{src.table} ({src.motif}) dans {os.path.abspath(dossier)}")
    return fs


def separateur(chemin: str) -> str:
    with open(chemin, encoding="utf-8-sig") as f:
        entete = f.readline()
    return ";" if entete.count(";") > entete.count(",") else ","   # le marketing est exporté avec « ; »


def lire(chemin: str, src: Source) -> pd.DataFrame:
    if src.format == "jsonl":
        with open(chemin, encoding="utf-8-sig") as f:
            df = pd.DataFrame({"ligne_json": [l.rstrip("\r\n") for l in f if l.strip()]})
    else:
        df = pd.read_csv(chemin, sep=separateur(chemin), dtype=str, keep_default_na=False, na_filter=False, encoding="utf-8-sig")
    df["num_ligne_fichier"] = range(1, len(df) + 1)
    return df


def sha256(chemin: str) -> str:
    h = hashlib.sha256()
    with open(chemin, "rb") as f:
        for bloc in iter(lambda: f.read(1 << 20), b""):
            h.update(bloc)
    return h.hexdigest()


# ---------------------------------------------------------------------------
# Connexion SQL Server
# ---------------------------------------------------------------------------
class Sql:
    def __init__(self, serveur: str, auth: str, utilisateur: str | None, pilote: str | None, base: str = DB_ADMIN, autocommit: bool = False):
        import pyodbc
        pilote = pilote or self._pilote(pyodbc)
        cnx = f"DRIVER={{{pilote}}};SERVER={serveur};DATABASE={base};TrustServerCertificate=yes;"
        if auth == "windows":
            cnx += "Trusted_Connection=yes;"
        else:
            mdp = os.environ.get("TUNISHOP_MDP")
            if not mdp:
                raise SystemExit("Définir la variable d'environnement TUNISHOP_MDP (mot de passe SQL).")
            cnx += f"UID={utilisateur};PWD={mdp};"
        self.cnx = pyodbc.connect(cnx, autocommit=autocommit)
        self.pyodbc = pyodbc

    @staticmethod
    def _pilote(pyodbc) -> str:
        for p in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server"):
            if p in pyodbc.drivers():
                return p
        raise SystemExit(f"Pilote ODBC SQL Server introuvable. Pilotes installés : {pyodbc.drivers()}")

    def exec(self, sql: str, *params, lire_tout: bool = True):
        cur = self.cnx.cursor()
        cur.execute(sql, *params)
        if lire_tout:                      # consommer tous les jeux de résultats : garantit l'exécution complète
            lignes = cur.fetchall() if cur.description else []
            while cur.nextset():
                pass
            return lignes
        return cur

    def scalaire(self, sql: str, *params):
        r = self.exec(sql, *params)
        return r[0][0] if r else None


# ---------------------------------------------------------------------------
# Étape 0 : déploiement des scripts SQL (alternative à SSMS)
# ---------------------------------------------------------------------------
def deployer(sql: Sql, dossier_sql: str):
    scripts = ["01_Creation_Bases.sql", "02_Audit_Logs.sql", "03_Procedures_CLEAN_INTEGRATED.sql"]
    for nom in scripts:
        chemin = os.path.join(dossier_sql, nom)
        texte = open(chemin, encoding="utf-8-sig").read()
        lots = [b for b in re.split(r"^\s*GO\s*$", texte, flags=re.M | re.I) if b.strip()]
        t0 = time.time()
        for i, lot in enumerate(lots, 1):
            try:
                cur = sql.cnx.cursor(); cur.execute(lot)
                while cur.nextset():
                    pass
            except Exception as e:
                raise SystemExit(f"{nom}, lot n° {i} :\n{lot[:400]}\n--> {e}")
        log.info("%-40s %4d lots exécutés en %.1f s", nom, len(lots), time.time() - t0)


# ---------------------------------------------------------------------------
# Étape 1 : chargement STG_RAW
# ---------------------------------------------------------------------------
def etape_raw(dossier: str, sql: Sql | None, forcer: bool = False) -> int:
    t0 = time.time()
    if sql and forcer:   # clôt un lot resté EN_COURS (exécution interrompue), sinon audit.usp_ouvrir_lot refuse un nouveau lot
        sql.exec("UPDATE audit.execution_lot SET statut = 'ECHEC', date_fin = SYSDATETIME(), commentaire = N'Clôturé par --forcer' "
                 "WHERE statut = 'EN_COURS'"); sql.cnx.commit()
    if sql:
        lot = int(sql.exec("SET NOCOUNT ON; DECLARE @id INT; "
                           "EXEC audit.usp_ouvrir_lot @declencheur = N'python', @commentaire = ?, @id_chargement = @id OUTPUT;",
                           f"Chargement depuis {os.path.abspath(dossier)}")[0][0])
        sql.cnx.commit()
    else:
        lot = 0
    log.info("=== STG_RAW — lot %s%s", lot, " (simulation, aucune écriture)" if not sql else "")
    objet = "raw"
    try:
        for src in SOURCES:
            objet = f"raw.{src.table}"
            fs = fichiers(dossier, src)
            if sql:
                cols = [r[0] for r in sql.exec(
                    f"SELECT name FROM [{DB_RAW}].sys.columns WHERE object_id = OBJECT_ID(?) AND name <> 'date_chargement' ORDER BY column_id",
                    f"{DB_RAW}.raw.{src.table}")]
                if not cols:
                    raise RuntimeError(f"Table {DB_RAW}.raw.{src.table} introuvable : exécuter 01_Creation_Bases.sql")
                sql.exec(f"TRUNCATE TABLE [{DB_RAW}].raw.[{src.table}];")
                cur = sql.cnx.cursor(); cur.fast_executemany = True
                insert = f"INSERT INTO [{DB_RAW}].raw.[{src.table}] ({', '.join('[' + c + ']' for c in cols)}) VALUES ({', '.join('?' * len(cols))})"
            lus = 0
            for chemin in fs:
                rel = os.path.relpath(chemin, dossier).replace("\\", "/")
                df = lire(chemin, src)
                lus += len(df)
                if not sql:
                    continue
                manquantes = [c for c in cols if c not in df.columns and c not in ("id_chargement", "fichier_source")]
                if manquantes:
                    raise ValueError(f"{rel} : colonnes absentes {manquantes}")
                df["id_chargement"] = lot
                df["fichier_source"] = rel
                lignes = list(df[cols].itertuples(index=False, name=None))
                for i in range(0, len(lignes), TAILLE_LOT):
                    cur.executemany(insert, lignes[i:i + TAILLE_LOT])
                sql.exec("INSERT INTO audit.fichier_source (id_chargement, table_cible, chemin_fichier, taille_octets, empreinte_sha256, "
                         "nb_lignes_fichier, nb_lignes_chargees) VALUES (?, ?, ?, ?, ?, ?, ?)",
                         lot, src.table, rel, os.path.getsize(chemin), sha256(chemin), len(df), len(df))
            if sql:
                sql.cnx.commit()
                en_base = sql.scalaire(f"SELECT COUNT(*) FROM [{DB_RAW}].raw.[{src.table}] WHERE id_chargement = ?", lot)
                if en_base != lus:
                    raise RuntimeError(f"{objet} : {lus} lignes lues, {en_base} en base")
                sql.exec("EXEC audit.usp_journaliser_tache @id_chargement=?, @couche='STG_RAW', @objet=?, @nb_lus=?, @nb_inseres=?, @nb_rejetes=0",
                         lot, objet, lus, en_base)
                sql.cnx.commit()
            attendu = ATTENDUS["raw"][src.table]
            log.info("  %-38s %2d fichier(s) %9d lignes %s", objet, len(fs), lus, "" if lus == attendu else f"(attendu {attendu})")
        log.info("STG_RAW chargé en %.1f s", time.time() - t0)
        return lot
    except Exception as e:
        if sql:
            erreur(sql, lot, objet, e)
        raise


def erreur(sql: Sql, lot: int, objet: str, e: Exception):
    try:
        sql.cnx.rollback()
        sql.exec("INSERT INTO audit.journal_erreur (id_chargement, objet, message, source) VALUES (?, ?, ?, 'PYTHON')", lot, objet, str(e)[:4000])
        sql.exec("EXEC audit.usp_fermer_lot @id_chargement = ?, @statut = 'ECHEC'", lot)
        sql.cnx.commit()
    except Exception:
        log.exception("Journalisation de l'erreur impossible")


# ---------------------------------------------------------------------------
# Étapes 2 et 3 : procédures SQL
# ---------------------------------------------------------------------------
def tache(sql: Sql, lot: int, objet: str):
    """Dernière ligne d'audit d'un objet pour le lot : lus, insérés, modifiés, supprimés, rejetés"""
    r = sql.exec("SELECT TOP (1) nb_lus, nb_inseres, nb_maj, nb_supprimes, nb_rejetes FROM audit.execution_tache "
                 "WHERE id_chargement = ? AND objet = ? ORDER BY id_tache DESC", lot, objet)
    return tuple(0 if v is None else v for v in r[0]) if r else (0, 0, 0, 0, 0)


def etape_clean(sql: Sql, lot: int, mode: str = "marquer"):
    log.info("=== STG_CLEAN — lot %s — incrémental, lignes disparues : %s", lot, mode)
    log.info("  %-34s %9s %8s %8s %8s %8s", "table", "actives", "ajout", "modif", "suppr", "rejets")
    t0 = time.time()
    for t in ORDRE_CLEAN:
        try:
            sql.exec(f"EXEC [{DB_CLEAN}].clean.usp_charger_{t} @id_chargement = ?, @mode_suppression = ?", lot, mode); sql.cnx.commit()
        except Exception as e:
            erreur(sql, lot, f"clean.usp_charger_{t}", e)
            raise SystemExit(f"Échec de clean.usp_charger_{t} : {e}")
        _, ins, maj, sup, rej = tache(sql, lot, f"clean.{t}")
        n = sql.scalaire(f"SELECT COUNT(*) FROM [{DB_CLEAN}].clean.[v_{t}]")
        att = ATTENDUS["clean"][t]
        log.info("  %-34s %9d %8d %8d %8d %8d %s", f"clean.{t}", n, ins, maj, sup, rej, "" if n == att else f"(attendu {att})")
    log.info("STG_CLEAN terminé en %.1f s", time.time() - t0)


def etape_integ(sql: Sql, lot: int, mode: str = "marquer"):
    log.info("=== STG_INTEGRATED — lot %s — incrémental, lignes disparues : %s", lot, mode)
    t0 = time.time()
    try:
        sql.exec(f"EXEC [{DB_INTEG}].integ.usp_integrer_tout @id_chargement = ?, @mode_suppression = ?", lot, mode); sql.cnx.commit()
    except Exception as e:
        erreur(sql, lot, "integ.usp_integrer_tout", e)
        raise SystemExit(f"Échec de integ.usp_integrer_tout : {e}")
    log.info("  %-34s %9s %8s %8s %8s", "table", "actives", "ajout", "modif", "suppr")
    for t, att in ATTENDUS["integ"].items():
        _, ins, maj, sup, _ = tache(sql, lot, f"integ.{t}")
        n = sql.scalaire(f"SELECT COUNT(*) FROM [{DB_INTEG}].integ.[v_{t}]")
        log.info("  %-34s %9d %8d %8d %8d %s", f"integ.{t}", n, ins, maj, sup, "" if n == att else f"(attendu {att})")
    log.info("STG_INTEGRATED terminé en %.1f s", time.time() - t0)


def bilan(sql: Sql, lot: int, fermer: bool = False):
    log.info("=== Bilan du lot %s", lot)
    for couche, base, schema, att in (("CLEAN", DB_CLEAN, "clean", "clean"), ("INTEGRATED", DB_INTEG, "integ", "integ")):
        ecarts = []
        for t, a in ATTENDUS[att].items():
            n = sql.scalaire(f"SELECT COUNT(*) FROM [{base}].{schema}.[v_{t}]")   # lignes actives
            if n != a:
                ecarts.append(f"{t} ({n} au lieu de {a})")
        log.info("  %-11s %s", couche, "volumes conformes aux attendus" if not ecarts else "ÉCARTS : " + ", ".join(ecarts))
    rej = sql.exec(f"""SELECT 'CLEAN' AS couche, regle_id, niveau, COUNT(*) FROM [{DB_CLEAN}].clean.rejets WHERE id_chargement = ? GROUP BY regle_id, niveau
                       UNION ALL
                       SELECT 'INTEGRATED', regle_id, niveau, COUNT(*) FROM [{DB_INTEG}].integ.rejets WHERE id_chargement = ? GROUP BY regle_id, niveau
                       ORDER BY 1, 2""", lot, lot)
    log.info("  Quarantaine (règles QRxx → Regles_Qualite_Transformation.xlsx) :")
    for c, r, niv, n in rej:
        log.info("    %-11s %-5s %-12s %7d", c, r, niv, n)
    err = sql.scalaire("SELECT COUNT(*) FROM audit.journal_erreur WHERE id_chargement = ?", lot)
    log.info("  Erreurs journalisées : %s", err)
    if fermer:
        sql.exec("EXEC audit.usp_fermer_lot @id_chargement = ?", lot); sql.cnx.commit()
        log.info("  Statut du lot : %s", sql.scalaire("SELECT statut FROM audit.execution_lot WHERE id_chargement = ?", lot))


def tester(sql: Sql):
    log.info("Connexion OK : %s", sql.scalaire("SELECT @@VERSION").splitlines()[0])
    for b in (DB_RAW, DB_CLEAN, DB_INTEG, DB_DWH, DB_ADMIN):
        log.info("  %-26s %s", b, "présente" if sql.scalaire("SELECT DB_ID(?)", b) else "ABSENTE — exécuter 01_Creation_Bases.sql")
    n = sql.scalaire("SELECT COUNT(*) FROM sys.procedures WHERE schema_id = SCHEMA_ID('audit')")
    log.info("  Procédures audit : %s %s", n, "" if n else "— exécuter 02_Audit_Logs.sql")



# ---------------------------------------------------------------------------
# Rapports de validation : chargement de donnees_reference et décision de fin de phase
# ---------------------------------------------------------------------------
def charger_reference(sql: Sql, dossier_ref: str):
    """Copie les 22 CSV de donnees_reference dans TuniShop_ADMIN.ref (texte brut) pour la comparaison d'exactitude."""
    fs = sorted(glob.glob(os.path.join(dossier_ref, "*.csv")))
    if not fs:
        raise SystemExit(f"Aucun CSV dans {os.path.abspath(dossier_ref)} (attendu : dossier donnees_reference)")
    sql.exec("IF SCHEMA_ID(N'ref') IS NULL EXEC (N'CREATE SCHEMA ref AUTHORIZATION dbo;');"); sql.cnx.commit()
    for f in fs:
        t = os.path.splitext(os.path.basename(f))[0]
        df = pd.read_csv(f, dtype=str, keep_default_na=False, na_filter=False, encoding="utf-8-sig")
        cols = ", ".join(f"[{c}] NVARCHAR(1000) NULL" for c in df.columns)
        sql.exec(f"DROP TABLE IF EXISTS ref.[{t}]; CREATE TABLE ref.[{t}] ({cols});")
        cur = sql.cnx.cursor(); cur.fast_executemany = True
        ins = f"INSERT INTO ref.[{t}] ({', '.join('[' + c + ']' for c in df.columns)}) VALUES ({', '.join('?' * len(df.columns))})"
        lignes = list(df.itertuples(index=False, name=None))
        for i in range(0, len(lignes), TAILLE_LOT):
            cur.executemany(ins, lignes[i:i + TAILLE_LOT])
        sql.cnx.commit()
        log.info("  ref.%-34s %9d lignes", t, len(df))
    log.info("donnees_reference chargé dans TuniShop_ADMIN.ref (%d tables)", len(fs))


def valider(sql: Sql, lot: int):
    """Mesures avant/après, comparaison à la référence et décision (audit.usp_valider_staging)."""
    cur = sql.cnx.cursor()
    cur.execute("EXEC audit.usp_valider_staging @lot = ?", lot)
    resultats = []
    while True:
        if cur.description:
            resultats.append(pd.DataFrame.from_records(cur.fetchall(), columns=[c[0] for c in cur.description]))
        if not cur.nextset():
            break
    sql.cnx.commit()
    dec = resultats[-1] if resultats else pd.DataFrame()
    log.info("=== Validation du staging — lot %s", lot)
    if len(dec):
        r = dec.iloc[0]
        for k in ("decision_raw", "fichiers_presents", "lignes_chargees", "combinaisons_conformes", "indicateurs_corriges",
                  "exactitude_moyenne_pct", "ecarts_non_expliques", "decision"):
            if k in dec.columns:
                log.info("  %-24s %s", k, r[k])

# ---------------------------------------------------------------------------
def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="TuniShop : fichiers → STG_RAW → STG_CLEAN → STG_INTEGRATED")
    p.add_argument("commande", choices=["tester", "deployer", "raw", "clean", "integ", "bilan", "tout", "reference", "valider"])
    p.add_argument("--dossier", default=os.environ.get("TUNISHOP_DOSSIER", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "donnees_brutes")), help="dossier donnees_brutes")    p.add_argument("--sql", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sql"), help="dossier des scripts .sql (deployer)")
    p.add_argument("--serveur", default=os.environ.get("TUNISHOP_SERVEUR", "localhost"), help=r"ex. localhost, .\SQLEXPRESS, MONPC\MSSQLSERVER01")
    p.add_argument("--auth", choices=["windows", "sql"], default="windows")
    p.add_argument("--utilisateur", default=os.environ.get("TUNISHOP_UTILISATEUR", "Abdeljaouad"))
    p.add_argument("--pilote", help="nom exact du pilote ODBC (détecté automatiquement sinon)")
    p.add_argument("--dossier-ref", default=os.environ.get("TUNISHOP_DOSSIER_REF", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "donnees_reference")), help="dossier donnees_reference (commande reference)")    p.add_argument("--lot", type=int, help="id_chargement (clean, integ, bilan)")
    p.add_argument("--simulation", action="store_true", help="raw : lit les fichiers sans rien écrire")
    p.add_argument("--suppression", choices=MODES_SUPPRESSION, default="marquer",
                   help="lignes disparues des fichiers : marquer (est_supprime = 1), supprimer ou ignorer")
    p.add_argument("--forcer", action="store_true", help="raw / tout : clôturer un lot resté EN_COURS avant d'en ouvrir un nouveau")
    a = p.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s  %(message)s", datefmt="%H:%M:%S")

    if a.commande == "raw" and a.simulation:
        etape_raw(a.dossier, None); return 0
    if a.commande == "deployer":
        deployer(Sql(a.serveur, a.auth, a.utilisateur, a.pilote, base="master", autocommit=True), a.sql); return 0
    sql = Sql(a.serveur, a.auth, a.utilisateur, a.pilote)
    if a.commande == "tester":
        tester(sql); return 0
    if a.commande == "reference":
        charger_reference(sql, a.dossier_ref); return 0
    if a.commande in ("clean", "integ", "bilan", "valider") and a.lot is None:
        a.lot = sql.scalaire("SELECT MAX(id_chargement) FROM audit.execution_lot")
        log.info("--lot non précisé : dernier lot = %s", a.lot)
    if a.commande == "raw":
        print(etape_raw(a.dossier, sql, a.forcer))
    elif a.commande == "clean":
        etape_clean(sql, a.lot, a.suppression)
    elif a.commande == "integ":
        etape_integ(sql, a.lot, a.suppression)
    elif a.commande == "bilan":
        bilan(sql, a.lot, fermer=True)
    elif a.commande == "valider":
        valider(sql, a.lot)
    elif a.commande == "tout":
        lot = etape_raw(a.dossier, sql, a.forcer)
        etape_clean(sql, lot, a.suppression)
        etape_integ(sql, lot, a.suppression)
        bilan(sql, lot, fermer=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
