/* =====================================================================================
   TuniShop — 02. Tables de résultats (schéma ana de TuniShop_ANALYTICS)
   =====================================================================================
   Auteure   : Sarra Abdeljaouad
   À lancer  : après 01. Peut être relancé : une table déjà présente n'est pas touchée.

   Une table par fichier de résultats (même colonnes, mêmes lignes) :
     06_Exports/Tables/<NOM>.csv          -> ana.<nom en minuscules>  (Q.. et G.. préfixés eda_)
     05_Data/features/segments_rfm.parquet -> ana.dm_segments_rfm, etc. (voir ctl.catalogue_tables)
   Les tables sont REMPLIES par les notebooks (module tunishop_analytics.publication).
   Si un notebook ajoute une colonne ou un nouveau tableau, Python crée ou recrée lui-même
   la table : ce script sert à préparer la base et les vues Power BI dès le départ.

   Structure générée à partir des tables réellement publiées (05_Data/metadata/Schema_Base_Analytics.json).
   ===================================================================================== */

USE TuniShop_ANALYTICS;
GO


/* --------------------------------------------------------------------------------
   EDA
   -------------------------------------------------------------------------------- */

-- Contrôle de qualité : coherence  (source : 06_Exports/Tables/EDA00_coherence.csv ; notebook 01_EDA_Global)
IF OBJECT_ID(N'ana.eda00_coherence', N'U') IS NULL
CREATE TABLE [ana].[eda00_coherence] (
    [controle] NVARCHAR(50) NULL,
    [indicateur] NVARCHAR(100) NULL,
    [valide_pv] FLOAT NULL,
    [sql_vues_bi] FLOAT NULL,
    [python_pandas] FLOAT NULL,
    [statut] NVARCHAR(50) NULL
);
GO

-- Contrôle de qualité : extremes  (source : 06_Exports/Tables/EDA00_extremes.csv ; notebook 01_EDA_Global)
IF OBJECT_ID(N'ana.eda00_extremes', N'U') IS NULL
CREATE TABLE [ana].[eda00_extremes] (
    [table] NVARCHAR(50) NULL,
    [variable] NVARCHAR(50) NULL,
    [libelle] NVARCHAR(100) NULL,
    [valeurs] INT NULL,
    [mediane] FLOAT NULL,
    [q3] FLOAT NULL,
    [seuil_haut] FLOAT NULL,
    [maximum] FLOAT NULL,
    [nb_extremes] INT NULL,
    [part_extremes] FLOAT NULL,
    [statut] NVARCHAR(50) NULL
);
GO

-- Contrôle de qualité : integrite  (source : 06_Exports/Tables/EDA00_integrite.csv ; notebook 01_EDA_Global)
IF OBJECT_ID(N'ana.eda00_integrite', N'U') IS NULL
CREATE TABLE [ana].[eda00_integrite] (
    [fait] NVARCHAR(50) NULL,
    [cle] NVARCHAR(50) NULL,
    [dimension] NVARCHAR(50) NULL,
    [lignes] INT NULL,
    [orphelines] INT NULL,
    [statut] NVARCHAR(50) NULL
);
GO

-- Contrôle de qualité : inventaire  (source : 06_Exports/Tables/EDA00_inventaire.csv ; notebook 01_EDA_Global)
IF OBJECT_ID(N'ana.eda00_inventaire', N'U') IS NULL
CREATE TABLE [ana].[eda00_inventaire] (
    [vue] NVARCHAR(50) NULL,
    [type] NVARCHAR(50) NULL,
    [lignes] INT NULL,
    [colonnes] INT NULL,
    [lignes_attendues] INT NULL,
    [ecart] INT NULL,
    [statut] NVARCHAR(50) NULL
);
GO

-- Contrôle de qualité : manquants  (source : 06_Exports/Tables/EDA00_manquants.csv ; notebook 01_EDA_Global)
IF OBJECT_ID(N'ana.eda00_manquants', N'U') IS NULL
CREATE TABLE [ana].[eda00_manquants] (
    [table] NVARCHAR(50) NULL,
    [colonne] NVARCHAR(50) NULL,
    [lignes] INT NULL,
    [vides] INT NULL,
    [part_vide] FLOAT NULL,
    [statut] NVARCHAR(50) NULL,
    [explication] NVARCHAR(255) NULL
);
GO

-- Contrôle de qualité : membres  (source : 06_Exports/Tables/EDA00_membres.csv ; notebook 01_EDA_Global)
IF OBJECT_ID(N'ana.eda00_membres', N'U') IS NULL
CREATE TABLE [ana].[eda00_membres] (
    [colonne] NVARCHAR(50) NULL,
    [inconnu_-1] INT NULL,
    [non_applicable_-2] INT NULL,
    [part_-1] FLOAT NULL,
    [part_-2] FLOAT NULL,
    [statut] NVARCHAR(50) NULL
);
GO

-- Contrôle de qualité : synthese qualite  (source : 06_Exports/Tables/EDA00_synthese_qualite.csv ; notebook 01_EDA_Global)
IF OBJECT_ID(N'ana.eda00_synthese_qualite', N'U') IS NULL
CREATE TABLE [ana].[eda00_synthese_qualite] (
    [controle] NVARCHAR(50) NULL,
    [libelle] NVARCHAR(100) NULL,
    [verifications] INT NULL,
    [ok] INT NULL,
    [ecart] INT NULL,
    [info] INT NULL,
    [statut] NVARCHAR(50) NULL
);
GO

-- Contrôle de qualité : unicite  (source : 06_Exports/Tables/EDA00_unicite.csv ; notebook 01_EDA_Global)
IF OBJECT_ID(N'ana.eda00_unicite', N'U') IS NULL
CREATE TABLE [ana].[eda00_unicite] (
    [table] NVARCHAR(50) NULL,
    [cle] NVARCHAR(50) NULL,
    [lignes] INT NULL,
    [doublons] INT NULL,
    [statut] NVARCHAR(50) NULL
);
GO

-- Vue d'ensemble annuelle : vue ensemble annuelle  (source : 06_Exports/Tables/G03_vue_ensemble_annuelle.csv ; notebook 01_EDA_Global)
IF OBJECT_ID(N'ana.eda_g03_vue_ensemble_annuelle', N'U') IS NULL
CREATE TABLE [ana].[eda_g03_vue_ensemble_annuelle] (
    [annee] INT NULL,
    [commandes_passees] INT NULL,
    [commandes_reconnues] INT NULL,
    [ca_reconnu_ttc] FLOAT NULL,
    [clients_actifs] INT NULL,
    [panier_moyen_ttc] FLOAT NULL,
    [taux_retard] FLOAT NULL,
    [note_moyenne] FLOAT NULL
);
GO

-- Tables de variables construites : tables variables  (source : 06_Exports/Tables/G04_tables_variables.csv ; notebook 01_EDA_Global)
IF OBJECT_ID(N'ana.eda_g04_tables_variables', N'U') IS NULL
CREATE TABLE [ana].[eda_g04_tables_variables] (
    [table] NVARCHAR(50) NULL,
    [lignes] INT NULL,
    [colonnes] INT NULL,
    [lignes apprentissage] INT NULL,
    [lignes test] INT NULL,
    [cible] NVARCHAR(50) NULL,
    [taux cible apprentissage] FLOAT NULL,
    [taux cible test] FLOAT NULL
);
GO

-- Verdict des 21 hypothèses du plan d'analyse  (source : 06_Exports/Tables/EDA_hypotheses_*.csv ; notebook 02 à 06 (01_EDA))
IF OBJECT_ID(N'ana.eda_hypotheses', N'U') IS NULL
CREATE TABLE [ana].[eda_hypotheses] (
    [notebook] NVARCHAR(50) NULL,
    [question] NVARCHAR(50) NOT NULL,
    [theme] NVARCHAR(50) NULL,
    [question_metier] NVARCHAR(255) NULL,
    [hypothese] NVARCHAR(255) NULL,
    [verdict] NVARCHAR(50) NULL,
    [constat] NVARCHAR(255) NULL,
    CONSTRAINT [PK_eda_hypotheses] PRIMARY KEY ([question])
);
GO

-- Q01 — Comment évoluent les ventes entre 2023 et 2025 ?  (source : 06_Exports/Tables/Q01_ventes_annuelles.csv ; notebook 02_EDA_Sales)
IF OBJECT_ID(N'ana.eda_q01_ventes_annuelles', N'U') IS NULL
CREATE TABLE [ana].[eda_q01_ventes_annuelles] (
    [annee] INT NULL,
    [commandes] INT NULL,
    [ca_reconnu_ttc] FLOAT NULL,
    [panier_moyen_ttc] FLOAT NULL,
    [croissance_ca] FLOAT NULL,
    [croissance_commandes] FLOAT NULL
);
GO

-- Q01 — Comment évoluent les ventes entre 2023 et 2025 ?  (source : 06_Exports/Tables/Q01_ventes_mensuelles.csv ; notebook 02_EDA_Sales)
IF OBJECT_ID(N'ana.eda_q01_ventes_mensuelles', N'U') IS NULL
CREATE TABLE [ana].[eda_q01_ventes_mensuelles] (
    [mois] DATE NULL,
    [ca_reconnu] FLOAT NULL,
    [commandes] INT NULL
);
GO

-- Q02 — Y a-t-il une saisonnalité ? Quel est l'effet du Ramadan et des périodes commerciales ?  (source : 06_Exports/Tables/Q02_ca_par_periode_commerciale.csv ; notebook 02_EDA_Sales)
IF OBJECT_ID(N'ana.eda_q02_ca_par_periode_commerciale', N'U') IS NULL
CREATE TABLE [ana].[eda_q02_ca_par_periode_commerciale] (
    [periode_commerciale] NVARCHAR(50) NULL,
    [jours] INT NULL,
    [ca_moyen_jour] FLOAT NULL,
    [indice] FLOAT NULL
);
GO

