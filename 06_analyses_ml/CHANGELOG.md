# Journal des versions — TuniShop, étape 7 : Analyses & ML

Auteure : Sarra Abdeljaouad. Les dates sont celles du planning du projet.

## Version 1.5 — 19/11/2026 · Modèle de retard réappris sur 12 mois et suivi historisé

Les résultats évalués de la phase (notebooks 02 à 06, `Comparaison_Modeles.xlsx`) ne changent pas. La version 1.5 change le **modèle de retard de production** et garde l'**historique du suivi**.

### Pourquoi
- Le suivi v1.2 levait une alerte SahelLog presque chaque mois : le modèle de retard sous-estime SahelLog depuis sa rupture de juillet 2024.
- Le modèle de production était réappris sur tout l'historique (2023-2025) : il mélange l'avant-rupture (7 % de retard) et l'après (37 %).
- `ana.ml_suivi` était entièrement remplacée à chaque exécution : aucune évolution visible dans le temps.

### Décision (prise sur le suivi, après l'évaluation)
Rejoué mois par mois sur 2025, chaque mois réappris sur les données d'avant :

| Modèle de production | Alertes de calibrage (48 transporteur × mois) | Écart moyen SahelLog | Alertes au S2 2025 | AUC moyenne |
|---|---|---|---|---|
| Tout l'historique (v1.2 à v1.4) | 14 | −16,0 pt | 6 | 0,814 |
| **12 derniers mois, réappris chaque mois (retenu)** | **7** | −6,0 pt | **0** | **0,822** |
| 6 derniers mois | 15 | −0,4 pt | 5 | 0,810 |

La fenêtre de 12 mois est retenue : la meilleure au global et stable ; SahelLog est bien calibré dès que la rupture sort de la fenêtre (mai 2025). Ce choix s'appuie sur 2025 (période de test) : c'est une décision de production, pas une nouvelle évaluation.

### Code
- **Nouveau module `suivi.py`** : `rejouer_fenetre_glissante` (rejeu de la production mois par mois) et `historiser` (historique des exécutions, repérées par la date des dernières données ; relancer sur les mêmes données remplace, de nouvelles données ajoutent).
- `temporal_split.FENETRE_RETARD_PRODUCTION_MOIS = 12`.
- **`08_Scoring_Actuel`** : le modèle de retard de production est réappris sur les 12 derniers mois (26 647 expéditions au lieu de 58 776) ; sa fiche du registre le dit.
- **`09_Suivi_Modeles`** :
  - section 4 bis : 48 indicateurs du modèle de production rejoué (cas `retard_production`), figure `ML09_2_retard_production` ;
  - historique `06_Exports/Tables/ML_suivi_historique.csv` → `ana.ml_suivi_historique`.
  - Sur les données au 31/12/2025 : **171 indicateurs, 26 alertes** (123 et 19 en v1.4 ; les 7 nouvelles : SahelLog de janvier à avril 2025, plus 3 alertes isolées de Poste Colis Plus et TunExpress au 1er semestre ; aucune au 2nd semestre).
- `publication.py` : clé de `ml_suivi_historique` (date_donnees, cas, objet, periode, indicateur).

