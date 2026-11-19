/* =====================================================================
   Projet      : TuniShop — Data Warehouse e-commerce (portfolio)
   Script      : 01_Creation_DWH.sql
   Objet       : Création du Data Warehouse TuniShop_DWH (schéma dw) : 13 dimensions, 10 tables de faits, membres inconnus, index et vues de restitution (schéma bi).
   Cible       : Microsoft SQL Server 2019+ (SSMS) — compatibilité 150
   Exécution   : SSMS, mode SQLCMD inutile ; exécuter en entier (F5)
   Généré le   : 2026-10-17 depuis le modèle de métadonnées du projet
   ===================================================================== */
SET NOCOUNT ON;
GO
USE [TuniShop_DWH];
GO
/* Suppression ordonnée : faits puis dimensions */
DROP TABLE IF EXISTS dw.[fact_ventes];
DROP TABLE IF EXISTS dw.[fact_commandes];
DROP TABLE IF EXISTS dw.[fact_paiements];
DROP TABLE IF EXISTS dw.[fact_livraisons];
DROP TABLE IF EXISTS dw.[fact_remboursements];
DROP TABLE IF EXISTS dw.[fact_avis];
DROP TABLE IF EXISTS dw.[fact_marketing_quotidien];
DROP TABLE IF EXISTS dw.[fact_achats_fournisseur];
DROP TABLE IF EXISTS dw.[fact_mouvements_stock];
DROP TABLE IF EXISTS dw.[fact_stock_mensuel];
DROP TABLE IF EXISTS dw.[dim_date];
DROP TABLE IF EXISTS dw.[dim_client];
DROP TABLE IF EXISTS dw.[dim_produit];
DROP TABLE IF EXISTS dw.[dim_fournisseur];
DROP TABLE IF EXISTS dw.[dim_geographie];
DROP TABLE IF EXISTS dw.[dim_entrepot];
DROP TABLE IF EXISTS dw.[dim_transporteur];
DROP TABLE IF EXISTS dw.[dim_campagne];
DROP TABLE IF EXISTS dw.[dim_coupon];
DROP TABLE IF EXISTS dw.[dim_canal];
DROP TABLE IF EXISTS dw.[dim_mode_paiement];
DROP TABLE IF EXISTS dw.[dim_statut_commande];
DROP TABLE IF EXISTS dw.[dim_motif_retour];
GO
/* dw.dim_date — Dimension : Calendrier jour
   Grain : 1 ligne par jour, du 1er janvier de la plus ancienne date du staging au 31 décembre de l'année suivant la plus récente (plage calculée à chaque chargement)
   Historisation : Statique */
CREATE TABLE dw.[dim_date] (
    [date_sk] INT NOT NULL,
    [date] DATE NOT NULL,
    [annee] SMALLINT NOT NULL,
    [trimestre] TINYINT NOT NULL,
    [libelle_trimestre] CHAR(7) NOT NULL,
    [mois] TINYINT NOT NULL,
    [nom_mois] NVARCHAR(10) NOT NULL,
    [annee_mois] CHAR(7) NOT NULL,
    [semaine_iso] TINYINT NOT NULL,
    [jour_mois] TINYINT NOT NULL,
    [jour_semaine] TINYINT NOT NULL,
    [nom_jour] NVARCHAR(10) NOT NULL,
    [est_weekend] BIT NOT NULL,
    [est_jour_ferie] BIT NOT NULL,
    [nom_jour_ferie] NVARCHAR(50) NULL,
    [est_ramadan] BIT NOT NULL,
    [periode_commerciale] VARCHAR(20) NOT NULL,
    CONSTRAINT [PK_dim_date] PRIMARY KEY CLUSTERED ([date_sk]),
    CONSTRAINT [UQ_dim_date_nk] UNIQUE ([date])
);
GO
/* dw.dim_client — Dimension : Clients maîtres (historisés)
   Grain : 1 ligne par client et version
   Historisation : SCD2 sur segment_fidelite, gouvernorat_id, ville ; SCD1 sur le reste */
CREATE TABLE dw.[dim_client] (
    [client_sk] INT IDENTITY(1,1) NOT NULL,
    [client_id] VARCHAR(12) NOT NULL,
    [type_client] VARCHAR(15) NOT NULL,
    [nom_complet] NVARCHAR(150) NULL,
    [genre] CHAR(1) NULL,
    [tranche_age] VARCHAR(10) NULL,
    [gouvernorat_id] VARCHAR(5) NOT NULL,
    [gouvernorat] NVARCHAR(50) NOT NULL,
    [region] NVARCHAR(50) NOT NULL,
    [ville] NVARCHAR(50) NULL,
    [canal_inscription] VARCHAR(30) NULL,
    [date_inscription] DATE NOT NULL,
    [cohorte_inscription] CHAR(7) NOT NULL,
    [opt_in_email] BIT NOT NULL,
    [opt_in_sms] BIT NOT NULL,
    [segment_fidelite] VARCHAR(10) NOT NULL,
    [hash_scd2] BINARY(32) NOT NULL,
    [date_debut_validite] DATE NOT NULL,
    [date_fin_validite] DATE NOT NULL,
    [est_courant] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_dim_client_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_dim_client_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_dim_client] PRIMARY KEY CLUSTERED ([client_sk])
);
GO
CREATE UNIQUE INDEX [UX_dim_client_courant] ON dw.dim_client (client_id) WHERE est_courant = 1;
CREATE INDEX [IX_dim_client_nk] ON dw.dim_client (client_id, date_debut_validite) INCLUDE (client_sk, date_fin_validite);
GO
/* dw.dim_produit — Dimension : Produits historisés par version de prix
   Grain : 1 ligne par produit et version de prix
   Historisation : SCD2 sur prix/coût (piloté par integ.produit_version_prix) ; SCD1 sur le reste */
CREATE TABLE dw.[dim_produit] (
    [produit_sk] INT IDENTITY(1,1) NOT NULL,
    [produit_id] VARCHAR(10) NOT NULL,
    [prix_id] VARCHAR(10) NULL,
    [sku] VARCHAR(15) NOT NULL,
    [nom_produit] NVARCHAR(100) NOT NULL,
    [marque] NVARCHAR(50) NOT NULL,
    [categorie] NVARCHAR(50) NOT NULL,
    [sous_categorie] NVARCHAR(50) NOT NULL,
    [fournisseur_id] VARCHAR(10) NOT NULL,
    [taux_tva] TINYINT NOT NULL,
    [gamme_prix] VARCHAR(15) NOT NULL,
    [statut_produit] VARCHAR(10) NOT NULL,
    [prix_catalogue_ttc] DECIMAL(14,3) NOT NULL,
    [cout_achat_unitaire_ht] DECIMAL(14,3) NOT NULL,
    [taux_retour_cible] DECIMAL(5,2) NOT NULL,
    [marge_brute_cible] DECIMAL(5,2) NOT NULL,
    [date_debut_validite] DATE NOT NULL,
    [date_fin_validite] DATE NOT NULL,
    [est_courant] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_dim_produit_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_dim_produit_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_dim_produit] PRIMARY KEY CLUSTERED ([produit_sk])
);
GO
CREATE UNIQUE INDEX [UX_dim_produit_version] ON dw.dim_produit (produit_id, date_debut_validite);
CREATE INDEX [IX_dim_produit_nk] ON dw.dim_produit (produit_id) INCLUDE (produit_sk, date_debut_validite, date_fin_validite);
GO
/* dw.dim_fournisseur — Dimension : Fournisseurs
   Grain : 1 ligne par fournisseur
   Historisation : SCD1 */