-- Q03 — Quelles catégories font le chiffre d'affaires et la marge ?  (source : 06_Exports/Tables/Q03_categories.csv ; notebook 04_EDA_Products)
IF OBJECT_ID(N'ana.eda_q03_categories', N'U') IS NULL
CREATE TABLE [ana].[eda_q03_categories] (
    [categorie] NVARCHAR(50) NULL,
    [ca_ht] FLOAT NULL,
    [marge] FLOAT NULL,
    [lignes] INT NULL,
    [taux_marge] FLOAT NULL,
    [part_ca] FLOAT NULL
);
GO

-- Q04 — Le CA est-il concentré sur quelques produits ? Quelles gammes de prix rapportent ?  (source : 06_Exports/Tables/Q04_gammes_prix.csv ; notebook 04_EDA_Products)
IF OBJECT_ID(N'ana.eda_q04_gammes_prix', N'U') IS NULL
CREATE TABLE [ana].[eda_q04_gammes_prix] (
    [gamme_prix] NVARCHAR(50) NULL,
    [lignes] INT NULL,
    [ca_ht] FLOAT NULL,
    [taux_marge] FLOAT NULL,
    [part_remise_promo] FLOAT NULL,
    [part_ca] FLOAT NULL
);
GO

-- Q05 — Combien de fois les clients achètent-ils ? D'où viennent les clients de l'année ?  (source : 06_Exports/Tables/Q05_nouveaux_clients.csv ; notebook 03_EDA_Customers)
IF OBJECT_ID(N'ana.eda_q05_nouveaux_clients', N'U') IS NULL
CREATE TABLE [ana].[eda_q05_nouveaux_clients] (
    [annee] INT NULL,
    [clients] INT NULL,
    [nouveaux] INT NULL,
    [part_nouveaux] FLOAT NULL
);
GO

