# -*- coding: utf-8 -*-
"""
chargement.py — liaison directe avec les vues bi du DWH TuniShop (SQL Server)
=============================================================================

C'est le SEUL fichier du projet qui parle à SQL Server. Tous les notebooks l'utilisent ainsi :

    from tunishop_analytics import chargement
    chargement.ouvrir_connexion()                      # 1. connexion (authentification Windows)
    chargement.inventaire_vues()                       # 2. les 23 vues bi.v_* et leur nombre de lignes
    vues, p = chargement.charger_donnees()             # 3. lecture des 23 vues + préparation
    sql = chargement.requete                           # 4. sql("SELECT ... FROM bi.v_...")

Trois principes :
    - on lit UNIQUEMENT les vues du schéma bi (jamais les tables dw.*), comme Power BI et Tableau ;
    - aucune donnée n'est recopiée par défaut : chaque exécution relit le DWH tel qu'il est ;
    - aucun mot de passe dans le code (authentification Windows, ou variable d'environnement TUNISHOP_MDP).

Les réglages (serveur, base, pilotes) sont dans config.py. Les contrôles (totaux validés,
intégrité, doublons...) sont dans validation.py.
"""
from __future__ import annotations

import datetime as dt
import os
import re
from decimal import Decimal

import pandas as pd

import tunishop_kpi as tk   # module de référence des KPI (phase BI), dans 00_Commun

from .config import BASE, DOSSIER_COPIE, PILOTES, RACINE, SCHEMA, SERVEUR

_connexion = None              # connexion ouverte, réutilisée par toutes les requêtes
_description = ""              # texte affiché : où est-on connecté ?


# ---------------------------------------------------------------------------
# 1. Connexion
# ---------------------------------------------------------------------------
def pilote_odbc() -> str:
    """Renvoie le pilote ODBC SQL Server installé sur ce PC (le plus récent de la liste PILOTES)."""
    import pyodbc
    installes = pyodbc.drivers()
    for pilote in PILOTES:
        if pilote in installes:
            return pilote
    raise RuntimeError(
        "Aucun pilote ODBC SQL Server trouvé. Pilotes installés : " + ", ".join(installes) +
        "\nInstalle « ODBC Driver 18 for SQL Server » (site Microsoft) puis relance le notebook.")


def ouvrir_connexion(serveur: str = SERVEUR, base: str = BASE, auth: str = "windows",
                     utilisateur: str | None = None):
    """Ouvre (une seule fois) la connexion au DWH et la garde pour toutes les requêtes.

    auth = "windows" : ton compte Windows (cas normal, rien à saisir) ;
    auth = "sql"     : compte SQL ; le mot de passe est lu dans la variable d'environnement
                       TUNISHOP_MDP (jamais écrit dans le notebook).
    """
    global _connexion, _description
    if _connexion is not None:
        return _connexion

    # Mode test : miroir SQLite des vues bi (voir outils/creer_base_test_sqlite.py)
    base_test = os.environ.get("TUNISHOP_BASE_TEST")
    if base_test:
        import sqlite3
        _connexion = sqlite3.connect(":memory:")
        _connexion.execute(f"ATTACH DATABASE '{base_test}' AS {SCHEMA}")
        _description = f"base de TEST (miroir SQLite des vues bi : {os.path.basename(base_test)})"
        print("Connecté à la", _description)
        return _connexion

    import pyodbc
    pilote = pilote_odbc()
    cs = f"DRIVER={{{pilote}}};SERVER={serveur};DATABASE={base};"
    if auth == "windows":
        cs += "Trusted_Connection=yes;"
    else:
        mdp = os.environ.get("TUNISHOP_MDP")
        if not utilisateur or not mdp:
            raise ValueError("Authentification SQL : indique utilisateur=... et crée la variable TUNISHOP_MDP.")
        cs += f"UID={utilisateur};PWD={mdp};"
    if pilote.startswith("ODBC Driver 18"):
        # Le pilote 18 chiffre la connexion par défaut ; ton SQL Server local utilise un
        # certificat auto-signé : on lui fait confiance (connexion locale uniquement).
        cs += "Encrypt=yes;TrustServerCertificate=yes;"
    try:
        _connexion = pyodbc.connect(cs, timeout=15)
    except pyodbc.Error as e:
        raise ConnectionError(
            f"Connexion impossible à {base} sur {serveur} avec « {pilote} ».\n"
            "Vérifie : 1) le service SQL Server (SQLEXPRESS ou MSSQLSERVER) est démarré ; "
            "2) le nom du serveur est le même que dans SSMS (ex. localhost ou localhost\\SQLEXPRESS) ; "
            "3) ton compte Windows a le droit de lire la base.\n"
            f"Message d'origine : {e}") from None
    _description = f"{base} sur {serveur} (pilote : {pilote})"
    print("Connecté à", _description)
    return _connexion


