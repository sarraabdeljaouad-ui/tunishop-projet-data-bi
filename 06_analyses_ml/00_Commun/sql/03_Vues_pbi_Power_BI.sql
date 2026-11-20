/* =====================================================================================
   TuniShop — 03. Vues pour Power BI (schéma pbi de TuniShop_ANALYTICS)
   =====================================================================================
   Auteure   : Sarra Abdeljaouad
   À lancer  : après 02. Peut être relancé (CREATE OR ALTER).

   Principe
     Power BI se connecte à UNE seule base, TuniShop_ANALYTICS, et ne lit QUE les vues pbi.
     Ces vues relient les résultats (tables ana) aux vues bi du DWH grâce au nom en trois
     parties  TuniShop_DWH.bi.v_...  (les deux bases doivent rester sur la même instance).

   Liens avec le DWH (aucune clé étrangère possible entre deux bases : le lien est contrôlé
   par la procédure ctl.usp_controler_publication du script 04)
     client_sk     -> TuniShop_DWH.bi.v_dim_client.client_sk
     produit_id    -> TuniShop_DWH.bi.v_dim_produit.produit_id  (version courante, est_courant = 1)
     livraison_id  -> TuniShop_DWH.bi.v_fact_livraisons.livraison_id
     mois          -> pbi.v_dim_mois.mois (premier jour du mois, construit depuis bi.v_dim_date)

   Droits : un compte qui lit ces vues doit aussi pouvoir lire les vues bi du DWH (script 05).
   ===================================================================================== */

USE TuniShop_ANALYTICS;
GO

/* -------------------------------------------------------------------------------------
   1. Dimensions reprises du DWH (pour les relations du modèle Power BI)
   ------------------------------------------------------------------------------------- */

-- Clients : toutes les versions (client_sk = une version du client, comme dans les faits)
CREATE OR ALTER VIEW pbi.v_dim_client
AS
SELECT c.client_sk, c.client_id, c.type_client, c.genre, c.tranche_age,
       c.gouvernorat, c.region, c.ville, c.canal_inscription, c.cohorte_inscription,
       c.segment_fidelite, c.est_courant
FROM TuniShop_DWH.bi.v_dim_client AS c;
GO

-- Produits : version courante (une ligne par produit_id, comme dans les prédictions de demande)
CREATE OR ALTER VIEW pbi.v_dim_produit
AS
SELECT p.produit_id, p.sku, p.nom_produit, p.marque, p.categorie, p.sous_categorie,
       p.gamme_prix, p.statut_produit, p.prix_catalogue_ttc
FROM TuniShop_DWH.bi.v_dim_produit AS p
WHERE p.est_courant = 1;
GO

-- Mois : une ligne par mois du calendrier du DWH (clé = 1er jour du mois)
CREATE OR ALTER VIEW pbi.v_dim_mois
AS
SELECT DATEFROMPARTS(d.annee, d.mois, 1) AS mois,
       d.annee, d.trimestre, d.mois AS numero_mois, MIN(d.nom_mois) AS nom_mois,
       MIN(d.annee_mois) AS annee_mois,
       SUM(CASE WHEN d.est_ramadan = 1 THEN 1 ELSE 0 END) AS jours_ramadan
FROM TuniShop_DWH.bi.v_dim_date AS d
WHERE d.annee BETWEEN 2023 AND 2026
GROUP BY d.annee, d.trimestre, d.mois;
GO

/* -------------------------------------------------------------------------------------
   2. EDA
   ------------------------------------------------------------------------------------- */

-- Les 21 hypothèses et leur verdict (écrites par les notebooks 02 à 06 de 01_EDA)
CREATE OR ALTER VIEW pbi.v_eda_hypotheses
AS
SELECT h.question,
       CAST(SUBSTRING(h.question, 2, 3) AS INT) AS ordre,
       h.theme, h.question_metier, h.hypothese, h.verdict, h.constat, h.notebook
FROM ana.eda_hypotheses AS h;
GO

-- Contrôles de qualité C01-C11 (01_EDA_Global)
CREATE OR ALTER VIEW pbi.v_eda_qualite
AS
SELECT q.controle, q.libelle, q.verifications, q.ok, q.ecart, q.info, q.statut
FROM ana.eda00_synthese_qualite AS q;
GO

-- Vue d'ensemble annuelle (01_EDA_Global)
CREATE OR ALTER VIEW pbi.v_eda_vue_ensemble
AS
SELECT v.*
FROM ana.eda_g03_vue_ensemble_annuelle AS v;
GO

/* -------------------------------------------------------------------------------------
   3. Data mining
   ------------------------------------------------------------------------------------- */

