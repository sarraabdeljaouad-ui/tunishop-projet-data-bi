# TuniShop — Étape 7 : analyse de données (EDA, data mining, machine learning)

Auteure : Sarra Abdeljaouad · Source : **TuniShop_DWH, lecture directe des 23 vues `bi`** (SQL Server)

## Arborescence

```
TuniShop_Etape7_Analyse/
├── 00_Commun/                    code commun + installation
│   ├── tunishop_analytics/       module Python partagé par tous les notebooks
│   │   ├── __init__.py
│   │   ├── config.py             réglages : serveur SQL, dossiers, valeurs validées, style, exports
│   │   ├── chargement.py         liaison directe avec les vues bi (connexion, sql(), lecture des vues)
│   │   ├── validation.py         contrôles de qualité C01 à C11 + Rapport_Qualite_Analytique.xlsx
│   │   ├── temporal_split.py     dates de coupure, apprentissage 2023-2024 / test 2025
│   │   ├── features.py           tables de variables, RFM, paniers, dictionnaire et lignage
│   │   ├── publication.py        copie de chaque résultat dans la base SQL TuniShop_ANALYTICS
│   │   ├── modeles.py            fiches d'identité et registre des modèles (v1.2)
│   │   └── documentation.py      lignage et dictionnaire des tables ana, vues pbi et mesures DAX (v1.2)
│   ├── sql/                      7 scripts SSMS de la base TuniShop_ANALYTICS + LISEZMOI
│   ├── executer_analyse.py       exécute tous les notebooks dans l'ordre (job SQL Agent) + journal
│   ├── figer_versions.py         écrit requirements-lock.txt (versions exactes du poste)
│   ├── docs/                     documentation technique du module (pdoc, index.html)
│   ├── tunishop_kpi.py           règles du dictionnaire des KPI (phase BI), utilisées par chargement
│   ├── requirements.txt          bibliothèques (versions bornées)
│   ├── requirements-dev.txt      pytest, pdoc, nbstripout
│   └── README.md
├── 01_EDA/                       6 notebooks d'analyse exploratoire
├── 02_Data_Mining/               phase 2
├── 03_Machine_Learning/          phase 3
├── 04_Livrables/                 rapports PDF et Excel par phase
├── 05_Data/
│   ├── features/                 clients, commandes, produits_mois, expeditions (.parquet)
│   └── metadata/                 Dictionnaire_Variables.xlsx, Data_Lineage.xlsx
├── 06_Exports/                   Figures, Tables, Modeles (+ fiches/), Predictions, Journaux
├── 07_PowerBI/                   projet Power BI TuniShop_Analyse_ML.pbip
├── tests/                        28 tests pytest
├── CHANGELOG.md                  journal des versions
└── 00_ORDRE_EXECUTION.md         ordre complet, numéroté
```

`tunishop_kpi.py` n'apparaît pas dans l'arborescence de départ : c'est le module validé de la phase BI,
il est placé dans `00_Commun` pour que l'analyse applique exactement les mêmes règles que le DWH, les cubes
et les tableaux de bord.

## Installation (une fois)

1. Vérifie dans SSMS que tu ouvres `TuniShop_DWH` avec ton compte Windows.
2. Si ton serveur ne s'appelle pas `localhost`, change `SERVEUR` en haut de `00_Commun/tunishop_analytics/config.py`
   (exemple : `SERVEUR = r"localhost\SQLEXPRESS"`).
3. Dans le terminal de VS Code : `pip install -r 00_Commun/requirements.txt`
4. Ouvre le dossier `TuniShop_Etape7_Analyse` dans VS Code (Fichier → Ouvrir le dossier).

Chaque notebook commence par `sys.path.insert(0, "../00_Commun")` : il doit rester dans son dossier
(01_EDA, 02_Data_Mining ou 03_Machine_Learning) pour trouver le module.

## Ordre d'exécution — phase 1 (EDA)

| Ordre | Notebook | Produit |
|---|---|---|
| 1 | `01_EDA/01_EDA_Global` | contrôles C01-C11, vue d'ensemble, `05_Data/features/*.parquet`, `05_Data/metadata/*.xlsx`, `04_Livrables/EDA/Rapport_Qualite_Analytique.xlsx` |
| 2 | `02_EDA_Sales` | Q1, Q2, Q9 |
| 3 | `03_EDA_Customers` | Q5, Q6, Q7, Q8, Q15, Q18 |
| 4 | `04_EDA_Products` | Q3, Q4, Q16 |
| 5 | `05_EDA_Stock_Logistics` | Q13, Q14, Q19, Q20, Q21 |
| 6 | `06_EDA_Marketing_Finance` | Q10, Q11, Q12, Q17 |

Les numéros Q1 à Q21 sont ceux du `Plan_Analyse_EDA.xlsx` (dossier 01_Cadrage_EDA). Chaque notebook enregistre
ses figures dans `06_Exports/Figures` et ses tableaux dans `06_Exports/Tables`.

## Livrables de la phase 1