CREATE TABLE dw.[dim_fournisseur] (
    [fournisseur_sk] INT IDENTITY(1,1) NOT NULL,
    [fournisseur_id] VARCHAR(10) NOT NULL,
    [nom_fournisseur] NVARCHAR(100) NOT NULL,
    [pays] NVARCHAR(50) NOT NULL,
    [est_local] BIT NOT NULL,
    [delai_appro_moyen_j] SMALLINT NOT NULL,
    [conditions_paiement] NVARCHAR(100) NOT NULL,
    [fiabilite_livraison] DECIMAL(5,2) NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_dim_fournisseur_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_dim_fournisseur_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_dim_fournisseur] PRIMARY KEY CLUSTERED ([fournisseur_sk]),
    CONSTRAINT [UQ_dim_fournisseur_nk] UNIQUE ([fournisseur_id])
);
GO
/* dw.dim_geographie — Dimension : Gouvernorats
   Grain : 1 ligne par gouvernorat
   Historisation : SCD1 */
CREATE TABLE dw.[dim_geographie] (
    [geographie_sk] INT IDENTITY(1,1) NOT NULL,
    [gouvernorat_id] VARCHAR(5) NOT NULL,
    [gouvernorat] NVARCHAR(50) NOT NULL,
    [region] NVARCHAR(50) NOT NULL,
    [zone_livraison] VARCHAR(5) NOT NULL,
    [entrepot_rattachement] NVARCHAR(50) NOT NULL,
    [pays] NVARCHAR(20) NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_dim_geographie_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_dim_geographie_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_dim_geographie] PRIMARY KEY CLUSTERED ([geographie_sk]),
    CONSTRAINT [UQ_dim_geographie_nk] UNIQUE ([gouvernorat_id])
);
GO
/* dw.dim_entrepot — Dimension : Entrepôts
   Grain : 1 ligne par entrepôt
   Historisation : SCD1 */
CREATE TABLE dw.[dim_entrepot] (
    [entrepot_sk] INT IDENTITY(1,1) NOT NULL,
    [entrepot_id] VARCHAR(5) NOT NULL,
    [nom_entrepot] NVARCHAR(50) NOT NULL,
    [ville] NVARCHAR(50) NOT NULL,
    [region] NVARCHAR(50) NOT NULL,
    [surface_m2] SMALLINT NOT NULL,
    [date_ouverture] DATE NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_dim_entrepot_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_dim_entrepot_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_dim_entrepot] PRIMARY KEY CLUSTERED ([entrepot_sk]),
    CONSTRAINT [UQ_dim_entrepot_nk] UNIQUE ([entrepot_id])
);
GO
/* dw.dim_transporteur — Dimension : Transporteurs
   Grain : 1 ligne par transporteur
   Historisation : SCD1 */
CREATE TABLE dw.[dim_transporteur] (
    [transporteur_sk] INT IDENTITY(1,1) NOT NULL,
    [transporteur_id] VARCHAR(5) NOT NULL,
    [nom_transporteur] NVARCHAR(50) NOT NULL,
    [couverture] NVARCHAR(50) NOT NULL,
    [cout_base_ht] DECIMAL(14,3) NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_dim_transporteur_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_dim_transporteur_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_dim_transporteur] PRIMARY KEY CLUSTERED ([transporteur_sk]),
    CONSTRAINT [UQ_dim_transporteur_nk] UNIQUE ([transporteur_id])
);
GO
/* dw.dim_campagne — Dimension : Campagnes marketing
   Grain : 1 ligne par campagne
   Historisation : SCD1 */
CREATE TABLE dw.[dim_campagne] (
    [campagne_sk] INT IDENTITY(1,1) NOT NULL,
    [campagne_id] VARCHAR(10) NOT NULL,
    [nom_campagne] NVARCHAR(100) NOT NULL,
    [canal_media] VARCHAR(15) NOT NULL,
    [type_canal] VARCHAR(15) NOT NULL,
    [objectif] VARCHAR(15) NOT NULL,
    [theme] VARCHAR(15) NOT NULL,
    [date_debut] DATE NOT NULL,
    [date_fin] DATE NOT NULL,
    [budget_ht] DECIMAL(14,3) NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_dim_campagne_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_dim_campagne_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_dim_campagne] PRIMARY KEY CLUSTERED ([campagne_sk]),
    CONSTRAINT [UQ_dim_campagne_nk] UNIQUE ([campagne_id])
);
GO
/* dw.dim_coupon — Dimension : Coupons
   Grain : 1 ligne par code
   Historisation : SCD1 */
CREATE TABLE dw.[dim_coupon] (
    [coupon_sk] INT IDENTITY(1,1) NOT NULL,
    [code_coupon] VARCHAR(15) NOT NULL,
    [type_remise] VARCHAR(15) NOT NULL,
    [valeur] DECIMAL(10,2) NOT NULL,
    [montant_min_ttc] DECIMAL(14,3) NOT NULL,
    [reserve_premiere_commande] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_dim_coupon_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_dim_coupon_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_dim_coupon] PRIMARY KEY CLUSTERED ([coupon_sk]),
    CONSTRAINT [UQ_dim_coupon_nk] UNIQUE ([code_coupon])
);
GO
/* dw.dim_canal — Dimension : Canal de vente × appareil (dimension junk)
   Grain : 1 ligne par combinaison
   Historisation : Statique */
CREATE TABLE dw.[dim_canal] (
    [canal_sk] INT IDENTITY(1,1) NOT NULL,
    [canal] VARCHAR(20) NOT NULL,
    [appareil] VARCHAR(10) NOT NULL,
    [libelle_canal] NVARCHAR(40) NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_dim_canal_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_dim_canal_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_dim_canal] PRIMARY KEY CLUSTERED ([canal_sk]),
    CONSTRAINT [UQ_dim_canal_nk] UNIQUE ([canal], [appareil])
);
GO
/* dw.dim_mode_paiement — Dimension : Modes de paiement
   Grain : 1 ligne par mode
   Historisation : Statique */
CREATE TABLE dw.[dim_mode_paiement] (
    [mode_paiement_sk] INT IDENTITY(1,1) NOT NULL,
    [mode_paiement] VARCHAR(30) NOT NULL,
    [libelle_mode_paiement] NVARCHAR(40) NOT NULL,
    [est_paiement_differe] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_dim_mode_paiement_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_dim_mode_paiement_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_dim_mode_paiement] PRIMARY KEY CLUSTERED ([mode_paiement_sk]),
    CONSTRAINT [UQ_dim_mode_paiement_nk] UNIQUE ([mode_paiement])
);
GO
/* dw.dim_statut_commande — Dimension : Statuts de commande
   Grain : 1 ligne par statut
   Historisation : Statique */
CREATE TABLE dw.[dim_statut_commande] (
    [statut_commande_sk] INT IDENTITY(1,1) NOT NULL,
    [statut_commande] VARCHAR(30) NOT NULL,
    [libelle_statut] NVARCHAR(40) NOT NULL,
    [famille_statut] VARCHAR(15) NOT NULL,
    [est_ca_reconnu] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_dim_statut_commande_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_dim_statut_commande_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_dim_statut_commande] PRIMARY KEY CLUSTERED ([statut_commande_sk]),
    CONSTRAINT [UQ_dim_statut_commande_nk] UNIQUE ([statut_commande])
);
GO
/* dw.dim_motif_retour — Dimension : Type et motif de remboursement
   Grain : 1 ligne par type × motif
   Historisation : Statique */
