/* =====================================================================
   14_Requetes_Partitions.sql — TuniShop — requêtes des partitions du cube
   ---------------------------------------------------------------------
   À coller dans Visual Studio : cube Ventes (et cube Marketing Clients pour Commandes) → onglet « Partitions »
   → partition → « Type de liaison » = Liaison de requête.
   Règle d'or : les partitions d'un même groupe de mesures ne doivent
   jamais se recouvrir ni laisser de trou, sinon le cube compte deux fois
   ou oublie des lignes. Les bornes ci-dessous se suivent sans trou ;
   la partition « autres » récupère les dates techniques (-1 / -2) et hors période.
   Contrôle : la somme des lignes des 4 partitions = 115 903 (ventes) et 66 268 (commandes).
   ===================================================================== */

-- ===================== Groupe de mesures « Ventes » =====================
-- Partition Ventes_2023
SELECT * FROM olap.v_fact_ventes WHERE date_commande_sk BETWEEN 20230101 AND 20231231;

-- Partition Ventes_2024
SELECT * FROM olap.v_fact_ventes WHERE date_commande_sk BETWEEN 20240101 AND 20241231;

-- Partition Ventes_2025
SELECT * FROM olap.v_fact_ventes WHERE date_commande_sk BETWEEN 20250101 AND 20251231;

-- Partition Ventes_autres (dates techniques ou hors 2023-2025)
SELECT * FROM olap.v_fact_ventes WHERE date_commande_sk < 20230101 OR date_commande_sk > 20251231;

-- ===================== Groupe de mesures « Commandes » ==================
-- Partition Commandes_2023
SELECT * FROM olap.v_fact_commandes WHERE date_commande_sk BETWEEN 20230101 AND 20231231;

-- Partition Commandes_2024
SELECT * FROM olap.v_fact_commandes WHERE date_commande_sk BETWEEN 20240101 AND 20241231;

-- Partition Commandes_2025
SELECT * FROM olap.v_fact_commandes WHERE date_commande_sk BETWEEN 20250101 AND 20251231;

-- Partition Commandes_autres
SELECT * FROM olap.v_fact_commandes WHERE date_commande_sk < 20230101 OR date_commande_sk > 20251231;

-- ===================== Vérification (dans SSMS, sur le DWH) ==============
-- Le total des 4 partitions doit égaler le total de la vue.
SELECT 'ventes' AS fait,
       SUM(CASE WHEN date_commande_sk BETWEEN 20230101 AND 20231231 THEN 1 ELSE 0 END) AS p2023,
       SUM(CASE WHEN date_commande_sk BETWEEN 20240101 AND 20241231 THEN 1 ELSE 0 END) AS p2024,
       SUM(CASE WHEN date_commande_sk BETWEEN 20250101 AND 20251231 THEN 1 ELSE 0 END) AS p2025,
       SUM(CASE WHEN date_commande_sk < 20230101 OR date_commande_sk > 20251231 THEN 1 ELSE 0 END) AS p_autres,
       COUNT(*) AS total
FROM olap.v_fact_ventes
UNION ALL
SELECT 'commandes',
       SUM(CASE WHEN date_commande_sk BETWEEN 20230101 AND 20231231 THEN 1 ELSE 0 END),
       SUM(CASE WHEN date_commande_sk BETWEEN 20240101 AND 20241231 THEN 1 ELSE 0 END),
       SUM(CASE WHEN date_commande_sk BETWEEN 20250101 AND 20251231 THEN 1 ELSE 0 END),
       SUM(CASE WHEN date_commande_sk < 20230101 OR date_commande_sk > 20251231 THEN 1 ELSE 0 END),
       COUNT(*)
FROM olap.v_fact_commandes;
