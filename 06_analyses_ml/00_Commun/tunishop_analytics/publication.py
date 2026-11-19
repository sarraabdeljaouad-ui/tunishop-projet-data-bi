# -*- coding: utf-8 -*-
"""
publication.py — copie des résultats de l'analyse dans la base SQL Server TuniShop_ANALYTICS
=============================================================================================

Pourquoi ?
    Les notebooks produisent leurs résultats sous forme de FICHIERS (CSV dans 06_Exports/Tables,
    Parquet dans 05_Data/features et 06_Exports/Predictions). Power BI peut lire des fichiers,
    mais il est plus solide de lire une BASE : un seul serveur, des droits, une actualisation
    après le job de nuit. Ce module écrit donc CHAQUE résultat à deux endroits :

        1. le fichier, exactement comme avant (rien ne change pour les rapports Word / PDF) ;
        2. une table du schéma ana de la base TuniShop_ANALYTICS (même colonnes, mêmes lignes).

Tu n'appelles presque jamais ce module toi-même : config.exporter_table(), config.exporter_resultat()
et features.sauvegarder() l'appellent automatiquement après avoir écrit le fichier.

Règles :
    - la base TuniShop_DWH n'est JAMAIS modifiée (on écrit seulement dans TuniShop_ANALYTICS) ;
    - chaque publication REMPLACE le contenu de la table (vider puis remplir, en une transaction :
      si une erreur survient, l'ancien contenu est conservé) ;
    - chaque publication est tracée dans ctl.journal_publication (table, lignes, date, compte) ;
    - aucun mot de passe : authentification Windows, comme pour le DWH ;
    - mode test (variable TUNISHOP_BASE_TEST) : écriture dans des fichiers SQLite à côté de la base
      de test, pour vérifier le code sans SQL Server.

Pour désactiver l'écriture SQL (ex. base pas encore créée) :
    mettre PUBLIER_SQL = False dans config.py, ou créer la variable d'environnement TUNISHOP_PUBLIER_SQL=0.
"""
from __future__ import annotations

import datetime as dt
import json
import math
import os
import re
from pathlib import Path

import numpy as np
import pandas as pd

from . import config

_connexion = None     # connexion à TuniShop_ANALYTICS, ouverte une seule fois
_sqlite = False       # True en mode test
_deja_averti = False

# ---------------------------------------------------------------------------
# 1. Quel nom de table pour quel fichier ?
# ---------------------------------------------------------------------------
# Résultats enregistrés en Parquet (features.sauvegarder ou config.exporter_resultat) qui sont publiés
TABLES_PARQUET = {
    "segments_rfm": "dm_segments_rfm",
    "clusters_clients": "dm_clusters_clients",
    "regles_association": "dm_regles_association",
    "ventes_2025_test": "ml_pred_ventes_2025",
    "ventes_2026": "ml_pred_ventes_2026",
    "churn_2025_test": "ml_pred_churn_2025",
    "demande_2025_test": "ml_pred_demande_2025",
    "retard_2025_test": "ml_pred_retard_2025",
    "churn_scores_actuels": "ml_scores_churn_actuels",       # 08_Scoring_Actuel : clients à risque aujourd'hui
    "retard_scores_en_cours": "ml_scores_retard_en_cours",   # 08_Scoring_Actuel : colis en transit
    "demande_scores_annee_suivante": "ml_scores_demande",    # 08_Scoring_Actuel : demande de l'année suivante (v1.3)
}
# Tables « partagées » : plusieurs notebooks écrivent chacun leurs lignes dans la même table.
# nom de fichier (expression régulière) -> (table SQL, colonne qui dit d'où viennent les lignes)
TABLES_PARTAGEES = {
    r"^EDA_hypotheses_(?P<valeur>.+)$": ("eda_hypotheses", "notebook"),
}
# Clés primaires (une ligne par valeur de la clé) des tables les plus utilisées par Power BI
CLES = {
    "dm_segments_rfm": ["client_sk", "date_observation"],
    "dm_clusters_clients": ["client_sk", "date_observation"],
    "ml_pred_churn_2025": ["client_sk", "date_observation"],
    "ml_pred_retard_2025": ["livraison_id"],
    "ml_pred_demande_2025": ["produit_id", "mois"],
    "ml_pred_ventes_2025": ["categorie", "mois"],
    "ml_pred_ventes_2026": ["categorie", "mois"],
    "eda_hypotheses": ["question"],
    "ml_scores_churn_actuels": ["client_sk"],
    "ml_scores_retard_en_cours": ["livraison_id"],
    "ml_scores_demande": ["produit_id", "mois"],
    "ml_registre_modeles": ["nom"],
    # Text mining des avis (02_Data_Mining/05_Text_Mining_Avis, version 1.4)
    "tm_avis": ["avis_id"],
    "tm_avis_themes": ["avis_id", "theme"],
    "tm_produits": ["produit_id"],
}


