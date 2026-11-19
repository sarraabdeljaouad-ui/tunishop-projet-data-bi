#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TuniShop — Scripts_Preparation.py
=================================
Extraction des fichiers sources et chargement de la couche TuniShop_STG_RAW (SQL Server),
avec journalisation dans la base de contrôle TuniShop_ADMIN (schéma audit) et profilage qualité des fichiers.

Rôle dans la chaîne :
    fichiers (CSV, JSONL)  --[ce script]-->  STG_RAW  --[SSIS + procédures]-->  STG_CLEAN -> STG_INTEGRATED -> DWH

Commandes :
    python Scripts_Preparation.py profiler  --dossier ./donnees_brutes [--sortie rapport_profilage.xlsx]
    python Scripts_Preparation.py charger   --dossier ./donnees_brutes --serveur localhost [--auth windows|sql --utilisateur sa]
    python Scripts_Preparation.py verifier  --dossier ./donnees_brutes --serveur localhost --lot 12
    python Scripts_Preparation.py charger   --dossier ./donnees_brutes --simulation     (aucune écriture SQL)

Principes :
    * RAW = copie fidèle : toutes les valeurs restent du texte, aucune correction ici
      (le nettoyage est fait en SQL dans STG_CLEAN pour rester traçable et rejouable).
    * Les 36 fichiers mensuels de commandes / lignes sont concaténés dans une seule table RAW.
    * Les paiements JSON Lines sont stockés ligne à ligne (colonne ligne_json) et aplatis en SQL (OPENJSON).
    * Chaque ligne reçoit id_chargement, fichier_source et num_ligne_fichier.
    * Empreinte SHA-256 de chaque fichier conservée dans audit.fichier_source.

Dépendances : pandas, pyodbc (et openpyxl pour le rapport de profilage)
    pip install pandas pyodbc openpyxl
Pilote : Microsoft ODBC Driver 17 ou 18 for SQL Server.
"""
from __future__ import annotations

import argparse
import glob
import hashlib
import json
import logging
import os
import re
import sys
import time
from dataclasses import dataclass
from typing import Iterator

import pandas as pd

# ---------------------------------------------------------------------------
# Configuration des sources (identique au modèle de métadonnées / Mapping_Source_Cible.xlsx)
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Source:
    table: str           # table cible dans TuniShop_STG_RAW.raw
    motif: str           # chemin relatif (motif glob) sous --dossier
    format: str          # csv | jsonl
    separateur: str | None = None   # None = détection automatique

SOURCES: list[Source] = [
    Source("categories",                      "catalogue/categories.csv",                       "csv"),
    Source("fournisseurs",                    "catalogue/fournisseurs.csv",                     "csv"),
    Source("produits",                        "catalogue/produits.csv",                         "csv"),
    Source("produits_prix_historique",        "catalogue/produits_prix_historique.csv",         "csv"),
    Source("clients",                         "crm/clients.csv",                                "csv"),
    Source("entrepots",                       "logistique/entrepots.csv",                       "csv"),
    Source("transporteurs",                   "logistique/transporteurs.csv",                   "csv"),
    Source("livraisons",                      "logistique/livraisons.csv",                      "csv"),
    Source("campagnes_marketing",             "marketing/campagnes_marketing.csv",              "csv", ";"),
    Source("coupons",                         "marketing/coupons.csv",                          "csv", ";"),
    Source("marketing_depenses_quotidiennes", "marketing/marketing_depenses_quotidiennes.csv",  "csv", ";"),
    Source("dim_calendrier",                  "referentiels/dim_calendrier.csv",                "csv"),
    Source("ref_gouvernorats",                "referentiels/ref_gouvernorats.csv",              "csv"),
    Source("remboursements",                  "sav/remboursements.csv",                         "csv"),
    Source("mouvements_stock",                "stocks/mouvements_stock.csv",                    "csv"),
    Source("stocks_mensuels",                 "stocks/stocks_mensuels.csv",                     "csv"),
    Source("commandes_fournisseurs",          "achats/commandes_fournisseurs.csv",              "csv"),
    Source("lignes_commande_fournisseur",     "achats/lignes_commande_fournisseur.csv",         "csv"),
    Source("avis_clients",                    "avis/avis_clients.csv",                          "csv"),
    Source("commandes",                       "ventes/commandes/commandes_*.csv",               "csv"),
    Source("lignes_commande",                 "ventes/lignes_commande/lignes_commande_*.csv",   "csv"),
    Source("paiements_api",                   "paiements_api/paiements.jsonl",                  "jsonl"),
]

DB_RAW, DB_DWH = "TuniShop_STG_RAW", "TuniShop_ADMIN"   # connexion à la base de contrôle (schéma audit)
TAILLE_LOT_INSERTION = 5_000

log = logging.getLogger("tunishop")


# ---------------------------------------------------------------------------
# Lecture des fichiers
# ---------------------------------------------------------------------------
def detecter_separateur(chemin: str) -> str:
    """Retourne ';' ou ',' selon l'en-tête (les fichiers marketing utilisent ';')."""
    with open(chemin, encoding="utf-8-sig") as f:
        entete = f.readline()
    return ";" if entete.count(";") > entete.count(",") else ","


