/* =====================================================================
   15_Journaliser_Cube.sql — TuniShop — tracer le traitement du cube dans l'audit
   À exécuter une fois sur l'instance Express (base TuniShop_ADMIN).
   1. autorise la couche « CUBE » dans audit.execution_tache ;
   2. crée audit.usp_journaliser_cube, appelée par SSIS après le traitement du cube.
   ===================================================================== */
USE TuniShop_ADMIN;
GO
ALTER TABLE audit.execution_tache DROP CONSTRAINT CK_execution_tache_couche;
ALTER TABLE audit.execution_tache ADD CONSTRAINT CK_execution_tache_couche
    CHECK (couche IN ('STG_RAW','STG_CLEAN','STG_INTEGRATED','DWH','CONTROLE','CUBE'));
GO
CREATE OR ALTER PROCEDURE audit.usp_journaliser_cube
    @id_chargement INT,
    @statut VARCHAR(12) = 'SUCCES',
    @objet NVARCHAR(200) = N'TuniShop_OLAP (ProcessFull)'
AS
BEGIN
    SET NOCOUNT ON;
    IF ISNULL(@id_chargement, 0) = 0
        SELECT @id_chargement = MAX(id_chargement) FROM audit.execution_lot;
    INSERT INTO audit.execution_tache (id_chargement, couche, objet, statut)
    VALUES (@id_chargement, 'CUBE', @objet, @statut);
END;
GO
/* Vérification : dernière trace du cube
SELECT TOP (5) * FROM audit.execution_tache WHERE couche = 'CUBE' ORDER BY id_tache DESC; */
