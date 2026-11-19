# -*- coding: utf-8 -*-
"""
TuniShop - DAG « tunishop_chaine_complete »                    Version 2.1
==========================================================================
Airflow (dans Docker) orchestre la chaîne complète TuniShop :

    controle -> staging_python -> dwh_et_cubes -> analyses_ml -> bilan

Airflow ne fait pas lui-même le travail lourd. SSIS, SSAS et le Python des
notebooks ne tournent que sous Windows. Chaque tâche du DAG démarre donc un
travail SQL Server Agent sur l'instance par défaut ABDELJAOUAD (le « bras »
Windows), attend qu'il se termine, lit son historique, puis réussit ou
échoue selon le résultat.

    Airflow (Docker, Linux)  --sp_start_job-->  SQL Server Agent (Windows)
                             <--historique----

Les 3 travaux « TuniShop AF » sont des clones des étapes du job de nuit
« TuniShop - Chaine complete » (script 01_Login_Airflow_et_Travaux_AF.sql).

Connexion Airflow utilisée : « mssql_tunishop »
(Admin > Connections, type Microsoft SQL Server, hôte host.docker.internal,
port 1433, schéma msdb, compte airflow_tunishop).

Changements par rapport à la version 1.0 (02/11/2026) :
  - instance ABDELJAOUAD au lieu de localhost\\DEV ;
  - connexion renommée « mssql_tunishop » ;
  - contrôle : refuse de démarrer si le job de nuit tourne déjà ;
  - travail 2 : DWH dimensions, DWH faits, cubes SSAS et journal du cube.

Changements de la version 2.1 (10/11/2026) :
  - correction : la fin d'un travail est détectée par l'apparition d'une
    NOUVELLE ligne de résultat dans l'historique de l'Agent, et non plus par
    une comparaison d'heures (l'Agent arrondit à la seconde, le DAG ne
    reconnaissait jamais la fin du travail) ;
 - délais maximum relevés : 3 h par travail (le staging dure entre 1 h 11 et 1 h 32).

Auteure : Sarra Abdeljaouad
"""
from __future__ import annotations

import logging
import time

import pendulum
from airflow.sdk import dag, task

# ---------------------------------------------------------------------------
# Réglages
# ---------------------------------------------------------------------------
CONNEXION = "mssql_tunishop"
FUSEAU = "Africa/Tunis"

# Planification. None = lancement manuel seulement (bouton « Trigger » dans Airflow).
# Le mode Airflow est une démonstration : on le laisse en manuel.
PLANIFICATION = None

# Job de nuit (mode Windows). Les deux modes ne doivent jamais tourner en même temps.
JOB_DE_NUIT = "TuniShop - Chaine complete"

TRAVAUX = {
    "staging": "TuniShop AF - 1 Staging Python",
    "dwh_cubes": "TuniShop AF - 2 DWH et cubes",
    "analyses": "TuniShop AF - 3 Analyses ML",
}
INTERVALLE_SONDAGE_S = 15  # Airflow regarde où en est le travail toutes les 15 secondes

log = logging.getLogger(__name__)

STATUTS_AGENT = {0: "ECHEC", 1: "SUCCES", 2: "NOUVELLE TENTATIVE", 3: "ANNULE", 4: "EN COURS"}


# ---------------------------------------------------------------------------
# Outils SQL Server Agent
# ---------------------------------------------------------------------------
def _connexion():
    """Connexion pymssql vers l'instance ABDELJAOUAD, à partir de la connexion Airflow."""
    from airflow.providers.microsoft.mssql.hooks.mssql import MsSqlHook

    cnx = MsSqlHook(mssql_conn_id=CONNEXION).get_conn()
    cnx.autocommit(True)
    return cnx


def _etat_travail(cur, nom: str):
    """Dernière activité du travail dans la session actuelle de l'Agent :
    (date de début, date de fin, id de la ligne d'historique)."""
    cur.execute(
        """
        SELECT TOP (1) a.start_execution_date, a.stop_execution_date, a.job_history_id
        FROM   msdb.dbo.sysjobactivity a
        JOIN   msdb.dbo.sysjobs j ON j.job_id = a.job_id
        WHERE  j.name = %s
          AND  a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
        ORDER BY a.start_execution_date DESC
        """,
        (nom,),
    )
    return cur.fetchone()