def nom_table(nom_fichier: str) -> tuple[str, str | None, str | None]:
    """Nom du fichier (sans extension) -> (table SQL, colonne de partage, valeur de partage).

    Q01_ventes_annuelles -> eda_q01_ventes_annuelles ; G03_... -> eda_g03_... ;
    DM01_... -> dm01_... ; ML02_... -> ml02_... ; churn_2025_test -> ml_pred_churn_2025.
    """
    if nom_fichier in TABLES_PARQUET:
        return TABLES_PARQUET[nom_fichier], None, None
    for motif, (table, colonne) in TABLES_PARTAGEES.items():
        m = re.match(motif, nom_fichier)
        if m:
            return table, colonne, m.group("valeur")
    t = re.sub(r"[^0-9a-zA-Z_]", "_", nom_fichier).lower()
    if re.match(r"^[qg]\d", t):
        t = "eda_" + t
    return t, None, None


# ---------------------------------------------------------------------------
# 2. Connexion à TuniShop_ANALYTICS
# ---------------------------------------------------------------------------
def actif() -> bool:
    """La publication SQL est-elle activée ? (config.PUBLIER_SQL et variable TUNISHOP_PUBLIER_SQL)"""
    return bool(config.PUBLIER_SQL) and os.environ.get("TUNISHOP_PUBLIER_SQL", "1") != "0"


def ouvrir_connexion():
    """Ouvre (une fois) la connexion à TuniShop_ANALYTICS (authentification Windows)."""
    global _connexion, _sqlite
    if _connexion is not None:
        return _connexion
    base_test = os.environ.get("TUNISHOP_BASE_TEST")
    if base_test:
        # Mode test : deux fichiers SQLite jouent le rôle des schémas ana et ctl
        import sqlite3
        dossier = Path(base_test).resolve().parent
        _connexion = sqlite3.connect(":memory:")
        for schema in (config.SCHEMA_RESULTATS, "ctl"):
            _connexion.execute(f"ATTACH DATABASE '{dossier / f'analytics_{schema}_test.sqlite'}' AS {schema}")
        _connexion.execute("""CREATE TABLE IF NOT EXISTS ctl.journal_publication (
            id_publication INTEGER PRIMARY KEY AUTOINCREMENT, table_sql TEXT, source_fichier TEXT,
            partage TEXT, lignes INTEGER, colonnes INTEGER, mode_source TEXT, publie_le TEXT, publie_par TEXT)""")
        _sqlite = True
        print("Publication : base de TEST (SQLite)", dossier)
        return _connexion

    import pyodbc
    from .chargement import pilote_odbc
    pilote = pilote_odbc()
    cs = (f"DRIVER={{{pilote}}};SERVER={config.SERVEUR};DATABASE={config.BASE_ANALYTICS};"
          "Trusted_Connection=yes;")
    if pilote.startswith("ODBC Driver 18"):
        cs += "Encrypt=yes;TrustServerCertificate=yes;"
    try:
        _connexion = pyodbc.connect(cs, timeout=15, autocommit=False)
    except pyodbc.Error as e:
        raise ConnectionError(
            f"Connexion impossible à la base {config.BASE_ANALYTICS} sur {config.SERVEUR}.\n"
            "  -> As-tu exécuté dans SSMS le script 00_Commun/sql/01_Creer_base_TuniShop_ANALYTICS.sql ?\n"
            "  -> Pour travailler sans la base : PUBLIER_SQL = False dans config.py.\n"
            f"Message d'origine : {e}") from None
    _sqlite = False
    print(f"Publication : connecté à {config.BASE_ANALYTICS} sur {config.SERVEUR}")
    return _connexion


