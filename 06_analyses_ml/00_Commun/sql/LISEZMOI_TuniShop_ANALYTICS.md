# TuniShop_ANALYTICS — mise en place pas à pas

Auteure : Sarra Abdeljaouad

## Ce que tu obtiens

```
TuniShop_DWH (vues bi, lecture seule) ──► notebooks Python ──► fichiers (CSV / Parquet, comme avant)
        ▲                                          └────────► TuniShop_ANALYTICS
        │                                                       ├── ana : 88 tables de résultats
        └──── jointures (TuniShop_DWH.bi.v_...) ◄──────────────┤ pbi : 24 vues pour Power BI
                                                                └── ctl : journal, catalogue, contrôles
TuniShop_ADMIN.audit.v_publication_analytics ──lit──► ctl.journal_publication   (facultatif)
Job SQL Agent « TuniShop - Chaine complete » : … ► étape « Analyse et publication »  (facultatif)
```

## Les 10 scripts (dossier `00_Commun/sql`)

| N° | Script | Obligatoire ? | Rôle |
|---|---|---|---|
| 01 | `01_Creer_base_TuniShop_ANALYTICS.sql` | oui | base, schémas `ana` / `pbi` / `ctl`, journal, catalogue |
| 02 | `02_Tables_ana.sql` | oui | les 84 tables de résultats + le catalogue (phase, notebook, fichier) |
| 03 | `03_Vues_pbi_Power_BI.sql` | oui | 20 vues pour Power BI, liées au DWH |
| 04 | `04_Controles_TuniShop_ANALYTICS.sql` | oui | procédure `ctl.usp_controler_publication` (liens avec le DWH, lignes) |
| 05 | `05_Droits_TuniShop_ANALYTICS.sql` | si un autre compte que le tien lance les notebooks ou lit Power BI | rôles et droits dans les 2 bases |
| 06 | `06_Lien_TuniShop_ADMIN.sql` | non | vue de suivi dans TuniShop_ADMIN |
| 07 | `07_Etape_job_Agent.sql` | non | ajoute l'analyse à la fin du job de nuit |
| 08 | `08_Journal_execution_TuniShop_ANALYTICS.sql` | conseillé | journal des exécutions des notebooks (`ctl.journal_execution`), réussies ou non |
| 09 | `09_Text_Mining_TuniShop_ANALYTICS.sql` | oui, après le notebook `05_Text_Mining_Avis` (v1.4) | 4 vues `pbi.v_tm_*`, catalogue, contrôles T1 à T6 |
| 09b | `09b_Correctif_v_tm_avis.sql` | une fois, pour passer à la v1.5.2 | réécrit `pbi.v_tm_avis` et prouve que le résultat ne change pas (0,12 s au lieu de 157 s) |

## Étape 1 — Créer la base (SSMS, une fois)

1. Ouvre SSMS et connecte-toi à `localhost` (le serveur du DWH) avec ton compte Windows.
2. Fichier > Ouvrir > Fichier… > `00_Commun/sql/01_Creer_base_TuniShop_ANALYTICS.sql`, puis **F5**.
   Message attendu : « Étape 01 terminée ».
3. Même chose avec `02_Tables_ana.sql` (« Étape 02 terminée : 84 tables… »).
4. Même chose avec `03_Vues_pbi_Power_BI.sql` (« Étape 03 terminée »).
5. Même chose avec `04_Controles_TuniShop_ANALYTICS.sql`. À ce stade les tables sont **vides** : le
   résultat montre des lignes P1 en INFO (« jamais publiée ») ; c'est normal.
6. Dans l'Explorateur d'objets, clic droit sur **Bases de données > Actualiser** : `TuniShop_ANALYTICS` apparaît.

## Étape 2 — Remplir la base depuis les notebooks

Rien à modifier dans les notebooks : `config.exporter_table`, `config.exporter_resultat` et
`features.sauvegarder` écrivent le fichier **puis** la table SQL. Sous chaque cellule d'export, une ligne
`✔ ana.<table>  N lignes` confirme la copie.