def fermer_connexion() -> None:
    """Ferme la connexion (à la fin du notebook, facultatif)."""
    global _connexion
    if _connexion is not None:
        _connexion.close()
        _connexion = None
        print("Connexion fermée.")


# ---------------------------------------------------------------------------
# 2. Requêtes SQL sur les vues
# ---------------------------------------------------------------------------
def _normaliser_types(df: pd.DataFrame) -> pd.DataFrame:
    """Rend les types SQL Server faciles à utiliser dans pandas :
    DECIMAL (objets Decimal) -> float ;
    DATE / DATETIME -> texte ISO (« 2025-03-15 »), exactement comme dans une photo CSV.

    Pourquoi du texte et pas des dates pandas ? Les dimensions historisées (SCD2) utilisent la
    date de fin « 9999-12-31 » pour la version courante. pandas ne sait pas représenter une date
    au-delà de l'an 2262 (erreur OutOfBoundsDatetime). Le texte garde la valeur intacte ;
    les analyses convertissent elles-mêmes les dates dont elles ont besoin (pd.to_datetime)."""
    for col in df.columns:
        if df[col].dtype != object:
            continue
        echantillon = df[col].dropna().head(50)
        if not len(echantillon):
            continue
        if all(isinstance(v, Decimal) for v in echantillon):
            df[col] = df[col].astype(float)
        elif all(isinstance(v, (dt.date, dt.datetime)) for v in echantillon):
            df[col] = df[col].map(_date_en_texte)
    return df


def _date_en_texte(v):
    """date(2025, 3, 15) -> "2025-03-15" ; datetime -> "2025-03-15 10:30:00" ; vide -> vide."""
    if isinstance(v, dt.datetime):
        return v.isoformat(sep=" ")
    if isinstance(v, dt.date):
        return v.isoformat()
    return v


def requete(sql: str, params: list | tuple | None = None) -> pd.DataFrame:
    """Exécute une requête SQL sur le DWH et renvoie le résultat sous forme de DataFrame.

    Paramètres : écrire « ? » dans la requête et donner les valeurs dans params, dans l'ordre.
        requete("SELECT COUNT(*) AS n FROM bi.v_fact_commandes WHERE date_commande_sk >= ?", [20250101])
    Ne jamais coller une valeur dans le texte SQL avec + ou f-string : les « ? » évitent les erreurs
    de guillemets et l'injection SQL.
    """
    cn = ouvrir_connexion()
    curseur = cn.cursor()
    curseur.execute(sql, list(params)) if params else curseur.execute(sql)
    colonnes = [c[0] if c[0] else f"col{i + 1}" for i, c in enumerate(curseur.description)]
    lignes = [tuple(ligne) for ligne in curseur.fetchall()]
    curseur.close()
    return _normaliser_types(pd.DataFrame.from_records(lignes, columns=colonnes))


def valeur(sql: str, params: list | tuple | None = None):
    """Exécute une requête qui renvoie UNE seule valeur (ex. SELECT COUNT(*) ...)."""
    v = requete(sql, params).iat[0, 0]
    return float(v) if isinstance(v, Decimal) else v