def fermer_connexion() -> None:
    global _connexion
    if _connexion is not None:
        _connexion.close()
        _connexion = None


# ---------------------------------------------------------------------------
# 3. Préparation du tableau et types SQL
# ---------------------------------------------------------------------------
_DATE_ISO = re.compile(r"^\d{4}-\d{2}-\d{2}$")
LONGUEURS = (50, 100, 255, 500, 1000, 4000)


def preparer(df: pd.DataFrame, index: bool = True) -> pd.DataFrame:
    """Met le tableau sous la forme d'une table SQL : index -> colonnes, noms de colonnes en texte uniques."""
    t = df.copy()
    simple_numero = isinstance(t.index, pd.RangeIndex) and t.index.name is None
    if index and not simple_numero:
        noms = [n if n is not None else ("cle" if t.index.nlevels == 1 else f"cle_{i + 1}")
                for i, n in enumerate(t.index.names)]
        t.index = t.index.set_names(noms)
        t = t.reset_index()
    else:
        t = t.reset_index(drop=True)
    if isinstance(t.columns, pd.MultiIndex):
        t.columns = [" | ".join(str(x) for x in c if str(x) != "") for c in t.columns]
    vus, colonnes = {}, []
    for c in t.columns:
        c = str(c).strip() or "colonne"
        c = c[:120]
        if c.lower() in vus:                      # SQL Server ne distingue pas majuscules / minuscules
            vus[c.lower()] += 1
            c = f"{c}_{vus[c.lower()]}"
        vus.setdefault(c.lower(), 1)
        colonnes.append(c)
    t.columns = colonnes
    return t


def type_sql(s: pd.Series) -> str:
    """Type SQL Server adapté à une colonne pandas (aussi accepté par SQLite en mode test)."""
    if pd.api.types.is_bool_dtype(s):
        return "BIT"
    if pd.api.types.is_integer_dtype(s):
        if s.dropna().empty or (s.min() >= -2**31 and s.max() < 2**31):
            return "INT"
        return "BIGINT"
    if pd.api.types.is_float_dtype(s):
        return "FLOAT"
    if pd.api.types.is_datetime64_any_dtype(s):
        v = s.dropna()
        return "DATE" if v.empty or (v.dt.normalize() == v).all() else "DATETIME2(0)"
    v = s.dropna()
    if not v.empty and all(isinstance(x, (bool, np.bool_)) for x in v):
        return "BIT"
    texte = v.astype(str)
    if not texte.empty and texte.str.match(_DATE_ISO).all():
        return "DATE"
    longueur = int(texte.str.len().max()) if not texte.empty else 0
    for n in LONGUEURS:
        if longueur * 1.5 <= n:
            return f"NVARCHAR({n})"
    return "NVARCHAR(MAX)"


def schema_table(t: pd.DataFrame, table: str) -> list[tuple[str, str, bool]]:
    """Liste (colonne, type SQL, NULL autorisé ?) ; les colonnes de la clé sont NOT NULL."""
    cle = CLES.get(table, [])
    return [(c, type_sql(t[c]), c not in cle) for c in t.columns]


def ddl_creation(table: str, colonnes: list[tuple[str, str, bool]], schema: str | None = None) -> str:
    """Instruction CREATE TABLE (T-SQL) pour la table de résultats."""
    schema = schema or config.SCHEMA_RESULTATS
    lignes = [f"    [{c}] {t} {'NULL' if nul else 'NOT NULL'}" for c, t, nul in colonnes]
    cle = [c for c in CLES.get(table, []) if c in [x[0] for x in colonnes]]
    if cle:
        lignes.append(f"    CONSTRAINT [PK_{table}] PRIMARY KEY ({', '.join(f'[{c}]' for c in cle)})")
    return f"CREATE TABLE [{schema}].[{table}] (\n" + ",\n".join(lignes) + "\n);"