def sha256(chemin: str) -> str:
    h = hashlib.sha256()
    with open(chemin, "rb") as f:
        for bloc in iter(lambda: f.read(1 << 20), b""):
            h.update(bloc)
    return h.hexdigest()


def lister_fichiers(dossier: str, src: Source) -> list[str]:
    fichiers = sorted(glob.glob(os.path.join(dossier, src.motif)))
    if not fichiers:
        raise FileNotFoundError(f"Aucun fichier pour {src.table} ({src.motif}) dans {dossier}")
    return fichiers


def lire_fichier(chemin: str, src: Source) -> pd.DataFrame:
    """Lit un fichier en texte brut : aucune conversion de type, aucune valeur NA implicite."""
    if src.format == "jsonl":
        with open(chemin, encoding="utf-8-sig") as f:
            lignes = [l.rstrip("\r\n") for l in f if l.strip()]
        df = pd.DataFrame({"ligne_json": lignes})
    else:
        sep = src.separateur or detecter_separateur(chemin)
        df = pd.read_csv(chemin, sep=sep, dtype=str, keep_default_na=False, na_filter=False,
                         encoding="utf-8-sig", quotechar='"')
    df.insert(len(df.columns), "num_ligne_fichier", range(1, len(df) + 1))
    return df


# ---------------------------------------------------------------------------
# Profilage (rapport de qualité des fichiers bruts)
# ---------------------------------------------------------------------------
def forme(valeur: str) -> str:
    """Motif d'une valeur : chiffres → 9, lettres → a (ex. '2023-01-05' → '9999-99-99')."""
    return re.sub(r"[A-Za-zÀ-ÿ]", "a", re.sub(r"\d", "9", valeur))


def profiler(dossier: str, sortie: str) -> pd.DataFrame:
    lignes = []
    for src in SOURCES:
        fichiers = lister_fichiers(dossier, src)
        df = pd.concat([lire_fichier(f, src) for f in fichiers], ignore_index=True).drop(columns="num_ligne_fichier")
        if src.format == "jsonl":   # profil des clés JSON après aplatissement
            df = pd.json_normalize([json.loads(x) for x in df["ligne_json"]]).astype(object).where(lambda d: d.notna(), "").astype(str)
        cle = df.columns[0]
        nb_doublons = int(df.duplicated().sum())
        for col in df.columns:
            s = df[col].fillna("").astype(str)
            formes = s.map(forme).value_counts()
            lignes.append({
                "table": src.table, "colonne": col, "nb_fichiers": len(fichiers), "nb_lignes": len(df),
                "doublons_lignes_entieres": nb_doublons if col == cle else None,
                "doublons_cle": int(s.duplicated().sum()) if col == cle else None,
                "nb_vides": int((s.str.strip() == "").sum()),
                "pct_vides": round(float((s.str.strip() == "").mean()), 4),
                "nb_distincts": int(s.nunique()),
                "nb_espaces_parasites": int((s != s.str.strip()).sum()),
                "nb_formes": len(formes),
                "formes_principales": "; ".join(f"{k} ({v})" for k, v in formes.head(4).items()),
                "longueur_max": int(s.str.len().max() or 0),
                "exemple": s[s.str.strip() != ""].iloc[0] if (s.str.strip() != "").any() else "",
            })
        log.info("profilé : %-35s %8d lignes", src.table, len(df))
    rapport = pd.DataFrame(lignes)
    if sortie.lower().endswith(".xlsx"):
        rapport.to_excel(sortie, index=False, sheet_name="profilage")
    else:
        rapport.to_csv(sortie, index=False, encoding="utf-8-sig", sep=";")
    log.info("Rapport de profilage écrit : %s (%d colonnes analysées)", sortie, len(rapport))
    return rapport