CREATE TABLE dw.[dim_motif_retour] (
    [motif_retour_sk] INT IDENTITY(1,1) NOT NULL,
    [type_remboursement] VARCHAR(20) NOT NULL,
    [motif] VARCHAR(50) NOT NULL,
    [libelle_motif] NVARCHAR(60) NOT NULL,
    [responsabilite] VARCHAR(15) NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_dim_motif_retour_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_dim_motif_retour_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_dim_motif_retour] PRIMARY KEY CLUSTERED ([motif_retour_sk]),
    CONSTRAINT [UQ_dim_motif_retour_nk] UNIQUE ([type_remboursement], [motif])
);
GO
/* dw.fact_ventes — Fait transactionnel : Ventes au détail
   Grain : 1 ligne par ligne de commande */
CREATE TABLE dw.[fact_ventes] (
    [ligne_id] VARCHAR(12) NOT NULL,
    [commande_id] VARCHAR(10) NOT NULL,
    [date_commande_sk] INT NOT NULL,
    [client_sk] INT NOT NULL,
    [produit_sk] INT NOT NULL,
    [geographie_sk] INT NOT NULL,
    [entrepot_sk] INT NOT NULL,
    [canal_sk] INT NOT NULL,
    [campagne_sk] INT NOT NULL,
    [coupon_sk] INT NOT NULL,
    [statut_commande_sk] INT NOT NULL,
    [quantite] INT NOT NULL,
    [prix_catalogue_ttc] DECIMAL(14,3) NOT NULL,
    [prix_unitaire_ttc] DECIMAL(14,3) NOT NULL,
    [montant_brut_ttc] DECIMAL(14,3) NOT NULL,
    [montant_remise_promo_ttc] DECIMAL(14,3) NOT NULL,
    [montant_ttc] DECIMAL(14,3) NOT NULL,
    [montant_ht] DECIMAL(14,3) NOT NULL,
    [montant_tva] DECIMAL(14,3) NOT NULL,
    [cout_achat_ht] DECIMAL(14,3) NOT NULL,
    [marge_brute_ht] DECIMAL(14,3) NOT NULL,
    [est_ca_reconnu] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_fact_ventes_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_fact_ventes_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_fact_ventes] PRIMARY KEY NONCLUSTERED ([ligne_id])
);
GO
/* dw.fact_commandes — Fait snapshot accumulé : Cycle de vie de la commande
   Grain : 1 ligne par commande */
CREATE TABLE dw.[fact_commandes] (
    [commande_id] VARCHAR(10) NOT NULL,
    [date_commande_sk] INT NOT NULL,
    [date_expedition_sk] INT NOT NULL,
    [date_livraison_sk] INT NOT NULL,
    [date_annulation_sk] INT NOT NULL,
    [client_sk] INT NOT NULL,
    [geographie_sk] INT NOT NULL,
    [entrepot_sk] INT NOT NULL,
    [canal_sk] INT NOT NULL,
    [campagne_sk] INT NOT NULL,
    [coupon_sk] INT NOT NULL,
    [mode_paiement_sk] INT NOT NULL,
    [statut_commande_sk] INT NOT NULL,
    [nb_lignes] TINYINT NOT NULL,
    [nb_articles] INT NOT NULL,
    [sous_total_ttc] DECIMAL(14,3) NOT NULL,
    [remise_coupon_ttc] DECIMAL(14,3) NOT NULL,
    [frais_livraison_ttc] DECIMAL(14,3) NOT NULL,
    [montant_total_ttc] DECIMAL(14,3) NOT NULL,
    [cout_achat_ht] DECIMAL(14,3) NOT NULL,
    [cout_transport_ht] DECIMAL(14,3) NULL,
    [montant_rembourse_ttc] DECIMAL(14,3) NOT NULL,
    [nb_tentatives_paiement] TINYINT NOT NULL,
    [delai_livraison_j] DECIMAL(8,2) NULL,
    [est_premiere_commande] BIT NOT NULL,
    [est_livree_a_temps] BIT NULL,
    [est_ca_reconnu] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_fact_commandes_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_fact_commandes_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_fact_commandes] PRIMARY KEY NONCLUSTERED ([commande_id])
);
GO
/* dw.fact_paiements — Fait transactionnel : Tentatives de paiement
   Grain : 1 ligne par tentative */
CREATE TABLE dw.[fact_paiements] (
    [paiement_id] VARCHAR(12) NOT NULL,
    [commande_id] VARCHAR(10) NOT NULL,
    [date_paiement_sk] INT NOT NULL,
    [date_reversement_sk] INT NOT NULL,
    [client_sk] INT NOT NULL,
    [mode_paiement_sk] INT NOT NULL,
    [num_tentative] TINYINT NOT NULL,
    [statut_paiement] VARCHAR(20) NOT NULL,
    [code_erreur] VARCHAR(40) NULL,
    [prestataire] NVARCHAR(50) NOT NULL,
    [montant_ttc] DECIMAL(14,3) NOT NULL,
    [est_reussi] BIT NOT NULL,
    [delai_reversement_j] SMALLINT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_fact_paiements_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_fact_paiements_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_fact_paiements] PRIMARY KEY NONCLUSTERED ([paiement_id])
);
GO
/* dw.fact_livraisons — Fait transactionnel : Expéditions
   Grain : 1 ligne par expédition */
CREATE TABLE dw.[fact_livraisons] (
    [livraison_id] VARCHAR(10) NOT NULL,
    [commande_id] VARCHAR(10) NOT NULL,
    [date_expedition_sk] INT NOT NULL,
    [date_prevue_sk] INT NOT NULL,
    [date_livraison_sk] INT NOT NULL,
    [client_sk] INT NOT NULL,
    [entrepot_sk] INT NOT NULL,
    [transporteur_sk] INT NOT NULL,
    [geographie_sk] INT NOT NULL,
    [statut_livraison] VARCHAR(30) NOT NULL,
    [nb_tentatives] TINYINT NULL,
    [poids_kg] DECIMAL(8,2) NOT NULL,
    [cout_transport_ht] DECIMAL(14,3) NOT NULL,
    [delai_preparation_h] DECIMAL(8,2) NULL,
    [delai_livraison_j] DECIMAL(8,2) NULL,
    [retard_j] SMALLINT NULL,
    [est_livree] BIT NOT NULL,
    [est_livree_a_temps] BIT NULL,
    [est_premiere_tentative] BIT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_fact_livraisons_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_fact_livraisons_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_fact_livraisons] PRIMARY KEY NONCLUSTERED ([livraison_id])
);
GO
/* dw.fact_remboursements — Fait transactionnel : Retours et remboursements
   Grain : 1 ligne par remboursement */
CREATE TABLE dw.[fact_remboursements] (
    [remboursement_id] VARCHAR(10) NOT NULL,
    [commande_id] VARCHAR(10) NOT NULL,
    [date_demande_sk] INT NOT NULL,
    [date_remboursement_sk] INT NOT NULL,
    [client_sk] INT NOT NULL,
    [produit_sk] INT NOT NULL,
    [motif_retour_sk] INT NOT NULL,
    [mode_remboursement] VARCHAR(30) NOT NULL,
    [statut] VARCHAR(15) NOT NULL,
    [etat_article] VARCHAR(20) NULL,
    [quantite] INT NULL,
    [montant_demande_ttc] DECIMAL(14,3) NOT NULL,
    [montant_rembourse_ttc] DECIMAL(14,3) NOT NULL,
    [delai_traitement_j] DECIMAL(8,2) NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_fact_remboursements_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_fact_remboursements_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_fact_remboursements] PRIMARY KEY NONCLUSTERED ([remboursement_id])
);
GO
/* dw.fact_avis — Fait transactionnel : Avis clients
   Grain : 1 ligne par avis */