-- Segment RFM et groupe k-means de chaque client à chaque date d'observation
CREATE OR ALTER VIEW pbi.v_dm_clients
AS
SELECT s.client_sk, s.date_observation, s.periode,
       s.score_r, s.score_f, s.score_m, s.code_rfm, s.segment_rfm,
       k.cluster,
       CASE WHEN s.date_observation = MAX(s.date_observation) OVER () THEN 1 ELSE 0 END AS est_derniere_observation
FROM ana.dm_segments_rfm AS s
LEFT JOIN ana.dm_clusters_clients AS k
       ON k.client_sk = s.client_sk AND k.date_observation = s.date_observation;
GO

-- Règles d'association (validées sur 2025)
CREATE OR ALTER VIEW pbi.v_dm_regles
AS
SELECT r.niveau, r.antecedents, r.consequents, r.support, r.confidence, r.lift,
       r.support_2025, r.confidence_2025, r.lift_2025, r.stable
FROM ana.dm_regles_association AS r;
GO

/* -------------------------------------------------------------------------------------
   4. Machine learning — prédictions sur le test 2025
   ------------------------------------------------------------------------------------- */

-- Prévision des ventes : CA réel / prévu par catégorie et par mois (2025), puis 2026 si publiée
CREATE OR ALTER VIEW pbi.v_ml_ventes
AS
SELECT v.mois, v.categorie, N'Test 2025' AS periode,
       v.reel                       AS ca_reel_ttc,
       v.prevision                  AS ca_prevu_ttc,          -- modèle retenu (Ridge « calendrier »)
       v.[Holt-Winters (référence)] AS ca_reference_ttc,
       v.prevision - v.reel         AS ecart_ttc
FROM ana.ml_pred_ventes_2025 AS v
UNION ALL
SELECT f.mois, f.categorie, N'Prévision 2026', NULL, f.prevision_ca_ttc, NULL, NULL
FROM ana.ml_pred_ventes_2026 AS f;
GO

-- Churn : probabilité, alerte (seuil choisi sur la validation), décile de risque, segment du client
CREATE OR ALTER VIEW pbi.v_ml_churn
AS
SELECT p.client_sk, p.date_observation,
       p.churn                                   AS churn_reel,        -- 1 = pas de commande dans les 90 jours
       p.proba_churn,
       p.prediction                              AS alerte_churn,      -- 1 = proba >= seuil retenu
       NTILE(10) OVER (PARTITION BY p.date_observation ORDER BY p.proba_churn DESC) AS decile_risque,
       s.segment_rfm, k.cluster
FROM ana.ml_pred_churn_2025 AS p
LEFT JOIN ana.dm_segments_rfm     AS s ON s.client_sk = p.client_sk AND s.date_observation = p.date_observation
LEFT JOIN ana.dm_clusters_clients AS k ON k.client_sk = p.client_sk AND k.date_observation = p.date_observation;
GO