-- Q06 — Le profil du client (type, âge, canal d'inscription) change-t-il sa valeur ?  (source : 06_Exports/Tables/Q06_valeur_par_canal_inscription.csv ; notebook 03_EDA_Customers)
IF OBJECT_ID(N'ana.eda_q06_valeur_par_canal_inscription', N'U') IS NULL
CREATE TABLE [ana].[eda_q06_valeur_par_canal_inscription] (
    [canal_inscription] NVARCHAR(50) NULL,
    [clients] INT NULL,
    [ca_reconnu_ttc] FLOAT NULL,
    [ca_par_client] FLOAT NULL,
    [commandes_par_client] FLOAT NULL
);
GO

-- Q06 — Le profil du client (type, âge, canal d'inscription) change-t-il sa valeur ?  (source : 06_Exports/Tables/Q06_valeur_par_type.csv ; notebook 03_EDA_Customers)
IF OBJECT_ID(N'ana.eda_q06_valeur_par_type', N'U') IS NULL
CREATE TABLE [ana].[eda_q06_valeur_par_type] (
    [type_client] NVARCHAR(50) NULL,
    [clients] INT NULL,
    [ca_reconnu_ttc] FLOAT NULL,
    [ca_par_client] FLOAT NULL,
    [commandes_par_client] FLOAT NULL
);
GO

-- Q07 — Les clients reviennent-ils ? (analyse de cohortes)  (source : 06_Exports/Tables/Q07_cohortes_retention.csv ; notebook 03_EDA_Customers)
IF OBJECT_ID(N'ana.eda_q07_cohortes_retention', N'U') IS NULL
CREATE TABLE [ana].[eda_q07_cohortes_retention] (
    [cohorte] NVARCHAR(50) NULL,
    [0] FLOAT NULL,
    [1] FLOAT NULL,
    [2] FLOAT NULL,
    [3] FLOAT NULL,
    [4] FLOAT NULL,
    [5] FLOAT NULL,
    [6] FLOAT NULL,
    [7] FLOAT NULL,
    [8] FLOAT NULL,
    [9] FLOAT NULL,
    [10] FLOAT NULL,
    [11] FLOAT NULL
);
GO

-- Q08 — Où sont les clients ?  (source : 06_Exports/Tables/Q08_regions.csv ; notebook 03_EDA_Customers)
IF OBJECT_ID(N'ana.eda_q08_regions', N'U') IS NULL
CREATE TABLE [ana].[eda_q08_regions] (
    [region] NVARCHAR(50) NULL,
    [commandes] INT NULL,
    [ca_reconnu_ttc] FLOAT NULL,
    [panier_moyen_ttc] FLOAT NULL,
    [part_ca] FLOAT NULL
);
GO

-- Q09 — Par quels canaux et modes de paiement les clients achètent-ils ?  (source : 06_Exports/Tables/Q09_echec_paiement.csv ; notebook 02_EDA_Sales)
IF OBJECT_ID(N'ana.eda_q09_echec_paiement', N'U') IS NULL
CREATE TABLE [ana].[eda_q09_echec_paiement] (
    [mode_paiement] NVARCHAR(50) NULL,
    [tentatives] INT NULL,
    [taux_reussite] FLOAT NULL,
    [taux_echec] FLOAT NULL
);
GO

-- Q09 — Par quels canaux et modes de paiement les clients achètent-ils ?  (source : 06_Exports/Tables/Q09_parts_canal.csv ; notebook 02_EDA_Sales)
IF OBJECT_ID(N'ana.eda_q09_parts_canal', N'U') IS NULL
CREATE TABLE [ana].[eda_q09_parts_canal] (
    [trimestre] NVARCHAR(50) NULL,
    [application_mobile] FLOAT NULL,
    [non_renseigne] FLOAT NULL,
    [reseaux_sociaux] FLOAT NULL,
    [site_web] FLOAT NULL
);
GO

-- Q10 — Pourquoi les paiements échouent-ils ? Une 2e tentative réussit-elle ?  (source : 06_Exports/Tables/Q10_causes_echec.csv ; notebook 06_EDA_Marketing_Finance)
IF OBJECT_ID(N'ana.eda_q10_causes_echec', N'U') IS NULL
CREATE TABLE [ana].[eda_q10_causes_echec] (
    [code_erreur] NVARCHAR(50) NULL,
    [echecs] INT NULL,
    [montant_ttc] FLOAT NULL,
    [part] FLOAT NULL
);
GO

-- Q11 — Quelles campagnes rapportent le plus par dinar dépensé ?  (source : 06_Exports/Tables/Q11_performance_canaux_media.csv ; notebook 06_EDA_Marketing_Finance)
IF OBJECT_ID(N'ana.eda_q11_performance_canaux_media', N'U') IS NULL
CREATE TABLE [ana].[eda_q11_performance_canaux_media] (
    [canal_media] NVARCHAR(50) NULL,
    [depense_ht] FLOAT NULL,
    [ca_attribue_ttc] FLOAT NULL,
    [roas] FLOAT NULL,
    [ctr] FLOAT NULL,
    [cpa_ht] FLOAT NULL,
    [nouveaux_clients] INT NULL,
    [part_depense] FLOAT NULL
);
GO

-- Q11 — Quelles campagnes rapportent le plus par dinar dépensé ?  (source : 06_Exports/Tables/Q11_roas_annuel.csv ; notebook 06_EDA_Marketing_Finance)
IF OBJECT_ID(N'ana.eda_q11_roas_annuel', N'U') IS NULL
CREATE TABLE [ana].[eda_q11_roas_annuel] (
    [canal_media] NVARCHAR(50) NULL,
    [2023] FLOAT NULL,
    [2024] FLOAT NULL,
    [2025] FLOAT NULL
);
GO

-- Q12 — Les coupons augmentent-ils le panier ? À qui servent-ils ?  (source : 06_Exports/Tables/Q12_coupons_annuels.csv ; notebook 06_EDA_Marketing_Finance)
IF OBJECT_ID(N'ana.eda_q12_coupons_annuels', N'U') IS NULL
CREATE TABLE [ana].[eda_q12_coupons_annuels] (
    [annee] INT NULL,
    [commandes] INT NULL,
    [part_avec_coupon] FLOAT NULL,
    [remise_coupon_ttc] FLOAT NULL
);
GO

-- Q13 — Les livraisons arrivent-elles à l'heure ? Qui est en retard ?  (source : 06_Exports/Tables/Q13_retard_transporteur_semestre.csv ; notebook 05_EDA_Stock_Logistics)
IF OBJECT_ID(N'ana.eda_q13_retard_transporteur_semestre', N'U') IS NULL
CREATE TABLE [ana].[eda_q13_retard_transporteur_semestre] (
    [transporteur] NVARCHAR(50) NULL,
    [2023-S1] FLOAT NULL,
    [2023-S2] FLOAT NULL,
    [2024-S1] FLOAT NULL,
    [2024-S2] FLOAT NULL,
    [2025-S1] FLOAT NULL,
    [2025-S2] FLOAT NULL
);
GO

-- Q14 — Quel est le rôle des entrepôts ? Combien de colis n'arrivent jamais ?  (source : 06_Exports/Tables/Q14_entrepots.csv ; notebook 05_EDA_Stock_Logistics)
IF OBJECT_ID(N'ana.eda_q14_entrepots', N'U') IS NULL
CREATE TABLE [ana].[eda_q14_entrepots] (
    [nom_entrepot] NVARCHAR(50) NULL,
    [expeditions] INT NULL,
    [taux_non_livree] FLOAT NULL,
    [preparation_moy_h] FLOAT NULL,
    [delai_livraison_moy_j] FLOAT NULL,
    [taux_retard] FLOAT NULL
);
GO

-- Q15 — Le retard dégrade-t-il la satisfaction ?  (source : 06_Exports/Tables/Q15_note_selon_retard.csv ; notebook 03_EDA_Customers)
IF OBJECT_ID(N'ana.eda_q15_note_selon_retard', N'U') IS NULL
CREATE TABLE [ana].[eda_q15_note_selon_retard] (
    [tranche_retard] NVARCHAR(50) NULL,
    [avis] FLOAT NULL,
    [note_moyenne] FLOAT NULL
);
GO

-- Q16 — Quelles catégories sont le plus retournées ?  (source : 06_Exports/Tables/Q16_retours_categorie.csv ; notebook 04_EDA_Products)
IF OBJECT_ID(N'ana.eda_q16_retours_categorie', N'U') IS NULL
CREATE TABLE [ana].[eda_q16_retours_categorie] (
    [categorie] NVARCHAR(50) NULL,
    [lignes] INT NULL,
    [taux_retour] FLOAT NULL
);
GO

-- Q17 — Pourquoi les clients demandent-ils un remboursement ? Qui en est responsable ?  (source : 06_Exports/Tables/Q17_motifs_remboursement.csv ; notebook 06_EDA_Marketing_Finance)
IF OBJECT_ID(N'ana.eda_q17_motifs_remboursement', N'U') IS NULL
CREATE TABLE [ana].[eda_q17_motifs_remboursement] (
    [responsabilite] NVARCHAR(50) NULL,
    [motif] NVARCHAR(100) NULL,
    [demandes] INT NULL,
    [taux_refus] FLOAT NULL,
    [delai_moy_j] FLOAT NULL,
    [rembourse_ttc] FLOAT NULL
);
GO

-- Q19 — Le stock suit-il la demande ? Quand les ruptures arrivent-elles ?  (source : 06_Exports/Tables/Q19_stock_mensuel.csv ; notebook 05_EDA_Stock_Logistics)
IF OBJECT_ID(N'ana.eda_q19_stock_mensuel', N'U') IS NULL
CREATE TABLE [ana].[eda_q19_stock_mensuel] (
    [annee_mois] NVARCHAR(50) NULL,
    [taux_rupture] FLOAT NULL,
    [valeur_stock_ht] FLOAT NULL,
    [mois] DATE NULL
);
GO

-- Q21 — Les fournisseurs livrent-ils à temps ? La fiabilité annoncée est-elle tenue ?  (source : 06_Exports/Tables/Q21_fournisseurs.csv ; notebook 05_EDA_Stock_Logistics)
IF OBJECT_ID(N'ana.eda_q21_fournisseurs', N'U') IS NULL
CREATE TABLE [ana].[eda_q21_fournisseurs] (
    [nom_fournisseur] NVARCHAR(50) NULL,
    [lignes] INT NULL,
    [taux_retard] FLOAT NULL,
    [fiabilite_annoncee] FLOAT NULL,
    [local] INT NULL
);
GO

-- Q21 — Les fournisseurs livrent-ils à temps ? La fiabilité annoncée est-elle tenue ?  (source : 06_Exports/Tables/Q21_fournisseurs_pays.csv ; notebook 05_EDA_Stock_Logistics)
IF OBJECT_ID(N'ana.eda_q21_fournisseurs_pays', N'U') IS NULL
CREATE TABLE [ana].[eda_q21_fournisseurs_pays] (
    [pays] NVARCHAR(50) NULL,
    [origine] NVARCHAR(50) NULL,
    [lignes_recues] INT NULL,
    [delai_moy_j] FLOAT NULL,
    [taux_retard] FLOAT NULL,
    [retard_moy_j] FLOAT NULL
);
GO


/* --------------------------------------------------------------------------------
   Data mining
   -------------------------------------------------------------------------------- */

-- actions segments  (source : 06_Exports/Tables/DM01_actions_segments.csv ; notebook 01_Segmentation_RFM)
IF OBJECT_ID(N'ana.dm01_actions_segments', N'U') IS NULL
CREATE TABLE [ana].[dm01_actions_segments] (
    [segment_rfm] NVARCHAR(50) NULL,
    [part_clients] FLOAT NULL,
    [part_montant] FLOAT NULL,
    [montant_median_ttc] FLOAT NULL,
    [churn_apprentissage] FLOAT NULL,
    [churn_test] FLOAT NULL,
    [action_recommandee] NVARCHAR(255) NULL
);
GO

-- churn par segment  (source : 06_Exports/Tables/DM01_churn_par_segment.csv ; notebook 01_Segmentation_RFM)
IF OBJECT_ID(N'ana.dm01_churn_par_segment', N'U') IS NULL
CREATE TABLE [ana].[dm01_churn_par_segment] (
    [segment_rfm] NVARCHAR(50) NULL,
    [apprentissage] FLOAT NULL,
    [test] FLOAT NULL,
    [photos_test] INT NULL
);
GO

-- migrations  (source : 06_Exports/Tables/DM01_migrations.csv ; notebook 01_Segmentation_RFM)
IF OBJECT_ID(N'ana.dm01_migrations', N'U') IS NULL
CREATE TABLE [ana].[dm01_migrations] (
    [segment_rfm] NVARCHAR(50) NULL,
    [Champions] FLOAT NULL,
    [Fidèles] FLOAT NULL,
    [Fidèles potentiels] FLOAT NULL,
    [Nouveaux] INT NULL,
    [À surveiller] FLOAT NULL,
    [À risque] FLOAT NULL,
    [Hibernants] FLOAT NULL,
    [Perdus] FLOAT NULL,
    [Inactif] FLOAT NULL
);
GO

-- profil segments  (source : 06_Exports/Tables/DM01_profil_segments.csv ; notebook 01_Segmentation_RFM)
IF OBJECT_ID(N'ana.dm01_profil_segments', N'U') IS NULL
CREATE TABLE [ana].[dm01_profil_segments] (
    [segment_rfm] NVARCHAR(50) NULL,
    [photos] INT NULL,
    [recence_mediane_j] FLOAT NULL,
    [frequence_mediane] FLOAT NULL,
    [montant_median_ttc] FLOAT NULL,
    [panier_moyen_ttc] FLOAT NULL,
    [montant_total_ttc] FLOAT NULL,
    [part_clients] FLOAT NULL,
    [part_montant] FLOAT NULL
);
GO

-- choix k  (source : 06_Exports/Tables/DM02_choix_k.csv ; notebook 02_Clustering_Clients)
IF OBJECT_ID(N'ana.dm02_choix_k', N'U') IS NULL
CREATE TABLE [ana].[dm02_choix_k] (
    [k] INT NULL,
    [inertie] FLOAT NULL,
    [silhouette] FLOAT NULL
);
GO

-- profil clusters  (source : 06_Exports/Tables/DM02_profil_clusters.csv ; notebook 02_Clustering_Clients)
IF OBJECT_ID(N'ana.dm02_profil_clusters', N'U') IS NULL
CREATE TABLE [ana].[dm02_profil_clusters] (
    [cluster] NVARCHAR(50) NULL,
    [clients] INT NULL,
    [recence_mediane_j] FLOAT NULL,
    [frequence_mediane] FLOAT NULL,
    [montant_median_ttc] FLOAT NULL,
    [panier_median_ttc] FLOAT NULL,
    [part_mobile] FLOAT NULL,
    [part_coupon] FLOAT NULL,
    [categories_medianes] FLOAT NULL,
    [part_retard] FLOAT NULL,
    [professionnels] FLOAT NULL,
    [part_clients] FLOAT NULL
);
GO

-- stabilite clusters  (source : 06_Exports/Tables/DM02_stabilite_clusters.csv ; notebook 02_Clustering_Clients)
IF OBJECT_ID(N'ana.dm02_stabilite_clusters', N'U') IS NULL
CREATE TABLE [ana].[dm02_stabilite_clusters] (
    [cluster] NVARCHAR(50) NULL,
    [apprentissage] FLOAT NULL,
    [test] FLOAT NULL,
    [part_apprentissage] FLOAT NULL,
    [part_test] FLOAT NULL
);
GO

-- evaluation recommandation  (source : 06_Exports/Tables/DM03_evaluation_recommandation.csv ; notebook 03_Association_Produits)
IF OBJECT_ID(N'ana.dm03_evaluation_recommandation', N'U') IS NULL
CREATE TABLE [ana].[dm03_evaluation_recommandation] (
    [cle] NVARCHAR(50) NULL,
    [taux de réussite (top 3)] FLOAT NULL,
    [paniers évalués] INT NULL
);
GO

-- lift paires categories  (source : 06_Exports/Tables/DM03_lift_paires_categories.csv ; notebook 03_Association_Produits)
IF OBJECT_ID(N'ana.dm03_lift_paires_categories', N'U') IS NULL
CREATE TABLE [ana].[dm03_lift_paires_categories] (
    [article] NVARCHAR(50) NULL,
    [Mode] FLOAT NULL,
    [Maison & Cuisine] FLOAT NULL,
    [Électronique & High-Tech] FLOAT NULL,
    [Beauté & Santé] FLOAT NULL,
    [Fournitures & Livres] FLOAT NULL,
    [Épicerie fine] FLOAT NULL,
    [Bébé & Enfants] FLOAT NULL,
    [Électroménager] FLOAT NULL,
    [Sport & Loisirs] FLOAT NULL
);
GO

-- regles retenues  (source : 06_Exports/Tables/DM03_regles_retenues.csv ; notebook 03_Association_Produits)
IF OBJECT_ID(N'ana.dm03_regles_retenues', N'U') IS NULL
CREATE TABLE [ana].[dm03_regles_retenues] (
    [antecedents] NVARCHAR(100) NULL,
    [consequents] NVARCHAR(100) NULL,
    [support] FLOAT NULL,
    [confidence] FLOAT NULL,
    [lift] FLOAT NULL,
    [support_2025] FLOAT NULL,
    [confidence_2025] FLOAT NULL,
    [lift_2025] FLOAT NULL,
    [niveau] NVARCHAR(50) NULL,
    [stable] BIT NULL
);
GO

-- taille paniers  (source : 06_Exports/Tables/DM03_taille_paniers.csv ; notebook 03_Association_Produits)
IF OBJECT_ID(N'ana.dm03_taille_paniers', N'U') IS NULL
CREATE TABLE [ana].[dm03_taille_paniers] (
    [cle] NVARCHAR(50) NULL,
    [catégorie] FLOAT NULL,
    [sous-catégorie] FLOAT NULL,
    [produit] FLOAT NULL
);
GO

-- composition paniers  (source : 06_Exports/Tables/DM04_composition_paniers.csv ; notebook 04_Analyse_Comportement_Achat)
IF OBJECT_ID(N'ana.dm04_composition_paniers', N'U') IS NULL
CREATE TABLE [ana].[dm04_composition_paniers] (
    [categories_panier] NVARCHAR(50) NULL,
    [part] FLOAT NULL,
    [montant_moyen_ttc] FLOAT NULL,
    [articles_moyens] FLOAT NULL,
    [part_coupon] FLOAT NULL
);
GO

-- coupon fidelite  (source : 06_Exports/Tables/DM04_coupon_fidelite.csv ; notebook 04_Analyse_Comportement_Achat)
IF OBJECT_ID(N'ana.dm04_coupon_fidelite', N'U') IS NULL
CREATE TABLE [ana].[dm04_coupon_fidelite] (
    [coupon_1re_commande] NVARCHAR(50) NULL,
    [clients] INT NULL,
    [rachat_90j] FLOAT NULL,
    [commandes_dans_l_annee] FLOAT NULL,
    [aucune_commande_dans_l_annee] FLOAT NULL
);
GO

-- facteurs rachat  (source : 06_Exports/Tables/DM04_facteurs_rachat.csv ; notebook 04_Analyse_Comportement_Achat)
IF OBJECT_ID(N'ana.dm04_facteurs_rachat', N'U') IS NULL
CREATE TABLE [ana].[dm04_facteurs_rachat] (
    [modalite] NVARCHAR(50) NULL,
    [clients] INT NULL,
    [taux_rachat_90j] FLOAT NULL,
    [facteur] NVARCHAR(50) NULL,
    [ecart_points] FLOAT NULL
);
GO

-- Groupe k-means (4 groupes) de chaque client à chaque date d'observation  (source : 05_Data/features/clusters_clients.parquet ; notebook 02_Clustering_Clients)
IF OBJECT_ID(N'ana.dm_clusters_clients', N'U') IS NULL
CREATE TABLE [ana].[dm_clusters_clients] (
    [client_sk] INT NOT NULL,
    [date_observation] DATE NOT NULL,
    [periode] NVARCHAR(50) NULL,
    [cluster] NVARCHAR(50) NULL,
    CONSTRAINT [PK_dm_clusters_clients] PRIMARY KEY ([client_sk], [date_observation])
);
GO

-- Règles d'association (2023-2024) et leur mesure sur 2025  (source : 06_Exports/Modeles/regles_association.parquet ; notebook 03_Association_Produits)
IF OBJECT_ID(N'ana.dm_regles_association', N'U') IS NULL
CREATE TABLE [ana].[dm_regles_association] (
    [antecedents] NVARCHAR(100) NULL,
    [consequents] NVARCHAR(100) NULL,
    [support] FLOAT NULL,
    [confidence] FLOAT NULL,
    [lift] FLOAT NULL,
    [support_2025] FLOAT NULL,
    [confidence_2025] FLOAT NULL,
    [lift_2025] FLOAT NULL,
    [niveau] NVARCHAR(50) NULL,
    [stable] BIT NULL
);
GO

-- Scores R, F, M et segment RFM de chaque client à chaque date d'observation  (source : 05_Data/features/segments_rfm.parquet ; notebook 01_Segmentation_RFM)
IF OBJECT_ID(N'ana.dm_segments_rfm', N'U') IS NULL
CREATE TABLE [ana].[dm_segments_rfm] (
    [client_sk] INT NOT NULL,
    [date_observation] DATE NOT NULL,
    [periode] NVARCHAR(50) NULL,
    [score_r] INT NULL,
    [score_f] INT NULL,
    [score_m] INT NULL,
    [code_rfm] NVARCHAR(50) NULL,
    [segment_rfm] NVARCHAR(50) NULL,
    CONSTRAINT [PK_dm_segments_rfm] PRIMARY KEY ([client_sk], [date_observation])
);
GO


/* --------------------------------------------------------------------------------
   Machine learning
   -------------------------------------------------------------------------------- */

-- cibles  (source : 06_Exports/Tables/ML01_cibles.csv ; notebook 01_Preparation_Datasets_ML)
IF OBJECT_ID(N'ana.ml01_cibles', N'U') IS NULL
CREATE TABLE [ana].[ml01_cibles] (
    [cas] NVARCHAR(50) NULL,
    [cible] NVARCHAR(50) NULL,
    [periode] NVARCHAR(50) NULL,
    [lignes] INT NULL,
    [moyenne] FLOAT NULL,
    [mediane] FLOAT NULL,
    [part_de_zero] FLOAT NULL
);
GO

-- derive  (source : 06_Exports/Tables/ML01_derive.csv ; notebook 01_Preparation_Datasets_ML)
IF OBJECT_ID(N'ana.ml01_derive', N'U') IS NULL
CREATE TABLE [ana].[ml01_derive] (
    [cas] NVARCHAR(50) NULL,
    [variable] NVARCHAR(50) NULL,
    [psi] FLOAT NULL,
    [niveau] NVARCHAR(50) NULL,
    [statut] NVARCHAR(50) NULL
);
GO

-- fiche jeux de donnees  (source : 06_Exports/Tables/ML01_fiche_jeux_de_donnees.csv ; notebook 01_Preparation_Datasets_ML)
IF OBJECT_ID(N'ana.ml01_fiche_jeux_de_donnees', N'U') IS NULL
CREATE TABLE [ana].[ml01_fiche_jeux_de_donnees] (
    [cas] NVARCHAR(50) NULL,
    [titre] NVARCHAR(100) NULL,
    [type] NVARCHAR(50) NULL,
    [grain] NVARCHAR(100) NULL,
    [cible] NVARCHAR(50) NULL,
    [lignes apprentissage] INT NULL,
    [lignes test] INT NULL,
    [variables numériques] INT NULL,
    [variables catégorielles] INT NULL
);
GO

-- fuites  (source : 06_Exports/Tables/ML01_fuites.csv ; notebook 01_Preparation_Datasets_ML)
IF OBJECT_ID(N'ana.ml01_fuites', N'U') IS NULL
CREATE TABLE [ana].[ml01_fuites] (
    [cas] NVARCHAR(50) NULL,
    [colonnes écartées] NVARCHAR(100) NULL,
    [raison] NVARCHAR(255) NULL,
    [statut] NVARCHAR(50) NULL
);
GO

-- valeurs manquantes  (source : 06_Exports/Tables/ML01_valeurs_manquantes.csv ; notebook 01_Preparation_Datasets_ML)
IF OBJECT_ID(N'ana.ml01_valeurs_manquantes', N'U') IS NULL
CREATE TABLE [ana].[ml01_valeurs_manquantes] (
    [cas] NVARCHAR(50) NULL,
    [variable] NVARCHAR(50) NULL,
    [part_vide_apprentissage] FLOAT NULL,
    [traitement] NVARCHAR(50) NULL,
    [raison] NVARCHAR(100) NULL
);
GO

-- choix alpha  (source : 06_Exports/Tables/ML02_choix_alpha.csv ; notebook 02_Prevision_Ventes)
IF OBJECT_ID(N'ana.ml02_choix_alpha', N'U') IS NULL
CREATE TABLE [ana].[ml02_choix_alpha] (
    [version] NVARCHAR(50) NULL,
    [alpha] FLOAT NULL,
    [MAPE validation (S2 2024)] FLOAT NULL
);
GO

-- mape categories  (source : 06_Exports/Tables/ML02_mape_categories.csv ; notebook 02_Prevision_Ventes)
IF OBJECT_ID(N'ana.ml02_mape_categories', N'U') IS NULL
CREATE TABLE [ana].[ml02_mape_categories] (
    [cle] NVARCHAR(50) NULL,
    [Naïf × croissance] FLOAT NULL,
    [Holt-Winters (référence)] FLOAT NULL,
    [Ridge « calendrier »] FLOAT NULL
);
GO

-- apport data mining  (source : 06_Exports/Tables/ML03_apport_data_mining.csv ; notebook 03_Prediction_Churn)
IF OBJECT_ID(N'ana.ml03_apport_data_mining', N'U') IS NULL
CREATE TABLE [ana].[ml03_apport_data_mining] (
    [cle] NVARCHAR(50) NULL,
    [AUC 2025] FLOAT NULL,
    [écart] FLOAT NULL
);
GO

-- importance  (source : 06_Exports/Tables/ML03_importance.csv ; notebook 03_Prediction_Churn)
IF OBJECT_ID(N'ana.ml03_importance', N'U') IS NULL
CREATE TABLE [ana].[ml03_importance] (
    [cle] NVARCHAR(50) NULL,
    [perte_AUC] FLOAT NULL
);
GO

-- validation  (source : 06_Exports/Tables/ML03_validation.csv ; notebook 03_Prediction_Churn)
IF OBJECT_ID(N'ana.ml03_validation', N'U') IS NULL
CREATE TABLE [ana].[ml03_validation] (
    [modele] NVARCHAR(50) NULL,
    [AUC validation] FLOAT NULL
);
GO

-- erreur par volume  (source : 06_Exports/Tables/ML04_erreur_par_volume.csv ; notebook 04_Prediction_Demande)
IF OBJECT_ID(N'ana.ml04_erreur_par_volume', N'U') IS NULL
CREATE TABLE [ana].[ml04_erreur_par_volume] (
    [classe] NVARCHAR(50) NULL,
    [produits] FLOAT NULL,
    [part_du_volume] FLOAT NULL,
    [WAPE] FLOAT NULL
);
GO

-- validation  (source : 06_Exports/Tables/ML04_validation.csv ; notebook 04_Prediction_Demande)
IF OBJECT_ID(N'ana.ml04_validation', N'U') IS NULL
CREATE TABLE [ana].[ml04_validation] (
    [modele] NVARCHAR(100) NULL,
    [WAPE validation] FLOAT NULL
);
GO

-- wape categories  (source : 06_Exports/Tables/ML04_wape_categories.csv ; notebook 04_Prediction_Demande)
IF OBJECT_ID(N'ana.ml04_wape_categories', N'U') IS NULL
CREATE TABLE [ana].[ml04_wape_categories] (
    [categorie] NVARCHAR(50) NULL,
    [Moyenne de l'année précédente (référence)] FLOAT NULL,
    [Catégorie × part produit (v2)] FLOAT NULL
);
GO

-- par transporteur  (source : 06_Exports/Tables/ML06_par_transporteur.csv ; notebook 06_Prediction_Retard_Livraison)
IF OBJECT_ID(N'ana.ml06_par_transporteur', N'U') IS NULL
CREATE TABLE [ana].[ml06_par_transporteur] (
    [transporteur] NVARCHAR(50) NULL,
    [expeditions] FLOAT NULL,
    [taux_reel] FLOAT NULL,
    [taux_prevu] FLOAT NULL,
    [AUC] FLOAT NULL
);
GO

-- validation  (source : 06_Exports/Tables/ML06_validation.csv ; notebook 06_Prediction_Retard_Livraison)
IF OBJECT_ID(N'ana.ml06_validation', N'U') IS NULL
CREATE TABLE [ana].[ml06_validation] (
    [modele] NVARCHAR(100) NULL,
    [fenetre] NVARCHAR(50) NULL,
    [AUC validation] FLOAT NULL,
    [lignes] FLOAT NULL,
    [taux prévu] FLOAT NULL,
    [taux réel] FLOAT NULL
);
GO

-- churn par segment  (source : 06_Exports/Tables/ML08_churn_par_segment.csv ; notebook 08_Scoring_Actuel)
IF OBJECT_ID(N'ana.ml08_churn_par_segment', N'U') IS NULL
CREATE TABLE [ana].[ml08_churn_par_segment] (
    [segment_rfm] NVARCHAR(50) NULL,
    [clients] INT NULL,
    [proba_moyenne] FLOAT NULL,
    [en_alerte] INT NULL,
    [montant_ttc] FLOAT NULL,
    [part_en_alerte] FLOAT NULL
);
GO

-- retard en cours  (source : 06_Exports/Tables/ML08_retard_en_cours.csv ; notebook 08_Scoring_Actuel)
IF OBJECT_ID(N'ana.ml08_retard_en_cours', N'U') IS NULL
CREATE TABLE [ana].[ml08_retard_en_cours] (
    [transporteur] NVARCHAR(50) NULL,
    [colis] INT NULL,
    [proba_moyenne] FLOAT NULL,
    [en_alerte] INT NULL
);
GO

-- Comparaison des modèles du cas « churn » (validation et test 2025)  (source : 06_Exports/Tables/ML_metriques_churn.csv ; notebook 03_Prediction_Churn)
IF OBJECT_ID(N'ana.ml_metriques_churn', N'U') IS NULL
CREATE TABLE [ana].[ml_metriques_churn] (
    [cas] NVARCHAR(50) NULL,
    [modele] NVARCHAR(50) NULL,
    [role] NVARCHAR(50) NULL,
    [AUC_validation] FLOAT NULL,
    [AUC] FLOAT NULL,
    [precision_moyenne] FLOAT NULL,
    [precision] FLOAT NULL,
    [rappel] FLOAT NULL,
    [F1] FLOAT NULL,
    [seuil] FLOAT NULL,
    [taux_reel] FLOAT NULL,
    [taux_prevu] FLOAT NULL,
    [capture_top_20] FLOAT NULL,
    [taux_positifs_top_20] FLOAT NULL,
    [AUC_apprentissage] FLOAT NULL,
    [retenu] BIT NULL
);
GO

-- Comparaison des modèles du cas « demande » (validation et test 2025)  (source : 06_Exports/Tables/ML_metriques_demande.csv ; notebook 04_Prediction_Demande)
IF OBJECT_ID(N'ana.ml_metriques_demande', N'U') IS NULL
CREATE TABLE [ana].[ml_metriques_demande] (
    [cas] NVARCHAR(50) NULL,
    [modele] NVARCHAR(100) NULL,
    [role] NVARCHAR(50) NULL,
    [WAPE_validation] FLOAT NULL,
    [WAPE_produit_mois] FLOAT NULL,
    [MAE_produit_mois] FLOAT NULL,
    [biais] FLOAT NULL,
    [WAPE_categorie_mois] FLOAT NULL,
    [gain_vs_reference] FLOAT NULL,
    [retenu] BIT NULL
);
GO

-- Comparaison des modèles du cas « retard » (validation et test 2025)  (source : 06_Exports/Tables/ML_metriques_retard.csv ; notebook 06_Prediction_Retard_Livraison)
IF OBJECT_ID(N'ana.ml_metriques_retard', N'U') IS NULL
CREATE TABLE [ana].[ml_metriques_retard] (
    [cas] NVARCHAR(50) NULL,
    [modele] NVARCHAR(100) NULL,
    [fenetre] NVARCHAR(50) NULL,
    [role] NVARCHAR(50) NULL,
    [AUC_validation] FLOAT NULL,
    [AUC] FLOAT NULL,
    [precision_moyenne] FLOAT NULL,
    [precision] FLOAT NULL,
    [rappel] FLOAT NULL,
    [F1] FLOAT NULL,
    [seuil] FLOAT NULL,
    [taux_reel] FLOAT NULL,
    [taux_prevu] FLOAT NULL,
    [capture_top_20] FLOAT NULL,
    [taux_positifs_top_20] FLOAT NULL,
    [AUC_apprentissage] FLOAT NULL,
    [retenu] BIT NULL
);
GO

-- Comparaison des modèles du cas « ventes » (validation et test 2025)  (source : 06_Exports/Tables/ML_metriques_ventes.csv ; notebook 02_Prevision_Ventes)
IF OBJECT_ID(N'ana.ml_metriques_ventes', N'U') IS NULL
CREATE TABLE [ana].[ml_metriques_ventes] (
    [cas] NVARCHAR(50) NULL,
    [modele] NVARCHAR(50) NULL,
    [role] NVARCHAR(50) NULL,
    [MAPE_total] FLOAT NULL,
    [WAPE_total] FLOAT NULL,
    [biais_total] FLOAT NULL,
    [MAPE_moyen_categories] FLOAT NULL,
    [gain_vs_reference] FLOAT NULL,
    [MAPE_validation] FLOAT NULL,
    [retenu] BIT NULL
);
GO

-- Probabilité de churn à 90 jours et alerte, test 2025  (source : 06_Exports/Predictions/churn_2025_test.parquet ; notebook 03_Prediction_Churn)
IF OBJECT_ID(N'ana.ml_pred_churn_2025', N'U') IS NULL
CREATE TABLE [ana].[ml_pred_churn_2025] (
    [client_sk] INT NOT NULL,
    [date_observation] DATE NOT NULL,
    [churn] INT NULL,
    [proba_churn] FLOAT NULL,
    [prediction] INT NULL,
    CONSTRAINT [PK_ml_pred_churn_2025] PRIMARY KEY ([client_sk], [date_observation])
);
GO

-- Quantité réelle et prévue par produit et par mois, test 2025  (source : 06_Exports/Predictions/demande_2025_test.parquet ; notebook 04_Prediction_Demande)
IF OBJECT_ID(N'ana.ml_pred_demande_2025', N'U') IS NULL
CREATE TABLE [ana].[ml_pred_demande_2025] (
    [produit_id] NVARCHAR(50) NOT NULL,
    [mois] DATE NOT NULL,
    [categorie] NVARCHAR(50) NULL,
    [quantite] FLOAT NULL,
    [Naïf saisonnier] FLOAT NULL,
    [Moyenne de l'année précédente (référence)] FLOAT NULL,
    [Gradient boosting (Poisson)] FLOAT NULL,
    [Gradient boosting (quadratique)] FLOAT NULL,
    [Catégorie × part produit (v2)] FLOAT NULL,
    [prevision_retenue] FLOAT NULL,
    CONSTRAINT [PK_ml_pred_demande_2025] PRIMARY KEY ([produit_id], [mois])
);
GO

-- Probabilité de retard de chaque expédition, test 2025  (source : 06_Exports/Predictions/retard_2025_test.parquet ; notebook 06_Prediction_Retard_Livraison)
IF OBJECT_ID(N'ana.ml_pred_retard_2025', N'U') IS NULL
CREATE TABLE [ana].[ml_pred_retard_2025] (
    [livraison_id] NVARCHAR(50) NOT NULL,
    [date_expedition] DATE NULL,
    [transporteur] NVARCHAR(50) NULL,
    [en_retard] INT NULL,
    [proba_retard] FLOAT NULL,
    CONSTRAINT [PK_ml_pred_retard_2025] PRIMARY KEY ([livraison_id])
);
GO

-- CA TTC réel et prévu par catégorie et par mois, test 2025  (source : 06_Exports/Predictions/ventes_2025_test.parquet ; notebook 02_Prevision_Ventes)
IF OBJECT_ID(N'ana.ml_pred_ventes_2025', N'U') IS NULL
CREATE TABLE [ana].[ml_pred_ventes_2025] (
    [mois] DATE NOT NULL,
    [categorie] NVARCHAR(50) NOT NULL,
    [prevision] FLOAT NULL,
    [reel] FLOAT NULL,
    [Naïf saisonnier] FLOAT NULL,
    [Naïf × croissance] FLOAT NULL,
    [Holt-Winters (référence)] FLOAT NULL,
    CONSTRAINT [PK_ml_pred_ventes_2025] PRIMARY KEY ([categorie], [mois])
);
GO

-- Prévision du CA TTC 2026 par catégorie (après chargement du calendrier 2026)  (source : 06_Exports/Predictions/ventes_2026.parquet ; notebook 02_Prevision_Ventes)
IF OBJECT_ID(N'ana.ml_pred_ventes_2026', N'U') IS NULL
CREATE TABLE [ana].[ml_pred_ventes_2026] (
    [mois] DATE NOT NULL,
    [categorie] NVARCHAR(100) NOT NULL,
    [prevision_ca_ttc] FLOAT NULL,
    CONSTRAINT [PK_ml_pred_ventes_2026] PRIMARY KEY ([categorie], [mois])
);
GO

-- Registre des modèles : fiche d'identité de chaque modèle  (source : 06_Exports/Tables/ML_registre_modeles.csv ; notebook 08_Scoring_Actuel)
IF OBJECT_ID(N'ana.ml_registre_modeles', N'U') IS NULL
CREATE TABLE [ana].[ml_registre_modeles] (
    [nom] NVARCHAR(50) NOT NULL,
    [cas] NVARCHAR(50) NULL,
    [role] NVARCHAR(50) NULL,
    [version] NVARCHAR(50) NULL,
    [appris_le] NVARCHAR(50) NULL,
    [periode_apprentissage] NVARCHAR(100) NULL,
    [lignes_apprentissage] FLOAT NULL,
    [taux_cible] FLOAT NULL,
    [empreinte_donnees] NVARCHAR(50) NULL,
    [nb_variables] INT NULL,
    [reglages] NVARCHAR(1000) NULL,
    [seuil] FLOAT NULL,
    [source] NVARCHAR(50) NULL,
    [fichier] NVARCHAR(100) NULL,
    [notes] NVARCHAR(255) NULL,
    [variables] NVARCHAR(1000) NULL,
    [mesure_AUC_test_2025] FLOAT NULL,
    [mesure_rappel_test_2025] FLOAT NULL,
    [mesure_precision_test_2025] FLOAT NULL,
    [version_python] NVARCHAR(50) NULL,
    [version_scikit-learn] NVARCHAR(50) NULL,
    [version_pandas] NVARCHAR(50) NULL,
    [mesure_WAPE_test_2025] FLOAT NULL,
    [mesure_MAPE_test_2025] FLOAT NULL,
    [mesure_capture_top_20_test_2025] FLOAT NULL,
    CONSTRAINT [PK_ml_registre_modeles] PRIMARY KEY ([nom])
);
GO

-- Probabilité de churn des clients actifs à la date de scoring  (source : 06_Exports/Predictions/churn_scores_actuels.parquet ; notebook 08_Scoring_Actuel)
IF OBJECT_ID(N'ana.ml_scores_churn_actuels', N'U') IS NULL
CREATE TABLE [ana].[ml_scores_churn_actuels] (
    [client_sk] INT NOT NULL,
    [date_scoring] DATE NULL,
    [segment_rfm] NVARCHAR(50) NULL,
    [cluster] NVARCHAR(50) NULL,
    [recence_j] INT NULL,
    [frequence] INT NULL,
    [montant_reconnu_ttc] FLOAT NULL,
    [proba_churn] FLOAT NULL,
    [alerte_churn] INT NULL,
    [decile_risque] INT NULL,
    [version_modele] NVARCHAR(50) NULL,
    CONSTRAINT [PK_ml_scores_churn_actuels] PRIMARY KEY ([client_sk])
);
GO

-- Probabilité de retard des colis en transit  (source : 06_Exports/Predictions/retard_scores_en_cours.parquet ; notebook 08_Scoring_Actuel)
IF OBJECT_ID(N'ana.ml_scores_retard_en_cours', N'U') IS NULL
CREATE TABLE [ana].[ml_scores_retard_en_cours] (
    [livraison_id] NVARCHAR(50) NOT NULL,
    [commande_id] NVARCHAR(50) NULL,
    [date_expedition] DATE NULL,
    [transporteur] NVARCHAR(50) NULL,
    [region] NVARCHAR(50) NULL,
    [zone_livraison] NVARCHAR(50) NULL,
    [entrepot] NVARCHAR(50) NULL,
    [proba_retard] FLOAT NULL,
    [alerte_retard] INT NULL,
    [date_scoring] DATE NULL,
    [version_modele] NVARCHAR(50) NULL,
    CONSTRAINT [PK_ml_scores_retard_en_cours] PRIMARY KEY ([livraison_id])
);
GO

-- Demande prévue par produit et par mois pour l'année suivante, avec stock de départ  (source : 06_Exports/Predictions/demande_scores_annee_suivante.parquet ; notebook 08_Scoring_Actuel)
IF OBJECT_ID(N'ana.ml_scores_demande', N'U') IS NULL
CREATE TABLE [ana].[ml_scores_demande] (
    [produit_id] NVARCHAR(50) NOT NULL,
    [categorie] NVARCHAR(50) NULL,
    [mois] DATE NOT NULL,
    [quantite_prevue] FLOAT NULL,
    [stock_depart] FLOAT NULL,
    [demande_cumulee] FLOAT NULL,
    [rupture_sans_reappro] INT NULL,
    [date_scoring] DATE NULL,
    [version_modele] NVARCHAR(50) NULL,
    CONSTRAINT [PK_ml_scores_demande] PRIMARY KEY ([produit_id], [mois])
);
GO

-- Suivi des modèles : indicateurs par période et alertes  (source : 06_Exports/Tables/ML_suivi.csv ; notebook 09_Suivi_Modeles)
IF OBJECT_ID(N'ana.ml_suivi', N'U') IS NULL
CREATE TABLE [ana].[ml_suivi] (
    [cas] NVARCHAR(50) NULL,
    [objet] NVARCHAR(50) NULL,
    [periode] NVARCHAR(50) NULL,
    [indicateur] NVARCHAR(100) NULL,             -- v1.5 : 100 (libellés du modèle de production)
    [valeur] FLOAT NULL,
    [seuil] FLOAT NULL,
    [statut] NVARCHAR(50) NULL
);
GO

-- Historique du suivi des modèles (v1.5) : toutes les exécutions, repérées par la date des dernières données
-- (source : 06_Exports/Tables/ML_suivi_historique.csv ; notebook 09_Suivi_Modeles)
IF OBJECT_ID(N'ana.ml_suivi_historique', N'U') IS NULL
CREATE TABLE [ana].[ml_suivi_historique] (
    [date_donnees] DATE NOT NULL,
    [calcule_le] NVARCHAR(50) NULL,
    [cas] NVARCHAR(50) NOT NULL,
    [objet] NVARCHAR(50) NOT NULL,
    [periode] NVARCHAR(50) NOT NULL,
    [indicateur] NVARCHAR(100) NOT NULL,
    [valeur] FLOAT NULL,
    [seuil] FLOAT NULL,
    [statut] NVARCHAR(50) NULL,
    CONSTRAINT [PK_ml_suivi_historique] PRIMARY KEY ([date_donnees], [cas], [objet], [periode], [indicateur])
);
GO


/* --------------------------------------------------------------------------------
   Catalogue des tables (ctl.catalogue_tables) : phase, notebook, fichier source, lien avec le DWH
   -------------------------------------------------------------------------------- */
MERGE ctl.catalogue_tables AS cible
USING (VALUES
    (N'ana.eda00_coherence', N'EDA', N'01_EDA_Global', N'06_Exports/Tables/EDA00_coherence.csv', NULL, NULL, N'Contrôle de qualité : coherence'),
    (N'ana.eda00_extremes', N'EDA', N'01_EDA_Global', N'06_Exports/Tables/EDA00_extremes.csv', NULL, NULL, N'Contrôle de qualité : extremes'),
    (N'ana.eda00_integrite', N'EDA', N'01_EDA_Global', N'06_Exports/Tables/EDA00_integrite.csv', NULL, NULL, N'Contrôle de qualité : integrite'),
    (N'ana.eda00_inventaire', N'EDA', N'01_EDA_Global', N'06_Exports/Tables/EDA00_inventaire.csv', NULL, NULL, N'Contrôle de qualité : inventaire'),
    (N'ana.eda00_manquants', N'EDA', N'01_EDA_Global', N'06_Exports/Tables/EDA00_manquants.csv', NULL, NULL, N'Contrôle de qualité : manquants'),
    (N'ana.eda00_membres', N'EDA', N'01_EDA_Global', N'06_Exports/Tables/EDA00_membres.csv', NULL, NULL, N'Contrôle de qualité : membres'),
    (N'ana.eda00_synthese_qualite', N'EDA', N'01_EDA_Global', N'06_Exports/Tables/EDA00_synthese_qualite.csv', NULL, NULL, N'Contrôle de qualité : synthese qualite'),
    (N'ana.eda00_unicite', N'EDA', N'01_EDA_Global', N'06_Exports/Tables/EDA00_unicite.csv', NULL, NULL, N'Contrôle de qualité : unicite'),
    (N'ana.eda_g03_vue_ensemble_annuelle', N'EDA', N'01_EDA_Global', N'06_Exports/Tables/G03_vue_ensemble_annuelle.csv', NULL, NULL, N'Vue d''ensemble annuelle : vue ensemble annuelle'),
    (N'ana.eda_g04_tables_variables', N'EDA', N'01_EDA_Global', N'06_Exports/Tables/G04_tables_variables.csv', NULL, NULL, N'Tables de variables construites : tables variables'),
    (N'ana.eda_hypotheses', N'EDA', N'02 à 06 (01_EDA)', N'06_Exports/Tables/EDA_hypotheses_*.csv', N'question', NULL, N'Verdict des 21 hypothèses du plan d''analyse'),
    (N'ana.eda_q01_ventes_annuelles', N'EDA', N'02_EDA_Sales', N'06_Exports/Tables/Q01_ventes_annuelles.csv', NULL, NULL, N'Q01 — Comment évoluent les ventes entre 2023 et 2025 ?'),
    (N'ana.eda_q01_ventes_mensuelles', N'EDA', N'02_EDA_Sales', N'06_Exports/Tables/Q01_ventes_mensuelles.csv', NULL, NULL, N'Q01 — Comment évoluent les ventes entre 2023 et 2025 ?'),
    (N'ana.eda_q02_ca_par_periode_commerciale', N'EDA', N'02_EDA_Sales', N'06_Exports/Tables/Q02_ca_par_periode_commerciale.csv', NULL, NULL, N'Q02 — Y a-t-il une saisonnalité ? Quel est l''effet du Ramadan et des périodes commerciales ?'),
    (N'ana.eda_q03_categories', N'EDA', N'04_EDA_Products', N'06_Exports/Tables/Q03_categories.csv', NULL, NULL, N'Q03 — Quelles catégories font le chiffre d''affaires et la marge ?'),
    (N'ana.eda_q04_gammes_prix', N'EDA', N'04_EDA_Products', N'06_Exports/Tables/Q04_gammes_prix.csv', NULL, NULL, N'Q04 — Le CA est-il concentré sur quelques produits ? Quelles gammes de prix rapportent ?'),
    (N'ana.eda_q05_nouveaux_clients', N'EDA', N'03_EDA_Customers', N'06_Exports/Tables/Q05_nouveaux_clients.csv', NULL, NULL, N'Q05 — Combien de fois les clients achètent-ils ? D''où viennent les clients de l''année ?'),
    (N'ana.eda_q06_valeur_par_canal_inscription', N'EDA', N'03_EDA_Customers', N'06_Exports/Tables/Q06_valeur_par_canal_inscription.csv', NULL, NULL, N'Q06 — Le profil du client (type, âge, canal d''inscription) change-t-il sa valeur ?'),
    (N'ana.eda_q06_valeur_par_type', N'EDA', N'03_EDA_Customers', N'06_Exports/Tables/Q06_valeur_par_type.csv', NULL, NULL, N'Q06 — Le profil du client (type, âge, canal d''inscription) change-t-il sa valeur ?'),
    (N'ana.eda_q07_cohortes_retention', N'EDA', N'03_EDA_Customers', N'06_Exports/Tables/Q07_cohortes_retention.csv', NULL, NULL, N'Q07 — Les clients reviennent-ils ? (analyse de cohortes)'),
    (N'ana.eda_q08_regions', N'EDA', N'03_EDA_Customers', N'06_Exports/Tables/Q08_regions.csv', NULL, NULL, N'Q08 — Où sont les clients ?'),
    (N'ana.eda_q09_echec_paiement', N'EDA', N'02_EDA_Sales', N'06_Exports/Tables/Q09_echec_paiement.csv', NULL, NULL, N'Q09 — Par quels canaux et modes de paiement les clients achètent-ils ?'),
    (N'ana.eda_q09_parts_canal', N'EDA', N'02_EDA_Sales', N'06_Exports/Tables/Q09_parts_canal.csv', NULL, NULL, N'Q09 — Par quels canaux et modes de paiement les clients achètent-ils ?'),
    (N'ana.eda_q10_causes_echec', N'EDA', N'06_EDA_Marketing_Finance', N'06_Exports/Tables/Q10_causes_echec.csv', NULL, NULL, N'Q10 — Pourquoi les paiements échouent-ils ? Une 2e tentative réussit-elle ?'),
    (N'ana.eda_q11_performance_canaux_media', N'EDA', N'06_EDA_Marketing_Finance', N'06_Exports/Tables/Q11_performance_canaux_media.csv', NULL, NULL, N'Q11 — Quelles campagnes rapportent le plus par dinar dépensé ?'),
    (N'ana.eda_q11_roas_annuel', N'EDA', N'06_EDA_Marketing_Finance', N'06_Exports/Tables/Q11_roas_annuel.csv', NULL, NULL, N'Q11 — Quelles campagnes rapportent le plus par dinar dépensé ?'),
    (N'ana.eda_q12_coupons_annuels', N'EDA', N'06_EDA_Marketing_Finance', N'06_Exports/Tables/Q12_coupons_annuels.csv', NULL, NULL, N'Q12 — Les coupons augmentent-ils le panier ? À qui servent-ils ?'),
    (N'ana.eda_q13_retard_transporteur_semestre', N'EDA', N'05_EDA_Stock_Logistics', N'06_Exports/Tables/Q13_retard_transporteur_semestre.csv', NULL, NULL, N'Q13 — Les livraisons arrivent-elles à l''heure ? Qui est en retard ?'),
    (N'ana.eda_q14_entrepots', N'EDA', N'05_EDA_Stock_Logistics', N'06_Exports/Tables/Q14_entrepots.csv', NULL, NULL, N'Q14 — Quel est le rôle des entrepôts ? Combien de colis n''arrivent jamais ?'),
    (N'ana.eda_q15_note_selon_retard', N'EDA', N'03_EDA_Customers', N'06_Exports/Tables/Q15_note_selon_retard.csv', NULL, NULL, N'Q15 — Le retard dégrade-t-il la satisfaction ?'),
    (N'ana.eda_q16_retours_categorie', N'EDA', N'04_EDA_Products', N'06_Exports/Tables/Q16_retours_categorie.csv', NULL, NULL, N'Q16 — Quelles catégories sont le plus retournées ?'),
    (N'ana.eda_q17_motifs_remboursement', N'EDA', N'06_EDA_Marketing_Finance', N'06_Exports/Tables/Q17_motifs_remboursement.csv', NULL, NULL, N'Q17 — Pourquoi les clients demandent-ils un remboursement ? Qui en est responsable ?'),
    (N'ana.eda_q19_stock_mensuel', N'EDA', N'05_EDA_Stock_Logistics', N'06_Exports/Tables/Q19_stock_mensuel.csv', NULL, NULL, N'Q19 — Le stock suit-il la demande ? Quand les ruptures arrivent-elles ?'),
    (N'ana.eda_q21_fournisseurs', N'EDA', N'05_EDA_Stock_Logistics', N'06_Exports/Tables/Q21_fournisseurs.csv', NULL, NULL, N'Q21 — Les fournisseurs livrent-ils à temps ? La fiabilité annoncée est-elle tenue ?'),
    (N'ana.eda_q21_fournisseurs_pays', N'EDA', N'05_EDA_Stock_Logistics', N'06_Exports/Tables/Q21_fournisseurs_pays.csv', NULL, NULL, N'Q21 — Les fournisseurs livrent-ils à temps ? La fiabilité annoncée est-elle tenue ?'),
    (N'ana.dm01_actions_segments', N'Data mining', N'01_Segmentation_RFM', N'06_Exports/Tables/DM01_actions_segments.csv', NULL, NULL, N'actions segments'),
    (N'ana.dm01_churn_par_segment', N'Data mining', N'01_Segmentation_RFM', N'06_Exports/Tables/DM01_churn_par_segment.csv', NULL, NULL, N'churn par segment'),
    (N'ana.dm01_migrations', N'Data mining', N'01_Segmentation_RFM', N'06_Exports/Tables/DM01_migrations.csv', NULL, NULL, N'migrations'),
    (N'ana.dm01_profil_segments', N'Data mining', N'01_Segmentation_RFM', N'06_Exports/Tables/DM01_profil_segments.csv', NULL, NULL, N'profil segments'),
    (N'ana.dm02_choix_k', N'Data mining', N'02_Clustering_Clients', N'06_Exports/Tables/DM02_choix_k.csv', NULL, NULL, N'choix k'),
    (N'ana.dm02_profil_clusters', N'Data mining', N'02_Clustering_Clients', N'06_Exports/Tables/DM02_profil_clusters.csv', NULL, NULL, N'profil clusters'),
    (N'ana.dm02_stabilite_clusters', N'Data mining', N'02_Clustering_Clients', N'06_Exports/Tables/DM02_stabilite_clusters.csv', NULL, NULL, N'stabilite clusters'),
    (N'ana.dm03_evaluation_recommandation', N'Data mining', N'03_Association_Produits', N'06_Exports/Tables/DM03_evaluation_recommandation.csv', NULL, NULL, N'evaluation recommandation'),
    (N'ana.dm03_lift_paires_categories', N'Data mining', N'03_Association_Produits', N'06_Exports/Tables/DM03_lift_paires_categories.csv', NULL, NULL, N'lift paires categories'),
    (N'ana.dm03_regles_retenues', N'Data mining', N'03_Association_Produits', N'06_Exports/Tables/DM03_regles_retenues.csv', NULL, NULL, N'regles retenues'),
    (N'ana.dm03_taille_paniers', N'Data mining', N'03_Association_Produits', N'06_Exports/Tables/DM03_taille_paniers.csv', NULL, NULL, N'taille paniers'),
    (N'ana.dm04_composition_paniers', N'Data mining', N'04_Analyse_Comportement_Achat', N'06_Exports/Tables/DM04_composition_paniers.csv', NULL, NULL, N'composition paniers'),
    (N'ana.dm04_coupon_fidelite', N'Data mining', N'04_Analyse_Comportement_Achat', N'06_Exports/Tables/DM04_coupon_fidelite.csv', NULL, NULL, N'coupon fidelite'),
    (N'ana.dm04_facteurs_rachat', N'Data mining', N'04_Analyse_Comportement_Achat', N'06_Exports/Tables/DM04_facteurs_rachat.csv', NULL, NULL, N'facteurs rachat'),
    (N'ana.dm_clusters_clients', N'Data mining', N'02_Clustering_Clients', N'05_Data/features/clusters_clients.parquet', N'client_sk, date_observation', N'client_sk', N'Groupe k-means (4 groupes) de chaque client à chaque date d''observation'),
    (N'ana.dm_regles_association', N'Data mining', N'03_Association_Produits', N'06_Exports/Modeles/regles_association.parquet', NULL, NULL, N'Règles d''association (2023-2024) et leur mesure sur 2025'),
    (N'ana.dm_segments_rfm', N'Data mining', N'01_Segmentation_RFM', N'05_Data/features/segments_rfm.parquet', N'client_sk, date_observation', N'client_sk', N'Scores R, F, M et segment RFM de chaque client à chaque date d''observation'),
    (N'ana.ml01_cibles', N'Machine learning', N'01_Preparation_Datasets_ML', N'06_Exports/Tables/ML01_cibles.csv', NULL, NULL, N'cibles'),
    (N'ana.ml01_derive', N'Machine learning', N'01_Preparation_Datasets_ML', N'06_Exports/Tables/ML01_derive.csv', NULL, NULL, N'derive'),
    (N'ana.ml01_fiche_jeux_de_donnees', N'Machine learning', N'01_Preparation_Datasets_ML', N'06_Exports/Tables/ML01_fiche_jeux_de_donnees.csv', NULL, NULL, N'fiche jeux de donnees'),
    (N'ana.ml01_fuites', N'Machine learning', N'01_Preparation_Datasets_ML', N'06_Exports/Tables/ML01_fuites.csv', NULL, NULL, N'fuites'),
    (N'ana.ml01_valeurs_manquantes', N'Machine learning', N'01_Preparation_Datasets_ML', N'06_Exports/Tables/ML01_valeurs_manquantes.csv', NULL, NULL, N'valeurs manquantes'),
    (N'ana.ml02_choix_alpha', N'Machine learning', N'02_Prevision_Ventes', N'06_Exports/Tables/ML02_choix_alpha.csv', NULL, NULL, N'choix alpha'),
    (N'ana.ml02_mape_categories', N'Machine learning', N'02_Prevision_Ventes', N'06_Exports/Tables/ML02_mape_categories.csv', NULL, NULL, N'mape categories'),
    (N'ana.ml03_apport_data_mining', N'Machine learning', N'03_Prediction_Churn', N'06_Exports/Tables/ML03_apport_data_mining.csv', NULL, NULL, N'apport data mining'),
    (N'ana.ml03_importance', N'Machine learning', N'03_Prediction_Churn', N'06_Exports/Tables/ML03_importance.csv', NULL, NULL, N'importance'),
    (N'ana.ml03_validation', N'Machine learning', N'03_Prediction_Churn', N'06_Exports/Tables/ML03_validation.csv', NULL, NULL, N'validation'),
    (N'ana.ml04_erreur_par_volume', N'Machine learning', N'04_Prediction_Demande', N'06_Exports/Tables/ML04_erreur_par_volume.csv', NULL, NULL, N'erreur par volume'),
    (N'ana.ml04_validation', N'Machine learning', N'04_Prediction_Demande', N'06_Exports/Tables/ML04_validation.csv', NULL, NULL, N'validation'),
    (N'ana.ml04_wape_categories', N'Machine learning', N'04_Prediction_Demande', N'06_Exports/Tables/ML04_wape_categories.csv', NULL, NULL, N'wape categories'),
    (N'ana.ml06_par_transporteur', N'Machine learning', N'06_Prediction_Retard_Livraison', N'06_Exports/Tables/ML06_par_transporteur.csv', NULL, NULL, N'par transporteur'),
    (N'ana.ml06_validation', N'Machine learning', N'06_Prediction_Retard_Livraison', N'06_Exports/Tables/ML06_validation.csv', NULL, NULL, N'validation'),
    (N'ana.ml08_churn_par_segment', N'Machine learning', N'08_Scoring_Actuel', N'06_Exports/Tables/ML08_churn_par_segment.csv', NULL, NULL, N'churn par segment'),
    (N'ana.ml08_retard_en_cours', N'Machine learning', N'08_Scoring_Actuel', N'06_Exports/Tables/ML08_retard_en_cours.csv', NULL, NULL, N'retard en cours'),
    (N'ana.ml_metriques_churn', N'Machine learning', N'03_Prediction_Churn', N'06_Exports/Tables/ML_metriques_churn.csv', NULL, NULL, N'Comparaison des modèles du cas « churn » (validation et test 2025)'),
    (N'ana.ml_metriques_demande', N'Machine learning', N'04_Prediction_Demande', N'06_Exports/Tables/ML_metriques_demande.csv', NULL, NULL, N'Comparaison des modèles du cas « demande » (validation et test 2025)'),
    (N'ana.ml_metriques_retard', N'Machine learning', N'06_Prediction_Retard_Livraison', N'06_Exports/Tables/ML_metriques_retard.csv', NULL, NULL, N'Comparaison des modèles du cas « retard » (validation et test 2025)'),
    (N'ana.ml_metriques_ventes', N'Machine learning', N'02_Prevision_Ventes', N'06_Exports/Tables/ML_metriques_ventes.csv', NULL, NULL, N'Comparaison des modèles du cas « ventes » (validation et test 2025)'),
    (N'ana.ml_pred_churn_2025', N'Machine learning', N'03_Prediction_Churn', N'06_Exports/Predictions/churn_2025_test.parquet', N'client_sk, date_observation', N'client_sk', N'Probabilité de churn à 90 jours et alerte, test 2025'),
    (N'ana.ml_pred_demande_2025', N'Machine learning', N'04_Prediction_Demande', N'06_Exports/Predictions/demande_2025_test.parquet', N'produit_id, mois', N'produit_id, mois', N'Quantité réelle et prévue par produit et par mois, test 2025'),
    (N'ana.ml_pred_retard_2025', N'Machine learning', N'06_Prediction_Retard_Livraison', N'06_Exports/Predictions/retard_2025_test.parquet', N'livraison_id', N'livraison_id', N'Probabilité de retard de chaque expédition, test 2025'),
    (N'ana.ml_pred_ventes_2025', N'Machine learning', N'02_Prevision_Ventes', N'06_Exports/Predictions/ventes_2025_test.parquet', N'categorie, mois', N'mois', N'CA TTC réel et prévu par catégorie et par mois, test 2025'),
    (N'ana.ml_pred_ventes_2026', N'Machine learning', N'02_Prevision_Ventes', N'06_Exports/Predictions/ventes_2026.parquet', N'categorie, mois', N'mois', N'Prévision du CA TTC 2026 par catégorie (après chargement du calendrier 2026)'),
    (N'ana.ml_registre_modeles', N'Machine learning', N'08_Scoring_Actuel', N'06_Exports/Tables/ML_registre_modeles.csv', N'nom', NULL, N'Registre des modèles : fiche d''identité de chaque modèle'),
    (N'ana.ml_scores_churn_actuels', N'Machine learning', N'08_Scoring_Actuel', N'06_Exports/Predictions/churn_scores_actuels.parquet', N'client_sk', N'client_sk', N'Probabilité de churn des clients actifs à la date de scoring'),
    (N'ana.ml_scores_retard_en_cours', N'Machine learning', N'08_Scoring_Actuel', N'06_Exports/Predictions/retard_scores_en_cours.parquet', N'livraison_id', N'livraison_id', N'Probabilité de retard des colis en transit'),
    (N'ana.ml_scores_demande', N'Machine learning', N'08_Scoring_Actuel', N'06_Exports/Predictions/demande_scores_annee_suivante.parquet', N'produit_id, mois', N'produit_id, mois', N'Demande prévue par produit et par mois pour l''année suivante, stock de départ et alerte de rupture'),
    (N'ana.ml_suivi', N'Machine learning', N'09_Suivi_Modeles', N'06_Exports/Tables/ML_suivi.csv', NULL, NULL, N'Suivi des modèles : indicateurs par période et alertes (dernière exécution)'),
    (N'ana.ml_suivi_historique', N'Machine learning', N'09_Suivi_Modeles', N'06_Exports/Tables/ML_suivi_historique.csv', N'date_donnees, cas, objet, periode, indicateur', NULL, N'Suivi des modèles : toutes les exécutions, repérées par la date des dernières données (v1.5)')
) AS source (table_sql, phase, notebook, source, cle, lien_dwh, description)
ON cible.table_sql = source.table_sql
WHEN MATCHED THEN UPDATE SET phase = source.phase, notebook = source.notebook, source = source.source,
                             cle = source.cle, lien_dwh = source.lien_dwh, description = source.description
WHEN NOT MATCHED THEN INSERT (table_sql, phase, notebook, source, cle, lien_dwh, description)
                      VALUES (source.table_sql, source.phase, source.notebook, source.source, source.cle, source.lien_dwh, source.description);
GO

PRINT N'Étape 02 terminée : 84 tables de résultats et le catalogue sont prêts.';
GO