# ---------------------------------------------------------------------------
# Accès SQL Server
# ---------------------------------------------------------------------------
class SqlServer:
    def __init__(self, serveur: str, auth: str, utilisateur: str | None, mot_de_passe: str | None, pilote: str):
        import pyodbc  # import tardif : la commande « profiler » n'en a pas besoin
        cnx = f"DRIVER={{{pilote}}};SERVER={serveur};DATABASE={DB_DWH};TrustServerCertificate=yes;"
        cnx += "Trusted_Connection=yes;" if auth == "windows" else f"UID={utilisateur};PWD={mot_de_passe};"
        self.cnx = pyodbc.connect(cnx, autocommit=False)
        self.cnx.add_output_converter(-155, lambda v: v)  # DATETIMEOFFSET éventuel

    def executer(self, sql: str, *params):
        cur = self.cnx.cursor()
        cur.execute(sql, *params)
        return cur

    def ouvrir_lot(self, commentaire: str) -> int:
        # audit.usp_ouvrir_lot renvoie l'identifiant dans son jeu de résultats (SELECT @id_chargement)
        cur = self.executer(
            "SET NOCOUNT ON; DECLARE @id INT; "
            "EXEC audit.usp_ouvrir_lot @declencheur = N'python', @commentaire = ?, @id_chargement = @id OUTPUT;", commentaire)
        id_lot = int(cur.fetchone()[0])
        self.cnx.commit()
        return id_lot

    def journaliser_tache(self, id_lot: int, objet: str, nb_lus: int, nb_inseres: int):
        self.executer("EXEC audit.usp_journaliser_tache @id_chargement=?, @couche='STG_RAW', @objet=?, @nb_lus=?, @nb_inseres=?, @nb_rejetes=0",
                      id_lot, objet, nb_lus, nb_inseres)
        self.cnx.commit()

    def journaliser_erreur(self, id_lot: int | None, objet: str, message: str):
        try:
            self.cnx.rollback()
            self.executer("INSERT INTO audit.journal_erreur (id_chargement, objet, message, source) VALUES (?, ?, ?, 'PYTHON')",
                          id_lot, objet, message[:4000])
            self.cnx.commit()
        except Exception:  # la journalisation ne doit jamais masquer l'erreur d'origine
            log.exception("Impossible de journaliser l'erreur")

    def fermer_lot(self, id_lot: int, statut: str | None = None):
        self.executer("EXEC audit.usp_fermer_lot @id_chargement=?, @statut=?", id_lot, statut)
        self.cnx.commit()

    def colonnes_raw(self, table: str) -> list[str]:
        cur = self.executer(f"SELECT name FROM [{DB_RAW}].sys.columns WHERE object_id = OBJECT_ID(?) ORDER BY column_id",
                            f"{DB_RAW}.raw.{table}")
        return [r[0] for r in cur.fetchall()]

    def vider(self, table: str):
        self.executer(f"TRUNCATE TABLE [{DB_RAW}].raw.[{table}];")

    def inserer(self, table: str, colonnes: list[str], lignes: Iterator[tuple]) -> int:
        cur = self.cnx.cursor()
        cur.fast_executemany = True
        sql = (f"INSERT INTO [{DB_RAW}].raw.[{table}] ({', '.join('[' + c + ']' for c in colonnes)}) "
               f"VALUES ({', '.join('?' * len(colonnes))})")
        total, tampon = 0, []
        for ligne in lignes:
            tampon.append(ligne)
            if len(tampon) >= TAILLE_LOT_INSERTION:
                cur.executemany(sql, tampon); total += len(tampon); tampon.clear()
        if tampon:
            cur.executemany(sql, tampon); total += len(tampon)
        return total

    def enregistrer_fichier(self, id_lot: int, table: str, chemin: str, taille: int, empreinte: str, nb_fichier: int, nb_charge: int):
        self.executer("INSERT INTO audit.fichier_source (id_chargement, table_cible, chemin_fichier, taille_octets, empreinte_sha256, "
                      "nb_lignes_fichier, nb_lignes_chargees) VALUES (?, ?, ?, ?, ?, ?, ?)",
                      id_lot, table, chemin, taille, empreinte, nb_fichier, nb_charge)

    def compter_raw(self, table: str, id_lot: int) -> int:
        return self.executer(f"SELECT COUNT(*) FROM [{DB_RAW}].raw.[{table}] WHERE id_chargement = ?", id_lot).fetchone()[0]


# ---------------------------------------------------------------------------
# Chargement STG_RAW
# ---------------------------------------------------------------------------
def preparer_lignes(df: pd.DataFrame, colonnes_cibles: list[str], id_lot: int, fichier_rel: str) -> Iterator[tuple]:
    """Aligne le DataFrame sur les colonnes de la table RAW (ordre SQL), ajoute les colonnes techniques."""
    absentes = [c for c in colonnes_cibles if c not in df.columns and c not in ("id_chargement", "fichier_source", "date_chargement")]
    if absentes:
        raise ValueError(f"Colonnes attendues absentes du fichier {fichier_rel} : {absentes}")
    for rec in df.itertuples(index=False):
        d = rec._asdict()
        yield tuple(id_lot if c == "id_chargement" else fichier_rel if c == "fichier_source" else d[c] for c in colonnes_cibles)