def _valeur(v, type_col: str):
    """Valeur pandas -> valeur Python acceptée par le pilote (None pour les vides)."""
    if v is None or (isinstance(v, float) and math.isnan(v)) or v is pd.NaT:
        return None
    try:
        if pd.isna(v):
            return None
    except (TypeError, ValueError):
        pass
    if isinstance(v, (np.bool_, bool)):
        return int(v)
    if isinstance(v, np.integer):
        return int(v)
    if isinstance(v, np.floating):
        return float(v)
    if isinstance(v, pd.Timestamp):
        v = v.to_pydatetime()
    if type_col == "DATE":
        if isinstance(v, dt.datetime):
            v = v.date()
        elif isinstance(v, str):
            v = dt.date.fromisoformat(v)
        return v.isoformat() if _sqlite else v
    if isinstance(v, dt.datetime):
        return v.isoformat(sep=" ") if _sqlite else v
    if isinstance(v, (list, tuple, set, dict)):
        return json.dumps(list(v) if isinstance(v, set) else v, ensure_ascii=False, default=str)
    if type_col.startswith("NVARCHAR") and not isinstance(v, str):
        return str(v)
    return v


# ---------------------------------------------------------------------------
# 4. Lecture de la structure existante
# ---------------------------------------------------------------------------
def colonnes_existantes(cur, table: str) -> list[tuple[str, str]]:
    """Colonnes de ana.<table> dans la base, avec leur type ([] si la table n'existe pas)."""
    schema = config.SCHEMA_RESULTATS
    if _sqlite:
        return [(r[1], r[2].upper()) for r in cur.execute(f"PRAGMA {schema}.table_info([{table}])").fetchall()]
    cur.execute("""SELECT c.name, UPPER(t.name), c.max_length
                   FROM sys.columns AS c JOIN sys.types AS t ON t.user_type_id = c.user_type_id
                   WHERE c.object_id = OBJECT_ID(?) ORDER BY c.column_id""", f"{schema}.{table}")
    res = []
    for nom, typ, longueur in cur.fetchall():
        if typ == "NVARCHAR":
            typ = "NVARCHAR(MAX)" if longueur == -1 else f"NVARCHAR({longueur // 2})"
        res.append((nom, typ))
    return res


def _famille(typ: str) -> str:
    return typ.split("(")[0]


def _compatible(ancien: str, nouveau: str) -> bool:
    """Le type déjà en base peut-il recevoir les nouvelles valeurs sans perte ?"""
    a, n = _famille(ancien), _famille(nouveau)
    if a == "NVARCHAR" and n == "NVARCHAR":
        longueur = lambda t: 10**9 if "MAX" in t else int(t.split("(")[1].rstrip(")"))
        return longueur(nouveau) <= longueur(ancien)
    if a == "BIGINT" and n == "INT":
        return True
    if a == "FLOAT" and n in ("INT", "BIGINT"):
        return True
    return a == n