### Base TuniShop_ANALYTICS
- `02_Tables_ana.sql` : table `ana.ml_suivi_historique` (clé primaire), ligne du catalogue (84 tables) ; `ana.ml_suivi.indicateur` passe à NVARCHAR(100). Sur une base existante, la publication recrée `ana.ml_suivi` d'elle-même (« structure modifiée »).
- `03_Vues_pbi_Power_BI.sql` : vue `pbi.v_ml_suivi_historique`.
- `04_Controles_TuniShop_ANALYTICS.sql` : contrôle **H1** (la dernière exécution est dans l'historique).

### Tests
- `tests/test_suivi.py` : 9 tests (historique, rejeu, publication avec clé). **80 tests** au total.

### À faire après exécution sur SQL Server
- Fiches modèles et guide d'exploitation : fenêtre de 12 mois du modèle de retard, historique du suivi.
- PV complémentaire v1.5, avec les chiffres de l'exécution.
- Plateforme vue 360 : la page Modèles affichera 171 indicateurs et 26 alertes après le prochain export ; elle peut lire l'historique (`pbi.v_ml_suivi_historique`) pour tracer le suivi dans le temps.

## Version 1.3 — 17/11/2026 · Demande de l'année suivante et clôture globale

Les résultats validés de la phase ne changent pas. La version 1.3 prolonge la demande par produit vers l'année suivante.

### Code et base
- **Demande de l'année suivante** (`03_Machine_Learning/08_Scoring_Actuel`, section 3 bis) : prévision 2026 par produit avec le modèle retenu (version 2), comparée au stock de départ ; mois de rupture sans réapprovisionnement.
- **Publication** (`publication.py`) : table `ana.ml_scores_demande` (7 140 lignes = 595 produits × 12 mois) et sa clé.
- **SQL** : table et ligne du catalogue (83 tables), vue `pbi.v_ml_scores_demande` (19 vues pbi), contrôle **L8** (produits absents du DWH).
- Exécution complète du 11/11/2026 par le job SQL Server Agent (publication de 18:46) : 19 notebooks sur 19, L1 à L8 au statut OK.

### Power BI
- **Page 7 « Demande prévue et risque de rupture »** (projet .pbip v1.3) : 5 cartes, courbe réel / prévu 2025 / prévision 2026, produits épuisés par catégorie, tableau des produits les plus urgents.
- 1 table, 2 relations, 13 mesures DAX (66 au total) ; 7 pages, 63 visuels.
- Résultat : 74 702 unités prévues pour 2026 (+6,9 %, un plancher) ; 495 produits épuisés sans réapprovisionnement, dont 224 au 1er trimestre.

### Documents
- Recette du tableau de bord v4.0 : 9/9 ouverture, 52/52 valeurs, 63/63 visuels, 3 observations mineures (OB3 : libellés tronqués en page 7).
- **PV global de clôture** (`PV_Global_Phase_Analyse`) : consolide les PV v1.0 à v1.2 et valide la v1.3.
- Rapport final et rapport de validation v5.0 ; rapport final global v3.0 (50 captures) ; contrôles v5.0 ; guides et fiches modèles v1.1.
- Addendum au rapport de modélisation : la demande v2 est retenue depuis la v1.2 (le rapport du 31/10/2026 décrivait la v1.1).

## Version 1.2 — 10/12/2026 · Exploitation et documentation (après la clôture)

Lot d'améliorations après le PV de clôture du 03/12/2026. Les résultats validés de la phase ne changent pas, **sauf la demande par produit** (voir ci-dessous).

### Code
- **Scores du jour** (`03_Machine_Learning/08_Scoring_Actuel`) :
  - modèles de production du churn et du retard, réappris sur 2023-2025 avec les réglages et seuils validés ;
  - scores des 7 377 clients actifs au 31/12/2025 (`ana.ml_scores_churn_actuels`) ;
  - scores des 211 colis en transit (`ana.ml_scores_retard_en_cours`).
- **Registre des modèles** (module `modeles.py`) : chaque modèle a une fiche d'identité (version, période, lignes, empreinte des données, réglages, seuil, mesures, versions des bibliothèques), enregistrée dans `06_Exports/Modeles/fiches/*.json` et publiée dans `ana.ml_registre_modeles`.
- **Suivi des modèles** (`09_Suivi_Modeles`) :
  - 123 indicateurs par période (erreur des ventes, WAPE de la demande, AUC et calibrage du churn, calibrage du retard par transporteur, PSI des variables) ;
  - statut OK / ALERTE dans `ana.ml_suivi`. Sur 2025 : 19 alertes, dont 12 mois de SahelLog (retard sous-estimé), 3 variables du retard en dérive (calendrier), décembre 2025 pour les ventes (34 %) et mars 2025 pour le calibrage du churn.
- **Demande, version 2** (`features.prevision_demande_v2`) : prévision par catégorie (saisonnalité et croissance de l'année précédente), répartie par produit.
  - **Retenue** sur la validation 2024 : WAPE 55,1 % contre 57,1 % pour la référence.
  - Test 2025 : 47,5 % contre 47,7 %.
  - La colonne `prevision_retenue` est ajoutée aux prédictions ; la vue `pbi.v_ml_demande` la lit.
- **Déciles de risque du churn** harmonisés : 1 = clients les plus à risque, dans le notebook comme dans Power BI.
- **Variables du clustering** déplacées dans le module (`features.variables_clustering`), pour que le scoring affecte les nouveaux clients exactement comme l'apprentissage.
- **Expéditions en cours** : `features.table_expeditions(..., en_cours=True)`.
- **Journal d'exécution** : `executer_analyse.py` écrit `06_Exports/Journaux/execution_*.log` et `journal_executions.csv`. L'ordre des notebooks passe à 01 → 06 → 05 → 08 → 09 → 07.
- **Tests automatiques** : `tests/`, 28 tests pytest (découpage dans le temps, mesures, PSI, segments RFM, absence de fuite, demande v2, publication, registre).
- **Versions** : `requirements.txt` avec bornes, `requirements-dev.txt`, `figer_versions.py` (écrit `requirements-lock.txt`).
- **Git** : `.gitignore` (données, exports, cache Power BI) et `.gitattributes` (nbstripout).
- **SQL** :
  - 4 nouvelles tables ;
  - 4 nouvelles vues (`pbi.v_ml_scores_churn`, `pbi.v_ml_scores_retard`, `pbi.v_ml_registre`, `pbi.v_ml_suivi`) ;
  - contrôles L6-L7 (clés des scores) ;
  - `pbi.v_ml_demande` lit le modèle retenu.

- **Power BI, page 6 « Scores du jour et suivi des modèles »** (projet .pbip v1.2) :
  - 6 cartes (date de scoring, clients actifs scorés, clients en alerte, clients à cibler — déciles 4 à 7, colis en transit, alertes du suivi) ;
  - probabilité de churn par décile, clients en alerte par segment RFM, colis en transit et en alerte par transporteur ;
  - tableau du suivi (alertes en premier) et registre des modèles ;
  - 4 tables ajoutées au modèle (vues `pbi.v_ml_scores_churn`, `v_ml_scores_retard`, `v_ml_registre`, `v_ml_suivi`), 14 mesures DAX (53 au total) ;
  - `v_ml_demande` : la prévision affichée est celle du modèle retenu (version 2), colonne `quantite_reference` ajoutée.

### Documentation
- `Data_Lineage.xlsx` : feuilles 07 (fichiers → tables `ana` → vues `pbi`) et 08 (vues → sources → visuels Power BI).
- `Dictionnaire_Variables.xlsx` : feuilles 10 (colonnes des tables `ana`), 11 (colonnes des vues chargées par Power BI) et 12 (mesures DAX).
- Ces feuilles sont régénérées par `07_Publication_Resultats`.
- Documentation technique du module : `00_Commun/docs/index.html` (pdoc).
- Nouveaux documents dans `04_Livrables/Exploitation` :
  - guide d'exploitation ;
  - fiches modèles ;
  - guide utilisateur du tableau de bord ;
  - note sur les données personnelles et l'équité ;
  - présentation portfolio.

### Effet sur les livrables validés
- Tableau de bord, page 3 : la WAPE de la demande passe de 47,7 % à **47,5 %**. La valeur attendue V22 de la recette devient 47,5 %.
- Le rapport de modélisation et le rapport final global (03/12/2026) décrivent la version 1.1 : la demande y utilise la référence. La version 2 est documentée ici et dans les fiches modèles.

## Version 1.1 — 03/12/2026 · Clôture
- Rapport final global, rapport de validation v3.0, PV de clôture : **validé sans réserve**.
- Tableau de bord Power BI v1.1 (anomalies de recette E1 à E7 corrigées), recette v2.0 sans réserve.
- Texte de la prévision 2026 corrigé dans `02_Prevision_Ventes` (anomalie A10).

## Version 1.0 — 26/11/2026 · Livraison des phases
- EDA (12/11/2026), data mining (19/11/2026), machine learning (26/11/2026).
- Base TuniShop_ANALYTICS (scripts 01 à 07), publication des résultats, tableau de bord Power BI v1.0.
- Réserves R1 (calendrier 2026) et R2 (exécution du ML sur le DWH réel), levées le 27/11/2026.