-- Demande par produit et par mois : prévision du modèle retenu (colonne prevision_retenue, v1.2)
CREATE OR ALTER VIEW pbi.v_ml_demande
AS
SELECT d.produit_id, d.mois, d.categorie,
       d.quantite                                              AS quantite_reelle,
       d.prevision_retenue                                     AS quantite_prevue,      -- modèle retenu (version 2 depuis le 10/12/2026)
       d.[Gradient boosting (Poisson)]                         AS quantite_gb_poisson,
       d.[Naïf saisonnier]                                     AS quantite_naif,
       ABS(d.prevision_retenue - d.quantite)                   AS erreur_absolue,
       d.[Moyenne de l'année précédente (référence)]           AS quantite_reference
FROM ana.ml_pred_demande_2025 AS d;
GO

-- Retard de livraison : probabilité, quintile de risque, détails de l'expédition pris dans le DWH
CREATE OR ALTER VIEW pbi.v_ml_retard
AS
SELECT r.livraison_id, r.date_expedition,
       DATEFROMPARTS(YEAR(r.date_expedition), MONTH(r.date_expedition), 1) AS mois,
       r.transporteur, r.en_retard AS retard_reel, r.proba_retard,
       NTILE(5) OVER (ORDER BY r.proba_retard DESC)            AS quintile_risque,   -- 1 = 20 % les plus risquées
       f.client_sk, e.nom_entrepot, g.region, g.zone_livraison, f.retard_j, f.statut_livraison
FROM ana.ml_pred_retard_2025 AS r
LEFT JOIN TuniShop_DWH.bi.v_fact_livraisons AS f ON f.livraison_id = r.livraison_id
LEFT JOIN TuniShop_DWH.bi.v_dim_entrepot    AS e ON e.entrepot_sk = f.entrepot_sk
LEFT JOIN TuniShop_DWH.bi.v_dim_geographie  AS g ON g.geographie_sk = f.geographie_sk;
GO

/* -------------------------------------------------------------------------------------
   5. Machine learning — comparaison des modèles (une ligne par modèle)
   ------------------------------------------------------------------------------------- */
CREATE OR ALTER VIEW pbi.v_ml_modeles
AS
SELECT N'Prévision des ventes' AS cas, modele, role, N'MAPE' AS mesure, N'plus bas = mieux' AS sens,
       MAPE_validation AS valeur_validation, MAPE_total AS valeur_test, gain_vs_reference,
       CAST(retenu AS BIT) AS retenu
FROM ana.ml_metriques_ventes
UNION ALL
SELECT N'Churn', modele, role, N'AUC', N'plus haut = mieux', AUC_validation, AUC, NULL, CAST(retenu AS BIT)
FROM ana.ml_metriques_churn
UNION ALL
SELECT N'Demande par produit', modele, role, N'WAPE', N'plus bas = mieux',
       WAPE_validation, WAPE_produit_mois, gain_vs_reference, CAST(retenu AS BIT)
FROM ana.ml_metriques_demande
UNION ALL
SELECT N'Retard de livraison', modele, role, N'AUC', N'plus haut = mieux', AUC_validation, AUC, NULL, CAST(retenu AS BIT)
FROM ana.ml_metriques_retard;
GO

/* -------------------------------------------------------------------------------------
   5bis. Scores du jour, registre et suivi des modèles (notebooks 08 et 09, v1.2)
   ------------------------------------------------------------------------------------- */

-- Clients actifs à la date de scoring : probabilité de churn, alerte, décile (1 = plus risqués)
CREATE OR ALTER VIEW pbi.v_ml_scores_churn
AS
SELECT s.client_sk, s.date_scoring, s.segment_rfm, s.cluster, s.recence_j, s.frequence, s.montant_reconnu_ttc,
       s.proba_churn, s.alerte_churn, s.decile_risque, s.version_modele,
       c.client_id, c.type_client, c.region, c.ville, c.canal_inscription
FROM ana.ml_scores_churn_actuels AS s
LEFT JOIN TuniShop_DWH.bi.v_dim_client AS c ON c.client_sk = s.client_sk;
GO

-- Colis en transit : probabilité de retard et alerte
CREATE OR ALTER VIEW pbi.v_ml_scores_retard
AS
SELECT r.livraison_id, r.commande_id, r.date_expedition, r.transporteur, r.region, r.zone_livraison, r.entrepot,
       r.proba_retard, r.alerte_retard, r.date_scoring, r.version_modele
FROM ana.ml_scores_retard_en_cours AS r;
GO

-- Demande prévue de l'année suivante (scoring 08, v1.3), avec le nom du produit pris dans le DWH
CREATE OR ALTER VIEW pbi.v_ml_scores_demande
AS
SELECT d.produit_id, p.nom_produit, d.categorie, d.mois,
       d.quantite_prevue, d.stock_depart, d.demande_cumulee, d.rupture_sans_reappro,
       d.date_scoring, d.version_modele
FROM ana.ml_scores_demande AS d
LEFT JOIN TuniShop_DWH.bi.v_dim_produit AS p
       ON p.produit_id = d.produit_id AND p.est_courant = 1;
GO

-- Registre des modèles (fiche d'identité de chaque modèle)
CREATE OR ALTER VIEW pbi.v_ml_registre
AS
SELECT r.nom, r.cas, r.role, r.version, r.appris_le, r.periode_apprentissage, r.lignes_apprentissage,
       r.nb_variables, r.seuil, r.empreinte_donnees, r.source, r.notes
FROM ana.ml_registre_modeles AS r;
GO

-- Suivi des modèles dans le temps (une ligne par indicateur et par période)
CREATE OR ALTER VIEW pbi.v_ml_suivi
AS
SELECT s.cas, s.objet, s.periode, s.indicateur, s.valeur, s.seuil, s.statut
FROM ana.ml_suivi AS s;
GO

-- Historique du suivi des modèles (v1.5) : une ligne par exécution, indicateur et période
CREATE OR ALTER VIEW pbi.v_ml_suivi_historique
AS
SELECT h.date_donnees, h.calcule_le, h.cas, h.objet, h.periode, h.indicateur, h.valeur, h.seuil, h.statut
FROM ana.ml_suivi_historique AS h;
GO

/* -------------------------------------------------------------------------------------
   6. Suivi des publications (page « Clôture » du tableau de bord)
   ------------------------------------------------------------------------------------- */
CREATE OR ALTER VIEW pbi.v_publications
AS
SELECT d.table_sql, c.phase, c.notebook, d.partage, d.lignes, d.mode_source, d.publie_le, d.publie_par
FROM ctl.v_derniere_publication AS d
LEFT JOIN ctl.catalogue_tables AS c ON c.table_sql = d.table_sql;
GO

PRINT N'Étape 03 terminée : vues pbi prêtes pour Power BI.';
GO