# ---------------------------------------------------------------------------
# 5. Publication
# ---------------------------------------------------------------------------
def publier(df: pd.DataFrame, nom_fichier: str, index: bool = True, source: str = "") -> int | None:
    """Copie un tableau de résultats dans TuniShop_ANALYTICS.ana.<table> (remplace l'ancien contenu).

    df          : le tableau (le même que celui écrit dans le fichier)
    nom_fichier : nom du fichier sans extension (donne le nom de la table, voir nom_table)
    index       : True si l'index du tableau fait partie des données (comme dans le CSV)
    Renvoie le nombre de lignes publiées (None si la publication est désactivée).
    """
    global _deja_averti
    if not actif():
        if not _deja_averti:
            print("Publication SQL désactivée (PUBLIER_SQL = False) : fichiers seulement.")
            _deja_averti = True
        return None
    table, col_partage, val_partage = nom_table(nom_fichier)
    t = preparer(df, index=index)
    if col_partage:
        t.insert(0, col_partage, val_partage)
    colonnes = schema_table(t, table)
    cle = [c for c in CLES.get(table, []) if c in t.columns]
    if cle and t.duplicated(subset=cle).any():
        raise ValueError(f"{table} : la clé {cle} contient des doublons, publication refusée.")

    cn = ouvrir_connexion()
    cur = cn.cursor()
    schema = config.SCHEMA_RESULTATS
    try:
        existantes = colonnes_existantes(cur, table)
        voulues = [c for c, _, _ in colonnes]
        if existantes:
            memes_noms = [c.lower() for c, _ in existantes] == [c.lower() for c in voulues]
            types_ok = memes_noms and all(_compatible(a, n) for (_, a), (_, n, _) in zip(existantes, colonnes))
            if not types_ok:
                # Colonnes ou types changés (nouvelle version du notebook, texte plus long...) :
                # on recrée la table pour ne rien tronquer
                print(f"  ⚠ {schema}.{table} : structure modifiée -> table recréée")
                cur.execute(f"DROP TABLE [{schema}].[{table}]")
                existantes = []
            else:
                # on garde les types déjà en base (ex. NVARCHAR(255) même si le texte est plus court)
                colonnes = [(c, a, nul) for (c, _, nul), (_, a) in zip(colonnes, existantes)]
        if not existantes:
            cur.execute(ddl_creation(table, colonnes))
        # Vider (toute la table, ou seulement les lignes de ce notebook pour une table partagée)
        if col_partage:
            cur.execute(f"DELETE FROM [{schema}].[{table}] WHERE [{col_partage}] = ?", (val_partage,))
        else:
            cur.execute(f"DELETE FROM [{schema}].[{table}]")
        # Remplir, par paquets de 5 000 lignes
        types = [ty for _, ty, _ in colonnes]
        lignes = [tuple(_valeur(v, ty) for v, ty in zip(ligne, types)) for ligne in t.itertuples(index=False)]
        insertion = (f"INSERT INTO [{schema}].[{table}] ({', '.join(f'[{c}]' for c in voulues)}) "
                     f"VALUES ({', '.join('?' * len(voulues))})")
        if not _sqlite:
            cur.fast_executemany = True          # envoi groupé : beaucoup plus rapide avec pyodbc
        for i in range(0, len(lignes), 5000):
            cur.executemany(insertion, lignes[i:i + 5000])
        # Contrôle : la base contient autant de lignes que le tableau
        if col_partage:
            cur.execute(f"SELECT COUNT(*) FROM [{schema}].[{table}] WHERE [{col_partage}] = ?", (val_partage,))
        else:
            cur.execute(f"SELECT COUNT(*) FROM [{schema}].[{table}]")
        n_base = cur.fetchone()[0]
        if n_base != len(t):
            raise RuntimeError(f"{table} : {n_base} lignes en base pour {len(t)} dans le tableau.")
        # Trace dans le journal
        mode = "TEST" if _sqlite else "DWH"
        quand = dt.datetime.now().replace(microsecond=0)
        compte = os.environ.get("USERNAME") or os.environ.get("USER") or ""
        cur.execute("INSERT INTO ctl.journal_publication (table_sql, source_fichier, partage, lignes, colonnes, "
                    "mode_source, publie_le, publie_par) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    (f"{schema}.{table}", source or nom_fichier, val_partage, len(t), len(voulues), mode,
                     quand.isoformat(sep=" ") if _sqlite else quand, compte))
        cn.commit()
    except Exception:
        cn.rollback()                            # rien n'est modifié si une étape échoue
        raise
    finally:
        cur.close()
    _memoriser_schema(table, colonnes, len(t), source or nom_fichier, col_partage)
    print(f"  ✔ {schema}.{table:<38} {len(t):>8,} lignes".replace(",", " "))
    return len(t)