def _en_cours(cur, nom: str) -> bool:
    """Vrai si le travail a démarré et n'est pas encore terminé."""
    etat = _etat_travail(cur, nom)
    return bool(etat and etat[0] is not None and etat[1] is None)


def _dernier_resultat(cur, nom: str) -> int:
    """Identifiant de la dernière ligne « résultat du travail » (étape 0) de l'historique.
    0 si le travail n'a encore jamais tourné."""
    cur.execute(
        """
        SELECT ISNULL(MAX(h.instance_id), 0)
        FROM   msdb.dbo.sysjobhistory h
        JOIN   msdb.dbo.sysjobs j ON j.job_id = h.job_id
        WHERE  j.name = %s AND h.step_id = 0
        """,
        (nom,),
    )
    return int(cur.fetchone()[0])


def _duree_agent(hhmmss: int) -> int:
    """Convertit run_duration (entier HHMMSS de l'Agent) en secondes."""
    h, reste = divmod(int(hhmmss or 0), 10000)
    m, s = divmod(reste, 100)
    return h * 3600 + m * 60 + s


def _date_agent(run_date: int, run_time: int) -> str:
    """Convertit run_date (AAAAMMJJ) et run_time (HHMMSS) en texte lisible."""
    d, t = f"{int(run_date):08d}", f"{int(run_time):06d}"
    return f"{d[:4]}-{d[4:6]}-{d[6:]} {t[:2]}:{t[2:4]}:{t[4:]}"


def lancer_travail_agent(nom: str, delai_max_minutes: int) -> dict:
    """Démarre un travail SQL Server Agent, attend sa fin, renvoie le bilan.
    Lève une exception (donc la tâche Airflow échoue) si le travail échoue.

    Principe : avant le démarrage, on note l'identifiant de la dernière ligne
    de résultat du travail dans l'historique. Le travail est terminé dès
    qu'une ligne de résultat plus récente apparaît. Aucune comparaison d'heures."""
    cnx = _connexion()
    cur = cnx.cursor()

    # 1. Le travail existe et est activé
    cur.execute("SELECT enabled FROM msdb.dbo.sysjobs WHERE name = %s", (nom,))
    ligne = cur.fetchone()
    if ligne is None:
        raise RuntimeError(f"Travail introuvable sur l'Agent : « {nom} ». As-tu exécuté 01_Login_Airflow_et_Travaux_AF.sql ?")
    if not ligne[0]:
        raise RuntimeError(f"Le travail « {nom} » est désactivé dans SQL Server Agent.")

    # 2. Ni lui ni le job de nuit ne tournent déjà
    if _en_cours(cur, nom):
        raise RuntimeError(f"Le travail « {nom} » est déjà en cours. On ne le lance pas deux fois.")
    if _en_cours(cur, JOB_DE_NUIT):
        raise RuntimeError(f"Le job de nuit « {JOB_DE_NUIT} » tourne en ce moment. Relance le DAG quand il sera fini.")

    # 3. Repère dans l'historique, puis démarrage
    repere = _dernier_resultat(cur, nom)
    cur.execute("EXEC msdb.dbo.sp_start_job @job_name = %s", (nom,))
    log.info("Travail « %s » démarré (repère historique : %s).", nom, repere)

    # 4. Attente d'une nouvelle ligne de résultat
    limite = time.monotonic() + delai_max_minutes * 60
    dernier_message = 0.0
    while True:
        time.sleep(INTERVALLE_SONDAGE_S)
        cur.execute(
            """
            SELECT TOP (1) h.instance_id, h.run_status, h.message, h.run_date, h.run_time, h.run_duration
            FROM   msdb.dbo.sysjobhistory h
            JOIN   msdb.dbo.sysjobs j ON j.job_id = h.job_id
            WHERE  j.name = %s AND h.step_id = 0 AND h.instance_id > %s
            ORDER BY h.instance_id
            """,
            (nom, repere),
        )
        resultat = cur.fetchone()
        if resultat is not None:
            id_resultat, statut_global, message_global, run_date, run_time, run_duration = resultat
            break
        if time.monotonic() > limite:
            raise RuntimeError(f"Le travail « {nom} » n'est pas terminé après {delai_max_minutes} min. "
                               "Vérifie-le dans SSMS (Moniteur d'activité des travaux).")
        if time.monotonic() - dernier_message >= 300:  # un message toutes les 5 minutes
            log.info("... « %s » toujours en cours.", nom)
            dernier_message = time.monotonic()

    # 5. Détail des étapes de CETTE exécution (entre le repère et la ligne de résultat)
    cur.execute(
        """
        SELECT h.step_id, h.step_name, h.run_status, h.run_duration, h.message
        FROM   msdb.dbo.sysjobhistory h
        JOIN   msdb.dbo.sysjobs j ON j.job_id = h.job_id
        WHERE  j.name = %s AND h.step_id > 0 AND h.instance_id > %s AND h.instance_id < %s
        ORDER BY h.instance_id
        """,
        (nom, repere, id_resultat),
    )
    etapes = cur.fetchall()
    cnx.close()

    for step_id, step_name, run_status, duree_etape, message in etapes:
        log.info("Étape %s « %s » : %s en %s s", step_id, step_name,
                 STATUTS_AGENT.get(run_status, run_status), _duree_agent(duree_etape))
        if run_status != 1:
            log.error("Message de l'Agent : %s", (message or "")[:3000])

    bilan = {"travail": nom, "statut": STATUTS_AGENT.get(statut_global, str(statut_global)),
             "debut": _date_agent(run_date, run_time), "duree_secondes": _duree_agent(run_duration)}
    if statut_global != 1:
        raise RuntimeError(f"Le travail « {nom} » a échoué ({bilan['statut']}). {(message_global or '')[:1000]}")
    log.info("Travail « %s » réussi en %s s.", nom, bilan["duree_secondes"])
    return bilan


