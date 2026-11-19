# TuniShop · Étape 1 : bases de données et staging (RAW → CLEAN → INTEGRATED)

Phases du planning couvertes : **P2 Base source** et **P3 Alimentation**.
Étape précédente : [`00_cadrage_conception`](../00_cadrage_conception). Étape suivante : [`02_dwh`](../02_dwh).

```
donnees_brutes/ ──(Python)──► TuniShop_STG_RAW ──(procédures SQL)──► TuniShop_STG_CLEAN ──► TuniShop_STG_INTEGRATED
   92 fichiers                  copie brute            nettoyage (MERGE)               intégration (MERGE)
                                       └──────── journalisation : TuniShop_ADMIN.audit ────────┘
```

## 1. Les 5 bases créées

| Base | Schéma | Rôle | Chargement |
|---|---|---|---|
| `TuniShop_STG_RAW` | `raw` | Copie fidèle des fichiers, tout en texte (22 tables) | Rechargée en entier à chaque lot |
| `TuniShop_STG_CLEAN` | `clean` | Données typées, dédoublonnées, normalisées (22 tables + `rejets`) | **Incrémental** (MERGE) |
| `TuniShop_STG_INTEGRATED` | `integ` | Client maître, liens entre tables, indicateurs dérivés (22 tables + `rejets`) | **Incrémental** (MERGE) |
| `TuniShop_DWH` | `dw`, `bi` | Entrepôt (créé vide ici, rempli par la partie 3) | — |
| `TuniShop_ADMIN` | `audit` | Base de contrôle : lots, tâches, erreurs, fichiers, contrôles | Alimentée par Python et les procédures |

## 2. Contenu du kit

| Fichier | Rôle |
|---|---|
| `sql/01_Creation_Bases.sql` | Crée les 5 bases, les schémas, toutes les tables de staging, les 44 vues `v_*` (lignes actives) et 2 fonctions de nettoyage |
| `sql/02_Audit_Logs.sql` | Crée l'audit dans `TuniShop_ADMIN` : 6 tables, procédures de journalisation et de contrôle, 5 vues de supervision |
| `sql/03_Procedures_CLEAN_INTEGRATED.sql` | 22 procédures `clean.usp_charger_*`, 22 procédures `integ.usp_integrer_*` et leurs orchestrateurs (règles qualité QR01 à QR49) |
| `sql/04_Index_Complementaires.sql` | 8 index pour accélérer les procédures INTEGRATED et la supervision |
| `python/tunishop_pipeline.py` | Script en ligne de commande : charge RAW, lance CLEAN et INTEGRATED, affiche le bilan |
| `python/tunishop_pipeline.ipynb` | Même traitement en notebook Jupyter, pas à pas, avec tests de l'incrémental |
| `python/requirements.txt` | Dépendances Python (`pandas`, `pyodbc`) |

## 3. Prérequis
- **SQL Server 2019 ou plus récent** (édition Developer gratuite, ou Express) et **SSMS**.
- **Python 3.10+** : `pip install -r python/requirements.txt`
- **Pilote ODBC Driver 18 (ou 17) for SQL Server**.
- Le dossier **`donnees_brutes/`** du jeu TuniShop (sous-dossiers `crm/`, `ventes/`, `paiements_api/`…).

## 4. Créer les bases (SSMS)
Ouvrir chaque fichier et l'exécuter en entier (F5), **dans cet ordre** :
1. `sql/01_Creation_Bases.sql`
2. `sql/02_Audit_Logs.sql`
3. `sql/03_Procedures_CLEAN_INTEGRATED.sql`
4. `sql/04_Index_Complementaires.sql` (peut aussi être exécuté après le chargement)

> ⚠️ `01_Creation_Bases.sql` **recrée** les tables (DROP/CREATE) et efface leur contenu : l'exécuter une seule fois, à l'installation.
> `03` (`CREATE OR ALTER`) et `04` (`IF NOT EXISTS`) peuvent être réexécutés sans perte de données.

Contrôle : la base `TuniShop_ADMIN` doit apparaître dans l'explorateur d'objets (clic droit → Actualiser).
Alternative sans SSMS : `python tunishop_pipeline.py deployer` (exécute 01, 02 et 03).

## 5. Charger les données

### Option A — Script Python
```bat
cd python
python tunishop_pipeline.py tester
python tunishop_pipeline.py tout --dossier "C:\TuniShop\tunishop_dataset\donnees_brutes"
```