- **Première fois** (les fichiers existent déjà) : exécute seulement
  `03_Machine_Learning/07_Publication_Resultats`. Il relit tous les fichiers et remplit les 82 tables
  (la prévision 2026 reste vide tant que le calendrier 2026 n'est pas dans le DWH).
- **Ensuite** : chaque notebook met à jour ses propres tables quand tu l'exécutes.
- **Tout d'un coup**, dans le terminal :
  `python 00_Commun/executer_analyse.py` (ou `… executer_analyse.py ml publication`).

Si la base n'est pas encore créée, les notebooks s'arrêtent avec un message qui l'explique. Pour travailler
sans la base : `PUBLIER_SQL = False` dans `00_Commun/tunishop_analytics/config.py`.

## Étape 3 — Contrôler

Dans SSMS : `EXEC TuniShop_ANALYTICS.ctl.usp_controler_publication;`

| Contrôle | Vérifie | Attendu |
|---|---|---|
| L1-L3 | `client_sk` des segments, groupes et scores de churn présents dans `bi.v_dim_client` | 0 orphelin |
| L4 | `produit_id` des prévisions de demande présents dans `bi.v_dim_produit` | 0 orphelin |
| L5 | `livraison_id` des scores de retard présents dans `bi.v_fact_livraisons` | 0 orphelin |
| L6 | `client_sk` des scores du jour (`ml_scores_churn_actuels`) présents dans `bi.v_dim_client` | 0 orphelin |
| L7 | `livraison_id` des colis en transit (`ml_scores_retard_en_cours`) présents dans `bi.v_fact_livraisons` | 0 orphelin |
| L8 | `produit_id` de la demande prévue (`ml_scores_demande`) présents dans `bi.v_dim_produit` (version courante) | 0 orphelin |
| H1 | lignes de la dernière exécution de l'historique du suivi = lignes de `ana.ml_suivi` (v1.5) | 171 pour 171 |
| N1 | lignes de chaque table = lignes notées au journal | OK partout |
| P1 | chaque table du catalogue a été publiée | OK (INFO pour `ml_pred_ventes_2026`) |

Une clé étrangère ne peut pas relier deux bases : c'est ce contrôle qui garantit le lien avec le DWH.

## Étape 4 — Droits (seulement si besoin)

Ton compte Windows est administrateur du serveur ? Passe cette étape. Sinon, ouvre
`05_Droits_TuniShop_ANALYTICS.sql`, remplis `@compte_job` (compte qui lance les notebooks dans le job,
celui du proxy) et/ou `@compte_lecteur` (lecteur du tableau de bord), puis F5.

## Étape 5 — Facultatif : TuniShop_ADMIN et job de nuit

- `06_Lien_TuniShop_ADMIN.sql` : ajoute la vue `audit.v_publication_analytics` dans TuniShop_ADMIN.
- `07_Etape_job_Agent.sql` : à lancer sur l'instance qui porte SQL Server Agent (pas l'Express). Adapte
  `@python`, `@racine` et `@proxy`, puis F5. Ordre obtenu :
  staging → DWH → cubes → **Analyse et publication**. Si une étape échoue, l'analyse ne tourne pas.

## Étape 6 — Power BI

1. Power BI Desktop > Obtenir des données > **SQL Server**.
2. Serveur `localhost`, base de données `TuniShop_ANALYTICS`, mode **Importer**.
3. Coche les vues du schéma **pbi** uniquement.
4. Relations : `v_ml_churn[client_sk]` → `v_dim_client[client_sk]` ; `v_ml_demande[produit_id]` →
   `v_dim_produit[produit_id]` ; `v_ml_ventes[mois]`, `v_ml_demande[mois]`, `v_ml_retard[mois]` → `v_dim_mois[mois]`.

Ce rapport est distinct des 6 rapports en connexion directe aux cubes : une connexion directe à un cube
ne peut pas être mélangée avec une autre source.

## Vues pbi disponibles

| Vue | Contenu |
|---|---|
| `pbi.v_dim_client`, `pbi.v_dim_produit`, `pbi.v_dim_mois` | dimensions reprises du DWH |
| `pbi.v_eda_hypotheses` | 21 hypothèses et verdicts |
| `pbi.v_eda_qualite` | contrôles C01-C11 |
| `pbi.v_eda_vue_ensemble` | indicateurs annuels 2023-2025 |
| `pbi.v_dm_clients` | segment RFM + groupe k-means par client et date d'observation |
| `pbi.v_dm_regles` | règles d'association |
| `pbi.v_ml_ventes` | CA réel / prévu / référence 2025 (+ prévision 2026) |
| `pbi.v_ml_churn` | probabilité, alerte, décile de risque, segment |
| `pbi.v_ml_demande` | quantité réelle / prévue (modèle retenu, colonne `prevision_retenue`) / référence par produit et mois |
| `pbi.v_ml_retard` | probabilité, quintile de risque, entrepôt, région (depuis le DWH) |
| `pbi.v_ml_modeles` | comparaison des modèles (validation, test, retenu) |
| `pbi.v_publications` | dernière publication de chaque table |
| `pbi.v_ml_scores_churn` | **v1.2** : score du jour de chaque client actif (probabilité, alerte, décile 1 = plus à risque) |
| `pbi.v_ml_scores_retard` | **v1.2** : score des colis en transit (probabilité, alerte, transporteur, région) |
| `pbi.v_ml_registre` | **v1.2** : registre des modèles (version, période, empreinte, seuil, mesures) |
| `pbi.v_ml_suivi` | **v1.2** : suivi des modèles par période (indicateur, valeur, seuil, OK / ALERTE) |
| `pbi.v_ml_scores_demande` | **v1.3** : demande prévue de l'année suivante par produit et mois, stock et rupture |
| `pbi.v_ml_suivi_historique` | **v1.5** : suivi des modèles, une ligne par exécution, indicateur et période |
| `pbi.v_tm_avis`, `pbi.v_tm_avis_themes` | **v1.4** : avis commentés et leurs thèmes, avec client et transporteur (vue réécrite en v1.5.2) |
| `pbi.v_tm_produits`, `pbi.v_tm_verification_faits` | **v1.4** : synthèse du text mining par produit, confrontation des thèmes aux faits |

Les autres tables `ana` (tableaux Q01…, DM01…, ML01…) restent lisibles directement si besoin.
