/* =====================================================================================
   TuniShop — 04. Contrôles de la base TuniShop_ANALYTICS
   =====================================================================================
   Auteure   : Sarra Abdeljaouad
   À lancer  : après 01 à 03 (crée la procédure), puis à chaque fois que tu veux vérifier :
                   EXEC ctl.usp_controler_publication;
               Le notebook 03_Machine_Learning/07_Publication_Resultats l'exécute aussi.

   Ce que la procédure vérifie (statut OK attendu partout)
     L1-L8  liens avec le DWH : aucune clé des résultats absente du DWH (0 orpheline),
            comme le contrôle C08 de l'EDA (une clé étrangère entre deux bases est impossible)
     H1     l'historique du suivi contient la dernière exécution (autant de lignes que ana.ml_suivi), v1.5
     N1     chaque table ana contient le nombre de lignes noté dans le journal à sa dernière publication
     P1     toutes les tables du catalogue ont été publiées au moins une fois
   ===================================================================================== */

USE TuniShop_ANALYTICS;
GO

CREATE OR ALTER PROCEDURE ctl.usp_controler_publication
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #resultats (
        controle    NVARCHAR(10)  NOT NULL,
        table_sql   NVARCHAR(256) NOT NULL,
        verification NVARCHAR(200) NOT NULL,
        attendu     BIGINT        NULL,
        obtenu      BIGINT        NULL,
        statut      NVARCHAR(10)  NOT NULL
    );

    /* ---- L1-L8 : liens avec le DWH (orphelins) ---- */
    INSERT INTO #resultats (controle, table_sql, verification, attendu, obtenu, statut)
    SELECT N'L1', N'ana.dm_segments_rfm', N'client_sk absent de bi.v_dim_client', 0, COUNT(*), N''
    FROM ana.dm_segments_rfm AS t
    WHERE NOT EXISTS (SELECT 1 FROM TuniShop_DWH.bi.v_dim_client AS c WHERE c.client_sk = t.client_sk)
    UNION ALL
    SELECT N'L2', N'ana.dm_clusters_clients', N'client_sk absent de bi.v_dim_client', 0, COUNT(*), N''
    FROM ana.dm_clusters_clients AS t
    WHERE NOT EXISTS (SELECT 1 FROM TuniShop_DWH.bi.v_dim_client AS c WHERE c.client_sk = t.client_sk)
    UNION ALL
    SELECT N'L3', N'ana.ml_pred_churn_2025', N'client_sk absent de bi.v_dim_client', 0, COUNT(*), N''
    FROM ana.ml_pred_churn_2025 AS t
    WHERE NOT EXISTS (SELECT 1 FROM TuniShop_DWH.bi.v_dim_client AS c WHERE c.client_sk = t.client_sk)
    UNION ALL
    SELECT N'L4', N'ana.ml_pred_demande_2025', N'produit_id absent de bi.v_dim_produit (version courante)', 0, COUNT(*), N''
    FROM ana.ml_pred_demande_2025 AS t
    WHERE NOT EXISTS (SELECT 1 FROM TuniShop_DWH.bi.v_dim_produit AS p
                      WHERE p.produit_id = t.produit_id AND p.est_courant = 1)
    UNION ALL
    SELECT N'L5', N'ana.ml_pred_retard_2025', N'livraison_id absent de bi.v_fact_livraisons', 0, COUNT(*), N''
    FROM ana.ml_pred_retard_2025 AS t
    WHERE NOT EXISTS (SELECT 1 FROM TuniShop_DWH.bi.v_fact_livraisons AS f WHERE f.livraison_id = t.livraison_id)
    UNION ALL
    SELECT N'L6', N'ana.ml_scores_churn_actuels', N'client_sk absent de bi.v_dim_client', 0, COUNT(*), N''
    FROM ana.ml_scores_churn_actuels AS t
    WHERE NOT EXISTS (SELECT 1 FROM TuniShop_DWH.bi.v_dim_client AS c WHERE c.client_sk = t.client_sk)
    UNION ALL
    SELECT N'L7', N'ana.ml_scores_retard_en_cours', N'livraison_id absent de bi.v_fact_livraisons', 0, COUNT(*), N''
    FROM ana.ml_scores_retard_en_cours AS t
    WHERE NOT EXISTS (SELECT 1 FROM TuniShop_DWH.bi.v_fact_livraisons AS f WHERE f.livraison_id = t.livraison_id)
    UNION ALL
    SELECT N'L8', N'ana.ml_scores_demande', N'produit_id absent de bi.v_dim_produit (version courante)', 0, COUNT(*), N''
    FROM ana.ml_scores_demande AS t
    WHERE NOT EXISTS (SELECT 1 FROM TuniShop_DWH.bi.v_dim_produit AS p
                      WHERE p.produit_id = t.produit_id AND p.est_courant = 1);

    /* ---- H1 (v1.5) : la dernière exécution du suivi est bien dans l'historique ---- */
    IF OBJECT_ID(N'ana.ml_suivi_historique', N'U') IS NOT NULL
        INSERT INTO #resultats (controle, table_sql, verification, attendu, obtenu, statut)
        SELECT N'H1', N'ana.ml_suivi_historique', N'lignes de la dernière exécution = lignes de ana.ml_suivi',
               (SELECT COUNT_BIG(*) FROM ana.ml_suivi),
               (SELECT COUNT_BIG(*) FROM ana.ml_suivi_historique
                WHERE date_donnees = (SELECT MAX(date_donnees) FROM ana.ml_suivi_historique)),
               N'';

    /* ---- N1 : lignes en base = lignes notées dans le journal (dernière publication) ----
       On construit une requête COUNT(*) par table (SQL dynamique) car la liste des tables évolue. */
    DECLARE @sql NVARCHAR(MAX);
    SELECT @sql = STRING_AGG(CAST(
        N'SELECT N''N1'', N''' + d.table_sql + N''', N''lignes en base = journal'', ' +
        CAST(d.lignes AS NVARCHAR(20)) + N', (SELECT COUNT_BIG(*) FROM ' +
        QUOTENAME(PARSENAME(d.table_sql, 2)) + N'.' + QUOTENAME(PARSENAME(d.table_sql, 1)) + N'), N'''''
        AS NVARCHAR(MAX)), N' UNION ALL ')
    FROM (SELECT table_sql, SUM(lignes) AS lignes            -- table partagée : somme des notebooks
          FROM ctl.v_derniere_publication
          WHERE OBJECT_ID(table_sql, N'U') IS NOT NULL
          GROUP BY table_sql) AS d;
    IF @sql IS NOT NULL
        INSERT INTO #resultats (controle, table_sql, verification, attendu, obtenu, statut)
        EXEC sys.sp_executesql @sql;

    /* ---- P1 : tables du catalogue jamais publiées ---- */
    INSERT INTO #resultats (controle, table_sql, verification, attendu, obtenu, statut)
    SELECT N'P1', c.table_sql, N'publiée au moins une fois', 1,
           CASE WHEN EXISTS (SELECT 1 FROM ctl.journal_publication AS j WHERE j.table_sql = c.table_sql) THEN 1 ELSE 0 END,
           N''
    FROM ctl.catalogue_tables AS c;

    UPDATE #resultats
    SET statut = CASE WHEN attendu = obtenu THEN N'OK'
                      WHEN controle = N'P1' THEN N'INFO'      -- ex. prévision 2026 pas encore produite
                      ELSE N'ÉCART' END;

    SELECT controle, table_sql, verification, attendu, obtenu, statut
    FROM #resultats
    ORDER BY CASE statut WHEN N'ÉCART' THEN 0 WHEN N'INFO' THEN 1 ELSE 2 END, controle, table_sql;
END;
GO

-- Lancement immédiat (affiche le résultat dans SSMS)
EXEC ctl.usp_controler_publication;
GO

-- Requêtes utiles
-- 1) Les 20 dernières publications
SELECT TOP (20) * FROM ctl.journal_publication ORDER BY id_publication DESC;
-- 2) Fraîcheur : date de la dernière publication de chaque phase
SELECT c.phase, MAX(d.publie_le) AS derniere_publication, COUNT(*) AS tables_publiees
FROM ctl.v_derniere_publication AS d
JOIN ctl.catalogue_tables AS c ON c.table_sql = d.table_sql
GROUP BY c.phase;
GO
