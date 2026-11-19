# TuniShop · Étape 7 : automatisation de la chaîne complète

Auteure : Sarra Abdeljaouad. Version 1.0 du 02/11/2026.

```
donnees_brutes ─► Staging (Python) ─► DWH (SSIS) ─► Cubes (SSAS) ─► Analyses et ML (notebooks)
```

Deux modes, à n'activer **jamais en même temps** :

| Mode | Qui décide quand ? | Qui exécute ? | Pour quoi |
|---|---|---|---|
| A. Windows | SQL Server Agent (planification quotidienne) | SQL Server Agent | L'exploitation réelle, simple et robuste |
| B. Airflow + Docker | Airflow (dans Docker) | SQL Server Agent, à la demande d'Airflow | La démonstration portfolio |

## Contenu

| Fichier | Où l'exécuter | Rôle |
|---|---|---|
| `mode_a_sql_agent/A01_Creer_job_TuniShop_Chaine_complete.sql` | SSMS, `localhost` | Crée le travail « TuniShop - Chaine complete » (staging, DWH, cubes, analyses ML) |
| `mode_a_sql_agent/A02_Automatisation_22h.sql` | SSMS, `localhost` | Planifie le travail chaque nuit à 22 h |
| `mode_a_sql_agent/A03_Désactiver_22h.sql` | SSMS, `localhost` | Désactive la planification |
| `mode_a_sql_agent/A04_Réactiver_22h.sql` | SSMS, `localhost` | Réactive la planification |
| `python/executer_notebooks.py` | Ton environnement Python | Exécute les notebooks dans l'ordre et journalise dans TuniShop_ADMIN |
| `python/requirements_automatisation.txt` | `pip install -r` | papermill, ipykernel, pyodbc |
| `mode_b_airflow_docker/sql/01_Login_Airflow_et_Travaux_AF.sql` | SSMS, `localhost\DEV` | Compte SQL d'Airflow et 3 travaux « TuniShop AF » |
| `mode_b_airflow_docker/Dockerfile`, `requirements.txt`, `.env.example` (à copier en `.env`) | Docker Desktop | Image Airflow 3.3.2 + pilote SQL Server |
| `mode_b_airflow_docker/docker-compose.yaml` | Docker Desktop | Fichier officiel Airflow 3.3.2, image locale, exemples désactivés |
| `mode_b_airflow_docker/dags/tunishop_chaine_complete.py` | Dossier `dags` | Le DAG : contrôle, staging, DWH et cubes, analyses ML, bilan |

Le guide pas à pas (document « TuniShop - Guide d'automatisation ») détaille chaque étape.

## Démarrage rapide (si tu as déjà lu le guide)

```powershell
# Mode A
pip install -r python\requirements_automatisation.txt
python python\executer_notebooks.py lister
python python\executer_notebooks.py tester
# puis mode_a_sql_agent\A01 et A02 dans SSMS

# Mode B
cd mode_b_airflow_docker
mkdir dags, logs, plugins, config -Force
docker compose build
docker compose up airflow-init
docker compose up -d
# http://localhost:8080  (airflow / airflow)
```

## Tests réalisés avant livraison

- `executer_notebooks.py` : exécuté sur des notebooks de test (succès, échec, arrêt au premier échec, code retour 0/1).
- DAG : chargé sans erreur par Airflow 3.3.2 ; enchaînement contrôle → staging → DWH/cubes → analyses → bilan vérifié.
- Logique d'attente des travaux Agent : testée sur un SQL Server simulé (succès, échec d'une étape, travail déjà en cours).
- **Non testé** : l'exécution réelle sur SQL Server, SSIS et SSAS (aucun accès à ton PC TuniShop). Les scripts SQL vérifient eux-mêmes les noms (proxy, packages SSIS) avant d'agir.
