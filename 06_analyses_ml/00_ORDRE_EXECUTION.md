# TuniShop — Étape 7 : ordre d'exécution complet (version 1.5.1)

Auteure : Sarra Abdeljaouad · Suis les numéros dans l'ordre. Chaque étape a besoin de la précédente.
Ce qui change depuis la version 1.1 : voir `CHANGELOG.md` et les sections G à J (mises à jour).

## A. Préparation — une seule fois

| N° | Où | Fichier / action | Résultat attendu |
|---|---|---|---|
| 1 | Terminal VS Code | `pip install -r 00_Commun/requirements.txt` | bibliothèques installées |
| 2 | SSMS (`localhost`), F5 | `00_Commun/sql/01_Creer_base_TuniShop_ANALYTICS.sql` | « Étape 01 terminée » |
| 3 | SSMS, F5 | `00_Commun/sql/02_Tables_ana.sql` | « Étape 02 terminée : 84 tables… » |
| 4 | SSMS, F5 | `00_Commun/sql/03_Vues_pbi_Power_BI.sql` | « Étape 03 terminée » (20 vues `pbi` ; les 4 vues `pbi.v_tm_*` viennent du script 09, v1.4) |
| 5 | SSMS, F5 | `00_Commun/sql/04_Controles_TuniShop_ANALYTICS.sql` | lignes P1 en INFO (tables encore vides : normal) |
| 6 | SSMS, F5 | `00_Commun/sql/05_Droits_TuniShop_ANALYTICS.sql` | **seulement** si un autre compte que le tien lance les notebooks ou lit Power BI |

## B. Analyse — à chaque fois (notebooks, dans VS Code : « Exécuter tout »)

