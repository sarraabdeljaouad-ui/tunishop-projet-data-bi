/* =====================================================================================
   TuniShop — 08. Journal des EXÉCUTIONS des notebooks dans TuniShop_ANALYTICS
   =====================================================================================
   Auteure   : Sarra Abdeljaouad
   À lancer  : après 01 à 05 (F5 dans SSMS), sur l'instance qui porte TuniShop_ANALYTICS.
               Peut être relancé sans risque.

   Pourquoi ce script ?
     ctl.journal_publication trace ce qui a été PUBLIÉ. Un notebook en erreur ne publie rien :
     il n'y laisse donc aucune trace. ctl.journal_execution trace chaque notebook lancé par
     00_Commun/executer_analyse.py, qu'il réussisse ou non (statut, durée, message d'erreur).

   Ce que fait le script
     1. crée la table ctl.journal_execution ;
     2. crée la vue ctl.v_derniere_execution (résultat de la dernière exécution, notebook par notebook) ;
     3. donne au rôle role_publication (script 05) le droit d'y écrire.
   ===================================================================================== */

USE TuniShop_ANALYTICS;
GO

IF SCHEMA_ID(N'ctl') IS NULL
BEGIN
    RAISERROR (N'Schéma ctl absent : lance d''abord le script 01.', 16, 1);
    SET NOEXEC ON;
END
GO

-- 1. Une ligne par notebook exécuté
IF OBJECT_ID(N'ctl.journal_execution', N'U') IS NULL
CREATE TABLE ctl.journal_execution (
    id_ligne        INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_journal_execution PRIMARY KEY,
    id_execution    CHAR(15)       NOT NULL,          -- AAAAMMJJ_HHMMSS : regroupe les notebooks d'un même lancement
    phase           NVARCHAR(20)   NOT NULL,          -- eda, dm, ml, publication
    notebook        NVARCHAR(200)  NOT NULL,          -- ex. 03_Machine_Learning/02_Prevision_Ventes
    statut          NVARCHAR(10)   NOT NULL CONSTRAINT CK_journal_execution_statut
                                            CHECK (statut IN (N'OK', N'ERREUR')),
    debut           DATETIME2(0)   NOT NULL,
    fin             DATETIME2(0)   NOT NULL,
    duree_s         INT            NOT NULL,
    message         NVARCHAR(4000) NULL,              -- fin du message d'erreur (vide si OK)
    machine         NVARCHAR(128)  NULL,              -- poste qui a lancé le script
    execute_par     NVARCHAR(128)  NULL CONSTRAINT DF_journal_execution_par DEFAULT (SUSER_SNAME())
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_journal_execution_id_execution')
CREATE INDEX IX_journal_execution_id_execution ON ctl.journal_execution (id_execution);
GO

-- 2. Dernière exécution : un coup d'œil le matin
CREATE OR ALTER VIEW ctl.v_derniere_execution
AS
SELECT j.id_execution, j.phase, j.notebook, j.statut, j.debut, j.fin, j.duree_s, j.message, j.execute_par
FROM ctl.journal_execution AS j
WHERE j.id_execution = (SELECT MAX(id_execution) FROM ctl.journal_execution);
GO

-- 3. Droits : le compte du job (membre de role_publication) doit pouvoir écrire le journal
IF DATABASE_PRINCIPAL_ID(N'role_publication') IS NOT NULL
BEGIN
    GRANT SELECT, INSERT ON ctl.journal_execution TO role_publication;
    PRINT N'Droits SELECT, INSERT donnés à role_publication sur ctl.journal_execution.';
END
ELSE
    PRINT N'Rôle role_publication absent : lance le script 05 si le job tourne avec un autre compte que le tien.';
GO

-- Vérification
SELECT TOP (20) * FROM ctl.journal_execution ORDER BY id_ligne DESC;
GO

SET NOEXEC OFF;
GO