CREATE TABLE dw.[fact_avis] (
    [avis_id] VARCHAR(10) NOT NULL,
    [commande_id] VARCHAR(10) NOT NULL,
    [date_avis_sk] INT NOT NULL,
    [client_sk] INT NOT NULL,
    [produit_sk] INT NOT NULL,
    [note] TINYINT NULL,
    [sentiment] VARCHAR(10) NULL,
    [a_commentaire] BIT NOT NULL,
    [commentaire] NVARCHAR(500) NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_fact_avis_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_fact_avis_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_fact_avis] PRIMARY KEY NONCLUSTERED ([avis_id])
);
GO
/* dw.fact_marketing_quotidien — Fait snapshot périodique : Performance média quotidienne
   Grain : 1 ligne par campagne et jour */
CREATE TABLE dw.[fact_marketing_quotidien] (
    [depense_id] VARCHAR(10) NOT NULL,
    [date_sk] INT NOT NULL,
    [campagne_sk] INT NOT NULL,
    [depense_ht] DECIMAL(14,3) NOT NULL,
    [impressions] INT NULL,
    [clics] INT NOT NULL,
    [commandes_attribuees] INT NOT NULL,
    [nouveaux_clients_attribues] INT NOT NULL,
    [ca_attribue_ttc] DECIMAL(14,3) NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_fact_marketing_quotidien_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_fact_marketing_quotidien_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_fact_marketing_quotidien] PRIMARY KEY NONCLUSTERED ([depense_id])
);
GO
/* dw.fact_achats_fournisseur — Fait transactionnel : Approvisionnements
   Grain : 1 ligne par ligne de commande fournisseur */
CREATE TABLE dw.[fact_achats_fournisseur] (
    [ligne_cf_id] VARCHAR(12) NOT NULL,
    [commande_fournisseur_id] VARCHAR(10) NOT NULL,
    [date_commande_sk] INT NOT NULL,
    [date_prevue_sk] INT NOT NULL,
    [date_reception_sk] INT NOT NULL,
    [fournisseur_sk] INT NOT NULL,
    [produit_sk] INT NOT NULL,
    [entrepot_sk] INT NOT NULL,
    [statut] VARCHAR(30) NOT NULL,
    [quantite_commandee] INT NOT NULL,
    [quantite_recue] INT NULL,
    [cout_unitaire_ht] DECIMAL(14,3) NOT NULL,
    [montant_ht] DECIMAL(14,3) NOT NULL,
    [delai_appro_reel_j] SMALLINT NULL,
    [retard_appro_j] SMALLINT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_fact_achats_fournisseur_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_fact_achats_fournisseur_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_fact_achats_fournisseur] PRIMARY KEY NONCLUSTERED ([ligne_cf_id])
);
GO
/* dw.fact_mouvements_stock — Fait transactionnel : Mouvements de stock
   Grain : 1 ligne par mouvement */
CREATE TABLE dw.[fact_mouvements_stock] (
    [mouvement_id] VARCHAR(12) NOT NULL,
    [date_sk] INT NOT NULL,
    [produit_sk] INT NOT NULL,
    [entrepot_sk] INT NOT NULL,
    [type_mouvement] VARCHAR(30) NOT NULL,
    [sens] CHAR(1) NOT NULL,
    [reference_id] VARCHAR(20) NULL,
    [quantite] INT NOT NULL,
    [valeur_ht] DECIMAL(16,3) NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_fact_mouvements_stock_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_fact_mouvements_stock_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_fact_mouvements_stock] PRIMARY KEY NONCLUSTERED ([mouvement_id])
);
GO
/* dw.fact_stock_mensuel — Fait snapshot périodique : Stock de fin de mois
   Grain : 1 ligne par produit, entrepôt et mois */
CREATE TABLE dw.[fact_stock_mensuel] (
    [date_sk] INT NOT NULL,
    [produit_sk] INT NOT NULL,
    [entrepot_sk] INT NOT NULL,
    [inventaire_id] VARCHAR(12) NOT NULL,
    [stock_fin_mois] INT NOT NULL,
    [quantite_en_commande] INT NOT NULL,
    [valeur_stock_ht] DECIMAL(16,3) NOT NULL,
    [est_rupture] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_maj] DATETIME2(0) NOT NULL CONSTRAINT [DF_fact_stock_mensuel_date_maj] DEFAULT (SYSDATETIME()),
    [est_supprime] BIT NOT NULL CONSTRAINT [DF_fact_stock_mensuel_est_supprime] DEFAULT (0),
    CONSTRAINT [PK_fact_stock_mensuel] PRIMARY KEY NONCLUSTERED ([date_sk], [produit_sk], [entrepot_sk]),
    CONSTRAINT [UQ_fact_stock_mensuel_inventaire] UNIQUE ([inventaire_id])
);
GO
/* ---------------------------------------------------------------------
   Membres spéciaux : -1 = Inconnu (clé introuvable), -2 = Non applicable (valeur absente attendue)
   --------------------------------------------------------------------- */
INSERT INTO dw.[dim_date] ([date_sk], [date], [annee], [trimestre], [libelle_trimestre], [mois], [nom_mois], [annee_mois], [semaine_iso], [jour_mois], [jour_semaine], [nom_jour], [est_weekend], [est_jour_ferie], [nom_jour_ferie], [est_ramadan], [periode_commerciale])
VALUES (-1, '1900-01-01', 1900, 1, 'N/D-T0', 1, N'Inconnu', 'N/D', 1, 1, 1, N'Inconnu', 0, 0, N'Inconnu', 0, 'Inconnu'),
       (-2, '1900-01-02', 1900, 1, 'N/A-T0', 1, N'N/A', 'N/A', 1, 2, 1, N'N/A', 0, 0, N'Non applicable', 0, 'Non applicable');
GO
SET IDENTITY_INSERT dw.[dim_client] ON;
INSERT INTO dw.[dim_client] ([client_sk], [client_id], [type_client], [nom_complet], [genre], [tranche_age], [gouvernorat_id], [gouvernorat], [region], [ville], [canal_inscription], [date_inscription], [cohorte_inscription], [opt_in_email], [opt_in_sms], [segment_fidelite], [hash_scd2], [date_debut_validite], [date_fin_validite], [est_courant], [id_chargement], [date_maj], [est_supprime])
VALUES (-1, '-1', 'Inconnu', N'Inconnu', 'N', 'Inconnu', 'N/D', N'Inconnu', N'Inconnu', N'Inconnu', 'Inconnu', '1900-01-01', 'Inconnu', 0, 0, 'Inconnu', 0x00, '1900-01-01', '9999-12-31', 1, 0, SYSDATETIME(), 0),
       (-2, '-2', 'Non applicable', N'Non applicable', 'N', 'N/A', 'N/A', N'Non applicable', N'Non applicable', N'Non applicable', 'Non applicable', '1900-01-01', 'N/A', 0, 0, 'N/A', 0x00, '1900-01-01', '9999-12-31', 1, 0, SYSDATETIME(), 0);
