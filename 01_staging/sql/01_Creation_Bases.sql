/* =====================================================================
   Projet      : TuniShop — Data Warehouse e-commerce (portfolio)
   Script      : Scripts_Creation_Bases.sql
   Objet       : Création des 5 bases (STG_RAW, STG_CLEAN, STG_INTEGRATED, DWH, ADMIN), des schémas, des tables de staging et des fonctions de nettoyage. Les objets du DWH sont dans Scripts_DWH.sql ; l'audit (base TuniShop_ADMIN) dans Scripts_Audit_Logs.sql.
   Cible       : Microsoft SQL Server 2019+ (SSMS) — compatibilité 150
   Exécution   : SSMS, mode SQLCMD inutile ; exécuter en entier (F5)
   Généré le   : 2026-10-17 depuis le modèle de métadonnées du projet
   ===================================================================== */
SET NOCOUNT ON;
GO
/* Ordre de déploiement :
   1. Scripts_Creation_Bases.sql   (ce script)
   2. Scripts_Audit_Logs.sql       (schéma audit dans TuniShop_ADMIN, base de contrôle)
   3. Scripts_DWH.sql              (dimensions, faits, vues)
   4. Scripts_Transformation.sql   (procédures RAW→CLEAN→INTEGRATED→DWH)
*/

/* ---------------------------------------------------------------------
   1. Bases de données
   Mode de récupération SIMPLE pour le staging (rechargé à chaque exécution),
   FULL pour le DWH (historique SCD2 à préserver).
   Adapter les chemins de fichiers si nécessaire (valeurs par défaut de l'instance ici).
   --------------------------------------------------------------------- */
USE master;
GO
IF DB_ID(N'TuniShop_STG_RAW') IS NULL
BEGIN
    CREATE DATABASE [TuniShop_STG_RAW] COLLATE French_CI_AS;
END
GO
ALTER DATABASE [TuniShop_STG_RAW] SET RECOVERY SIMPLE;
ALTER DATABASE [TuniShop_STG_RAW] SET COMPATIBILITY_LEVEL = 150;
GO
IF DB_ID(N'TuniShop_STG_CLEAN') IS NULL
BEGIN
    CREATE DATABASE [TuniShop_STG_CLEAN] COLLATE French_CI_AS;
END
GO
ALTER DATABASE [TuniShop_STG_CLEAN] SET RECOVERY SIMPLE;
ALTER DATABASE [TuniShop_STG_CLEAN] SET COMPATIBILITY_LEVEL = 150;
GO
IF DB_ID(N'TuniShop_STG_INTEGRATED') IS NULL
BEGIN
    CREATE DATABASE [TuniShop_STG_INTEGRATED] COLLATE French_CI_AS;
END
GO
ALTER DATABASE [TuniShop_STG_INTEGRATED] SET RECOVERY SIMPLE;
ALTER DATABASE [TuniShop_STG_INTEGRATED] SET COMPATIBILITY_LEVEL = 150;
GO
IF DB_ID(N'TuniShop_DWH') IS NULL
BEGIN
    CREATE DATABASE [TuniShop_DWH] COLLATE French_CI_AS;
END
GO
ALTER DATABASE [TuniShop_DWH] SET RECOVERY FULL;
ALTER DATABASE [TuniShop_DWH] SET COMPATIBILITY_LEVEL = 150;
GO
IF DB_ID(N'TuniShop_ADMIN') IS NULL
BEGIN
    CREATE DATABASE [TuniShop_ADMIN] COLLATE French_CI_AS;
END
GO
ALTER DATABASE [TuniShop_ADMIN] SET RECOVERY FULL;
ALTER DATABASE [TuniShop_ADMIN] SET COMPATIBILITY_LEVEL = 150;
GO
/* ---------------------------------------------------------------------
   2. TuniShop_STG_RAW — schéma raw
   Copie fidèle des fichiers : toutes les colonnes en NVARCHAR, aucune contrainte
   métier, + 4 colonnes techniques de traçabilité. Rechargée (TRUNCATE) à chaque lot
   par Scripts_Preparation.py.
   --------------------------------------------------------------------- */