_IDENTIFIANT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def lire_vue(vue: str, colonnes: list[str] | None = None, filtre: str | None = None,
             params: list | tuple | None = None) -> pd.DataFrame:
    """Lit une vue bi.v_* (toutes les colonnes, ou seulement celles demandées).

        lire_vue("v_dim_campagne")
        lire_vue("v_fact_livraisons", ["livraison_id", "retard_j"], "date_expedition_sk >= ?", [20250101])
    """
    if vue not in tk.VUES:
        raise ValueError(f"Vue inconnue : {vue}. Vues disponibles : {', '.join(tk.VUES)}")
    if colonnes:
        for c in colonnes:
            if not _IDENTIFIANT.match(c):
                raise ValueError(f"Nom de colonne invalide : {c}")
        liste = ", ".join(f"[{c}]" for c in colonnes)
    else:
        liste = "*"
    sql = f"SELECT {liste} FROM {SCHEMA}.[{vue}]"
    if filtre:
        sql += f" WHERE {filtre}"
    return requete(sql, params)


def inventaire_vues() -> pd.DataFrame:
    """Les 23 vues du schéma bi : nombre de lignes et de colonnes, lus en direct dans le DWH."""
    cn = ouvrir_connexion()
    lignes = []
    for vue in tk.VUES:
        curseur = cn.cursor()
        curseur.execute(f"SELECT * FROM {SCHEMA}.[{vue}] WHERE 1 = 0")      # 0 ligne : juste les colonnes
        nb_colonnes = len(curseur.description)
        curseur.close()
        n = valeur(f"SELECT COUNT(*) FROM {SCHEMA}.[{vue}]")
        lignes.append({"vue": f"{SCHEMA}.{vue}", "type": "dimension" if vue.startswith("v_dim") else "fait",
                       "lignes": int(n), "colonnes": nb_colonnes})
    return pd.DataFrame(lignes)


# ---------------------------------------------------------------------------
# 3. Chargement complet pour l'analyse
# ---------------------------------------------------------------------------
def charger_donnees(source: str = "dwh", figer: bool = False,
                    dossier_copie=DOSSIER_COPIE) -> tuple[dict, dict]:
    """Charge les 23 vues bi.v_* et les prépare avec tunishop_kpi.preparer().

    source = "dwh"   : lecture DIRECTE des vues dans SQL Server (par défaut) ;
                       figer=True enregistre en plus une photo CSV dans dossier_copie.
    source = "copie" : relecture d'une photo CSV déjà enregistrée (sans SQL Server).

    Renvoie
        vues : {nom de vue sans "v_": DataFrame}, ex. vues["fact_commandes"]
        p    : tables préparées : cmd, lig, liv, rmb, avis, mkt, stk, mvt, ach, pai, cli
    """
    if source == "dwh":
        ouvrir_connexion()
        print(f"Lecture directe des vues {SCHEMA}.v_* — {dt.datetime.now():%d/%m/%Y %H:%M}")
        vues = {}
        for vue in tk.VUES:
            vues[vue[2:]] = lire_vue(vue)
            print(f"  {vue:<30} {len(vues[vue[2:]]):>8,} lignes".replace(",", " "))
        if figer:
            tk.exporter_vues(vues, str(dossier_copie))
            print(f"Photo CSV enregistrée dans : {os.path.relpath(dossier_copie, RACINE)}")
    elif source == "copie":
        if not os.path.isdir(str(dossier_copie)):
            raise FileNotFoundError(f"Photo introuvable : {dossier_copie}. "
                                    "Lance charger_donnees(source='dwh', figer=True) pour la créer.")
        print(f"Lecture de la photo CSV : {os.path.relpath(dossier_copie, RACINE)}")
        vues = tk.charger_vues_dossier(str(dossier_copie))
    else:
        raise ValueError("source doit valoir 'dwh' ou 'copie'")
    return vues, tk.preparer(vues)