SET IDENTITY_INSERT dw.[dim_client] OFF;
GO
SET IDENTITY_INSERT dw.[dim_produit] ON;
INSERT INTO dw.[dim_produit] ([produit_sk], [produit_id], [prix_id], [sku], [nom_produit], [marque], [categorie], [sous_categorie], [fournisseur_id], [taux_tva], [gamme_prix], [statut_produit], [prix_catalogue_ttc], [cout_achat_unitaire_ht], [taux_retour_cible], [marge_brute_cible], [date_debut_validite], [date_fin_validite], [est_courant], [id_chargement], [date_maj], [est_supprime])
VALUES (-1, '-1', 'Inconnu', 'Inconnu', N'Inconnu', N'Inconnu', N'Inconnu', N'Inconnu', 'Inconnu', 0, 'Inconnu', 'Inconnu', 0, 0, 0, 0, '1900-01-01', '9999-12-31', 1, 0, SYSDATETIME(), 0),
       (-2, '-2', 'N/A', 'Non applicable', N'Non applicable', N'Non applicable', N'Non applicable', N'Non applicable', 'N/A', 0, 'Non applicable', 'N/A', 0, 0, 0, 0, '1900-01-01', '9999-12-31', 1, 0, SYSDATETIME(), 0);
SET IDENTITY_INSERT dw.[dim_produit] OFF;
GO
SET IDENTITY_INSERT dw.[dim_fournisseur] ON;
INSERT INTO dw.[dim_fournisseur] ([fournisseur_sk], [fournisseur_id], [nom_fournisseur], [pays], [est_local], [delai_appro_moyen_j], [conditions_paiement], [fiabilite_livraison], [id_chargement], [date_maj], [est_supprime])
VALUES (-1, '-1', N'Inconnu', N'Inconnu', 0, 0, N'Inconnu', 0, 0, SYSDATETIME(), 0),
       (-2, '-2', N'Non applicable', N'Non applicable', 0, 0, N'Non applicable', 0, 0, SYSDATETIME(), 0);
SET IDENTITY_INSERT dw.[dim_fournisseur] OFF;
GO
SET IDENTITY_INSERT dw.[dim_geographie] ON;
INSERT INTO dw.[dim_geographie] ([geographie_sk], [gouvernorat_id], [gouvernorat], [region], [zone_livraison], [entrepot_rattachement], [pays], [id_chargement], [date_maj], [est_supprime])
VALUES (-1, '-1', N'Inconnu', N'Inconnu', 'N/D', N'Inconnu', N'Inconnu', 0, SYSDATETIME(), 0),
       (-2, '-2', N'Non applicable', N'Non applicable', 'N/A', N'Non applicable', N'Non applicable', 0, SYSDATETIME(), 0);
SET IDENTITY_INSERT dw.[dim_geographie] OFF;
GO
SET IDENTITY_INSERT dw.[dim_entrepot] ON;
INSERT INTO dw.[dim_entrepot] ([entrepot_sk], [entrepot_id], [nom_entrepot], [ville], [region], [surface_m2], [date_ouverture], [id_chargement], [date_maj], [est_supprime])
VALUES (-1, '-1', N'Inconnu', N'Inconnu', N'Inconnu', 0, '1900-01-01', 0, SYSDATETIME(), 0),
       (-2, '-2', N'Non applicable', N'Non applicable', N'Non applicable', 0, '1900-01-01', 0, SYSDATETIME(), 0);
SET IDENTITY_INSERT dw.[dim_entrepot] OFF;
GO
SET IDENTITY_INSERT dw.[dim_transporteur] ON;
INSERT INTO dw.[dim_transporteur] ([transporteur_sk], [transporteur_id], [nom_transporteur], [couverture], [cout_base_ht], [id_chargement], [date_maj], [est_supprime])
VALUES (-1, '-1', N'Inconnu', N'Inconnu', 0, 0, SYSDATETIME(), 0),
       (-2, '-2', N'Non applicable', N'Non applicable', 0, 0, SYSDATETIME(), 0);
SET IDENTITY_INSERT dw.[dim_transporteur] OFF;
GO
SET IDENTITY_INSERT dw.[dim_campagne] ON;
INSERT INTO dw.[dim_campagne] ([campagne_sk], [campagne_id], [nom_campagne], [canal_media], [type_canal], [objectif], [theme], [date_debut], [date_fin], [budget_ht], [id_chargement], [date_maj], [est_supprime])
VALUES (-1, '-1', N'Inconnu', 'Inconnu', 'Inconnu', 'Inconnu', 'Inconnu', '1900-01-01', '1900-01-01', 0, 0, SYSDATETIME(), 0),
       (-2, '-2', N'Non applicable', 'Non applicable', 'Non applicable', 'Non applicable', 'Non applicable', '1900-01-01', '1900-01-01', 0, 0, SYSDATETIME(), 0);
SET IDENTITY_INSERT dw.[dim_campagne] OFF;
GO
SET IDENTITY_INSERT dw.[dim_coupon] ON;
INSERT INTO dw.[dim_coupon] ([coupon_sk], [code_coupon], [type_remise], [valeur], [montant_min_ttc], [reserve_premiere_commande], [id_chargement], [date_maj], [est_supprime])
VALUES (-1, '-1', 'Inconnu', 0, 0, 0, 0, SYSDATETIME(), 0),
       (-2, '-2', 'Non applicable', 0, 0, 0, 0, SYSDATETIME(), 0);
SET IDENTITY_INSERT dw.[dim_coupon] OFF;
GO
SET IDENTITY_INSERT dw.[dim_canal] ON;
INSERT INTO dw.[dim_canal] ([canal_sk], [canal], [appareil], [libelle_canal], [id_chargement], [date_maj], [est_supprime])
VALUES (-1, '-1', '-1', N'Inconnu', 0, SYSDATETIME(), 0),
       (-2, '-2', '-2', N'Non applicable', 0, SYSDATETIME(), 0);
SET IDENTITY_INSERT dw.[dim_canal] OFF;
GO
SET IDENTITY_INSERT dw.[dim_mode_paiement] ON;
INSERT INTO dw.[dim_mode_paiement] ([mode_paiement_sk], [mode_paiement], [libelle_mode_paiement], [est_paiement_differe], [id_chargement], [date_maj], [est_supprime])
VALUES (-1, '-1', N'Inconnu', 0, 0, SYSDATETIME(), 0),
       (-2, '-2', N'Non applicable', 0, 0, SYSDATETIME(), 0);
SET IDENTITY_INSERT dw.[dim_mode_paiement] OFF;
GO
SET IDENTITY_INSERT dw.[dim_statut_commande] ON;
INSERT INTO dw.[dim_statut_commande] ([statut_commande_sk], [statut_commande], [libelle_statut], [famille_statut], [est_ca_reconnu], [id_chargement], [date_maj], [est_supprime])
VALUES (-1, '-1', N'Inconnu', 'Inconnu', 0, 0, SYSDATETIME(), 0),
       (-2, '-2', N'Non applicable', 'Non applicable', 0, 0, SYSDATETIME(), 0);
SET IDENTITY_INSERT dw.[dim_statut_commande] OFF;
GO
SET IDENTITY_INSERT dw.[dim_motif_retour] ON;
INSERT INTO dw.[dim_motif_retour] ([motif_retour_sk], [type_remboursement], [motif], [libelle_motif], [responsabilite], [id_chargement], [date_maj], [est_supprime])
VALUES (-1, '-1', '-1', N'Inconnu', 'Inconnu', 0, SYSDATETIME(), 0),
       (-2, '-2', '-2', N'Non applicable', 'Non applicable', 0, SYSDATETIME(), 0);
