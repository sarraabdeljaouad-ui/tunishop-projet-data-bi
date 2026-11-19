/* =====================================================================================
   TuniShop — 01. Création de la base des résultats d'analyse : TuniShop_ANALYTICS
   =====================================================================================
   Auteure   : Sarra Abdeljaouad
   Serveur   : le SQL Server qui héberge TuniShop_DWH (localhost)
   À lancer  : UNE fois, dans SSMS (F5). Le script peut être relancé sans risque :
               il ne crée que ce qui n'existe pas encore et ne supprime rien.

   Rôle de la base
     Les notebooks (EDA, data mining, machine learning) LISENT le DWH (vues bi) et ÉCRIVENT
     leurs résultats ici. Le DWH n'est jamais modifié.

   Organisation en 3 schémas
     ana  : tables de résultats, remplies par Python (module tunishop_analytics.publication)
     pbi  : vues lues par Power BI ; elles relient les résultats aux vues bi du DWH
     ctl  : contrôle (journal des publications, catalogue des tables, procédure de contrôle)

   Ordre des scripts
     01 (ce script) -> 02 tables -> 03 vues Power BI -> 04 contrôles -> 05 droits
     -> 06 lien avec TuniShop_ADMIN (facultatif) -> 07 étape du job Agent (facultatif)
   ===================================================================================== */

USE master;
GO

-- 1. La base (fichiers dans les dossiers par défaut de l'instance, comme les autres bases TuniShop)
IF DB_ID(N'TuniShop_ANALYTICS') IS NULL
BEGIN
    CREATE DATABASE TuniShop_ANALYTICS;
    PRINT N'Base TuniShop_ANALYTICS créée.';
END
ELSE
    PRINT N'Base TuniShop_ANALYTICS déjà présente : rien à créer.';
GO

-- Mode de récupération SIMPLE : les résultats se recalculent à partir du DWH,
-- inutile de garder tout l'historique du journal de transactions (la base reste petite).
ALTER DATABASE TuniShop_ANALYTICS SET RECOVERY SIMPLE;
GO

USE TuniShop_ANALYTICS;
GO

-- 2. Les trois schémas (CREATE SCHEMA doit être seul dans son lot : d'où EXEC)
IF SCHEMA_ID(N'ana') IS NULL EXEC (N'CREATE SCHEMA ana AUTHORIZATION dbo;');
IF SCHEMA_ID(N'pbi') IS NULL EXEC (N'CREATE SCHEMA pbi AUTHORIZATION dbo;');
IF SCHEMA_ID(N'ctl') IS NULL EXEC (N'CREATE SCHEMA ctl AUTHORIZATION dbo;');
GO

-- 3. Journal des publications : une ligne à chaque fois qu'un notebook remplit une table ana
IF OBJECT_ID(N'ctl.journal_publication', N'U') IS NULL
CREATE TABLE ctl.journal_publication (
    id_publication  INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_journal_publication PRIMARY KEY,
    table_sql       NVARCHAR(256) NOT NULL,          -- ex. ana.ml_pred_churn_2025
    source_fichier  NVARCHAR(400) NULL,              -- fichier écrit en même temps (06_Exports/...)
    partage         NVARCHAR(100) NULL,              -- table partagée : notebook qui a écrit ses lignes
    lignes          INT           NOT NULL,          -- lignes écrites (contrôlées par Python)
    colonnes        INT           NOT NULL,
    mode_source     NVARCHAR(10)  NOT NULL,          -- DWH (cas normal) ou TEST
    publie_le       DATETIME2(0)  NOT NULL CONSTRAINT DF_journal_publie_le DEFAULT (SYSDATETIME()),
    publie_par      NVARCHAR(128) NULL     CONSTRAINT DF_journal_publie_par DEFAULT (SUSER_SNAME())
);
GO

-- 4. Catalogue : à quoi sert chaque table de résultats (rempli par le script 02)
IF OBJECT_ID(N'ctl.catalogue_tables', N'U') IS NULL
CREATE TABLE ctl.catalogue_tables (
    table_sql     NVARCHAR(256) NOT NULL CONSTRAINT PK_catalogue_tables PRIMARY KEY,
    phase         NVARCHAR(30)  NOT NULL,            -- EDA, Data mining, Machine learning
    notebook      NVARCHAR(100) NOT NULL,            -- notebook qui produit la table
    source        NVARCHAR(400) NOT NULL,            -- fichier écrit en même temps
    cle           NVARCHAR(200) NULL,                -- clé primaire (si la table en a une)
    lien_dwh      NVARCHAR(200) NULL,                -- colonne qui relie la table au DWH
    description   NVARCHAR(400) NULL
);
GO

-- 5. Dernière publication de chaque table (utile pour Power BI : « données publiées le ... »)
CREATE OR ALTER VIEW ctl.v_derniere_publication
AS
WITH classees AS (
    SELECT j.*,
           ROW_NUMBER() OVER (PARTITION BY j.table_sql, ISNULL(j.partage, N'')
                              ORDER BY j.id_publication DESC) AS rang
    FROM ctl.journal_publication AS j
)
SELECT table_sql, partage, source_fichier, lignes, colonnes, mode_source, publie_le, publie_par
FROM classees
WHERE rang = 1;
GO

PRINT N'Étape 01 terminée : base, schémas ana / pbi / ctl, journal et catalogue prêts.';
GO