| N° | Dossier | Notebook | Produit |
|---|---|---|---|
| 7 | `01_EDA` | `01_EDA_Global` | contrôles C01-C11, 4 tables de variables (à faire en premier) |
| 8 | `01_EDA` | `02_EDA_Sales` | Q1, Q2, Q9 |
| 9 | `01_EDA` | `03_EDA_Customers` | Q5, Q6, Q7, Q8, Q15, Q18 |
| 10 | `01_EDA` | `04_EDA_Products` | Q3, Q4, Q16 |
| 11 | `01_EDA` | `05_EDA_Stock_Logistics` | Q13, Q14, Q19, Q20, Q21 |
| 12 | `01_EDA` | `06_EDA_Marketing_Finance` | Q10, Q11, Q12, Q17 |
| 13 | `02_Data_Mining` | `01_Segmentation_RFM` | segments RFM |
| 14 | `02_Data_Mining` | `02_Clustering_Clients` | groupes k-means |
| 15 | `02_Data_Mining` | `03_Association_Produits` | règles d'association |
| 16 | `02_Data_Mining` | `04_Analyse_Comportement_Achat` | facteurs de rachat |
| 16 bis | `02_Data_Mining` | `05_Text_Mining_Avis` | **v1.4** : thèmes, langue, polarité des avis, confrontation aux faits (4 tables `ana.tm_*`) |
| 17 | `03_Machine_Learning` | `01_Preparation_Datasets_ML` | 4 jeux de données ML |
| 18 | `03_Machine_Learning` | `02_Prevision_Ventes` | prévision des ventes (2025 et 2026) |
| 19 | `03_Machine_Learning` | `03_Prediction_Churn` | scores de churn (test 2025) |
| 20 | `03_Machine_Learning` | `04_Prediction_Demande` | prévision de la demande (version 2 retenue) |
| 21 | `03_Machine_Learning` | `06_Prediction_Retard_Livraison` | **avant le 05** : scores de retard (test 2025) |
| 22 | `03_Machine_Learning` | `05_Evaluation_Modeles` | `Comparaison_Modeles.xlsx` (après 02, 03, 04 et 06) |
| 23 | `03_Machine_Learning` | `08_Scoring_Actuel` | modèles de production (**v1.5** : retard réappris sur les 12 derniers mois ; **v1.5.1** : seuil d'alerte choisi sur la production rejouée), scores des clients actifs et des colis en transit, registre des modèles |
| 24 | `03_Machine_Learning` | `09_Suivi_Modeles` | 171 indicateurs de suivi et alertes (`ana.ml_suivi`) ; **v1.5** : modèle de retard de production rejoué mois par mois, historique des exécutions (`ana.ml_suivi_historique`) |
| 25 | `03_Machine_Learning` | `07_Publication_Resultats` | toutes les tables `ana` remplies et contrôlées, lignage et dictionnaire mis à jour (en dernier) |

Raccourci : les étapes 7 à 25 se lancent d'un coup dans le terminal avec
`python 00_Commun/executer_analyse.py` (arrêt au premier notebook en erreur ; journal dans `06_Exports/Journaux`).
Ordre des notebooks ML : 01 → 02 → 03 → 04 → 06 → 05 → 08 → 09 → 07.

## C. Vérification

| N° | Où | Action | Résultat attendu |
|---|---|---|---|
| 26 | SSMS | `EXEC TuniShop_ANALYTICS.ctl.usp_controler_publication;` | OK partout, L6, L7 et H1 compris (INFO seulement pour une table jamais publiée) |
| 27 | Excel | `06_Exports/Journaux/journal_executions.csv` | toutes les lignes de l'exécution à « OK » |
| 28 | Terminal | `pip install -r 00_Commun/requirements-dev.txt`, puis `python -m pytest -q tests` | 81 tests réussis (28 + 43 du text mining, v1.4 + 10 du suivi, v1.5 et v1.5.1) |
| 29 | Terminal | `python 00_Commun/figer_versions.py` | `00_Commun/requirements-lock.txt` écrit (versions exactes de ton poste) |

## D. Facultatif

| N° | Où | Fichier | Quand |
|---|---|---|---|
| 30 | SSMS, F5 | `00_Commun/sql/06_Lien_TuniShop_ADMIN.sql` | pour suivre l'analyse dans TuniShop_ADMIN |
| 31 | SSMS (instance avec SQL Server Agent), F5 | `00_Commun/sql/07_Etape_job_Agent.sql` | pour lancer l'analyse chaque nuit après les cubes (adapter `@python`, `@racine`, `@proxy`) |
| 32 | Terminal | `git init`, `nbstripout --install --attributes .gitattributes`, `git add .`, `git commit`, `git tag v1.5.1` | pour versionner le projet (guide d'exploitation, section 8) |

## E. Résultat final : Power BI

| N° | Où | Action |
|---|---|---|
| 33 | Power BI Desktop | Ouvrir `07_PowerBI/TuniShop_Analyse_ML.pbip`, puis Accueil > **Actualiser** (identifiants Windows) : 7 pages prêtes (page 6 « Scores du jour et suivi » ajoutée en v1.2, page 7 « Demande prévue et risque de rupture » en v1.3) |
| 34 | Excel | Recette : `04_Livrables/Tableaux_de_bord/Recette_Tableau_de_bord_Analyse.xlsx` ; en version 1.2, la valeur attendue **V22 (WAPE de la demande) devient 47,5 %** |

## F. Cas particulier : prévision de l'année suivante

Après avoir chargé le calendrier de l'année dans le DWH (lignes ajoutées à `dim_calendrier.csv`, puis rechargement
de la chaîne staging → DWH), relance les étapes 18 (`02_Prevision_Ventes`), 22, 23, 24 et 25, puis 26 :
la table `ana.ml_pred_ventes_2026` (ou de l'année suivante) est alors remplie.

## G. Passer de la version 1.1 à la version 1.2 (une fois)

1. Fermer Power BI ; garder une copie de l'ancien dossier (`TuniShop_Etape7_Analyse_v1.1`).
2. `pip install -r 00_Commun/requirements.txt`.
3. SSMS : `02_Tables_ana.sql` (4 nouvelles tables).
4. Exécuter toute la chaîne (étapes 7 à 25) : la table `ana.ml_pred_demande_2025` est recréée automatiquement avec la colonne `prevision_retenue`.
5. SSMS : `03_Vues_pbi_Power_BI.sql` **après** la chaîne (la vue `pbi.v_ml_demande` lit `prevision_retenue`), puis `04_Controles_TuniShop_ANALYTICS.sql`.
6. Étapes 26 à 29, puis Power BI > Actualiser : seule la WAPE de la demande change (47,7 % → 47,5 %).

Documents d'exploitation : `04_Livrables/Exploitation` (guide d'exploitation, fiches modèles, guide utilisateur du
tableau de bord, note données personnelles et équité).


## H. Passer à la version 1.4 : text mining des avis (une fois)

1. Copier les fichiers du kit v1.4 à leur place (voir `LISEZMOI_v1.4.md`).
2. Terminal : `python -m pytest -q tests` → 71 tests réussis.
3. VS Code : exécuter `02_Data_Mining/05_Text_Mining_Avis` (« Exécuter tout ») : les 4 tables `ana.tm_*` sont créées et remplies.
4. SSMS, F5 : `00_Commun/sql/09_Text_Mining_TuniShop_ANALYTICS.sql` (4 vues `pbi.v_tm_*`, catalogue, contrôles T1 à T5).
5. Ensuite, le notebook fait partie de la chaîne : `executer_analyse.py` et le job de nuit le lancent avec le data mining.


## I. Passer à la version 1.5 : modèle de retard sur 12 mois et suivi historisé (une fois)

1. Copier les fichiers du kit v1.5 à leur place (voir `LISEZMOI_v1.5.md`).
2. Terminal : `python -m pytest -q tests` → 81 tests réussis (v1.5.1).
3. SSMS, F5 : `02_Tables_ana.sql` (table `ana.ml_suivi_historique`), puis `03_Vues_pbi_Power_BI.sql` (vue `pbi.v_ml_suivi_historique`), puis `04_Controles_TuniShop_ANALYTICS.sql` (contrôle H1).
4. VS Code, dans l'ordre : `08_Scoring_Actuel`, `09_Suivi_Modeles`, `07_Publication_Resultats` (« Exécuter tout »).
5. SSMS : `EXEC TuniShop_ANALYTICS.ctl.usp_controler_publication;` → OK partout, H1 compris.
6. Ensuite, la chaîne complète (`executer_analyse.py`, job de nuit) fait tout : chaque exécution sur de nouvelles données ajoute ses lignes à l'historique.

## J. Passer à la version 1.5.1 : seuil d'alerte du retard (une fois)

1. Copier les fichiers du kit v1.5.1 à leur place (voir `LISEZMOI_v1.5.md`, section « Version 1.5.1 »).
2. Terminal : `python -m pytest -q tests` → 81 tests réussis.
3. VS Code, « Exécuter tout » : `08_Scoring_Actuel` (attendu : « seuil de production … : 0.22 »), `09_Suivi_Modeles`, `07_Publication_Resultats`. Aucun script SQL à relancer.
4. Plateforme vue 360 : `.\scripts\mettre_a_jour.ps1` depuis la version HTML.