# ---------------------------------------------------------------------------
# Le DAG
# ---------------------------------------------------------------------------
@dag(
    dag_id="tunishop_chaine_complete",
    description="TuniShop : staging Python -> DWH (SSIS) -> cubes (SSAS) -> analyses et ML (notebooks)",
    schedule=PLANIFICATION,
    start_date=pendulum.datetime(2026, 11, 1, tz=FUSEAU),
    catchup=False,
    max_active_runs=1,
    default_args={"owner": "Sarra Abdeljaouad", "retries": 0},
    tags=["tunishop", "portfolio", "sql-server-agent"],
    doc_md=__doc__,
)
def tunishop_chaine_complete():

    @task
    def controle() -> str:
        """Vérifie qu'Airflow joint SQL Server, que les 3 travaux existent
        et que le job de nuit ne tourne pas."""
        cnx = _connexion()
        cur = cnx.cursor()
        cur.execute("SELECT @@SERVERNAME, @@VERSION")
        serveur, version = cur.fetchone()
        log.info("Connecté à %s | %s", serveur, version.splitlines()[0])
        manquants = []
        for nom in TRAVAUX.values():
            cur.execute("SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name = %s", (nom,))
            if cur.fetchone()[0] == 0:
                manquants.append(nom)
        nuit_en_cours = _en_cours(cur, JOB_DE_NUIT)
        cnx.close()
        if manquants:
            raise RuntimeError(f"Travaux absents sur {serveur} : {manquants}")
        if nuit_en_cours:
            raise RuntimeError(f"Le job de nuit « {JOB_DE_NUIT} » tourne en ce moment. Relance le DAG quand il sera fini.")
        return serveur

    @task
    def staging_python() -> dict:
        """Fichiers bruts -> STG_RAW -> STG_CLEAN -> STG_INTEGRATED."""
        return lancer_travail_agent(TRAVAUX["staging"], delai_max_minutes=180)

    @task
    def dwh_et_cubes() -> dict:
        """DWH dimensions (SSIS), DWH faits (SSIS), traitement des cubes (SSAS), journal du cube."""
        return lancer_travail_agent(TRAVAUX["dwh_cubes"], delai_max_minutes=180)

    @task
    def analyses_ml() -> dict:
        """Notebooks EDA, data mining, ML et publication dans TuniShop_ANALYTICS."""
        return lancer_travail_agent(TRAVAUX["analyses"], delai_max_minutes=240)

    @task
    def bilan(serveur: str, resultats: list[dict]) -> None:
        total = sum(r["duree_secondes"] for r in resultats)
        log.info("=== BILAN TuniShop sur %s ===", serveur)
        for r in resultats:
            log.info("%-35s %-8s %6s s", r["travail"], r["statut"], r["duree_secondes"])
        log.info("Durée totale : %s min %s s", total // 60, total % 60)

    serveur = controle()
    s = staging_python()
    d = dwh_et_cubes()
    a = analyses_ml()
    serveur >> s >> d >> a
    bilan(serveur, [s, d, a])


tunishop_chaine_complete()