| Option | Usage |
|---|---|
| `--serveur .\SQLEXPRESS` | si le serveur n'est pas `localhost` (nom affiché dans SSMS) |
| `--auth sql --utilisateur sa` | authentification SQL (`set TUNISHOP_MDP=...` avant) ; sinon authentification Windows |
| `--suppression marquer` | lignes disparues des fichiers : `marquer` (défaut, `est_supprime = 1`), `supprimer` ou `ignorer` |
| `--forcer` | clôturer un lot resté en cours après une interruption |

Étape par étape : `raw`, puis `clean`, puis `integ`, puis `bilan` (au lieu de `tout`).
Réglages permanents : lignes `--dossier` et `--serveur` dans la fonction `main()` du script.

### Option B — Notebook Jupyter
Ouvrir `python/tunishop_pipeline.ipynb`, modifier **uniquement** la cellule « 1. Paramètres » (`DOSSIER`, `SERVEUR`, `AUTH`, `MODE_SUPPRESSION`), puis exécuter les cellules dans l'ordre.
Premier essai conseillé : `SIMULATION = True` (lecture des fichiers seulement, colonne `ecart` à 0 partout).

## 6. Chargement incrémental

| Situation d'une ligne | Action dans CLEAN et INTEGRATED |
|---|---|
| Clé absente | ajout (INSERT) |
| Clé présente, empreinte `hash_ligne` différente | modification (UPDATE) |
| Clé présente, empreinte identique | rien |
| Clé disparue des fichiers | selon le mode de suppression |

Colonnes techniques de chaque table : `id_chargement`, date de dernière modification, `date_creation`, `hash_ligne`, `est_supprime`.
Les vues `clean.v_*` et `integ.v_*` ne contiennent que les lignes actives : ce sont elles que lisent INTEGRATED et le DWH.

**Test** : relancer le chargement sans modifier les fichiers → 0 ajout, 0 modification, 0 suppression.

## 7. Résultats attendus
Le script et le notebook comparent chaque table aux volumes mesurés pendant la conception et affichent « (attendu …) » en cas d'écart.

| Couche | Volumes |
|---|---|
| RAW | 92 fichiers, 569 869 lignes (commandes 66 568, lignes de commande 116 023, paiements 65 137) |
| CLEAN | commandes 66 268, lignes 115 903, paiements 64 493, clients 16 150 (doublons exacts retirés) |
| INTEGRATED | clients 16 000 (150 doublons fusionnés), commandes 66 268, paiements 64 491 (2 orphelins rejetés) |

## 8. Vérifier dans SSMS
```sql
SELECT * FROM TuniShop_ADMIN.audit.v_supervision_lots ORDER BY id_chargement DESC;   -- un lot par exécution
SELECT couche, objet, nb_lus, nb_inseres, nb_maj, nb_supprimes, nb_rejetes
FROM TuniShop_ADMIN.audit.execution_tache ORDER BY id_tache;                          -- volumes par table
SELECT * FROM TuniShop_ADMIN.audit.v_rejets_par_regle;                                -- quarantaine par règle QRxx
SELECT * FROM TuniShop_ADMIN.audit.journal_erreur;                                    -- erreurs éventuelles
```

## 9. En cas d'erreur

| Message | Solution |
|---|---|
| `Pilote ODBC SQL Server introuvable` | installer ODBC Driver 18 for SQL Server |
| `Login failed` / `Cannot open server` | reprendre le nom de serveur exact de SSMS ; vérifier le mode d'authentification |
| `Cannot open database "TuniShop_ADMIN"` | exécuter 01 puis 02 (version actuelle des scripts) |
| `Aucun fichier pour raw.…` | `--dossier` doit pointer sur `donnees_brutes`, pas sur le dossier parent |
| `Un lot est déjà en cours` | ajouter `--forcer` (ou `FORCER = True` dans le notebook) |
| Erreur dans une procédure | voir `audit.journal_erreur` (procédure et ligne), corriger, réexécuter `03`, relancer `clean` ou `integ` |

Ces scripts ont été validés (syntaxe, simulation) sans exécution sur un vrai SQL Server : noter chaque correction dans le journal de bord du projet.

## 10. Étape suivante
Partie 3 — `TuniShop_Etape3_DWH` : création du DWH (`05`, `06`) et packages SSIS de chargement des dimensions et des faits.
