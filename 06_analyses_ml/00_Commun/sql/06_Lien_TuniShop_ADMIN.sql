/* =====================================================================================
   TuniShop — 06. Lien avec la base de contrôle TuniShop_ADMIN (FACULTATIF)
   =====================================================================================
   Auteure   : Sarra Abdeljaouad
   À lancer  : après 01 à 05, si tu veux suivre les publications de l'analyse au même endroit
               que le reste de la chaîne (staging, DWH, cubes) : la base TuniShop_ADMIN.

   Ce que fait le script (v1.1)
     Il AJOUTE deux vues dans TuniShop_ADMIN, qui lisent les journaux de TuniShop_ANALYTICS :
       - audit.v_publication_analytics : ce qui a été PUBLIÉ (une ligne par table écrite) ;
       - audit.v_execution_analytics   : ce qui a été EXÉCUTÉ (une ligne par notebook, OK ou ERREUR).
     Aucune table existante de TuniShop_ADMIN n'est modifiée.
     Si le schéma audit n'existe pas, le script s'arrête avec un message.

   Prérequis
     - script 08 lancé (table ctl.journal_execution) ;
     - TuniShop_ADMIN et TuniShop_ANALYTICS sur la MÊME instance (requête entre deux bases) ;
     - le compte qui lit ces vues doit aussi avoir SELECT sur les tables ctl lues dans
       TuniShop_ANALYTICS (le chaînage de propriété entre bases est désactivé par défaut).
   ===================================================================================== */

-- Garde-fou : si la base ou le schéma manque, SET NOEXEC ON fait ignorer la suite du script
IF DB_ID(N'TuniShop_ADMIN') IS NULL
BEGIN
    PRINT N'Base TuniShop_ADMIN introuvable sur ce serveur : script ignoré.';
    SET NOEXEC ON;
END
ELSE IF NOT EXISTS (SELECT 1 FROM TuniShop_ADMIN.sys.schemas WHERE name = N'audit')
BEGIN
    PRINT N'Schéma audit absent de TuniShop_ADMIN : vérifie le nom du schéma de journalisation.';
    SET NOEXEC ON;
END
GO

USE TuniShop_ADMIN;
GO

-- Publications de l'analyse, au format « une ligne par table publiée »
CREATE OR ALTER VIEW audit.v_publication_analytics
AS
SELECT j.id_publication,
       N'Analyse et ML'          AS etape_chaine,
       j.table_sql               AS objet,
       j.partage,
       j.lignes,
       j.mode_source,
       j.publie_le               AS date_fin,
       j.publie_par              AS compte,
       N'TuniShop_ANALYTICS'     AS base_cible
FROM TuniShop_ANALYTICS.ctl.journal_publication AS j;
GO

-- Exécutions des notebooks : une ligne par notebook, y compris ceux en ERREUR
CREATE OR ALTER VIEW audit.v_execution_analytics
AS
SELECT e.id_ligne,
       e.id_execution,
       N'Analyse et ML'          AS etape_chaine,
       e.phase,
       e.notebook                AS objet,
       e.statut,
       e.debut                   AS date_debut,
       e.fin                     AS date_fin,
       e.duree_s,
       e.message,
       e.execute_par             AS compte,
       N'TuniShop_ANALYTICS'     AS base_cible
FROM TuniShop_ANALYTICS.ctl.journal_execution AS e;
GO

-- Exemples : dernières exécutions et publications de l'analyse, à côté de tes autres contrôles de la nuit
SELECT TOP (20) * FROM audit.v_execution_analytics ORDER BY id_ligne DESC;
SELECT TOP (10) * FROM audit.v_publication_analytics ORDER BY id_publication DESC;

-- Le matin : la dernière exécution a-t-elle eu une erreur ?
SELECT objet, statut, date_fin, message
FROM audit.v_execution_analytics
WHERE id_execution = (SELECT MAX(id_execution) FROM audit.v_execution_analytics)
  AND statut = N'ERREUR';
GO

SET NOEXEC OFF;   -- remet l'exécution normale (utile si le garde-fou s'est déclenché)
GO
