# TuniShop · Analyses & Machine Learning

**Projet portfolio data / BI de bout en bout · Étape 7 · Sarra Abdeljaouad · version 1.6**

TuniShop est une enseigne e-commerce tunisienne **fictive** ; toutes les données sont **synthétiques**.
Cette étape transforme l'entrepôt de données (TuniShop_DWH) en décisions mesurées : exploration, data mining,
quatre modèles de machine learning, une base de résultats SQL Server et un tableau de bord Power BI.

```
Staging (3 bases) ──► TuniShop_DWH (23 vues bi, lecture seule)
                          │
                          ▼
              20 notebooks Python (EDA ▸ data mining ▸ text mining ▸ ML ▸ scores ▸ suivi)
                          │                    │
                          ▼                    ▼
              fichiers CSV / Parquet     TuniShop_ANALYTICS (88 tables ana, 24 vues pbi, contrôles ctl)
                                               │
                                               ▼
                                   Power BI TuniShop_Analyse_ML (7 pages)
```

## Résultats clés (test sur 2025, jamais vu à l'apprentissage)

| Cas | Modèle retenu | Mesure | Modèle | Référence |
|---|---|---|---|---|
| Ventes mensuelles par catégorie | Ridge « calendrier » | MAPE | **9,5 %** | 15,3 % (Holt-Winters) |
| Churn à 90 jours | Gradient boosting, sans genre ni âge (v1.6) | AUC | **0,818** | 0,794 (règle « récence ») |
| Demande par produit | Catégorie × part produit (v2) | WAPE | **47,5 %** | 47,7 % (moyenne de l'année précédente) |
| Retard de livraison | Régression logistique | AUC | **0,811** | 0,728 (règle transporteur) |

La version 1.6 ne change pas ces résultats : le churn garde son AUC sans genre ni tranche d'âge, et la demande corrigée (v3) n'a pas remplacé la v2 (voir plus bas).

- EDA : CA reconnu +110,8 % entre 2023 et 2025 ; retards de livraison de 9,6 % à 17,3 % ; 21 hypothèses testées.
- Data mining : 8 segments RFM (churn de 30 % pour les Champions à 90 % pour les Perdus), 4 groupes k-means.
- Prévision : 10,37 M DT de CA TTC en 2026 (7,07 M DT en 2025).
- Demande de l'année suivante (v1.3) : 74 702 unités prévues pour 595 produits, à lire comme un plancher (biais de −23,5 % sur 2025) ; sans réapprovisionnement, 224 produits épuisés dès le 1er trimestre 2026. La version corrigée (v1.6) ramène le biais à −6,8 % mais ne gagne pas produit par produit.
- Équité (v1.6) : le genre et la tranche d'âge ne sont plus des variables du churn, sans perte de performance (AUC 0,8179 sans, 0,8177 avec). Le score reste aussi juste pour les femmes et les hommes (AUC 0,817 / 0,819) et selon l'âge (0,804 à 0,829).

## Version 1.6 (26/12/2026) : churn sans données personnelles, demande corrigée du biais

Deux points de suivi du PV final sont traités.

**Churn.** Le genre et la tranche d'âge sont retirés des variables du modèle (données personnelles sensibles, loi tunisienne 2004-63). Ils restent lus à part, uniquement pour mesurer l'équité :

- coût en performance : le même modèle est réappris avec ces deux variables et comparé sur 2025 ;
- équité : AUC, rappel et précision du modèle retenu par genre et par tranche d'âge (`ML03_cout_equite`, `ML03_equite`).

**Demande.** La version 3 multiplie la version 2 par un coefficient par catégorie : réel / prévu de l'année précédente, borné entre 0,8 et 1,5 (`features.prevision_demande_v3`). Pour le test 2025, le coefficient est appris sur 2024 ; pour la prévision 2026, sur 2025. La version 2 reste publiée dans la colonne `quantite_plancher`.

**Règles de décision, fixées avant l'exécution**

- Churn : le modèle sans genre ni tranche d'âge est gardé si ces deux variables apportent moins de 0,005 d'AUC sur 2025.
- Demande : la v3 remplace la v2 si, sur 2025, son biais est plus proche de 0 **et** sa WAPE n'est pas plus mauvaise.
- Limite assumée : la v3 ne peut pas passer par la validation 2024, puisque son coefficient vient de 2024. C'est le test 2025 qui tranche, selon la règle ci-dessus.

**Fichiers modifiés**

| Fichier | Changement |
|---|---|
| `00_Commun/tunishop_analytics/features.py` | `genre` et `tranche_age` retirés de `CAS_ML["churn"]`, gardés dans `VARIABLES_SENSIBLES_CHURN` ; `coefficients_correction_demande` et `prevision_demande_v3` |
| `03_Machine_Learning/03_Prediction_Churn.ipynb` | modèle sans genre ni âge ; section 3 bis (coût et équité) |
| `03_Machine_Learning/04_Prediction_Demande.ipynb` | candidat v3, règle de choix v1.6, table `ML04_coefficients_v3` |
| `03_Machine_Learning/08_Scoring_Actuel.ipynb` | lit le modèle de demande retenu ; colonne `quantite_plancher` ; fiche `demande_v3` au registre si retenue |

**Résultats (test 2025)**

| Cas | Comparaison | Résultat | Décision |
|---|---|---|---|
| Churn | sans / avec genre et tranche d'âge | AUC 0,8179 / 0,8177 ; seuil 0,40 / 0,37 ; rappel 89,4 % / 91,3 % ; précision 75,4 % / 74,3 % | **sans** (gain des deux variables : −0,0002) |
| Demande | v3 / v2 | biais −6,8 % / −23,5 % ; WAPE catégorie × mois 20,3 % / 27,4 % ; WAPE produit × mois 48,0 % / 47,5 % | **v2 gardée** (une seule condition remplie) |

- Équité : clients sans tranche d'âge (542 photos, surtout des professionnels) : rappel de 72 %, contre environ 90 % pour les autres ; à suivre.
- Scores du jour au 31/12/2025 : 5 779 clients en alerte sur 7 377 (78,3 %), contre 5 950 avant (seuil 0,40 au lieu de 0,37).
- Contrôles : 81 tests sur 81 ; `ctl.usp_controler_publication` au statut OK, les 3 nouvelles tables comprises.

**Exécution de la v1.6**

1. Tests : `python -m pytest -q tests`.
2. Notebooks, dans l'ordre : `03_Prediction_Churn`, `04_Prediction_Demande`, `05_Evaluation_Modeles`, `08_Scoring_Actuel`, `09_Suivi_Modeles`, `07_Publication_Resultats`.
3. Contrôle dans SSMS : `EXEC ctl.usp_controler_publication`.

La chaîne complète (`python 00_Commun/executer_analyse.py` ou le job SQL Server Agent) fait les mêmes étapes. `01_Preparation_Datasets_ML` n'a pas besoin d'être réexécuté : s'il l'est, `03` relit le genre et la tranche d'âge depuis la table `clients`.

À la publication, `ana.ml_scores_demande` et `ana.ml_pred_demande_2025` reçoivent une colonne de plus et sont recréées (message « structure modifiée »). Le script `02_Tables_ana.sql` (v1.6) ajoute les 3 nouvelles tables au catalogue (87 tables). Dans Power BI, cliquer sur Actualiser : la page 7 ne change pas, les pages 2 et 6 lisent le nouveau modèle de churn.

## Ce qui rend le projet « exploitable »

- **Méthode** : apprentissage 2023-2024, choix sur une validation interne à 2024, test 2025 ; un modèle n'est retenu que s'il bat une référence simple d'au moins 1 %.
- **Double sortie** : chaque résultat est écrit en fichier et dans une table SQL (une transaction), contrôlée par `ctl.usp_controler_publication`.
- **Production** : scores du jour (clients actifs, colis en transit), registre des modèles versionné ; le modèle de retard en production est réappris sur une fenêtre glissante de 12 mois, calibré par transporteur, avec un seuil d'alerte recalculé à chaque exécution sur la production rejouée (v1.5 et 1.5.1).
- **Suivi** : 171 indicateurs (erreur, calibrage, PSI), production rejouée mois par mois sur 2025 (12 mois, 26 alertes) et historique des exécutions dans `ana.ml_suivi_historique` (v1.5).
- **Qualité** : 81 tests pytest, versions bornées et figées, journal d'exécution, Git + nbstripout, documentation pdoc.
- **Sécurité** : aucun mot de passe dans le code (authentification Windows), lecture seule de l'entrepôt.

## Démarrer

1. Lire `00_ORDRE_EXECUTION.md` : toutes les étapes sont numérotées (SSMS, notebooks, contrôles, Power BI).
2. Installation : `pip install -r 00_Commun/requirements.txt` ; base : scripts `00_Commun/sql/01` à `04` dans SSMS.
3. Tout exécuter : `python 00_Commun/executer_analyse.py`.
4. Tests : `pip install -r 00_Commun/requirements-dev.txt` puis `python -m pytest -q tests`.

## Arborescence

| Dossier | Contenu |
|---|---|
| `00_Commun` | module `tunishop_analytics`, scripts SQL, lanceur, versions, documentation technique |
| `01_EDA`, `02_Data_Mining`, `03_Machine_Learning` | 20 notebooks |
| `04_Livrables` | rapports par phase, rapport final global, recette du tableau de bord, documents d'exploitation |
| `05_Data` | tables de variables, dictionnaire, lignage |
| `06_Exports` | figures, tableaux, modèles et fiches, prédictions, journaux |
| `07_PowerBI` | projet Power BI (.pbip) |
| `tests` | tests automatiques |

## Documents à lire en premier

- `04_Livrables/Phase_Analyse/Rapport_Final_Global_Phase_Analyse.pdf` : la phase de bout en bout.
- `04_Livrables/Exploitation/` : guide d'exploitation, fiches modèles, guide utilisateur du tableau de bord, note données personnelles et équité.
- `CHANGELOG.md` : historique des versions, de la 1.0 à la 1.6 (modèle de retard sur 12 mois, seuil d'alerte recalculé, suivi historisé, vue `pbi.v_tm_avis` réécrite : 0,12 s au lieu de 157 s, le 20/12/2026 ; affichage du tableau de bord corrigé, le 23/12/2026 ; churn sans données personnelles et demande corrigée, le 26/12/2026).
- `04_Livrables/Phase_Analyse/PV_Final_Global_Phase_Analyse.pdf` : PV de clôture de la phase, versions 1.0 à 1.6.

## Compétences

SQL Server / T-SQL · Python (pandas, scikit-learn) · validation temporelle et suivi de dérive · Power BI (PBIP, DAX) ·
tests et documentation · protection des données (loi tunisienne 2004-63).

## Limites connues

Retard de SahelLog : corrigé en v1.5 par la fenêtre glissante de 12 mois (37,3 % prévu pour 37,3 % réel) ; erreur forte sur les petits produits ;
churn expliqué surtout par la récence ; rappel plus faible pour les clients professionnels (72 %) ; correction de la demande (v3) jugée sur le test 2025, faute de validation possible, et non retenue.
Détails dans le rapport final et les fiches modèles.
