/* =====================================================================
   02_Valeurs_Reference_Recette_Cube.sql — TuniShop
   Valeurs de référence calculées en SQL sur les vues bi.*, par année.
   À comparer, en phase 06, avec les mêmes mesures interrogées dans le cube
   (Excel connecté au cube, ou requête DAX dans SSMS).
   Tolérance : écart = 0 pour les comptages, ≤ 0,01 TND pour les montants.
   Les règles reprennent exactement les formules DAX du modèle (onglet 05).
   ===================================================================== */
USE TuniShop_DWH;
SET NOCOUNT ON;

/* V01, V02, M01, M02, X01 : ventes (relation active : date de commande) */
SELECT d.annee,
       SUM(CASE WHEN f.est_ca_reconnu = 1 THEN f.montant_ttc END)    AS [CA TTC],
       SUM(CASE WHEN f.est_ca_reconnu = 1 THEN f.montant_ht END)     AS [CA HT],
       SUM(CASE WHEN f.est_ca_reconnu = 1 THEN f.marge_brute_ht END) AS [Marge brute],
       SUM(CASE WHEN f.est_ca_reconnu = 1 THEN f.marge_brute_ht END)
         / NULLIF(SUM(CASE WHEN f.est_ca_reconnu = 1 THEN f.montant_ht END), 0) AS [Taux marge brute],
       SUM(CASE WHEN f.est_ca_reconnu = 1 THEN f.quantite END)       AS [Quantité vendue]
FROM bi.v_fact_ventes f JOIN bi.v_dim_date d ON d.date_sk = f.date_commande_sk
GROUP BY ROLLUP(d.annee) ORDER BY GROUPING(d.annee), d.annee;
GO

/* V04, V05, V06, V07, C02 : commandes */
SELECT d.annee,
       COUNT(*)                                                            AS [Nb commandes],
       SUM(CASE WHEN f.est_ca_reconnu = 1 THEN 1 ELSE 0 END)              AS [Nb commandes CA],
       SUM(CASE WHEN f.est_ca_reconnu = 1 THEN f.montant_total_ttc END)
         / NULLIF(SUM(CASE WHEN f.est_ca_reconnu = 1 THEN 1 ELSE 0 END), 0) AS [Panier moyen],
       SUM(CASE WHEN f.est_ca_reconnu = 1 THEN f.nb_articles END) * 1.0
         / NULLIF(SUM(CASE WHEN f.est_ca_reconnu = 1 THEN 1 ELSE 0 END), 0) AS [Articles par commande],
       SUM(CASE WHEN f.est_premiere_commande = 1 THEN 1 ELSE 0 END)       AS [Nouveaux clients]
FROM bi.v_fact_commandes f JOIN bi.v_dim_date d ON d.date_sk = f.date_commande_sk
GROUP BY ROLLUP(d.annee) ORDER BY GROUPING(d.annee), d.annee;
GO

/* C01 : clients actifs (client_id distincts : la dimension est en SCD2) */
SELECT d.annee, COUNT(DISTINCT c.client_id) AS [Clients actifs]
FROM bi.v_fact_commandes f
JOIN bi.v_dim_date d   ON d.date_sk = f.date_commande_sk
JOIN bi.v_dim_client c ON c.client_sk = f.client_sk
WHERE f.est_ca_reconnu = 1
GROUP BY ROLLUP(d.annee) ORDER BY GROUPING(d.annee), d.annee;
GO

/* L01, L02, X04 : livraisons (relation active : date d'expédition) */
SELECT d.annee,
       COUNT(*) AS [Nb livraisons],
       SUM(CASE WHEN f.est_livree_a_temps = 1 THEN 1 ELSE 0 END) * 1.0
         / NULLIF(SUM(CASE WHEN f.est_livree = 1 THEN 1 ELSE 0 END), 0) AS [Taux OTD],
       AVG(CAST(f.delai_livraison_j AS DECIMAL(10,4))) AS [Délai livraison j]
FROM bi.v_fact_livraisons f JOIN bi.v_dim_date d ON d.date_sk = f.date_expedition_sk
GROUP BY ROLLUP(d.annee) ORDER BY GROUPING(d.annee), d.annee;
GO

/* K01, K02, K03 : marketing */
SELECT d.annee,
       SUM(f.depense_ht) AS [Dépense marketing],
       SUM(f.ca_attribue_ttc) / NULLIF(SUM(f.depense_ht), 0) AS [ROAS],
       SUM(f.depense_ht) / NULLIF(SUM(f.nouveaux_clients_attribues), 0) AS [CAC]
FROM bi.v_fact_marketing_quotidien f JOIN bi.v_dim_date d ON d.date_sk = f.date_sk
GROUP BY ROLLUP(d.annee) ORDER BY GROUPING(d.annee), d.annee;
GO

/* C05, C06 : avis */
SELECT d.annee,
       AVG(CAST(f.note AS DECIMAL(6,4))) AS [Note moyenne],
       SUM(CASE WHEN f.sentiment = 'negatif' THEN 1 ELSE 0 END) * 1.0
         / NULLIF(SUM(CASE WHEN f.note IS NOT NULL THEN 1 ELSE 0 END), 0) AS [Taux avis négatifs]
FROM bi.v_fact_avis f JOIN bi.v_dim_date d ON d.date_sk = f.date_avis_sk
GROUP BY ROLLUP(d.annee) ORDER BY GROUPING(d.annee), d.annee;
GO

/* R02 : délai de remboursement (relation active : date de demande) */
SELECT d.annee, AVG(CAST(f.delai_traitement_j AS DECIMAL(10,4))) AS [Délai remboursement j]
FROM bi.v_fact_remboursements f JOIN bi.v_dim_date d ON d.date_sk = f.date_demande_sk
GROUP BY ROLLUP(d.annee) ORDER BY GROUPING(d.annee), d.annee;
GO

/* S01 : valeur du stock à la dernière date d'inventaire de chaque année (mesure semi-additive) */
WITH der AS (
  SELECT d.annee, MAX(d.[date]) AS derniere_date
  FROM bi.v_fact_stock_mensuel f JOIN bi.v_dim_date d ON d.date_sk = f.date_sk GROUP BY d.annee)
SELECT der.annee, der.derniere_date, SUM(f.valeur_stock_ht) AS [Valeur stock]
FROM der JOIN bi.v_dim_date d ON d.[date] = der.derniere_date
JOIN bi.v_fact_stock_mensuel f ON f.date_sk = d.date_sk
GROUP BY der.annee, der.derniere_date ORDER BY der.annee;