SET IDENTITY_INSERT dw.[dim_motif_retour] OFF;
GO
/* Clés étrangères faits → dimensions */
ALTER TABLE dw.[fact_ventes] WITH CHECK ADD CONSTRAINT [FK_fact_ventes_date_commande_sk] FOREIGN KEY ([date_commande_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_ventes] WITH CHECK ADD CONSTRAINT [FK_fact_ventes_client_sk] FOREIGN KEY ([client_sk]) REFERENCES dw.[dim_client] ([client_sk]);
ALTER TABLE dw.[fact_ventes] WITH CHECK ADD CONSTRAINT [FK_fact_ventes_produit_sk] FOREIGN KEY ([produit_sk]) REFERENCES dw.[dim_produit] ([produit_sk]);
ALTER TABLE dw.[fact_ventes] WITH CHECK ADD CONSTRAINT [FK_fact_ventes_geographie_sk] FOREIGN KEY ([geographie_sk]) REFERENCES dw.[dim_geographie] ([geographie_sk]);
ALTER TABLE dw.[fact_ventes] WITH CHECK ADD CONSTRAINT [FK_fact_ventes_entrepot_sk] FOREIGN KEY ([entrepot_sk]) REFERENCES dw.[dim_entrepot] ([entrepot_sk]);
ALTER TABLE dw.[fact_ventes] WITH CHECK ADD CONSTRAINT [FK_fact_ventes_canal_sk] FOREIGN KEY ([canal_sk]) REFERENCES dw.[dim_canal] ([canal_sk]);
ALTER TABLE dw.[fact_ventes] WITH CHECK ADD CONSTRAINT [FK_fact_ventes_campagne_sk] FOREIGN KEY ([campagne_sk]) REFERENCES dw.[dim_campagne] ([campagne_sk]);
ALTER TABLE dw.[fact_ventes] WITH CHECK ADD CONSTRAINT [FK_fact_ventes_coupon_sk] FOREIGN KEY ([coupon_sk]) REFERENCES dw.[dim_coupon] ([coupon_sk]);
ALTER TABLE dw.[fact_ventes] WITH CHECK ADD CONSTRAINT [FK_fact_ventes_statut_commande_sk] FOREIGN KEY ([statut_commande_sk]) REFERENCES dw.[dim_statut_commande] ([statut_commande_sk]);
ALTER TABLE dw.[fact_commandes] WITH CHECK ADD CONSTRAINT [FK_fact_commandes_date_commande_sk] FOREIGN KEY ([date_commande_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_commandes] WITH CHECK ADD CONSTRAINT [FK_fact_commandes_date_expedition_sk] FOREIGN KEY ([date_expedition_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_commandes] WITH CHECK ADD CONSTRAINT [FK_fact_commandes_date_livraison_sk] FOREIGN KEY ([date_livraison_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_commandes] WITH CHECK ADD CONSTRAINT [FK_fact_commandes_date_annulation_sk] FOREIGN KEY ([date_annulation_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_commandes] WITH CHECK ADD CONSTRAINT [FK_fact_commandes_client_sk] FOREIGN KEY ([client_sk]) REFERENCES dw.[dim_client] ([client_sk]);
ALTER TABLE dw.[fact_commandes] WITH CHECK ADD CONSTRAINT [FK_fact_commandes_geographie_sk] FOREIGN KEY ([geographie_sk]) REFERENCES dw.[dim_geographie] ([geographie_sk]);
ALTER TABLE dw.[fact_commandes] WITH CHECK ADD CONSTRAINT [FK_fact_commandes_entrepot_sk] FOREIGN KEY ([entrepot_sk]) REFERENCES dw.[dim_entrepot] ([entrepot_sk]);
ALTER TABLE dw.[fact_commandes] WITH CHECK ADD CONSTRAINT [FK_fact_commandes_canal_sk] FOREIGN KEY ([canal_sk]) REFERENCES dw.[dim_canal] ([canal_sk]);
ALTER TABLE dw.[fact_commandes] WITH CHECK ADD CONSTRAINT [FK_fact_commandes_campagne_sk] FOREIGN KEY ([campagne_sk]) REFERENCES dw.[dim_campagne] ([campagne_sk]);
ALTER TABLE dw.[fact_commandes] WITH CHECK ADD CONSTRAINT [FK_fact_commandes_coupon_sk] FOREIGN KEY ([coupon_sk]) REFERENCES dw.[dim_coupon] ([coupon_sk]);
ALTER TABLE dw.[fact_commandes] WITH CHECK ADD CONSTRAINT [FK_fact_commandes_mode_paiement_sk] FOREIGN KEY ([mode_paiement_sk]) REFERENCES dw.[dim_mode_paiement] ([mode_paiement_sk]);
ALTER TABLE dw.[fact_commandes] WITH CHECK ADD CONSTRAINT [FK_fact_commandes_statut_commande_sk] FOREIGN KEY ([statut_commande_sk]) REFERENCES dw.[dim_statut_commande] ([statut_commande_sk]);
ALTER TABLE dw.[fact_paiements] WITH CHECK ADD CONSTRAINT [FK_fact_paiements_date_paiement_sk] FOREIGN KEY ([date_paiement_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_paiements] WITH CHECK ADD CONSTRAINT [FK_fact_paiements_date_reversement_sk] FOREIGN KEY ([date_reversement_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_paiements] WITH CHECK ADD CONSTRAINT [FK_fact_paiements_client_sk] FOREIGN KEY ([client_sk]) REFERENCES dw.[dim_client] ([client_sk]);
ALTER TABLE dw.[fact_paiements] WITH CHECK ADD CONSTRAINT [FK_fact_paiements_mode_paiement_sk] FOREIGN KEY ([mode_paiement_sk]) REFERENCES dw.[dim_mode_paiement] ([mode_paiement_sk]);
ALTER TABLE dw.[fact_livraisons] WITH CHECK ADD CONSTRAINT [FK_fact_livraisons_date_expedition_sk] FOREIGN KEY ([date_expedition_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_livraisons] WITH CHECK ADD CONSTRAINT [FK_fact_livraisons_date_prevue_sk] FOREIGN KEY ([date_prevue_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_livraisons] WITH CHECK ADD CONSTRAINT [FK_fact_livraisons_date_livraison_sk] FOREIGN KEY ([date_livraison_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_livraisons] WITH CHECK ADD CONSTRAINT [FK_fact_livraisons_client_sk] FOREIGN KEY ([client_sk]) REFERENCES dw.[dim_client] ([client_sk]);
ALTER TABLE dw.[fact_livraisons] WITH CHECK ADD CONSTRAINT [FK_fact_livraisons_entrepot_sk] FOREIGN KEY ([entrepot_sk]) REFERENCES dw.[dim_entrepot] ([entrepot_sk]);
ALTER TABLE dw.[fact_livraisons] WITH CHECK ADD CONSTRAINT [FK_fact_livraisons_transporteur_sk] FOREIGN KEY ([transporteur_sk]) REFERENCES dw.[dim_transporteur] ([transporteur_sk]);
ALTER TABLE dw.[fact_livraisons] WITH CHECK ADD CONSTRAINT [FK_fact_livraisons_geographie_sk] FOREIGN KEY ([geographie_sk]) REFERENCES dw.[dim_geographie] ([geographie_sk]);
ALTER TABLE dw.[fact_remboursements] WITH CHECK ADD CONSTRAINT [FK_fact_remboursements_date_demande_sk] FOREIGN KEY ([date_demande_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_remboursements] WITH CHECK ADD CONSTRAINT [FK_fact_remboursements_date_remboursement_sk] FOREIGN KEY ([date_remboursement_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_remboursements] WITH CHECK ADD CONSTRAINT [FK_fact_remboursements_client_sk] FOREIGN KEY ([client_sk]) REFERENCES dw.[dim_client] ([client_sk]);
ALTER TABLE dw.[fact_remboursements] WITH CHECK ADD CONSTRAINT [FK_fact_remboursements_produit_sk] FOREIGN KEY ([produit_sk]) REFERENCES dw.[dim_produit] ([produit_sk]);
ALTER TABLE dw.[fact_remboursements] WITH CHECK ADD CONSTRAINT [FK_fact_remboursements_motif_retour_sk] FOREIGN KEY ([motif_retour_sk]) REFERENCES dw.[dim_motif_retour] ([motif_retour_sk]);
ALTER TABLE dw.[fact_avis] WITH CHECK ADD CONSTRAINT [FK_fact_avis_date_avis_sk] FOREIGN KEY ([date_avis_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_avis] WITH CHECK ADD CONSTRAINT [FK_fact_avis_client_sk] FOREIGN KEY ([client_sk]) REFERENCES dw.[dim_client] ([client_sk]);
ALTER TABLE dw.[fact_avis] WITH CHECK ADD CONSTRAINT [FK_fact_avis_produit_sk] FOREIGN KEY ([produit_sk]) REFERENCES dw.[dim_produit] ([produit_sk]);
ALTER TABLE dw.[fact_marketing_quotidien] WITH CHECK ADD CONSTRAINT [FK_fact_marketing_quotidien_date_sk] FOREIGN KEY ([date_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_marketing_quotidien] WITH CHECK ADD CONSTRAINT [FK_fact_marketing_quotidien_campagne_sk] FOREIGN KEY ([campagne_sk]) REFERENCES dw.[dim_campagne] ([campagne_sk]);
ALTER TABLE dw.[fact_achats_fournisseur] WITH CHECK ADD CONSTRAINT [FK_fact_achats_fournisseur_date_commande_sk] FOREIGN KEY ([date_commande_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_achats_fournisseur] WITH CHECK ADD CONSTRAINT [FK_fact_achats_fournisseur_date_prevue_sk] FOREIGN KEY ([date_prevue_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_achats_fournisseur] WITH CHECK ADD CONSTRAINT [FK_fact_achats_fournisseur_date_reception_sk] FOREIGN KEY ([date_reception_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_achats_fournisseur] WITH CHECK ADD CONSTRAINT [FK_fact_achats_fournisseur_fournisseur_sk] FOREIGN KEY ([fournisseur_sk]) REFERENCES dw.[dim_fournisseur] ([fournisseur_sk]);
ALTER TABLE dw.[fact_achats_fournisseur] WITH CHECK ADD CONSTRAINT [FK_fact_achats_fournisseur_produit_sk] FOREIGN KEY ([produit_sk]) REFERENCES dw.[dim_produit] ([produit_sk]);
ALTER TABLE dw.[fact_achats_fournisseur] WITH CHECK ADD CONSTRAINT [FK_fact_achats_fournisseur_entrepot_sk] FOREIGN KEY ([entrepot_sk]) REFERENCES dw.[dim_entrepot] ([entrepot_sk]);
ALTER TABLE dw.[fact_mouvements_stock] WITH CHECK ADD CONSTRAINT [FK_fact_mouvements_stock_date_sk] FOREIGN KEY ([date_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_mouvements_stock] WITH CHECK ADD CONSTRAINT [FK_fact_mouvements_stock_produit_sk] FOREIGN KEY ([produit_sk]) REFERENCES dw.[dim_produit] ([produit_sk]);
ALTER TABLE dw.[fact_mouvements_stock] WITH CHECK ADD CONSTRAINT [FK_fact_mouvements_stock_entrepot_sk] FOREIGN KEY ([entrepot_sk]) REFERENCES dw.[dim_entrepot] ([entrepot_sk]);
ALTER TABLE dw.[fact_stock_mensuel] WITH CHECK ADD CONSTRAINT [FK_fact_stock_mensuel_date_sk] FOREIGN KEY ([date_sk]) REFERENCES dw.[dim_date] ([date_sk]);
ALTER TABLE dw.[fact_stock_mensuel] WITH CHECK ADD CONSTRAINT [FK_fact_stock_mensuel_produit_sk] FOREIGN KEY ([produit_sk]) REFERENCES dw.[dim_produit] ([produit_sk]);
ALTER TABLE dw.[fact_stock_mensuel] WITH CHECK ADD CONSTRAINT [FK_fact_stock_mensuel_entrepot_sk] FOREIGN KEY ([entrepot_sk]) REFERENCES dw.[dim_entrepot] ([entrepot_sk]);
GO
/* Index : columnstore clustered sur les faits (requêtes analytiques Power BI / Tableau) */
CREATE CLUSTERED COLUMNSTORE INDEX [CCI_fact_ventes] ON dw.[fact_ventes];
CREATE CLUSTERED COLUMNSTORE INDEX [CCI_fact_commandes] ON dw.[fact_commandes];
CREATE CLUSTERED COLUMNSTORE INDEX [CCI_fact_paiements] ON dw.[fact_paiements];
CREATE CLUSTERED COLUMNSTORE INDEX [CCI_fact_livraisons] ON dw.[fact_livraisons];
CREATE CLUSTERED COLUMNSTORE INDEX [CCI_fact_remboursements] ON dw.[fact_remboursements];
CREATE CLUSTERED COLUMNSTORE INDEX [CCI_fact_avis] ON dw.[fact_avis];
CREATE CLUSTERED COLUMNSTORE INDEX [CCI_fact_marketing_quotidien] ON dw.[fact_marketing_quotidien];
CREATE CLUSTERED COLUMNSTORE INDEX [CCI_fact_achats_fournisseur] ON dw.[fact_achats_fournisseur];
CREATE CLUSTERED COLUMNSTORE INDEX [CCI_fact_mouvements_stock] ON dw.[fact_mouvements_stock];
CREATE CLUSTERED COLUMNSTORE INDEX [CCI_fact_stock_mensuel] ON dw.[fact_stock_mensuel];
GO
/* ---------------------------------------------------------------------
   Vues de restitution (schéma bi) : colonnes techniques masquées, noms stables pour les outils BI
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW bi.[v_dim_date] AS
SELECT [date_sk], [date], [annee], [trimestre], [libelle_trimestre], [mois], [nom_mois], [annee_mois], [semaine_iso], [jour_mois], [jour_semaine], [nom_jour], [est_weekend], [est_jour_ferie], [nom_jour_ferie], [est_ramadan], [periode_commerciale]
FROM dw.[dim_date];
GO
CREATE OR ALTER VIEW bi.[v_dim_client] AS
SELECT [client_sk], [client_id], [type_client], [nom_complet], [genre], [tranche_age], [gouvernorat_id], [gouvernorat], [region], [ville], [canal_inscription], [date_inscription], [cohorte_inscription], [opt_in_email], [opt_in_sms], [segment_fidelite], [date_debut_validite], [date_fin_validite], [est_courant], [est_supprime]
FROM dw.[dim_client];
GO
CREATE OR ALTER VIEW bi.[v_dim_produit] AS
SELECT [produit_sk], [produit_id], [prix_id], [sku], [nom_produit], [marque], [categorie], [sous_categorie], [fournisseur_id], [taux_tva], [gamme_prix], [statut_produit], [prix_catalogue_ttc], [cout_achat_unitaire_ht], [taux_retour_cible], [marge_brute_cible], [date_debut_validite], [date_fin_validite], [est_courant], [est_supprime]
FROM dw.[dim_produit];
GO
CREATE OR ALTER VIEW bi.[v_dim_fournisseur] AS
SELECT [fournisseur_sk], [fournisseur_id], [nom_fournisseur], [pays], [est_local], [delai_appro_moyen_j], [conditions_paiement], [fiabilite_livraison], [est_supprime]
FROM dw.[dim_fournisseur];
GO
CREATE OR ALTER VIEW bi.[v_dim_geographie] AS
SELECT [geographie_sk], [gouvernorat_id], [gouvernorat], [region], [zone_livraison], [entrepot_rattachement], [pays], [est_supprime]
FROM dw.[dim_geographie];
GO
CREATE OR ALTER VIEW bi.[v_dim_entrepot] AS
SELECT [entrepot_sk], [entrepot_id], [nom_entrepot], [ville], [region], [surface_m2], [date_ouverture], [est_supprime]
FROM dw.[dim_entrepot];
GO
CREATE OR ALTER VIEW bi.[v_dim_transporteur] AS
SELECT [transporteur_sk], [transporteur_id], [nom_transporteur], [couverture], [cout_base_ht], [est_supprime]
FROM dw.[dim_transporteur];
GO
CREATE OR ALTER VIEW bi.[v_dim_campagne] AS
SELECT [campagne_sk], [campagne_id], [nom_campagne], [canal_media], [type_canal], [objectif], [theme], [date_debut], [date_fin], [budget_ht], [est_supprime]
FROM dw.[dim_campagne];
GO
CREATE OR ALTER VIEW bi.[v_dim_coupon] AS
SELECT [coupon_sk], [code_coupon], [type_remise], [valeur], [montant_min_ttc], [reserve_premiere_commande], [est_supprime]
FROM dw.[dim_coupon];
GO
CREATE OR ALTER VIEW bi.[v_dim_canal] AS
SELECT [canal_sk], [canal], [appareil], [libelle_canal], [est_supprime]
FROM dw.[dim_canal];
GO
CREATE OR ALTER VIEW bi.[v_dim_mode_paiement] AS
SELECT [mode_paiement_sk], [mode_paiement], [libelle_mode_paiement], [est_paiement_differe], [est_supprime]
FROM dw.[dim_mode_paiement];
GO
CREATE OR ALTER VIEW bi.[v_dim_statut_commande] AS
SELECT [statut_commande_sk], [statut_commande], [libelle_statut], [famille_statut], [est_ca_reconnu], [est_supprime]
FROM dw.[dim_statut_commande];
GO
CREATE OR ALTER VIEW bi.[v_dim_motif_retour] AS
SELECT [motif_retour_sk], [type_remboursement], [motif], [libelle_motif], [responsabilite], [est_supprime]
FROM dw.[dim_motif_retour];
GO
CREATE OR ALTER VIEW bi.[v_fact_ventes] AS
SELECT [ligne_id], [commande_id], [date_commande_sk], [client_sk], [produit_sk], [geographie_sk], [entrepot_sk], [canal_sk], [campagne_sk], [coupon_sk], [statut_commande_sk], [quantite], [prix_catalogue_ttc], [prix_unitaire_ttc], [montant_brut_ttc], [montant_remise_promo_ttc], [montant_ttc], [montant_ht], [montant_tva], [cout_achat_ht], [marge_brute_ht], [est_ca_reconnu]
FROM dw.[fact_ventes]
WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW bi.[v_fact_commandes] AS
SELECT [commande_id], [date_commande_sk], [date_expedition_sk], [date_livraison_sk], [date_annulation_sk], [client_sk], [geographie_sk], [entrepot_sk], [canal_sk], [campagne_sk], [coupon_sk], [mode_paiement_sk], [statut_commande_sk], [nb_lignes], [nb_articles], [sous_total_ttc], [remise_coupon_ttc], [frais_livraison_ttc], [montant_total_ttc], [cout_achat_ht], [cout_transport_ht], [montant_rembourse_ttc], [nb_tentatives_paiement], [delai_livraison_j], [est_premiere_commande], [est_livree_a_temps], [est_ca_reconnu]
FROM dw.[fact_commandes]
WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW bi.[v_fact_paiements] AS
SELECT [paiement_id], [commande_id], [date_paiement_sk], [date_reversement_sk], [client_sk], [mode_paiement_sk], [num_tentative], [statut_paiement], [code_erreur], [prestataire], [montant_ttc], [est_reussi], [delai_reversement_j]
FROM dw.[fact_paiements]
WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW bi.[v_fact_livraisons] AS
SELECT [livraison_id], [commande_id], [date_expedition_sk], [date_prevue_sk], [date_livraison_sk], [client_sk], [entrepot_sk], [transporteur_sk], [geographie_sk], [statut_livraison], [nb_tentatives], [poids_kg], [cout_transport_ht], [delai_preparation_h], [delai_livraison_j], [retard_j], [est_livree], [est_livree_a_temps], [est_premiere_tentative]
FROM dw.[fact_livraisons]
WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW bi.[v_fact_remboursements] AS
SELECT [remboursement_id], [commande_id], [date_demande_sk], [date_remboursement_sk], [client_sk], [produit_sk], [motif_retour_sk], [mode_remboursement], [statut], [etat_article], [quantite], [montant_demande_ttc], [montant_rembourse_ttc], [delai_traitement_j]
FROM dw.[fact_remboursements]
WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW bi.[v_fact_avis] AS
SELECT [avis_id], [commande_id], [date_avis_sk], [client_sk], [produit_sk], [note], [sentiment], [a_commentaire], [commentaire]
FROM dw.[fact_avis]
WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW bi.[v_fact_marketing_quotidien] AS
SELECT [depense_id], [date_sk], [campagne_sk], [depense_ht], [impressions], [clics], [commandes_attribuees], [nouveaux_clients_attribues], [ca_attribue_ttc]
FROM dw.[fact_marketing_quotidien]
WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW bi.[v_fact_achats_fournisseur] AS
SELECT [ligne_cf_id], [commande_fournisseur_id], [date_commande_sk], [date_prevue_sk], [date_reception_sk], [fournisseur_sk], [produit_sk], [entrepot_sk], [statut], [quantite_commandee], [quantite_recue], [cout_unitaire_ht], [montant_ht], [delai_appro_reel_j], [retard_appro_j]
FROM dw.[fact_achats_fournisseur]
WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW bi.[v_fact_mouvements_stock] AS
SELECT [mouvement_id], [date_sk], [produit_sk], [entrepot_sk], [type_mouvement], [sens], [reference_id], [quantite], [valeur_ht]
FROM dw.[fact_mouvements_stock]
WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW bi.[v_fact_stock_mensuel] AS
SELECT [date_sk], [produit_sk], [entrepot_sk], [inventaire_id], [stock_fin_mois], [quantite_en_commande], [valeur_stock_ht], [est_rupture]
FROM dw.[fact_stock_mensuel]
WHERE est_supprime = 0;
GO
