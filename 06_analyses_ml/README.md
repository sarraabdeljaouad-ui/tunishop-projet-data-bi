# TuniShop — Analyses & Machine Learning

**Projet portfolio data / BI de bout en bout · Étape 6 · Sarra Abdeljaouad · version 1.5.2**

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
| Churn à 90 jours | Gradient boosting | AUC | **0,818** | 0,794 (règle « récence ») |
| Demande par produit | Catégorie × part produit (v2) | WAPE | **47,5 %** | 47,7 % (moyenne de l'année précédente) |
| Retard de livraison | Régression logistique | AUC | **0,811** | 0,728 (règle transporteur) |

- EDA : CA reconnu +110,8 % entre 2023 et 2025 ; retards de livraison de 9,6 % à 17,3 % ; 21 hypothèses testées.
- Data mining : 8 segments RFM (churn de 30 % pour les Champions à 90 % pour les Perdus), 4 groupes k-means.
- Prévision : 10,37 M DT de CA TTC en 2026 (7,07 M DT en 2025).
- Demande de l'année suivante (v1.3) : 74 702 unités prévues pour 595 produits ; sans réapprovisionnement, 224 produits épuisés dès le 1er trimestre 2026.
- Équité : le score de churn est aussi juste pour les femmes et les hommes (AUC 0,817 / 0,818) et selon l'âge.

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

- `04_Livrables/Phase_Analyse/Rapport_Final_Global_Phase_Analyse.pdf` — la phase de bout en bout.
- `04_Livrables/Exploitation/` — guide d'exploitation, fiches modèles, guide utilisateur du tableau de bord, note données personnelles et équité.
- `CHANGELOG.md` — historique des versions, de la 1.0 à la 1.5.2 (modèle de retard sur 12 mois, seuil d'alerte recalculé, suivi historisé, vue `pbi.v_tm_avis` réécrite : 0,12 s au lieu de 157 s, 20/11/2026).
- `04_Livrables/Phase_Analyse/PV_Final_Global_Phase_Analyse.pdf` — PV de clôture de la phase, versions 1.0 à 1.5.2.

## Compétences

SQL Server / T-SQL · Python (pandas, scikit-learn) · validation temporelle et suivi de dérive · Power BI (PBIP, DAX) ·
tests et documentation · protection des données (loi tunisienne 2004-63).

## Limites connues

Retard de SahelLog : corrigé en v1.5 par la fenêtre glissante de 12 mois (37,3 % prévu pour 37,3 % réel) ; erreur forte sur les petits produits ; churn expliqué
surtout par la récence. Détails dans le rapport final et les fiches modèles.