USE [TuniShop_STG_RAW];
GO
IF SCHEMA_ID(N'raw') IS NULL EXEC (N'CREATE SCHEMA raw AUTHORIZATION dbo;');
GO
-- Référentiel des catégories et sous-catégories produit — source : catalogue/categories.csv (CSV, 19 lignes reçues)
DROP TABLE IF EXISTS raw.[categories];
CREATE TABLE raw.[categories] (
    [categorie_id] NVARCHAR(10) NULL,
    [categorie] NVARCHAR(50) NULL,
    [sous_categorie] NVARCHAR(100) NULL,
    [taux_tva] NVARCHAR(10) NULL,
    [taux_retour_cible] NVARCHAR(10) NULL,
    [marge_brute_cible] NVARCHAR(10) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_categories_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_categories_lot ON raw.[categories] (id_chargement);
GO
-- Référentiel des fournisseurs — source : catalogue/fournisseurs.csv (CSV, 40 lignes reçues)
DROP TABLE IF EXISTS raw.[fournisseurs];
CREATE TABLE raw.[fournisseurs] (
    [fournisseur_id] NVARCHAR(20) NULL,
    [nom_fournisseur] NVARCHAR(50) NULL,
    [pays] NVARCHAR(20) NULL,
    [delai_appro_moyen_j] NVARCHAR(10) NULL,
    [conditions_paiement] NVARCHAR(100) NULL,
    [fiabilite_livraison] NVARCHAR(10) NULL,
    [email_contact] NVARCHAR(100) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_fournisseurs_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_fournisseurs_lot ON raw.[fournisseurs] (id_chargement);
GO
-- Catalogue produits — source : catalogue/produits.csv (CSV, 596 lignes reçues)
DROP TABLE IF EXISTS raw.[produits];
CREATE TABLE raw.[produits] (
    [produit_id] NVARCHAR(20) NULL,
    [sku] NVARCHAR(50) NULL,
    [nom_produit] NVARCHAR(100) NULL,
    [categorie_id] NVARCHAR(10) NULL,
    [marque] NVARCHAR(50) NULL,
    [fournisseur_id] NVARCHAR(20) NULL,
    [prix_catalogue_ttc_actuel] NVARCHAR(20) NULL,
    [cout_achat_unitaire_ht_actuel] NVARCHAR(20) NULL,
    [taux_tva] NVARCHAR(10) NULL,
    [poids_kg] NVARCHAR(10) NULL,
    [date_lancement] NVARCHAR(20) NULL,
    [date_arret] NVARCHAR(20) NULL,
    [statut_produit] NVARCHAR(20) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_produits_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_produits_lot ON raw.[produits] (id_chargement);
GO
-- Historique des prix et coûts produit — source : catalogue/produits_prix_historique.csv (CSV, 1,601 lignes reçues)
DROP TABLE IF EXISTS raw.[produits_prix_historique];
CREATE TABLE raw.[produits_prix_historique] (
    [prix_id] NVARCHAR(20) NULL,
    [produit_id] NVARCHAR(20) NULL,
    [date_debut] NVARCHAR(20) NULL,
    [date_fin] NVARCHAR(20) NULL,
    [prix_catalogue_ttc] NVARCHAR(20) NULL,
    [cout_achat_unitaire_ht] NVARCHAR(20) NULL,
    [est_prix_actuel] NVARCHAR(10) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_produits_prix_historique_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_produits_prix_historique_lot ON raw.[produits_prix_historique] (id_chargement);
GO
-- Comptes clients — source : crm/clients.csv (CSV, 16,150 lignes reçues)
DROP TABLE IF EXISTS raw.[clients];
CREATE TABLE raw.[clients] (
    [client_id] NVARCHAR(20) NULL,
    [type_client] NVARCHAR(50) NULL,
    [prenom] NVARCHAR(20) NULL,
    [nom] NVARCHAR(50) NULL,
    [genre] NVARCHAR(10) NULL,
    [date_naissance] NVARCHAR(20) NULL,
    [raison_sociale] NVARCHAR(100) NULL,
    [matricule_fiscal] NVARCHAR(50) NULL,
    [email] NVARCHAR(100) NULL,
    [telephone] NVARCHAR(50) NULL,
    [gouvernorat_id] NVARCHAR(10) NULL,
    [ville] NVARCHAR(50) NULL,
    [date_inscription] NVARCHAR(50) NULL,
    [canal_inscription] NVARCHAR(50) NULL,
    [campagne_acquisition_id] NVARCHAR(20) NULL,
    [opt_in_email] NVARCHAR(10) NULL,
    [opt_in_sms] NVARCHAR(10) NULL,
    [segment_fidelite] NVARCHAR(20) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_clients_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_clients_lot ON raw.[clients] (id_chargement);
GO
-- Référentiel des entrepôts — source : logistique/entrepots.csv (CSV, 3 lignes reçues)
DROP TABLE IF EXISTS raw.[entrepots];
CREATE TABLE raw.[entrepots] (
    [entrepot_id] NVARCHAR(10) NULL,
    [nom_entrepot] NVARCHAR(50) NULL,
    [ville] NVARCHAR(20) NULL,
    [gouvernorat_id] NVARCHAR(10) NULL,
    [date_ouverture] NVARCHAR(20) NULL,
    [surface_m2] NVARCHAR(10) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_entrepots_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_entrepots_lot ON raw.[entrepots] (id_chargement);
GO
-- Référentiel des transporteurs — source : logistique/transporteurs.csv (CSV, 4 lignes reçues)
DROP TABLE IF EXISTS raw.[transporteurs];
CREATE TABLE raw.[transporteurs] (
    [transporteur_id] NVARCHAR(10) NULL,
    [nom_transporteur] NVARCHAR(50) NULL,
    [couverture] NVARCHAR(50) NULL,
    [cout_base_ht] NVARCHAR(10) NULL,
    [ecart_delai_moyen_j] NVARCHAR(10) NULL,
    [date_debut_contrat] NVARCHAR(20) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_transporteurs_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_transporteurs_lot ON raw.[transporteurs] (id_chargement);
GO
-- Expéditions et suivi de livraison — source : logistique/livraisons.csv (CSV, 61,793 lignes reçues)
DROP TABLE IF EXISTS raw.[livraisons];
CREATE TABLE raw.[livraisons] (
    [livraison_id] NVARCHAR(20) NULL,
    [commande_id] NVARCHAR(20) NULL,
    [entrepot_id] NVARCHAR(10) NULL,
    [transporteur_id] NVARCHAR(10) NULL,
    [gouvernorat_destination_id] NVARCHAR(10) NULL,
    [date_expedition] NVARCHAR(50) NULL,
    [date_livraison_prevue] NVARCHAR(20) NULL,
    [date_livraison_reelle] NVARCHAR(50) NULL,
    [date_dernier_evenement] NVARCHAR(50) NULL,
    [statut_livraison] NVARCHAR(50) NULL,
    [nb_tentatives] NVARCHAR(10) NULL,
    [poids_kg] NVARCHAR(20) NULL,
    [cout_transport_ht] NVARCHAR(20) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_livraisons_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_livraisons_lot ON raw.[livraisons] (id_chargement);
GO
-- Campagnes marketing — source : marketing/campagnes_marketing.csv (CSV, 152 lignes reçues)
DROP TABLE IF EXISTS raw.[campagnes_marketing];
CREATE TABLE raw.[campagnes_marketing] (
    [campagne_id] NVARCHAR(20) NULL,
    [nom_campagne] NVARCHAR(100) NULL,
    [canal] NVARCHAR(50) NULL,
    [objectif] NVARCHAR(50) NULL,
    [theme] NVARCHAR(20) NULL,
    [categorie_ciblee_id] NVARCHAR(10) NULL,
    [code_coupon] NVARCHAR(50) NULL,
    [date_debut] NVARCHAR(20) NULL,
    [date_fin] NVARCHAR(20) NULL,
    [budget_ht] NVARCHAR(20) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_campagnes_marketing_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_campagnes_marketing_lot ON raw.[campagnes_marketing] (id_chargement);
GO
-- Codes promotionnels — source : marketing/coupons.csv (CSV, 68 lignes reçues)
DROP TABLE IF EXISTS raw.[coupons];
CREATE TABLE raw.[coupons] (
    [code_coupon] NVARCHAR(50) NULL,
    [type_remise] NVARCHAR(50) NULL,
    [valeur] NVARCHAR(10) NULL,
    [montant_min_ttc] NVARCHAR(10) NULL,
    [plafond_remise_ttc] NVARCHAR(10) NULL,
    [date_debut] NVARCHAR(20) NULL,
    [date_fin] NVARCHAR(20) NULL,
    [campagne_id] NVARCHAR(20) NULL,
    [reserve_premiere_commande] NVARCHAR(10) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_coupons_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_coupons_lot ON raw.[coupons] (id_chargement);
GO
-- Dépenses et performances quotidiennes par campagne — source : marketing/marketing_depenses_quotidiennes.csv (CSV, 3,427 lignes reçues)
DROP TABLE IF EXISTS raw.[marketing_depenses_quotidiennes];
CREATE TABLE raw.[marketing_depenses_quotidiennes] (
    [depense_id] NVARCHAR(20) NULL,
    [campagne_id] NVARCHAR(20) NULL,
    [date] NVARCHAR(20) NULL,
    [canal] NVARCHAR(50) NULL,
    [depense_ht] NVARCHAR(20) NULL,
    [impressions] NVARCHAR(20) NULL,
    [clics] NVARCHAR(10) NULL,
    [commandes_attribuees] NVARCHAR(10) NULL,
    [nouveaux_clients_attribues] NVARCHAR(10) NULL,
    [ca_attribue_ttc] NVARCHAR(20) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_marketing_depenses_quotidiennes_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_marketing_depenses_quotidiennes_lot ON raw.[marketing_depenses_quotidiennes] (id_chargement);
GO
-- Calendrier 2023-2025 avec fériés et périodes commerciales — source : referentiels/dim_calendrier.csv (CSV, 1,096 lignes reçues)
DROP TABLE IF EXISTS raw.[dim_calendrier];
CREATE TABLE raw.[dim_calendrier] (
    [date] NVARCHAR(20) NULL,
    [annee] NVARCHAR(10) NULL,
    [trimestre] NVARCHAR(10) NULL,
    [mois] NVARCHAR(10) NULL,
    [nom_mois] NVARCHAR(20) NULL,
    [semaine_iso] NVARCHAR(10) NULL,
    [jour_semaine] NVARCHAR(10) NULL,
    [nom_jour] NVARCHAR(20) NULL,
    [est_weekend] NVARCHAR(10) NULL,
    [est_jour_ferie] NVARCHAR(10) NULL,
    [nom_jour_ferie] NVARCHAR(50) NULL,
    [est_ramadan] NVARCHAR(10) NULL,
    [periode_commerciale] NVARCHAR(50) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_dim_calendrier_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_dim_calendrier_lot ON raw.[dim_calendrier] (id_chargement);
GO
-- Référentiel des 24 gouvernorats — source : referentiels/ref_gouvernorats.csv (CSV, 24 lignes reçues)
DROP TABLE IF EXISTS raw.[ref_gouvernorats];
CREATE TABLE raw.[ref_gouvernorats] (
    [gouvernorat_id] NVARCHAR(10) NULL,
    [gouvernorat] NVARCHAR(50) NULL,
    [region] NVARCHAR(50) NULL,
    [entrepot_rattachement_id] NVARCHAR(10) NULL,
    [zone_livraison] NVARCHAR(10) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_ref_gouvernorats_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_ref_gouvernorats_lot ON raw.[ref_gouvernorats] (id_chargement);
GO
-- Retours, annulations et gestes commerciaux — source : sav/remboursements.csv (CSV, 8,815 lignes reçues)
DROP TABLE IF EXISTS raw.[remboursements];
CREATE TABLE raw.[remboursements] (
    [remboursement_id] NVARCHAR(20) NULL,
    [commande_id] NVARCHAR(20) NULL,
    [ligne_id] NVARCHAR(50) NULL,
    [type_remboursement] NVARCHAR(50) NULL,
    [motif] NVARCHAR(100) NULL,
    [quantite] NVARCHAR(10) NULL,
    [montant_rembourse_ttc] NVARCHAR(20) NULL,
    [montant_demande_ttc] NVARCHAR(20) NULL,
    [date_demande] NVARCHAR(50) NULL,
    [date_reception_retour] NVARCHAR(50) NULL,
    [date_remboursement] NVARCHAR(50) NULL,
    [mode_remboursement] NVARCHAR(50) NULL,
    [statut] NVARCHAR(20) NULL,
    [etat_article] NVARCHAR(50) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_remboursements_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_remboursements_lot ON raw.[remboursements] (id_chargement);
GO
-- Journal des mouvements de stock — source : stocks/mouvements_stock.csv (CSV, 140,284 lignes reçues)
DROP TABLE IF EXISTS raw.[mouvements_stock];
CREATE TABLE raw.[mouvements_stock] (
    [mouvement_id] NVARCHAR(20) NULL,
    [date_mouvement] NVARCHAR(50) NULL,
    [produit_id] NVARCHAR(20) NULL,
    [entrepot_id] NVARCHAR(10) NULL,
    [type_mouvement] NVARCHAR(100) NULL,
    [quantite] NVARCHAR(10) NULL,
    [reference_id] NVARCHAR(50) NULL,
    [cout_unitaire_ht] NVARCHAR(20) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_mouvements_stock_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_mouvements_stock_lot ON raw.[mouvements_stock] (id_chargement);
GO
-- Inventaires de fin de mois — source : stocks/stocks_mensuels.csv (CSV, 56,562 lignes reçues)
DROP TABLE IF EXISTS raw.[stocks_mensuels];
CREATE TABLE raw.[stocks_mensuels] (
    [inventaire_id] NVARCHAR(20) NULL,
    [date_inventaire] NVARCHAR(20) NULL,
    [produit_id] NVARCHAR(20) NULL,
    [entrepot_id] NVARCHAR(10) NULL,
    [stock_fin_mois] NVARCHAR(10) NULL,
    [quantite_en_commande] NVARCHAR(10) NULL,
    [cout_unitaire_ht] NVARCHAR(20) NULL,
    [valeur_stock_ht] NVARCHAR(20) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_stocks_mensuels_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_stocks_mensuels_lot ON raw.[stocks_mensuels] (id_chargement);
GO
-- En-têtes de commandes fournisseurs — source : achats/commandes_fournisseurs.csv (CSV, 10,370 lignes reçues)
DROP TABLE IF EXISTS raw.[commandes_fournisseurs];
CREATE TABLE raw.[commandes_fournisseurs] (
    [commande_fournisseur_id] NVARCHAR(20) NULL,
    [fournisseur_id] NVARCHAR(20) NULL,
    [entrepot_id] NVARCHAR(10) NULL,
    [date_commande] NVARCHAR(50) NULL,
    [date_livraison_prevue] NVARCHAR(20) NULL,
    [date_reception] NVARCHAR(50) NULL,
    [statut] NVARCHAR(100) NULL,
    [montant_total_ht] NVARCHAR(20) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_commandes_fournisseurs_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_commandes_fournisseurs_lot ON raw.[commandes_fournisseurs] (id_chargement);
GO
-- Lignes de commandes fournisseurs — source : achats/lignes_commande_fournisseur.csv (CSV, 11,793 lignes reçues)
DROP TABLE IF EXISTS raw.[lignes_commande_fournisseur];
CREATE TABLE raw.[lignes_commande_fournisseur] (
    [ligne_cf_id] NVARCHAR(20) NULL,
    [commande_fournisseur_id] NVARCHAR(20) NULL,
    [produit_id] NVARCHAR(20) NULL,
    [quantite_commandee] NVARCHAR(10) NULL,
    [quantite_recue] NVARCHAR(10) NULL,
    [cout_unitaire_ht] NVARCHAR(20) NULL,
    [montant_ligne_ht] NVARCHAR(20) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_lignes_commande_fournisseur_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_lignes_commande_fournisseur_lot ON raw.[lignes_commande_fournisseur] (id_chargement);
GO
-- Avis et notes clients — source : avis/avis_clients.csv (CSV, 9,344 lignes reçues)
DROP TABLE IF EXISTS raw.[avis_clients];
CREATE TABLE raw.[avis_clients] (
    [avis_id] NVARCHAR(20) NULL,
    [commande_id] NVARCHAR(20) NULL,
    [ligne_id] NVARCHAR(50) NULL,
    [produit_id] NVARCHAR(20) NULL,
    [client_id] NVARCHAR(20) NULL,
    [date_avis] NVARCHAR(50) NULL,
    [note] NVARCHAR(10) NULL,
    [commentaire] NVARCHAR(255) NULL,
    [achat_verifie] NVARCHAR(10) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_avis_clients_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_avis_clients_lot ON raw.[avis_clients] (id_chargement);
GO
-- En-têtes de commandes clients — source : ventes/commandes/commandes_*.csv (CSV (36 fichiers mensuels), 66,568 lignes reçues)
DROP TABLE IF EXISTS raw.[commandes];
CREATE TABLE raw.[commandes] (
    [commande_id] NVARCHAR(20) NULL,
    [client_id] NVARCHAR(20) NULL,
    [date_commande] NVARCHAR(50) NULL,
    [canal] NVARCHAR(50) NULL,
    [appareil] NVARCHAR(20) NULL,
    [gouvernorat_livraison_id] NVARCHAR(10) NULL,
    [ville_livraison] NVARCHAR(50) NULL,
    [entrepot_id] NVARCHAR(10) NULL,
    [campagne_id] NVARCHAR(20) NULL,
    [code_coupon] NVARCHAR(50) NULL,
    [mode_paiement] NVARCHAR(50) NULL,
    [nb_lignes] NVARCHAR(10) NULL,
    [nb_articles] NVARCHAR(10) NULL,
    [sous_total_ttc] NVARCHAR(20) NULL,
    [remise_coupon_ttc] NVARCHAR(20) NULL,
    [frais_livraison_ttc] NVARCHAR(10) NULL,
    [montant_total_ttc] NVARCHAR(20) NULL,
    [statut_commande] NVARCHAR(50) NULL,
    [motif_annulation] NVARCHAR(50) NULL,
    [date_annulation] NVARCHAR(50) NULL,
    [est_premiere_commande] NVARCHAR(10) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_commandes_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_commandes_lot ON raw.[commandes] (id_chargement);
GO
-- Lignes de commandes clients — source : ventes/lignes_commande/lignes_commande_*.csv (CSV (36 fichiers mensuels), 116,023 lignes reçues)
DROP TABLE IF EXISTS raw.[lignes_commande];
CREATE TABLE raw.[lignes_commande] (
    [ligne_id] NVARCHAR(50) NULL,
    [commande_id] NVARCHAR(20) NULL,
    [num_ligne] NVARCHAR(10) NULL,
    [produit_id] NVARCHAR(20) NULL,
    [quantite] NVARCHAR(10) NULL,
    [prix_catalogue_ttc] NVARCHAR(20) NULL,
    [remise_promo_unitaire_ttc] NVARCHAR(10) NULL,
    [prix_unitaire_ttc] NVARCHAR(20) NULL,
    [taux_tva] NVARCHAR(10) NULL,
    [montant_ligne_ttc] NVARCHAR(20) NULL,
    [montant_ligne_ht] NVARCHAR(20) NULL,
    [montant_tva] NVARCHAR(20) NULL,
    [cout_achat_unitaire_ht] NVARCHAR(20) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_lignes_commande_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_lignes_commande_lot ON raw.[lignes_commande] (id_chargement);
GO
-- Tentatives de paiement exportées de l'API (JSON imbriqué) — source : paiements_api/paiements.jsonl (JSON Lines, 65,137 lignes reçues)
DROP TABLE IF EXISTS raw.[paiements_api];
CREATE TABLE raw.[paiements_api] (
    [ligne_json] NVARCHAR(4000) NULL,
    [id_chargement] INT NOT NULL,
    [fichier_source] NVARCHAR(260) NOT NULL,
    [num_ligne_fichier] INT NOT NULL,
    [date_chargement] DATETIME2(0) NOT NULL CONSTRAINT [DF_raw_paiements_api_date_chargement] DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_raw_paiements_api_lot ON raw.[paiements_api] (id_chargement);
GO
/* ---------------------------------------------------------------------
   3. TuniShop_STG_CLEAN — schéma clean
   Données typées, dédoublonnées, formats normalisés, corrections intra-table.
   Chargement INCRÉMENTAL (MERGE) : hash_ligne détecte les modifications, est_supprime marque
   les lignes disparues de la source. Ne pas réexécuter ce script après le premier chargement :
   il recrée les tables (DROP/CREATE) et efface donc l'historique.
   Clé primaire sur l'identifiant métier. Pas de clé étrangère (l'intégrité
   inter-tables est traitée dans STG_INTEGRATED).
   --------------------------------------------------------------------- */
USE [TuniShop_STG_CLEAN];
GO
IF SCHEMA_ID(N'clean') IS NULL EXEC (N'CREATE SCHEMA clean AUTHORIZATION dbo;');
GO
-- Fonction : suppression des accents usuels (statuts saisis avec accents)
CREATE OR ALTER FUNCTION clean.fn_sans_accent (@s NVARCHAR(4000))
RETURNS NVARCHAR(4000)
WITH SCHEMABINDING
AS
BEGIN
    IF @s IS NULL RETURN NULL;
    RETURN REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
           @s COLLATE Latin1_General_CS_AS,
           N'é',N'e'),N'è',N'e'),N'ê',N'e'),N'ë',N'e'),N'à',N'a'),N'â',N'a'),N'î',N'i'),N'ô',N'o'),N'û',N'u');
END;
GO
-- Fonction : normalisation des téléphones tunisiens au format +216XXXXXXXX (règle QR09)
CREATE OR ALTER FUNCTION clean.fn_normaliser_telephone (@tel NVARCHAR(50))
RETURNS VARCHAR(16)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @d VARCHAR(50) = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(@tel),' ',''),'-',''),'.',''),'(',''),')',''),'+','');
    IF @d IS NULL OR @d = '' OR @d LIKE '%[^0-9]%' RETURN NULL;
    IF LEN(@d) = 8                          RETURN '+216' + @d;
    IF LEN(@d) = 11 AND LEFT(@d,3) = '216'  RETURN '+' + @d;
    IF LEN(@d) = 13 AND LEFT(@d,5) = '00216' RETURN '+' + SUBSTRING(@d,3,11);
    RETURN NULL;
END;
GO
-- Table de quarantaine : rejets et signalements qualité
DROP TABLE IF EXISTS clean.rejets;
CREATE TABLE clean.rejets (
    [rejet_id] BIGINT IDENTITY(1,1) NOT NULL,
    [id_chargement] INT NOT NULL,
    [table_source] SYSNAME NOT NULL,
    [cle_enregistrement] NVARCHAR(100) NULL,
    [colonne] SYSNAME NULL,
    [valeur_recue] NVARCHAR(4000) NULL,
    [regle_id] VARCHAR(10) NOT NULL,
    [niveau] VARCHAR(12) NOT NULL,
    [message] NVARCHAR(400) NULL,
    [date_rejet] DATETIME2(0) NOT NULL CONSTRAINT DF_clean_rejets_date DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_clean_rejets PRIMARY KEY CLUSTERED (rejet_id)
);
CREATE INDEX IX_clean_rejets_lot ON clean.rejets (id_chargement, table_source, regle_id);
GO
-- Référentiel des catégories et sous-catégories produit
DROP TABLE IF EXISTS clean.[categories];
CREATE TABLE clean.[categories] (
    [categorie_id] VARCHAR(10) NOT NULL,
    [categorie] NVARCHAR(50) NULL,
    [sous_categorie] NVARCHAR(50) NULL,
    [taux_tva] TINYINT NULL,
    [taux_retour_cible] DECIMAL(5,2) NULL,
    [marge_brute_cible] DECIMAL(5,2) NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_categories] PRIMARY KEY CLUSTERED ([categorie_id])
);
GO
-- Référentiel des fournisseurs
DROP TABLE IF EXISTS clean.[fournisseurs];
CREATE TABLE clean.[fournisseurs] (
    [fournisseur_id] VARCHAR(10) NOT NULL,
    [nom_fournisseur] NVARCHAR(100) NULL,
    [pays] NVARCHAR(50) NULL,
    [delai_appro_moyen_j] SMALLINT NULL,
    [conditions_paiement] NVARCHAR(50) NULL,
    [fiabilite_livraison] DECIMAL(5,2) NULL,
    [email_contact] NVARCHAR(100) NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_fournisseurs] PRIMARY KEY CLUSTERED ([fournisseur_id])
);
GO
-- Catalogue produits
DROP TABLE IF EXISTS clean.[produits];
CREATE TABLE clean.[produits] (
    [produit_id] VARCHAR(10) NOT NULL,
    [sku] VARCHAR(15) NULL,
    [nom_produit] NVARCHAR(100) NULL,
    [categorie_id] VARCHAR(10) NULL,
    [marque] NVARCHAR(50) NULL,
    [fournisseur_id] VARCHAR(10) NULL,
    [prix_catalogue_ttc_actuel] DECIMAL(14,3) NULL,
    [cout_achat_unitaire_ht_actuel] DECIMAL(14,3) NULL,
    [taux_tva] TINYINT NULL,
    [poids_kg] DECIMAL(8,2) NULL,
    [date_lancement] DATE NULL,
    [date_arret] DATE NULL,
    [statut_produit] VARCHAR(10) NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_produits] PRIMARY KEY CLUSTERED ([produit_id])
);
GO
-- Historique des prix et coûts produit
DROP TABLE IF EXISTS clean.[produits_prix_historique];
CREATE TABLE clean.[produits_prix_historique] (
    [prix_id] VARCHAR(10) NOT NULL,
    [produit_id] VARCHAR(10) NULL,
    [date_debut] DATE NULL,
    [date_fin] DATE NULL,
    [prix_catalogue_ttc] DECIMAL(14,3) NULL,
    [cout_achat_unitaire_ht] DECIMAL(14,3) NULL,
    [est_prix_actuel] BIT NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_produits_prix_historique] PRIMARY KEY CLUSTERED ([prix_id])
);
GO
-- Comptes clients
DROP TABLE IF EXISTS clean.[clients];
CREATE TABLE clean.[clients] (
    [client_id] VARCHAR(12) NOT NULL,
    [type_client] VARCHAR(15) NULL,
    [prenom] NVARCHAR(50) NULL,
    [nom] NVARCHAR(50) NULL,
    [genre] VARCHAR(5) NULL,
    [date_naissance] DATE NULL,
    [raison_sociale] NVARCHAR(50) NULL,
    [matricule_fiscal] VARCHAR(20) NULL,
    [email] NVARCHAR(100) NULL,
    [telephone] VARCHAR(16) NULL,
    [gouvernorat_id] VARCHAR(5) NULL,
    [ville] NVARCHAR(50) NULL,
    [date_inscription] DATETIME2(0) NULL,
    [canal_inscription] VARCHAR(30) NULL,
    [campagne_acquisition_id] VARCHAR(10) NULL,
    [opt_in_email] BIT NULL,
    [opt_in_sms] BIT NULL,
    [segment_fidelite] VARCHAR(10) NULL,
    [genre_impute] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_clients] PRIMARY KEY CLUSTERED ([client_id])
);
GO
-- Référentiel des entrepôts
DROP TABLE IF EXISTS clean.[entrepots];
CREATE TABLE clean.[entrepots] (
    [entrepot_id] VARCHAR(10) NOT NULL,
    [nom_entrepot] NVARCHAR(50) NULL,
    [ville] NVARCHAR(50) NULL,
    [gouvernorat_id] VARCHAR(5) NULL,
    [date_ouverture] DATE NULL,
    [surface_m2] SMALLINT NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_entrepots] PRIMARY KEY CLUSTERED ([entrepot_id])
);
GO
-- Référentiel des transporteurs
DROP TABLE IF EXISTS clean.[transporteurs];
CREATE TABLE clean.[transporteurs] (
    [transporteur_id] VARCHAR(10) NOT NULL,
    [nom_transporteur] NVARCHAR(50) NULL,
    [couverture] NVARCHAR(50) NULL,
    [cout_base_ht] DECIMAL(14,3) NULL,
    [ecart_delai_moyen_j] DECIMAL(5,2) NULL,
    [date_debut_contrat] DATE NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_transporteurs] PRIMARY KEY CLUSTERED ([transporteur_id])
);
GO
-- Expéditions et suivi de livraison
DROP TABLE IF EXISTS clean.[livraisons];
CREATE TABLE clean.[livraisons] (
    [livraison_id] VARCHAR(12) NOT NULL,
    [commande_id] VARCHAR(12) NULL,
    [entrepot_id] VARCHAR(10) NULL,
    [transporteur_id] VARCHAR(10) NULL,
    [gouvernorat_destination_id] VARCHAR(5) NULL,
    [date_expedition] DATETIME2(0) NULL,
    [date_livraison_prevue] DATE NULL,
    [date_livraison_reelle] DATETIME2(0) NULL,
    [date_dernier_evenement] DATETIME2(0) NULL,
    [statut_livraison] VARCHAR(30) NULL,
    [nb_tentatives] TINYINT NULL,
    [poids_kg] DECIMAL(8,2) NULL,
    [cout_transport_ht] DECIMAL(14,3) NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_livraisons] PRIMARY KEY CLUSTERED ([livraison_id])
);
GO
-- Campagnes marketing
DROP TABLE IF EXISTS clean.[campagnes_marketing];
CREATE TABLE clean.[campagnes_marketing] (
    [campagne_id] VARCHAR(10) NOT NULL,
    [nom_campagne] NVARCHAR(100) NULL,
    [canal] VARCHAR(15) NULL,
    [objectif] VARCHAR(12) NULL,
    [theme] VARCHAR(10) NULL,
    [categorie_ciblee_id] VARCHAR(10) NULL,
    [code_coupon] VARCHAR(15) NULL,
    [date_debut] DATE NULL,
    [date_fin] DATE NULL,
    [budget_ht] DECIMAL(14,3) NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_campagnes_marketing] PRIMARY KEY CLUSTERED ([campagne_id])
);
GO
-- Codes promotionnels
DROP TABLE IF EXISTS clean.[coupons];
CREATE TABLE clean.[coupons] (
    [code_coupon] VARCHAR(15) NOT NULL,
    [type_remise] VARCHAR(12) NULL,
    [valeur] DECIMAL(10,2) NULL,
    [montant_min_ttc] DECIMAL(14,3) NULL,
    [plafond_remise_ttc] DECIMAL(14,3) NULL,
    [date_debut] DATE NULL,
    [date_fin] DATE NULL,
    [campagne_id] VARCHAR(10) NULL,
    [reserve_premiere_commande] BIT NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_coupons] PRIMARY KEY CLUSTERED ([code_coupon])
);
GO
-- Dépenses et performances quotidiennes par campagne
DROP TABLE IF EXISTS clean.[marketing_depenses_quotidiennes];
CREATE TABLE clean.[marketing_depenses_quotidiennes] (
    [depense_id] VARCHAR(12) NOT NULL,
    [campagne_id] VARCHAR(10) NULL,
    [date] DATE NULL,
    [canal] VARCHAR(15) NULL,
    [depense_ht] DECIMAL(14,3) NULL,
    [impressions] INT NULL,
    [clics] INT NULL,
    [commandes_attribuees] INT NULL,
    [nouveaux_clients_attribues] INT NULL,
    [ca_attribue_ttc] DECIMAL(14,3) NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_marketing_depenses_quotidiennes] PRIMARY KEY CLUSTERED ([depense_id])
);
GO
-- Calendrier 2023-2025 avec fériés et périodes commerciales
DROP TABLE IF EXISTS clean.[dim_calendrier];
CREATE TABLE clean.[dim_calendrier] (
    [date] DATE NOT NULL,
    [annee] SMALLINT NULL,
    [trimestre] TINYINT NULL,
    [mois] TINYINT NULL,
    [nom_mois] NVARCHAR(50) NULL,
    [semaine_iso] TINYINT NULL,
    [jour_semaine] TINYINT NULL,
    [nom_jour] VARCHAR(10) NULL,
    [est_weekend] BIT NULL,
    [est_jour_ferie] BIT NULL,
    [nom_jour_ferie] NVARCHAR(50) NULL,
    [est_ramadan] BIT NULL,
    [periode_commerciale] VARCHAR(20) NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_dim_calendrier] PRIMARY KEY CLUSTERED ([date])
);
GO
-- Référentiel des 24 gouvernorats
DROP TABLE IF EXISTS clean.[ref_gouvernorats];
CREATE TABLE clean.[ref_gouvernorats] (
    [gouvernorat_id] VARCHAR(5) NOT NULL,
    [gouvernorat] NVARCHAR(50) NULL,
    [region] NVARCHAR(50) NULL,
    [entrepot_rattachement_id] VARCHAR(10) NULL,
    [zone_livraison] VARCHAR(5) NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_ref_gouvernorats] PRIMARY KEY CLUSTERED ([gouvernorat_id])
);
GO
-- Retours, annulations et gestes commerciaux
DROP TABLE IF EXISTS clean.[remboursements];
CREATE TABLE clean.[remboursements] (
    [remboursement_id] VARCHAR(12) NOT NULL,
    [commande_id] VARCHAR(12) NULL,
    [ligne_id] VARCHAR(15) NULL,
    [type_remboursement] VARCHAR(20) NULL,
    [motif] VARCHAR(50) NULL,
    [quantite] INT NULL,
    [montant_rembourse_ttc] DECIMAL(14,3) NULL,
    [montant_demande_ttc] DECIMAL(14,3) NULL,
    [date_demande] DATETIME2(0) NULL,
    [date_reception_retour] DATETIME2(0) NULL,
    [date_remboursement] DATETIME2(0) NULL,
    [mode_remboursement] VARCHAR(20) NULL,
    [statut] VARCHAR(10) NULL,
    [etat_article] VARCHAR(15) NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_remboursements] PRIMARY KEY CLUSTERED ([remboursement_id])
);
GO
-- Journal des mouvements de stock
DROP TABLE IF EXISTS clean.[mouvements_stock];
CREATE TABLE clean.[mouvements_stock] (
    [mouvement_id] VARCHAR(12) NOT NULL,
    [date_mouvement] DATETIME2(0) NULL,
    [produit_id] VARCHAR(10) NULL,
    [entrepot_id] VARCHAR(10) NULL,
    [type_mouvement] VARCHAR(30) NULL,
    [quantite] INT NULL,
    [reference_id] VARCHAR(20) NULL,
    [cout_unitaire_ht] DECIMAL(14,3) NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_mouvements_stock] PRIMARY KEY CLUSTERED ([mouvement_id])
);
GO
-- Inventaires de fin de mois
DROP TABLE IF EXISTS clean.[stocks_mensuels];
CREATE TABLE clean.[stocks_mensuels] (
    [inventaire_id] VARCHAR(12) NOT NULL,
    [date_inventaire] DATE NULL,
    [produit_id] VARCHAR(10) NULL,
    [entrepot_id] VARCHAR(10) NULL,
    [stock_fin_mois] INT NULL,
    [quantite_en_commande] INT NULL,
    [cout_unitaire_ht] DECIMAL(14,3) NULL,
    [valeur_stock_ht] DECIMAL(14,3) NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_stocks_mensuels] PRIMARY KEY CLUSTERED ([inventaire_id])
);
GO
-- En-têtes de commandes fournisseurs
DROP TABLE IF EXISTS clean.[commandes_fournisseurs];
CREATE TABLE clean.[commandes_fournisseurs] (
    [commande_fournisseur_id] VARCHAR(10) NOT NULL,
    [fournisseur_id] VARCHAR(10) NULL,
    [entrepot_id] VARCHAR(10) NULL,
    [date_commande] DATETIME2(0) NULL,
    [date_livraison_prevue] DATE NULL,
    [date_reception] DATETIME2(0) NULL,
    [statut] VARCHAR(30) NULL,
    [montant_total_ht] DECIMAL(14,3) NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_commandes_fournisseurs] PRIMARY KEY CLUSTERED ([commande_fournisseur_id])
);
GO
-- Lignes de commandes fournisseurs
DROP TABLE IF EXISTS clean.[lignes_commande_fournisseur];
CREATE TABLE clean.[lignes_commande_fournisseur] (
    [ligne_cf_id] VARCHAR(12) NOT NULL,
    [commande_fournisseur_id] VARCHAR(10) NULL,
    [produit_id] VARCHAR(10) NULL,
    [quantite_commandee] INT NULL,
    [quantite_recue] INT NULL,
    [cout_unitaire_ht] DECIMAL(14,3) NULL,
    [montant_ligne_ht] DECIMAL(14,3) NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_lignes_commande_fournisseur] PRIMARY KEY CLUSTERED ([ligne_cf_id])
);
GO
-- Avis et notes clients
DROP TABLE IF EXISTS clean.[avis_clients];
CREATE TABLE clean.[avis_clients] (
    [avis_id] VARCHAR(12) NOT NULL,
    [commande_id] VARCHAR(12) NULL,
    [ligne_id] VARCHAR(15) NULL,
    [produit_id] VARCHAR(10) NULL,
    [client_id] VARCHAR(12) NULL,
    [date_avis] DATETIME2(0) NULL,
    [note] TINYINT NULL,
    [commentaire] NVARCHAR(500) NULL,
    [achat_verifie] BIT NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_avis_clients] PRIMARY KEY CLUSTERED ([avis_id])
);
GO
-- En-têtes de commandes clients
DROP TABLE IF EXISTS clean.[commandes];
CREATE TABLE clean.[commandes] (
    [commande_id] VARCHAR(12) NOT NULL,
    [client_id] VARCHAR(12) NULL,
    [date_commande] DATETIME2(0) NULL,
    [canal] VARCHAR(20) NULL,
    [appareil] VARCHAR(10) NULL,
    [gouvernorat_livraison_id] VARCHAR(5) NULL,
    [ville_livraison] NVARCHAR(50) NULL,
    [entrepot_id] VARCHAR(10) NULL,
    [campagne_id] VARCHAR(10) NULL,
    [code_coupon] VARCHAR(15) NULL,
    [mode_paiement] VARCHAR(30) NULL,
    [nb_lignes] TINYINT NULL,
    [nb_articles] INT NULL,
    [sous_total_ttc] DECIMAL(14,3) NULL,
    [remise_coupon_ttc] DECIMAL(14,3) NULL,
    [frais_livraison_ttc] DECIMAL(14,3) NULL,
    [montant_total_ttc] DECIMAL(14,3) NULL,
    [statut_commande] VARCHAR(30) NULL,
    [motif_annulation] VARCHAR(20) NULL,
    [date_annulation] DATETIME2(0) NULL,
    [est_premiere_commande] BIT NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_commandes] PRIMARY KEY CLUSTERED ([commande_id])
);
GO
-- Lignes de commandes clients
DROP TABLE IF EXISTS clean.[lignes_commande];
CREATE TABLE clean.[lignes_commande] (
    [ligne_id] VARCHAR(15) NOT NULL,
    [commande_id] VARCHAR(12) NULL,
    [num_ligne] TINYINT NULL,
    [produit_id] VARCHAR(10) NULL,
    [quantite] INT NULL,
    [prix_catalogue_ttc] DECIMAL(14,3) NULL,
    [remise_promo_unitaire_ttc] DECIMAL(14,3) NULL,
    [prix_unitaire_ttc] DECIMAL(14,3) NULL,
    [taux_tva] TINYINT NULL,
    [montant_ligne_ttc] DECIMAL(14,3) NULL,
    [montant_ligne_ht] DECIMAL(14,3) NULL,
    [montant_tva] DECIMAL(14,3) NULL,
    [cout_achat_unitaire_ht] DECIMAL(14,3) NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_lignes_commande] PRIMARY KEY CLUSTERED ([ligne_id])
);
GO
-- Tentatives de paiement (JSON aplati)
DROP TABLE IF EXISTS clean.[paiements];
CREATE TABLE clean.[paiements] (
    [paiement_id] VARCHAR(12) NOT NULL,
    [commande_id] VARCHAR(12) NULL,
    [num_tentative] TINYINT NULL,
    [mode_paiement] VARCHAR(30) NULL,
    [montant_ttc] DECIMAL(14,3) NULL,
    [devise] CHAR(3) NULL,
    [statut_paiement] VARCHAR(20) NULL,
    [code_erreur] VARCHAR(40) NULL,
    [date_paiement] DATETIME2(0) NULL,
    [prestataire] NVARCHAR(50) NULL,
    [reference_transaction] VARCHAR(20) NULL,
    [date_reversement] DATE NULL,
    [id_chargement] INT NOT NULL,
    [date_traitement] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_clean_paiements] PRIMARY KEY CLUSTERED ([paiement_id])
);
GO
-- Vues des lignes actives (est_supprime = 0) : lues par STG_INTEGRATED
CREATE OR ALTER VIEW clean.[v_categories] AS SELECT * FROM clean.[categories] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_fournisseurs] AS SELECT * FROM clean.[fournisseurs] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_produits] AS SELECT * FROM clean.[produits] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_produits_prix_historique] AS SELECT * FROM clean.[produits_prix_historique] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_clients] AS SELECT * FROM clean.[clients] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_entrepots] AS SELECT * FROM clean.[entrepots] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_transporteurs] AS SELECT * FROM clean.[transporteurs] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_livraisons] AS SELECT * FROM clean.[livraisons] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_campagnes_marketing] AS SELECT * FROM clean.[campagnes_marketing] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_coupons] AS SELECT * FROM clean.[coupons] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_marketing_depenses_quotidiennes] AS SELECT * FROM clean.[marketing_depenses_quotidiennes] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_dim_calendrier] AS SELECT * FROM clean.[dim_calendrier] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_ref_gouvernorats] AS SELECT * FROM clean.[ref_gouvernorats] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_remboursements] AS SELECT * FROM clean.[remboursements] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_mouvements_stock] AS SELECT * FROM clean.[mouvements_stock] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_stocks_mensuels] AS SELECT * FROM clean.[stocks_mensuels] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_commandes_fournisseurs] AS SELECT * FROM clean.[commandes_fournisseurs] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_lignes_commande_fournisseur] AS SELECT * FROM clean.[lignes_commande_fournisseur] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_avis_clients] AS SELECT * FROM clean.[avis_clients] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_commandes] AS SELECT * FROM clean.[commandes] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_lignes_commande] AS SELECT * FROM clean.[lignes_commande] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW clean.[v_paiements] AS SELECT * FROM clean.[paiements] WHERE est_supprime = 0;
GO
/* ---------------------------------------------------------------------
   4. TuniShop_STG_INTEGRATED — schéma integ
   Entités conformées : client maître (dédoublonnage), intégrité référentielle
   résolue, indicateurs dérivés. Clés étrangères déclarées entre tables integ.
   --------------------------------------------------------------------- */