# Description des tables publiées (05_Data/metadata/Schema_Base_Analytics.json), utile pour la documentation
def _memoriser_schema(table, colonnes, n, source, partage) -> None:
    chemin = config.DOSSIER_METADATA / "Schema_Base_Analytics.json"
    try:
        contenu = json.loads(chemin.read_text(encoding="utf-8")) if chemin.exists() else {}
    except (OSError, ValueError):
        contenu = {}
    ancien = contenu.get(table, {})
    sources = sorted(set(ancien.get("sources", [])) | {source}) if partage else [source]
    contenu[table] = {"colonnes": colonnes, "lignes": n, "sources": sources, "partage": partage,
                      "cle": CLES.get(table, []), "publie_le": dt.datetime.now().strftime("%d/%m/%Y %H:%M")}
    chemin.parent.mkdir(parents=True, exist_ok=True)
    chemin.write_text(json.dumps(dict(sorted(contenu.items())), ensure_ascii=False, indent=1), encoding="utf-8")


# ---------------------------------------------------------------------------
# 6. Republier tout d'un coup (notebook 07_Publication_Resultats ou job de nuit)
# ---------------------------------------------------------------------------
def republier_tout() -> pd.DataFrame:
    """Relit tous les fichiers de résultats déjà produits et les publie. Renvoie le bilan."""
    bilan = []
    # a) tableaux CSV de 06_Exports/Tables (écrits par config.exporter_table : « ; » et décimale « , »)
    for f in sorted(config.DOSSIER_TABLES.glob("*.csv")):
        df = pd.read_csv(f, sep=";", decimal=",", encoding="utf-8-sig")
        premiere = df.columns[0]
        if str(premiere).startswith("Unnamed"):               # index sans nom dans le CSV
            if df[premiere].tolist() == list(range(len(df))):  # simple numéro de ligne : ignoré
                df = df.drop(columns=premiere)
            else:
                df = df.rename(columns={premiere: "cle"})
        df = _retyper(df)
        bilan.append((f.name, *_publier_sans_echec(df, f.stem, False, f"06_Exports/Tables/{f.name}")))
    # b) résultats Parquet
    for dossier in (config.DOSSIER_FEATURES, config.DOSSIER_PREDICTIONS, config.DOSSIER_MODELES):
        for f in sorted(dossier.glob("*.parquet")):
            if f.stem in TABLES_PARQUET:
                bilan.append((f.name, *_publier_sans_echec(pd.read_parquet(f), f.stem, False,
                                                           str(f.relative_to(config.RACINE)).replace("\\", "/"))))
    return pd.DataFrame(bilan, columns=["fichier", "table", "lignes", "statut"])


_DATE_HEURE = re.compile(r"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?$")


def _retyper(df: pd.DataFrame) -> pd.DataFrame:
    """Un CSV relu ne garde pas les types : on retrouve les booléens et les dates."""
    for c in df.columns:
        v = df[c].dropna()
        if v.empty or df[c].dtype != object:
            continue
        texte = v.astype(str)
        if texte.isin(["True", "False"]).all():
            df[c] = df[c].map({"True": True, "False": False, True: True, False: False})
        elif texte.str.match(_DATE_HEURE).all():
            df[c] = pd.to_datetime(df[c])
    return df


def _publier_sans_echec(df, nom, index, source):
    table = nom_table(nom)[0]
    try:
        return f"{config.SCHEMA_RESULTATS}.{table}", publier(df, nom, index=index, source=source), "OK"
    except Exception as e:                                   # on continue avec les autres fichiers
        print(f"  ✘ {table} : {e}")
        return f"{config.SCHEMA_RESULTATS}.{table}", 0, f"ÉCART : {e}"


def journal(n: int = 20) -> pd.DataFrame:
    """Dernières publications enregistrées dans ctl.journal_publication."""
    cn = ouvrir_connexion()
    haut = "" if _sqlite else f"TOP ({int(n)}) "
    fin = f" LIMIT {int(n)}" if _sqlite else ""
    return pd.read_sql(f"SELECT {haut}* FROM ctl.journal_publication ORDER BY id_publication DESC{fin}", cn)