| Fichier | Contenu |
|---|---|
| `04_Livrables/EDA/Rapport_EDA_Global.pdf` | rapport complet : démarche, qualité, vue d'ensemble, 21 questions avec verdicts, transmission au DM et au ML |
| `04_Livrables/EDA/Rapport_Qualite_Analytique.xlsx` | les 11 contrôles de qualité (régénéré par 01_EDA_Global) |
| `04_Livrables/EDA/Synthese_Insights.pdf` | 10 insights, implications, actions recommandées, ce qui est transmis à la suite |

## Ordre d'exécution — phase 2 (data mining)

Prérequis : `01_EDA/01_EDA_Global` exécuté (tables de `05_Data/features`). Chaque notebook vérifie sa table par une
requête SQL directe sur les vues du DWH ; `RECONSTRUIRE = True` reconstruit la table depuis le DWH.

| Ordre | Notebook | Produit |
|---|---|---|
| 1 | `02_Data_Mining/01_Segmentation_RFM` | `05_Data/features/segments_rfm.parquet` (variable du churn), `06_Exports/Modeles/rfm_seuils.json` |
| 2 | `02_Clustering_Clients` (après le 1) | `05_Data/features/clusters_clients.parquet`, `06_Exports/Modeles/clustering_kmeans.joblib` |
| 3 | `03_Association_Produits` | `06_Exports/Modeles/regles_association.parquet`, `articles_populaires.json` |
| 4 | `04_Analyse_Comportement_Achat` | facteurs de rachat et rythme d'achat (`06_Exports/Tables/DM04_*`) |

Livrables : `04_Livrables/Data_Mining/Rapport_Segmentation.pdf` (RFM, clustering, comportement d'achat) et
`Rapport_Associations.pdf`, datés du 19/11/2026.

`segments_rfm.parquet` et `clusters_clients.parquet` ne figurent pas dans l'arborescence de départ de `05_Data/features` :
ce sont les variables produites par le data mining pour le modèle de churn.

## Ordre d'exécution — phase 3 (machine learning)

Prérequis : phases 1 et 2 exécutées (tables de `05_Data/features`, segments RFM et groupes k-means).

| Ordre | Notebook | Produit |
|---|---|---|
| 1 | `03_Machine_Learning/01_Preparation_Datasets_ML` | `05_Data/features/ml_*.parquet` (cibles, fuites, vides, dérive contrôlés) |
| 2 | `02_Prevision_Ventes` | Ridge « calendrier » (retenu), prévisions 2025, prévision 2026 si le calendrier est renseigné dans `v_dim_date` |
| 3 | `03_Prediction_Churn` | gradient boosting (retenu) |
| 4 | `04_Prediction_Demande` | version 2 « catégorie × part produit » retenue (v1.2) ; le ML ne bat pas la référence |
| 5 | `06_Prediction_Retard_Livraison` | régression logistique (retenue) — notebook ajouté à l'arborescence de départ |
| 6 | `05_Evaluation_Modeles` | `04_Livrables/Machine_Learning/Comparaison_Modeles.xlsx` |
| 7 | `08_Scoring_Actuel` | modèles de production, scores du jour (clients actifs, colis en transit), registre des modèles |
| 8 | `09_Suivi_Modeles` | suivi des modèles : erreurs par période, calibrage, PSI, alertes |
| 9 | `07_Publication_Resultats` | republie tous les résultats dans TuniShop_ANALYTICS, contrôle la base, met à jour lignage et dictionnaire (en dernier) |

Règle commune : apprentissage 2023-2024, choix des modèles et des seuils sur une validation interne à 2024,
test 2025 utilisé une seule fois. Modèles dans `06_Exports/Modeles`, prédictions dans `06_Exports/Predictions`.
Livrables : `Rapport_Modelisation.pdf` et `Comparaison_Modeles.xlsx`, datés du 26/11/2026.

## Base des résultats TuniShop_ANALYTICS (pour Power BI)

Chaque tableau de résultats est écrit à **deux endroits** : le fichier (CSV dans `06_Exports/Tables`, Parquet
dans `05_Data/features` et `06_Exports/Predictions`), exactement comme avant, **et** une table du schéma `ana`
de la base SQL Server `TuniShop_ANALYTICS` (même serveur que le DWH). Power BI lit les vues `pbi.*` de cette base,
qui relient les résultats aux vues `bi` du DWH. Le DWH n'est jamais modifié.

Mise en place : voir `00_Commun/sql/LISEZMOI_TuniShop_ANALYTICS.md` (scripts 01 à 05 dans SSMS, une fois).
Pour travailler sans la base : `PUBLIER_SQL = False` dans `config.py`.

## Sécurité

Aucun mot de passe dans le code : authentification Windows. En authentification SQL, le mot de passe est lu
dans la variable d'environnement `TUNISHOP_MDP`.

## Tests et documentation (v1.2)

- Tests : `pip install -r 00_Commun/requirements-dev.txt`, puis `python -m pytest -q tests` (28 tests ; base SQLite temporaire, aucun accès au DWH).
- Documentation du module : ouvrir `00_Commun/docs/index.html` ; pour la régénérer : `pdoc -o 00_Commun/docs 00_Commun/tunishop_analytics`.
- Exploitation : `04_Livrables/Exploitation/Guide_Exploitation_Phase_Analyse.pdf`.