USE [TuniShop_STG_INTEGRATED];
GO
IF SCHEMA_ID(N'integ') IS NULL EXEC (N'CREATE SCHEMA integ AUTHORIZATION dbo;');
GO
DROP TABLE IF EXISTS integ.rejets;
CREATE TABLE integ.rejets (
    [rejet_id] BIGINT IDENTITY(1,1) NOT NULL,
    [id_chargement] INT NOT NULL,
    [table_source] SYSNAME NOT NULL,
    [cle_enregistrement] NVARCHAR(100) NULL,
    [colonne] SYSNAME NULL,
    [valeur_recue] NVARCHAR(4000) NULL,
    [regle_id] VARCHAR(10) NOT NULL,
    [niveau] VARCHAR(12) NOT NULL,
    [message] NVARCHAR(400) NULL,
    [date_rejet] DATETIME2(0) NOT NULL CONSTRAINT DF_integ_rejets_date DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_integ_rejets PRIMARY KEY CLUSTERED (rejet_id)
);
GO
-- Suppression dans l'ordre inverse des dépendances
DROP TABLE IF EXISTS integ.[stock_mensuel];
DROP TABLE IF EXISTS integ.[mouvement_stock];
DROP TABLE IF EXISTS integ.[ligne_commande_fournisseur];
DROP TABLE IF EXISTS integ.[commande_fournisseur];
DROP TABLE IF EXISTS integ.[avis];
DROP TABLE IF EXISTS integ.[remboursement];
DROP TABLE IF EXISTS integ.[livraison];
DROP TABLE IF EXISTS integ.[paiement];
DROP TABLE IF EXISTS integ.[ligne_commande];
DROP TABLE IF EXISTS integ.[commande];
DROP TABLE IF EXISTS integ.[depense_marketing];
DROP TABLE IF EXISTS integ.[coupon];
DROP TABLE IF EXISTS integ.[campagne];
DROP TABLE IF EXISTS integ.[calendrier];
DROP TABLE IF EXISTS integ.[produit_version_prix];
DROP TABLE IF EXISTS integ.[produit];
DROP TABLE IF EXISTS integ.[fournisseur];
DROP TABLE IF EXISTS integ.[transporteur];
DROP TABLE IF EXISTS integ.[entrepot];
DROP TABLE IF EXISTS integ.[geographie];
DROP TABLE IF EXISTS integ.[client];
DROP TABLE IF EXISTS integ.[client_correspondance];
GO
-- Table de correspondance identifiant source → client maître (résolution d'identité) — grain : 1 ligne par client_id source
CREATE TABLE integ.[client_correspondance] (
    [client_id_source] VARCHAR(12) NOT NULL,
    [client_id_maitre] VARCHAR(12) NOT NULL,
    [methode_rapprochement] VARCHAR(30) NOT NULL,
    [est_doublon] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_client_correspondance] PRIMARY KEY CLUSTERED ([client_id_source])
);
GO
-- Clients maîtres dédoublonnés et enrichis — grain : 1 ligne par client maître
CREATE TABLE integ.[client] (
    [client_id] VARCHAR(12) NOT NULL,
    [type_client] VARCHAR(15) NOT NULL,
    [prenom] NVARCHAR(50) NULL,
    [nom] NVARCHAR(50) NULL,
    [nom_complet] NVARCHAR(150) NULL,
    [genre] CHAR(1) NULL,
    [genre_impute] BIT NOT NULL,
    [date_naissance] DATE NULL,
    [raison_sociale] NVARCHAR(100) NULL,
    [matricule_fiscal] VARCHAR(20) NULL,
    [email] NVARCHAR(100) NULL,
    [telephone] VARCHAR(16) NULL,
    [gouvernorat_id] VARCHAR(5) NOT NULL,
    [ville] NVARCHAR(50) NULL,
    [date_inscription] DATETIME2(0) NOT NULL,
    [canal_inscription] VARCHAR(30) NULL,
    [campagne_acquisition_id] VARCHAR(10) NULL,
    [opt_in_email] BIT NOT NULL,
    [opt_in_sms] BIT NOT NULL,
    [segment_fidelite] VARCHAR(10) NOT NULL,
    [tranche_age] VARCHAR(10) NULL,
    [nb_identifiants_fusionnes] TINYINT NOT NULL,
    [date_premiere_commande] DATETIME2(0) NULL,
    [date_derniere_commande] DATETIME2(0) NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_client] PRIMARY KEY CLUSTERED ([client_id])
);
GO
-- Gouvernorats, régions, zones et entrepôt de rattachement — grain : 1 ligne par gouvernorat
CREATE TABLE integ.[geographie] (
    [gouvernorat_id] VARCHAR(5) NOT NULL,
    [gouvernorat] NVARCHAR(50) NOT NULL,
    [region] NVARCHAR(50) NOT NULL,
    [zone_livraison] VARCHAR(5) NOT NULL,
    [entrepot_rattachement_id] VARCHAR(5) NOT NULL,
    [nom_entrepot_rattachement] NVARCHAR(50) NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_geographie] PRIMARY KEY CLUSTERED ([gouvernorat_id])
);
GO
-- Entrepôts — grain : 1 ligne par entrepôt
CREATE TABLE integ.[entrepot] (
    [entrepot_id] VARCHAR(5) NOT NULL,
    [nom_entrepot] NVARCHAR(50) NOT NULL,
    [ville] NVARCHAR(50) NOT NULL,
    [gouvernorat_id] VARCHAR(5) NOT NULL,
    [region] NVARCHAR(50) NOT NULL,
    [date_ouverture] DATE NOT NULL,
    [surface_m2] SMALLINT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_entrepot] PRIMARY KEY CLUSTERED ([entrepot_id])
);
GO
-- Transporteurs — grain : 1 ligne par transporteur
CREATE TABLE integ.[transporteur] (
    [transporteur_id] VARCHAR(5) NOT NULL,
    [nom_transporteur] NVARCHAR(50) NOT NULL,
    [couverture] NVARCHAR(50) NOT NULL,
    [cout_base_ht] DECIMAL(14,3) NOT NULL,
    [ecart_delai_moyen_j] DECIMAL(5,2) NOT NULL,
    [date_debut_contrat] DATE NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_transporteur] PRIMARY KEY CLUSTERED ([transporteur_id])
);
GO
-- Fournisseurs — grain : 1 ligne par fournisseur
CREATE TABLE integ.[fournisseur] (
    [fournisseur_id] VARCHAR(10) NOT NULL,
    [nom_fournisseur] NVARCHAR(100) NOT NULL,
    [pays] NVARCHAR(50) NOT NULL,
    [est_local] BIT NOT NULL,
    [delai_appro_moyen_j] SMALLINT NOT NULL,
    [conditions_paiement] NVARCHAR(100) NOT NULL,
    [fiabilite_livraison] DECIMAL(5,2) NOT NULL,
    [email_contact] NVARCHAR(100) NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_fournisseur] PRIMARY KEY CLUSTERED ([fournisseur_id])
);
GO
-- Produits conformés avec leur catégorie — grain : 1 ligne par produit
CREATE TABLE integ.[produit] (
    [produit_id] VARCHAR(10) NOT NULL,
    [sku] VARCHAR(15) NOT NULL,
    [nom_produit] NVARCHAR(100) NOT NULL,
    [marque] NVARCHAR(50) NOT NULL,
    [categorie_id] VARCHAR(5) NOT NULL,
    [categorie] NVARCHAR(50) NOT NULL,
    [sous_categorie] NVARCHAR(50) NOT NULL,
    [taux_retour_cible] DECIMAL(5,2) NOT NULL,
    [marge_brute_cible] DECIMAL(5,2) NOT NULL,
    [fournisseur_id] VARCHAR(10) NOT NULL,
    [taux_tva] TINYINT NOT NULL,
    [poids_kg] DECIMAL(8,2) NOT NULL,
    [date_lancement] DATE NOT NULL,
    [date_arret] DATE NULL,
    [statut_produit] VARCHAR(10) NOT NULL,
    [prix_catalogue_ttc_actuel] DECIMAL(14,3) NOT NULL,
    [cout_achat_unitaire_ht_actuel] DECIMAL(14,3) NOT NULL,
    [gamme_prix] VARCHAR(15) NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_produit] PRIMARY KEY CLUSTERED ([produit_id]),
    CONSTRAINT [UQ_integ_produit_sku] UNIQUE ([sku])
);
GO
-- Versions de prix datées (préparation SCD2) — grain : 1 ligne par produit et période de prix
CREATE TABLE integ.[produit_version_prix] (
    [prix_id] VARCHAR(10) NOT NULL,
    [produit_id] VARCHAR(10) NOT NULL,
    [date_debut] DATE NOT NULL,
    [date_fin] DATE NOT NULL,
    [prix_catalogue_ttc] DECIMAL(14,3) NOT NULL,
    [prix_catalogue_ht] DECIMAL(14,3) NOT NULL,
    [cout_achat_unitaire_ht] DECIMAL(14,3) NOT NULL,
    [taux_marge_theorique] DECIMAL(7,4) NULL,
    [num_version] TINYINT NOT NULL,
    [est_prix_actuel] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_produit_version_prix] PRIMARY KEY CLUSTERED ([prix_id])
);
GO
-- Calendrier conformé — grain : 1 ligne par jour
CREATE TABLE integ.[calendrier] (
    [date] DATE NOT NULL,
    [annee] SMALLINT NOT NULL,
    [trimestre] TINYINT NOT NULL,
    [mois] TINYINT NOT NULL,
    [nom_mois] NVARCHAR(10) NOT NULL,
    [semaine_iso] TINYINT NOT NULL,
    [jour_semaine] TINYINT NOT NULL,
    [nom_jour] NVARCHAR(10) NOT NULL,
    [est_weekend] BIT NOT NULL,
    [est_jour_ferie] BIT NOT NULL,
    [nom_jour_ferie] NVARCHAR(50) NULL,
    [est_ramadan] BIT NOT NULL,
    [periode_commerciale] VARCHAR(20) NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_calendrier] PRIMARY KEY CLUSTERED ([date])
);
GO
-- Campagnes marketing — grain : 1 ligne par campagne
CREATE TABLE integ.[campagne] (
    [campagne_id] VARCHAR(10) NOT NULL,
    [nom_campagne] NVARCHAR(100) NOT NULL,
    [canal] VARCHAR(15) NOT NULL,
    [type_canal] VARCHAR(15) NOT NULL,
    [objectif] VARCHAR(15) NOT NULL,
    [theme] VARCHAR(15) NOT NULL,
    [categorie_ciblee_id] VARCHAR(5) NULL,
    [code_coupon] VARCHAR(15) NULL,
    [date_debut] DATE NOT NULL,
    [date_fin] DATE NOT NULL,
    [duree_jours] SMALLINT NOT NULL,
    [budget_ht] DECIMAL(14,3) NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_campagne] PRIMARY KEY CLUSTERED ([campagne_id])
);
GO
-- Coupons — grain : 1 ligne par code
CREATE TABLE integ.[coupon] (
    [code_coupon] VARCHAR(15) NOT NULL,
    [type_remise] VARCHAR(15) NOT NULL,
    [valeur] DECIMAL(10,2) NOT NULL,
    [montant_min_ttc] DECIMAL(14,3) NOT NULL,
    [plafond_remise_ttc] DECIMAL(14,3) NULL,
    [date_debut] DATE NOT NULL,
    [date_fin] DATE NULL,
    [campagne_id] VARCHAR(10) NULL,
    [reserve_premiere_commande] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_coupon] PRIMARY KEY CLUSTERED ([code_coupon])
);
GO
-- Dépenses et performances quotidiennes rattachées — grain : 1 ligne par campagne et jour
CREATE TABLE integ.[depense_marketing] (
    [depense_id] VARCHAR(10) NOT NULL,
    [campagne_id] VARCHAR(10) NULL,
    [campagne_id_source] VARCHAR(10) NOT NULL,
    [date] DATE NOT NULL,
    [canal] VARCHAR(15) NOT NULL,
    [depense_ht] DECIMAL(14,3) NOT NULL,
    [impressions] INT NULL,
    [clics] INT NOT NULL,
    [commandes_attribuees] INT NOT NULL,
    [nouveaux_clients_attribues] INT NOT NULL,
    [ca_attribue_ttc] DECIMAL(14,3) NOT NULL,
    [est_rattachement_corrige] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_depense_marketing] PRIMARY KEY CLUSTERED ([depense_id])
);
GO
-- Commandes conformées (client maître, intégrité, indicateurs) — grain : 1 ligne par commande
CREATE TABLE integ.[commande] (
    [commande_id] VARCHAR(10) NOT NULL,
    [client_id] VARCHAR(12) NULL,
    [client_id_source] VARCHAR(12) NOT NULL,
    [date_commande] DATETIME2(0) NOT NULL,
    [canal] VARCHAR(20) NOT NULL,
    [appareil] VARCHAR(10) NOT NULL,
    [gouvernorat_livraison_id] VARCHAR(5) NOT NULL,
    [ville_livraison] NVARCHAR(50) NULL,
    [entrepot_id] VARCHAR(5) NULL,
    [campagne_id] VARCHAR(10) NULL,
    [code_coupon] VARCHAR(15) NULL,
    [mode_paiement] VARCHAR(30) NOT NULL,
    [nb_lignes] TINYINT NOT NULL,
    [nb_articles] INT NOT NULL,
    [sous_total_ttc] DECIMAL(14,3) NOT NULL,
    [sous_total_ht] DECIMAL(14,3) NOT NULL,
    [remise_coupon_ttc] DECIMAL(14,3) NOT NULL,
    [frais_livraison_ttc] DECIMAL(14,3) NOT NULL,
    [montant_total_ttc] DECIMAL(14,3) NOT NULL,
    [cout_achat_total_ht] DECIMAL(14,3) NOT NULL,
    [statut_commande] VARCHAR(30) NOT NULL,
    [motif_annulation] VARCHAR(30) NULL,
    [date_annulation] DATETIME2(0) NULL,
    [est_premiere_commande] BIT NOT NULL,
    [est_ca_reconnu] BIT NOT NULL,
    [est_client_orphelin] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_commande] PRIMARY KEY CLUSTERED ([commande_id])
);
GO
-- Lignes de commande conformées avec marge — grain : 1 ligne par ligne de commande
CREATE TABLE integ.[ligne_commande] (
    [ligne_id] VARCHAR(12) NOT NULL,
    [commande_id] VARCHAR(10) NOT NULL,
    [num_ligne] TINYINT NOT NULL,
    [produit_id] VARCHAR(10) NULL,
    [produit_id_source] VARCHAR(10) NOT NULL,
    [quantite] INT NOT NULL,
    [prix_catalogue_ttc] DECIMAL(14,3) NOT NULL,
    [remise_promo_unitaire_ttc] DECIMAL(14,3) NOT NULL,
    [prix_unitaire_ttc] DECIMAL(14,3) NOT NULL,
    [taux_tva] TINYINT NOT NULL,
    [montant_ligne_ttc] DECIMAL(14,3) NOT NULL,
    [montant_ligne_ht] DECIMAL(14,3) NOT NULL,
    [montant_tva] DECIMAL(14,3) NOT NULL,
    [montant_remise_promo_ttc] DECIMAL(14,3) NOT NULL,
    [cout_achat_unitaire_ht] DECIMAL(14,3) NOT NULL,
    [cout_achat_total_ht] DECIMAL(14,3) NOT NULL,
    [marge_brute_ht] DECIMAL(14,3) NOT NULL,
    [est_produit_orphelin] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_ligne_commande] PRIMARY KEY CLUSTERED ([ligne_id])
);
GO
-- Tentatives de paiement rattachées — grain : 1 ligne par tentative
CREATE TABLE integ.[paiement] (
    [paiement_id] VARCHAR(12) NOT NULL,
    [commande_id] VARCHAR(10) NOT NULL,
    [num_tentative] TINYINT NOT NULL,
    [mode_paiement] VARCHAR(30) NOT NULL,
    [montant_ttc] DECIMAL(14,3) NOT NULL,
    [statut_paiement] VARCHAR(20) NOT NULL,
    [code_erreur] VARCHAR(40) NULL,
    [date_paiement] DATETIME2(0) NOT NULL,
    [prestataire] NVARCHAR(50) NOT NULL,
    [reference_transaction] VARCHAR(20) NOT NULL,
    [date_reversement] DATE NULL,
    [delai_reversement_j] SMALLINT NULL,
    [est_reussi] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_paiement] PRIMARY KEY CLUSTERED ([paiement_id])
);
GO
-- Expéditions avec délais calculés — grain : 1 ligne par expédition
CREATE TABLE integ.[livraison] (
    [livraison_id] VARCHAR(10) NOT NULL,
    [commande_id] VARCHAR(10) NOT NULL,
    [entrepot_id] VARCHAR(5) NOT NULL,
    [transporteur_id] VARCHAR(5) NOT NULL,
    [gouvernorat_destination_id] VARCHAR(5) NOT NULL,
    [date_expedition] DATETIME2(0) NULL,
    [date_livraison_prevue] DATE NOT NULL,
    [date_livraison_reelle] DATETIME2(0) NULL,
    [date_dernier_evenement] DATETIME2(0) NULL,
    [statut_livraison] VARCHAR(30) NOT NULL,
    [nb_tentatives] TINYINT NULL,
    [poids_kg] DECIMAL(8,2) NOT NULL,
    [cout_transport_ht] DECIMAL(14,3) NOT NULL,
    [delai_preparation_h] DECIMAL(8,2) NULL,
    [delai_livraison_j] DECIMAL(8,2) NULL,
    [retard_j] SMALLINT NULL,
    [est_livree_a_temps] BIT NULL,
    [est_premiere_tentative] BIT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_livraison] PRIMARY KEY CLUSTERED ([livraison_id])
);
GO
-- Remboursements conformés — grain : 1 ligne par remboursement
CREATE TABLE integ.[remboursement] (
    [remboursement_id] VARCHAR(10) NOT NULL,
    [commande_id] VARCHAR(10) NOT NULL,
    [ligne_id] VARCHAR(12) NULL,
    [produit_id] VARCHAR(10) NULL,
    [type_remboursement] VARCHAR(20) NOT NULL,
    [motif] VARCHAR(50) NOT NULL,
    [quantite] INT NULL,
    [montant_demande_ttc] DECIMAL(14,3) NOT NULL,
    [montant_rembourse_ttc] DECIMAL(14,3) NOT NULL,
    [date_demande] DATETIME2(0) NOT NULL,
    [date_reception_retour] DATETIME2(0) NULL,
    [date_remboursement] DATETIME2(0) NULL,
    [delai_traitement_j] DECIMAL(8,2) NULL,
    [mode_remboursement] VARCHAR(30) NOT NULL,
    [statut] VARCHAR(15) NOT NULL,
    [etat_article] VARCHAR(20) NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_remboursement] PRIMARY KEY CLUSTERED ([remboursement_id])
);
GO
-- Avis clients rattachés au client maître — grain : 1 ligne par avis
CREATE TABLE integ.[avis] (
    [avis_id] VARCHAR(10) NOT NULL,
    [commande_id] VARCHAR(10) NOT NULL,
    [ligne_id] VARCHAR(12) NOT NULL,
    [produit_id] VARCHAR(10) NOT NULL,
    [client_id] VARCHAR(12) NOT NULL,
    [date_avis] DATETIME2(0) NOT NULL,
    [note] TINYINT NULL,
    [commentaire] NVARCHAR(500) NULL,
    [a_commentaire] BIT NOT NULL,
    [sentiment] VARCHAR(10) NULL,
    [achat_verifie] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_avis] PRIMARY KEY CLUSTERED ([avis_id])
);
GO
-- Commandes fournisseurs — grain : 1 ligne par commande fournisseur
CREATE TABLE integ.[commande_fournisseur] (
    [commande_fournisseur_id] VARCHAR(10) NOT NULL,
    [fournisseur_id] VARCHAR(10) NOT NULL,
    [entrepot_id] VARCHAR(5) NOT NULL,
    [date_commande] DATETIME2(0) NOT NULL,
    [date_livraison_prevue] DATE NOT NULL,
    [date_reception] DATETIME2(0) NULL,
    [statut] VARCHAR(30) NOT NULL,
    [montant_total_ht] DECIMAL(14,3) NOT NULL,
    [delai_appro_reel_j] SMALLINT NULL,
    [retard_appro_j] SMALLINT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_commande_fournisseur] PRIMARY KEY CLUSTERED ([commande_fournisseur_id])
);
GO
-- Lignes de commandes fournisseurs — grain : 1 ligne par ligne fournisseur
CREATE TABLE integ.[ligne_commande_fournisseur] (
    [ligne_cf_id] VARCHAR(12) NOT NULL,
    [commande_fournisseur_id] VARCHAR(10) NOT NULL,
    [produit_id] VARCHAR(10) NOT NULL,
    [quantite_commandee] INT NOT NULL,
    [quantite_recue] INT NULL,
    [taux_service] DECIMAL(7,4) NULL,
    [cout_unitaire_ht] DECIMAL(14,3) NOT NULL,
    [montant_ligne_ht] DECIMAL(14,3) NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_ligne_commande_fournisseur] PRIMARY KEY CLUSTERED ([ligne_cf_id])
);
GO
-- Mouvements de stock signés — grain : 1 ligne par mouvement
CREATE TABLE integ.[mouvement_stock] (
    [mouvement_id] VARCHAR(12) NOT NULL,
    [date_mouvement] DATETIME2(0) NOT NULL,
    [produit_id] VARCHAR(10) NOT NULL,
    [entrepot_id] VARCHAR(5) NOT NULL,
    [type_mouvement] VARCHAR(30) NOT NULL,
    [sens] CHAR(1) NOT NULL,
    [quantite] INT NOT NULL,
    [reference_id] VARCHAR(20) NULL,
    [cout_unitaire_ht] DECIMAL(14,3) NOT NULL,
    [valeur_mouvement_ht] DECIMAL(16,3) NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_mouvement_stock] PRIMARY KEY CLUSTERED ([mouvement_id])
);
GO
-- Inventaires de fin de mois — grain : 1 ligne par produit, entrepôt et mois
CREATE TABLE integ.[stock_mensuel] (
    [inventaire_id] VARCHAR(12) NOT NULL,
    [date_inventaire] DATE NOT NULL,
    [produit_id] VARCHAR(10) NOT NULL,
    [entrepot_id] VARCHAR(5) NOT NULL,
    [stock_fin_mois] INT NOT NULL,
    [quantite_en_commande] INT NOT NULL,
    [cout_unitaire_ht] DECIMAL(14,3) NOT NULL,
    [valeur_stock_ht] DECIMAL(16,3) NOT NULL,
    [est_rupture] BIT NOT NULL,
    [id_chargement] INT NOT NULL,
    [date_integration] DATETIME2(0) NOT NULL,
    [date_creation] DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    [hash_ligne] BINARY(32) NULL,
    [est_supprime] BIT NOT NULL DEFAULT (0),
    CONSTRAINT [PK_integ_stock_mensuel] PRIMARY KEY CLUSTERED ([inventaire_id])
);
GO
-- Clés étrangères et index de jointure
ALTER TABLE integ.[client] WITH CHECK ADD CONSTRAINT [FK_client_gouvernorat_id] FOREIGN KEY ([gouvernorat_id]) REFERENCES integ.[geographie] ([gouvernorat_id]);
CREATE INDEX [IX_integ_client_gouvernorat_id] ON integ.[client] ([gouvernorat_id]);
ALTER TABLE integ.[client] WITH CHECK ADD CONSTRAINT [FK_client_campagne_acquisition_id] FOREIGN KEY ([campagne_acquisition_id]) REFERENCES integ.[campagne] ([campagne_id]);
CREATE INDEX [IX_integ_client_campagne_acquisition_id] ON integ.[client] ([campagne_acquisition_id]);
ALTER TABLE integ.[entrepot] WITH CHECK ADD CONSTRAINT [FK_entrepot_gouvernorat_id] FOREIGN KEY ([gouvernorat_id]) REFERENCES integ.[geographie] ([gouvernorat_id]);
CREATE INDEX [IX_integ_entrepot_gouvernorat_id] ON integ.[entrepot] ([gouvernorat_id]);
ALTER TABLE integ.[produit] WITH CHECK ADD CONSTRAINT [FK_produit_fournisseur_id] FOREIGN KEY ([fournisseur_id]) REFERENCES integ.[fournisseur] ([fournisseur_id]);
CREATE INDEX [IX_integ_produit_fournisseur_id] ON integ.[produit] ([fournisseur_id]);
ALTER TABLE integ.[produit_version_prix] WITH CHECK ADD CONSTRAINT [FK_produit_version_prix_produit_id] FOREIGN KEY ([produit_id]) REFERENCES integ.[produit] ([produit_id]);
CREATE INDEX [IX_integ_produit_version_prix_produit_id] ON integ.[produit_version_prix] ([produit_id]);
ALTER TABLE integ.[campagne] WITH CHECK ADD CONSTRAINT [FK_campagne_code_coupon] FOREIGN KEY ([code_coupon]) REFERENCES integ.[coupon] ([code_coupon]);
CREATE INDEX [IX_integ_campagne_code_coupon] ON integ.[campagne] ([code_coupon]);
ALTER TABLE integ.[coupon] WITH CHECK ADD CONSTRAINT [FK_coupon_campagne_id] FOREIGN KEY ([campagne_id]) REFERENCES integ.[campagne] ([campagne_id]);
CREATE INDEX [IX_integ_coupon_campagne_id] ON integ.[coupon] ([campagne_id]);
ALTER TABLE integ.[depense_marketing] WITH CHECK ADD CONSTRAINT [FK_depense_marketing_campagne_id] FOREIGN KEY ([campagne_id]) REFERENCES integ.[campagne] ([campagne_id]);
CREATE INDEX [IX_integ_depense_marketing_campagne_id] ON integ.[depense_marketing] ([campagne_id]);
ALTER TABLE integ.[depense_marketing] WITH CHECK ADD CONSTRAINT [FK_depense_marketing_date] FOREIGN KEY ([date]) REFERENCES integ.[calendrier] ([date]);
CREATE INDEX [IX_integ_depense_marketing_date] ON integ.[depense_marketing] ([date]);
ALTER TABLE integ.[commande] WITH CHECK ADD CONSTRAINT [FK_commande_client_id] FOREIGN KEY ([client_id]) REFERENCES integ.[client] ([client_id]);
CREATE INDEX [IX_integ_commande_client_id] ON integ.[commande] ([client_id]);
ALTER TABLE integ.[commande] WITH CHECK ADD CONSTRAINT [FK_commande_gouvernorat_livraison_id] FOREIGN KEY ([gouvernorat_livraison_id]) REFERENCES integ.[geographie] ([gouvernorat_id]);
CREATE INDEX [IX_integ_commande_gouvernorat_livraison_id] ON integ.[commande] ([gouvernorat_livraison_id]);
ALTER TABLE integ.[commande] WITH CHECK ADD CONSTRAINT [FK_commande_entrepot_id] FOREIGN KEY ([entrepot_id]) REFERENCES integ.[entrepot] ([entrepot_id]);
CREATE INDEX [IX_integ_commande_entrepot_id] ON integ.[commande] ([entrepot_id]);
ALTER TABLE integ.[commande] WITH CHECK ADD CONSTRAINT [FK_commande_campagne_id] FOREIGN KEY ([campagne_id]) REFERENCES integ.[campagne] ([campagne_id]);
CREATE INDEX [IX_integ_commande_campagne_id] ON integ.[commande] ([campagne_id]);
ALTER TABLE integ.[commande] WITH CHECK ADD CONSTRAINT [FK_commande_code_coupon] FOREIGN KEY ([code_coupon]) REFERENCES integ.[coupon] ([code_coupon]);
CREATE INDEX [IX_integ_commande_code_coupon] ON integ.[commande] ([code_coupon]);
ALTER TABLE integ.[ligne_commande] WITH CHECK ADD CONSTRAINT [FK_ligne_commande_commande_id] FOREIGN KEY ([commande_id]) REFERENCES integ.[commande] ([commande_id]);
CREATE INDEX [IX_integ_ligne_commande_commande_id] ON integ.[ligne_commande] ([commande_id]);
ALTER TABLE integ.[ligne_commande] WITH CHECK ADD CONSTRAINT [FK_ligne_commande_produit_id] FOREIGN KEY ([produit_id]) REFERENCES integ.[produit] ([produit_id]);
CREATE INDEX [IX_integ_ligne_commande_produit_id] ON integ.[ligne_commande] ([produit_id]);
ALTER TABLE integ.[paiement] WITH CHECK ADD CONSTRAINT [FK_paiement_commande_id] FOREIGN KEY ([commande_id]) REFERENCES integ.[commande] ([commande_id]);
CREATE INDEX [IX_integ_paiement_commande_id] ON integ.[paiement] ([commande_id]);
ALTER TABLE integ.[livraison] WITH CHECK ADD CONSTRAINT [FK_livraison_commande_id] FOREIGN KEY ([commande_id]) REFERENCES integ.[commande] ([commande_id]);
CREATE INDEX [IX_integ_livraison_commande_id] ON integ.[livraison] ([commande_id]);
ALTER TABLE integ.[livraison] WITH CHECK ADD CONSTRAINT [FK_livraison_entrepot_id] FOREIGN KEY ([entrepot_id]) REFERENCES integ.[entrepot] ([entrepot_id]);
CREATE INDEX [IX_integ_livraison_entrepot_id] ON integ.[livraison] ([entrepot_id]);
ALTER TABLE integ.[livraison] WITH CHECK ADD CONSTRAINT [FK_livraison_transporteur_id] FOREIGN KEY ([transporteur_id]) REFERENCES integ.[transporteur] ([transporteur_id]);
CREATE INDEX [IX_integ_livraison_transporteur_id] ON integ.[livraison] ([transporteur_id]);
ALTER TABLE integ.[livraison] WITH CHECK ADD CONSTRAINT [FK_livraison_gouvernorat_destination_id] FOREIGN KEY ([gouvernorat_destination_id]) REFERENCES integ.[geographie] ([gouvernorat_id]);
CREATE INDEX [IX_integ_livraison_gouvernorat_destination_id] ON integ.[livraison] ([gouvernorat_destination_id]);
ALTER TABLE integ.[remboursement] WITH CHECK ADD CONSTRAINT [FK_remboursement_commande_id] FOREIGN KEY ([commande_id]) REFERENCES integ.[commande] ([commande_id]);
CREATE INDEX [IX_integ_remboursement_commande_id] ON integ.[remboursement] ([commande_id]);
ALTER TABLE integ.[remboursement] WITH CHECK ADD CONSTRAINT [FK_remboursement_ligne_id] FOREIGN KEY ([ligne_id]) REFERENCES integ.[ligne_commande] ([ligne_id]);
CREATE INDEX [IX_integ_remboursement_ligne_id] ON integ.[remboursement] ([ligne_id]);
ALTER TABLE integ.[remboursement] WITH CHECK ADD CONSTRAINT [FK_remboursement_produit_id] FOREIGN KEY ([produit_id]) REFERENCES integ.[produit] ([produit_id]);
CREATE INDEX [IX_integ_remboursement_produit_id] ON integ.[remboursement] ([produit_id]);
ALTER TABLE integ.[avis] WITH CHECK ADD CONSTRAINT [FK_avis_commande_id] FOREIGN KEY ([commande_id]) REFERENCES integ.[commande] ([commande_id]);
CREATE INDEX [IX_integ_avis_commande_id] ON integ.[avis] ([commande_id]);
ALTER TABLE integ.[avis] WITH CHECK ADD CONSTRAINT [FK_avis_ligne_id] FOREIGN KEY ([ligne_id]) REFERENCES integ.[ligne_commande] ([ligne_id]);
CREATE INDEX [IX_integ_avis_ligne_id] ON integ.[avis] ([ligne_id]);
ALTER TABLE integ.[avis] WITH CHECK ADD CONSTRAINT [FK_avis_produit_id] FOREIGN KEY ([produit_id]) REFERENCES integ.[produit] ([produit_id]);
CREATE INDEX [IX_integ_avis_produit_id] ON integ.[avis] ([produit_id]);
ALTER TABLE integ.[avis] WITH CHECK ADD CONSTRAINT [FK_avis_client_id] FOREIGN KEY ([client_id]) REFERENCES integ.[client] ([client_id]);
CREATE INDEX [IX_integ_avis_client_id] ON integ.[avis] ([client_id]);
ALTER TABLE integ.[commande_fournisseur] WITH CHECK ADD CONSTRAINT [FK_commande_fournisseur_fournisseur_id] FOREIGN KEY ([fournisseur_id]) REFERENCES integ.[fournisseur] ([fournisseur_id]);
CREATE INDEX [IX_integ_commande_fournisseur_fournisseur_id] ON integ.[commande_fournisseur] ([fournisseur_id]);
ALTER TABLE integ.[commande_fournisseur] WITH CHECK ADD CONSTRAINT [FK_commande_fournisseur_entrepot_id] FOREIGN KEY ([entrepot_id]) REFERENCES integ.[entrepot] ([entrepot_id]);
CREATE INDEX [IX_integ_commande_fournisseur_entrepot_id] ON integ.[commande_fournisseur] ([entrepot_id]);
ALTER TABLE integ.[ligne_commande_fournisseur] WITH CHECK ADD CONSTRAINT [FK_ligne_commande_fournisseur_commande_fournisseur_id] FOREIGN KEY ([commande_fournisseur_id]) REFERENCES integ.[commande_fournisseur] ([commande_fournisseur_id]);
CREATE INDEX [IX_integ_ligne_commande_fournisseur_commande_fournisseur_id] ON integ.[ligne_commande_fournisseur] ([commande_fournisseur_id]);
ALTER TABLE integ.[ligne_commande_fournisseur] WITH CHECK ADD CONSTRAINT [FK_ligne_commande_fournisseur_produit_id] FOREIGN KEY ([produit_id]) REFERENCES integ.[produit] ([produit_id]);
CREATE INDEX [IX_integ_ligne_commande_fournisseur_produit_id] ON integ.[ligne_commande_fournisseur] ([produit_id]);
ALTER TABLE integ.[mouvement_stock] WITH CHECK ADD CONSTRAINT [FK_mouvement_stock_produit_id] FOREIGN KEY ([produit_id]) REFERENCES integ.[produit] ([produit_id]);
CREATE INDEX [IX_integ_mouvement_stock_produit_id] ON integ.[mouvement_stock] ([produit_id]);
ALTER TABLE integ.[mouvement_stock] WITH CHECK ADD CONSTRAINT [FK_mouvement_stock_entrepot_id] FOREIGN KEY ([entrepot_id]) REFERENCES integ.[entrepot] ([entrepot_id]);
CREATE INDEX [IX_integ_mouvement_stock_entrepot_id] ON integ.[mouvement_stock] ([entrepot_id]);
ALTER TABLE integ.[stock_mensuel] WITH CHECK ADD CONSTRAINT [FK_stock_mensuel_date_inventaire] FOREIGN KEY ([date_inventaire]) REFERENCES integ.[calendrier] ([date]);
CREATE INDEX [IX_integ_stock_mensuel_date_inventaire] ON integ.[stock_mensuel] ([date_inventaire]);
ALTER TABLE integ.[stock_mensuel] WITH CHECK ADD CONSTRAINT [FK_stock_mensuel_produit_id] FOREIGN KEY ([produit_id]) REFERENCES integ.[produit] ([produit_id]);
CREATE INDEX [IX_integ_stock_mensuel_produit_id] ON integ.[stock_mensuel] ([produit_id]);
ALTER TABLE integ.[stock_mensuel] WITH CHECK ADD CONSTRAINT [FK_stock_mensuel_entrepot_id] FOREIGN KEY ([entrepot_id]) REFERENCES integ.[entrepot] ([entrepot_id]);
CREATE INDEX [IX_integ_stock_mensuel_entrepot_id] ON integ.[stock_mensuel] ([entrepot_id]);
GO
-- Vues des lignes actives (est_supprime = 0) : lues par les procédures INTEGRATED et par le chargement du DWH
CREATE OR ALTER VIEW integ.[v_client_correspondance] AS SELECT * FROM integ.[client_correspondance] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_client] AS SELECT * FROM integ.[client] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_geographie] AS SELECT * FROM integ.[geographie] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_entrepot] AS SELECT * FROM integ.[entrepot] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_transporteur] AS SELECT * FROM integ.[transporteur] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_fournisseur] AS SELECT * FROM integ.[fournisseur] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_produit] AS SELECT * FROM integ.[produit] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_produit_version_prix] AS SELECT * FROM integ.[produit_version_prix] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_calendrier] AS SELECT * FROM integ.[calendrier] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_campagne] AS SELECT * FROM integ.[campagne] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_coupon] AS SELECT * FROM integ.[coupon] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_depense_marketing] AS SELECT * FROM integ.[depense_marketing] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_commande] AS SELECT * FROM integ.[commande] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_ligne_commande] AS SELECT * FROM integ.[ligne_commande] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_paiement] AS SELECT * FROM integ.[paiement] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_livraison] AS SELECT * FROM integ.[livraison] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_remboursement] AS SELECT * FROM integ.[remboursement] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_avis] AS SELECT * FROM integ.[avis] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_commande_fournisseur] AS SELECT * FROM integ.[commande_fournisseur] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_ligne_commande_fournisseur] AS SELECT * FROM integ.[ligne_commande_fournisseur] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_mouvement_stock] AS SELECT * FROM integ.[mouvement_stock] WHERE est_supprime = 0;
GO
CREATE OR ALTER VIEW integ.[v_stock_mensuel] AS SELECT * FROM integ.[stock_mensuel] WHERE est_supprime = 0;
GO
/* ---------------------------------------------------------------------
   5. TuniShop_DWH — schémas (objets créés par Scripts_DWH.sql)
   --------------------------------------------------------------------- */
USE [TuniShop_DWH];
GO
IF SCHEMA_ID(N'dw')    IS NULL EXEC (N'CREATE SCHEMA dw AUTHORIZATION dbo;');
IF SCHEMA_ID(N'bi')    IS NULL EXEC (N'CREATE SCHEMA bi AUTHORIZATION dbo;');   -- vues exposées à Power BI / Tableau
GO
GO
/* ---------------------------------------------------------------------
   6. TuniShop_ADMIN — base de contrôle (schéma audit)
   Journal des exécutions de toute la chaîne (Python, procédures, SSIS),
   séparé des données : il survit à une reconstruction du staging ou du DWH.
   Objets créés par Scripts_Audit_Logs.sql.
   --------------------------------------------------------------------- */
USE [TuniShop_ADMIN];
GO
IF SCHEMA_ID(N'audit') IS NULL EXEC (N'CREATE SCHEMA audit AUTHORIZATION dbo;');
GO
PRINT N'Bases, schémas et tables de staging créés.';
GO