def charger(dossier: str, sql: SqlServer | None, tables: list[str] | None) -> int | None:
    debut = time.time()
    id_lot = sql.ouvrir_lot(f"Chargement STG_RAW depuis {os.path.abspath(dossier)}") if sql else 0
    log.info("Lot ouvert : id_chargement = %s%s", id_lot, " (simulation)" if not sql else "")
    objet = None
    try:
        for src in SOURCES:
            if tables and src.table not in tables:
                continue
            objet = f"raw.{src.table}"
            fichiers = lister_fichiers(dossier, src)
            if sql:
                colonnes = [c for c in sql.colonnes_raw(src.table) if c != "date_chargement"]
                sql.vider(src.table)
            total_lu = total_charge = 0
            for chemin in fichiers:
                rel = os.path.relpath(chemin, dossier).replace("\\", "/")
                df = lire_fichier(chemin, src)
                total_lu += len(df)
                if sql:
                    n = sql.inserer(src.table, colonnes, preparer_lignes(df, colonnes, id_lot, rel))
                    sql.enregistrer_fichier(id_lot, src.table, rel, os.path.getsize(chemin), sha256(chemin), len(df), n)
                    total_charge += n
                else:
                    total_charge += len(df)
            if sql:
                sql.cnx.commit()
                controle = sql.compter_raw(src.table, id_lot)
                if controle != total_lu:
                    raise RuntimeError(f"{objet} : {total_lu} lignes lues mais {controle} présentes en base")
                sql.journaliser_tache(id_lot, objet, total_lu, total_charge)
            log.info("%-40s %3d fichier(s) %9d lignes", objet, len(fichiers), total_charge)
        log.info("STG_RAW chargé en %.1f s. Étape suivante : package SSIS 00_Maitre (ou dw.usp_executer_chaine @id_chargement = %s).",
                 time.time() - debut, id_lot)
        return id_lot
    except Exception as e:
        log.exception("Échec du chargement")
        if sql:
            sql.journaliser_erreur(id_lot, objet or "Scripts_Preparation.py", str(e))
            sql.fermer_lot(id_lot, "ECHEC")
        raise


def verifier(dossier: str, sql: SqlServer, id_lot: int) -> bool:
    """Réconciliation nombre de lignes fichiers ↔ STG_RAW pour un lot."""
    ok = True
    for src in SOURCES:
        attendu = sum(len(lire_fichier(f, src)) for f in lister_fichiers(dossier, src))
        present = sql.compter_raw(src.table, id_lot)
        etat = "OK" if attendu == present else "ÉCART"
        ok &= attendu == present
        log.info("%-35s fichiers=%9d  raw=%9d  %s", src.table, attendu, present, etat)
    return ok


# ---------------------------------------------------------------------------
def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="TuniShop — extraction et chargement STG_RAW")
    p.add_argument("commande", choices=["profiler", "charger", "verifier"])
    p.add_argument("--dossier", default=os.environ.get("TUNISHOP_DOSSIER", "./donnees_brutes"), help="Dossier donnees_brutes")
    p.add_argument("--serveur", default=os.environ.get("TUNISHOP_SERVEUR", "localhost"))
    p.add_argument("--auth", choices=["windows", "sql"], default="windows")
    p.add_argument("--utilisateur", default=os.environ.get("TUNISHOP_UTILISATEUR"))
    p.add_argument("--mot-de-passe", default=os.environ.get("TUNISHOP_MDP"), help="Préférer la variable d'environnement TUNISHOP_MDP")
    p.add_argument("--pilote", default="ODBC Driver 18 for SQL Server")
    p.add_argument("--tables", nargs="*", help="Limiter à certaines tables RAW")
    p.add_argument("--lot", type=int, help="id_chargement (commande verifier)")
    p.add_argument("--sortie", default="rapport_profilage.xlsx")
    p.add_argument("--simulation", action="store_true", help="Lecture des fichiers sans écriture SQL")
    p.add_argument("-v", "--verbeux", action="store_true")
    a = p.parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if a.verbeux else logging.INFO, format="%(asctime)s %(levelname)-7s %(message)s", datefmt="%H:%M:%S")

    if a.commande == "profiler":
        profiler(a.dossier, a.sortie)
        return 0
    sql = None if a.simulation else SqlServer(a.serveur, a.auth, a.utilisateur, a.mot_de_passe, a.pilote)
    if a.commande == "charger":
        id_lot = charger(a.dossier, sql, a.tables)
        print(id_lot)   # sortie standard exploitable par SSIS (tâche Exécuter le processus) ou un script appelant
        return 0
    if a.commande == "verifier":
        if sql is None or a.lot is None:
            p.error("verifier nécessite une connexion SQL et --lot")
        return 0 if verifier(a.dossier, sql, a.lot) else 2
    return 1


if __name__ == "__main__":
    sys.exit(main())
