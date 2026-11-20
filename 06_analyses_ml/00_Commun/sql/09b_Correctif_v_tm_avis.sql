/* =============================================================================
   TuniShop — Étape 7, version 1.5.2 : correctif de la vue pbi.v_tm_avis
   Script 09b : à exécuter UNE fois, dans SSMS (instance ABDELJAOUAD), F5.
   Auteure : Sarra Abdeljaouad

   Problème : la vue cherchait le transporteur de chaque avis ligne à ligne (OUTER APPLY ... TOP (1)),
   soit 6 081 recherches dans les livraisons du DWH : 157 s pour pbi.v_tm_avis et 132 s pour
   pbi.v_tm_avis_themes, qui la lit (export de démonstration du 20/11/2026).
   Correctif : même règle (transporteur de la 1re livraison de la commande, par livraison_id), calculée
   en une seule passe avec ROW_NUMBER, puis jointe aux avis.

   Le script prouve que le résultat ne change pas :
     1. il garde le résultat de l'ancienne vue dans une table temporaire (compter ~2 à 3 minutes) ;
     2. il remplace la vue ;
     3. il compare les deux résultats, colonne par colonne, dans les deux sens (attendu : 0 et 0) ;
     4. il mesure la durée de lecture des deux vues.
   Il peut être relancé : l'étape 1 relit alors la vue déjà corrigée, et la comparaison reste à 0.
   ============================================================================= */
USE TuniShop_ANALYTICS;
GO
SET NOCOUNT ON;

/* 1. Résultat de l'ancienne vue (lent : c'est le problème corrigé) */
IF OBJECT_ID(N'tempdb..#avant') IS NOT NULL DROP TABLE #avant;
DECLARE @t0 DATETIME2 = SYSDATETIME();
SELECT * INTO #avant FROM pbi.v_tm_avis;
PRINT N'1. Ancienne vue lue en ' + CAST(DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) / 1000.0 AS NVARCHAR(20)) + N' s ('
      + CAST(@@ROWCOUNT AS NVARCHAR(20)) + N' lignes).';
GO

/* 2. Nouvelle définition (identique à celle du script 09, version 1.5.2) */
CREATE OR ALTER VIEW pbi.v_tm_avis
AS
-- Transporteur de la 1re livraison de chaque commande (plus petit livraison_id dont le transporteur est connu),
-- calculé une seule fois pour toutes les commandes, puis joint aux avis (v1.5.2 : remplace un OUTER APPLY ligne à ligne).
WITH premiere_livraison AS (
    SELECT l.commande_id, t.nom_transporteur,
           ROW_NUMBER() OVER (PARTITION BY l.commande_id ORDER BY l.livraison_id) AS rang
    FROM TuniShop_DWH.bi.v_fact_livraisons AS l
    JOIN TuniShop_DWH.bi.v_dim_transporteur AS t ON t.transporteur_sk = l.transporteur_sk
)
SELECT a.avis_id, a.commande_id, a.client_sk, c.client_id, a.produit_id, a.categorie,
       a.date_avis, a.note, a.sentiment_dwh, a.langue, a.texte_nettoye, a.texte_fr,
       a.themes, a.nb_themes, a.polarite_globale, a.coherence,
       tr.nom_transporteur AS transporteur
FROM ana.tm_avis AS a
LEFT JOIN TuniShop_DWH.bi.v_dim_client AS c ON c.client_sk = a.client_sk
LEFT JOIN premiere_livraison AS tr ON tr.commande_id = a.commande_id AND tr.rang = 1;
GO
PRINT N'2. Vue pbi.v_tm_avis remplacée.';
GO

/* 3 et 4. Comparaison et durées */
SET NOCOUNT ON;
DECLARE @t1 DATETIME2 = SYSDATETIME();
IF OBJECT_ID(N'tempdb..#apres') IS NOT NULL DROP TABLE #apres;
SELECT * INTO #apres FROM pbi.v_tm_avis;
DECLARE @duree_avis DECIMAL(9, 2) = DATEDIFF(MILLISECOND, @t1, SYSDATETIME()) / 1000.0;

DECLARE @t2 DATETIME2 = SYSDATETIME();
DECLARE @themes INT = (SELECT COUNT(*) FROM pbi.v_tm_avis_themes);
DECLARE @duree_themes DECIMAL(9, 2) = DATEDIFF(MILLISECOND, @t2, SYSDATETIME()) / 1000.0;

-- texte_nettoye et texte_fr sont comparés tels quels (NVARCHAR) : EXCEPT les traite comme les autres colonnes
SELECT N'C1 lignes : ancienne / nouvelle'            AS controle,
       CONCAT((SELECT COUNT(*) FROM #avant), N' / ', (SELECT COUNT(*) FROM #apres)) AS resultat,
       N'égales (6 081)' AS attendu
UNION ALL
SELECT N'C2 lignes de l''ancienne absentes de la nouvelle',
       CAST((SELECT COUNT(*) FROM (SELECT * FROM #avant EXCEPT SELECT * FROM #apres) AS x) AS NVARCHAR(20)), N'0'
UNION ALL
SELECT N'C3 lignes de la nouvelle absentes de l''ancienne',
       CAST((SELECT COUNT(*) FROM (SELECT * FROM #apres EXCEPT SELECT * FROM #avant) AS x) AS NVARCHAR(20)), N'0'
UNION ALL
SELECT N'C4 avis avec transporteur : ancienne / nouvelle',
       CONCAT((SELECT COUNT(transporteur) FROM #avant), N' / ', (SELECT COUNT(transporteur) FROM #apres)), N'égaux'
UNION ALL
SELECT N'C5 durée de pbi.v_tm_avis (s)', CAST(@duree_avis AS NVARCHAR(20)), N'quelques secondes (157 s avant)'
UNION ALL
SELECT N'C6 durée de pbi.v_tm_avis_themes (s)', CONCAT(@duree_themes, N' (', @themes, N' lignes)'),
       N'quelques secondes (132 s avant)';
GO
DROP TABLE IF EXISTS #avant;
DROP TABLE IF EXISTS #apres;
PRINT N'Script 09b terminé : reporter C1 à C6 dans la recette.';
GO
