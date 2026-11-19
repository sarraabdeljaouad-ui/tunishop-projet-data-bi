/* =====================================================================
   19_Vues_Tableau.sql — TuniShop — source des tableaux de bord Tableau
   Auteur : Sarra Abdeljaouad · v1.0 du 29/10/2026
   ---------------------------------------------------------------------
   À exécuter sur l'instance du DWH (localhost), base TuniShop_DWH.
   Crée le schéma tab et 2 vues « tout-en-un » lues par Tableau Desktop :
     tab.v_direction : 8 familles de lignes (Commande, Ligne, Stock, Achat, Livraison, Avis, Marketing)
     tab.v_ventes    : 3 familles de lignes (Commande, Ligne, Paiement)
   Chaque ligne porte une colonne « source » et ses propres mesures ; les mesures
   des autres familles valent NULL. Les KPI sont recalculés dans Tableau avec les
   MÊMES règles que les cubes (11a à 11f) : CA reconnu = commandes de la famille
   « aboutie », clients actifs = clients distincts hors « paiement_echoue », etc.
   Les vues lisent la couche olap.v_* (script 10) : mêmes lignes que les cubes.
   Lecture seule, réexécutable (CREATE OR ALTER).
   ===================================================================== */
USE TuniShop_DWH;
GO
IF SCHEMA_ID('tab') IS NULL EXEC ('CREATE SCHEMA tab AUTHORIZATION dbo');
GO

/* ---------------------------------------------------------------------
   1. Vue Direction
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW tab.v_direction AS
-- Commandes (date de commande) : CA reconnu, commandes reconnues, clients actifs
SELECT N'Commande' AS source, d.[date] AS date_jour, d.annee, d.mois, d.trimestre,
       g.region, g.gouvernorat, CAST(NULL AS NVARCHAR(100)) AS categorie,
       CASE WHEN s.famille_statut = 'aboutie' THEN c.montant_total_ttc END AS ca_reconnu_ttc,
       CASE WHEN s.famille_statut = 'aboutie' THEN c.nb_commandes END AS nb_cmd_reconnues,
       CASE WHEN COALESCE(s.statut_commande, '') <> 'paiement_echoue' THEN c.client_sk END AS client_actif_sk,
       CAST(NULL AS DECIMAL(18,3)) AS ca_ht_reconnu, CAST(NULL AS DECIMAL(18,3)) AS marge_reconnue_ht,
       CAST(NULL AS INT) AS nb_inventaires, CAST(NULL AS INT) AS nb_ruptures, CAST(NULL AS DECIMAL(18,3)) AS valeur_stock_ht,
       CAST(NULL AS DECIMAL(18,3)) AS montant_achat_ht, CAST(NULL AS INT) AS quantite_recue, CAST(NULL AS INT) AS quantite_commandee_recue,
       CAST(NULL AS INT) AS nb_livrees, CAST(NULL AS INT) AS nb_livrees_a_temps,
       CAST(NULL AS INT) AS somme_notes, CAST(NULL AS INT) AS nb_avis_notes,
       CAST(NULL AS DECIMAL(18,3)) AS depense_ht, CAST(NULL AS DECIMAL(18,3)) AS ca_attribue_ttc
FROM olap.v_fact_commandes c
JOIN olap.v_dim_date d ON d.date_sk = c.date_commande_sk
LEFT JOIN olap.v_dim_geographie g ON g.geographie_sk = c.geographie_sk
LEFT JOIN olap.v_dim_statut_commande s ON s.statut_commande_sk = c.statut_commande_sk
UNION ALL
-- Lignes de vente (date de commande) : CA HT et marge reconnus, par catégorie
SELECT N'Ligne', d.[date], d.annee, d.mois, d.trimestre, g.region, g.gouvernorat, p.categorie,
       NULL, NULL, NULL,
       CASE WHEN s.famille_statut = 'aboutie' THEN v.montant_ht END,
       CASE WHEN s.famille_statut = 'aboutie' THEN v.marge_brute_ht END,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM olap.v_fact_ventes v
JOIN olap.v_dim_date d ON d.date_sk = v.date_commande_sk
LEFT JOIN olap.v_dim_geographie g ON g.geographie_sk = v.geographie_sk
LEFT JOIN olap.v_dim_produit p ON p.produit_sk = v.produit_sk
LEFT JOIN olap.v_dim_statut_commande s ON s.statut_commande_sk = v.statut_commande_sk
UNION ALL
-- Stock mensuel (photo de fin de mois) : pas de région
SELECT N'Stock', d.[date], d.annee, d.mois, d.trimestre, NULL, NULL, p.categorie,
       NULL, NULL, NULL, NULL, NULL,
       sm.nb_inventaires, sm.nb_ruptures, sm.valeur_stock_ht,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM olap.v_fact_stock_mensuel sm
JOIN olap.v_dim_date d ON d.date_sk = sm.date_sk
LEFT JOIN olap.v_dim_produit p ON p.produit_sk = sm.produit_sk
UNION ALL
-- Achats fournisseurs (date de commande fournisseur) : pas de région
SELECT N'Achat', d.[date], d.annee, d.mois, d.trimestre, NULL, NULL, p.categorie,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       a.montant_ht, a.quantite_recue, a.quantite_commandee_recue,
       NULL, NULL, NULL, NULL, NULL, NULL
FROM olap.v_fact_achats_fournisseur a
JOIN olap.v_dim_date d ON d.date_sk = a.date_commande_sk
LEFT JOIN olap.v_dim_produit p ON p.produit_sk = a.produit_sk
UNION ALL
-- Livraisons (date d'expédition, comme le cube Direction) : région du client livré
SELECT N'Livraison', d.[date], d.annee, d.mois, d.trimestre, g.region, g.gouvernorat, NULL,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       l.nb_livrees, l.nb_livrees_a_temps,
       NULL, NULL, NULL, NULL
FROM olap.v_fact_livraisons l
JOIN olap.v_dim_date d ON d.date_sk = l.date_expedition_sk
LEFT JOIN olap.v_dim_geographie g ON g.geographie_sk = l.geographie_sk
UNION ALL
-- Avis clients (date de l'avis) : pas de région
SELECT N'Avis', d.[date], d.annee, d.mois, d.trimestre, NULL, NULL, p.categorie,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       av.note, av.nb_avis_notes,
       NULL, NULL
FROM olap.v_fact_avis av
JOIN olap.v_dim_date d ON d.date_sk = av.date_avis_sk
LEFT JOIN olap.v_dim_produit p ON p.produit_sk = av.produit_sk
UNION ALL
-- Marketing quotidien : pas de région
SELECT N'Marketing', d.[date], d.annee, d.mois, d.trimestre, NULL, NULL, NULL,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       mk.depense_ht, mk.ca_attribue_ttc
FROM olap.v_fact_marketing_quotidien mk
JOIN olap.v_dim_date d ON d.date_sk = mk.date_sk;
GO

/* ---------------------------------------------------------------------
   2. Vue Ventes : toutes les lignes portent les attributs de la commande
      (région, canal, mode de paiement, statut) pour que les filtres
      s'appliquent partout de la même façon.
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW tab.v_ventes AS
SELECT N'Commande' AS source, d.[date] AS date_jour, d.annee, d.trimestre, d.mois, d.periode_commerciale,
       g.region, g.gouvernorat, ca.canal, ca.libelle_canal AS canal_appareil,
       mp.libelle_mode_paiement AS mode_paiement, s.famille_statut, s.libelle_statut AS statut,
       CAST(NULL AS NVARCHAR(100)) AS categorie, CAST(NULL AS NVARCHAR(100)) AS sous_categorie,
       CAST(NULL AS NVARCHAR(100)) AS marque, CAST(NULL AS NVARCHAR(100)) AS type_remise,
       c.nb_commandes, c.montant_total_ttc AS ca_commande_ttc,
       CASE WHEN s.famille_statut = 'aboutie' THEN c.montant_total_ttc END AS ca_reconnu_ttc,
       CASE WHEN s.famille_statut = 'aboutie' THEN c.nb_commandes END AS nb_cmd_reconnues,
       CASE WHEN s.famille_statut = 'aboutie' THEN c.montant_rembourse_ttc END AS rembourse_reconnu_ttc,
       CASE WHEN s.famille_statut = 'aboutie' THEN c.nb_articles END AS nb_articles_reconnus,
       CASE WHEN ca.canal = 'application_mobile' THEN c.nb_commandes ELSE 0 END AS nb_cmd_application,
       CASE WHEN mp.mode_paiement = 'paiement_a_la_livraison' THEN c.nb_commandes ELSE 0 END AS nb_cmd_paiement_livraison,
       CASE WHEN s.statut_commande = 'annulee' THEN c.nb_commandes ELSE 0 END AS nb_cmd_annulees,
       CASE WHEN s.statut_commande = 'livraison_echouee' THEN c.nb_commandes ELSE 0 END AS nb_cmd_livraison_echouee,
       CAST(NULL AS DECIMAL(18,3)) AS brut_reconnu_ttc, CAST(NULL AS DECIMAL(18,3)) AS remise_promo_reconnue_ttc,
       CAST(NULL AS DECIMAL(18,3)) AS ca_ht_reconnu, CAST(NULL AS DECIMAL(18,3)) AS marge_reconnue_ht,
       CAST(NULL AS INT) AS nb_tentatives_paiement, CAST(NULL AS INT) AS nb_paiements_reussis
FROM olap.v_fact_commandes c
JOIN olap.v_dim_date d ON d.date_sk = c.date_commande_sk
LEFT JOIN olap.v_dim_geographie g ON g.geographie_sk = c.geographie_sk
LEFT JOIN olap.v_dim_canal ca ON ca.canal_sk = c.canal_sk
LEFT JOIN olap.v_dim_mode_paiement mp ON mp.mode_paiement_sk = c.mode_paiement_sk
LEFT JOIN olap.v_dim_statut_commande s ON s.statut_commande_sk = c.statut_commande_sk
UNION ALL
SELECT N'Ligne', d.[date], d.annee, d.trimestre, d.mois, d.periode_commerciale,
       g.region, g.gouvernorat, ca.canal, ca.libelle_canal, mp.libelle_mode_paiement, s.famille_statut, s.libelle_statut,
       p.categorie, p.sous_categorie, p.marque, cp.type_remise,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       CASE WHEN s.famille_statut = 'aboutie' THEN v.montant_brut_ttc END,
       CASE WHEN s.famille_statut = 'aboutie' THEN v.montant_remise_promo_ttc END,
       CASE WHEN s.famille_statut = 'aboutie' THEN v.montant_ht END,
       CASE WHEN s.famille_statut = 'aboutie' THEN v.marge_brute_ht END,
       NULL, NULL
FROM olap.v_fact_ventes v
JOIN olap.v_dim_date d ON d.date_sk = v.date_commande_sk
LEFT JOIN olap.v_fact_commandes c ON c.commande_id = v.commande_id
LEFT JOIN olap.v_dim_geographie g ON g.geographie_sk = v.geographie_sk
LEFT JOIN olap.v_dim_canal ca ON ca.canal_sk = v.canal_sk
LEFT JOIN olap.v_dim_mode_paiement mp ON mp.mode_paiement_sk = c.mode_paiement_sk
LEFT JOIN olap.v_dim_statut_commande s ON s.statut_commande_sk = v.statut_commande_sk
LEFT JOIN olap.v_dim_produit p ON p.produit_sk = v.produit_sk
LEFT JOIN olap.v_dim_coupon cp ON cp.coupon_sk = v.coupon_sk
UNION ALL
-- Paiements : date du paiement (comme le cube), autres attributs repris de la commande
SELECT N'Paiement', d.[date], d.annee, d.trimestre, d.mois, d.periode_commerciale,
       g.region, g.gouvernorat, ca.canal, ca.libelle_canal, mp.libelle_mode_paiement, s.famille_statut, s.libelle_statut,
       NULL, NULL, NULL, NULL,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       pa.nb_tentatives, pa.nb_reussies
FROM olap.v_fact_paiements pa
JOIN olap.v_dim_date d ON d.date_sk = pa.date_paiement_sk
LEFT JOIN olap.v_fact_commandes c ON c.commande_id = pa.commande_id
LEFT JOIN olap.v_dim_geographie g ON g.geographie_sk = c.geographie_sk
LEFT JOIN olap.v_dim_canal ca ON ca.canal_sk = c.canal_sk
LEFT JOIN olap.v_dim_mode_paiement mp ON mp.mode_paiement_sk = pa.mode_paiement_sk
LEFT JOIN olap.v_dim_statut_commande s ON s.statut_commande_sk = c.statut_commande_sk;
GO

/* ---------------------------------------------------------------------
   3. Contrôle : doit redonner les valeurs de la recette des cubes
      (12a et 12f) — Total, 2023, 2024, 2025
   --------------------------------------------------------------------- */
SELECT COALESCE(CAST(annee AS NVARCHAR(10)), N'Total') AS periode,
       CAST(SUM(ca_reconnu_ttc) AS DECIMAL(18,3))                                   AS [CA Reconnu TTC (attendu 15 541 665,655 · 3 384 688,310 · 5 022 224,580 · 7 134 752,765)],
       CAST(100.0 * SUM(marge_reconnue_ht) / NULLIF(SUM(ca_ht_reconnu), 0) AS DECIMAL(9,2)) AS [Taux Marge % (31,17 · 30,78 · 31,28 · 31,28)],
       CAST(SUM(ca_reconnu_ttc) / NULLIF(SUM(nb_cmd_reconnues), 0) AS DECIMAL(9,2))  AS [Panier Moyen (264,42 · 253,82 · 265,75 · 268,80)],
       COUNT(DISTINCT client_actif_sk)                                               AS [Clients Actifs (12 412 · 4 015 · 5 521 · 7 366)],
       CAST(100.0 * SUM(nb_ruptures) / NULLIF(SUM(nb_inventaires), 0) AS DECIMAL(9,2)) AS [Taux Rupture % (2,72 · 2,30 · 2,62 · 3,13)],
       CAST(SUM(montant_achat_ht) AS DECIMAL(18,3))                                   AS [Achats HT (8 999 975,580 · 1 874 945,057 · 2 943 552,147 · 4 181 478,376)],
       CAST(100.0 * SUM(quantite_recue) / NULLIF(SUM(quantite_commandee_recue), 0) AS DECIMAL(9,2)) AS [Service fournisseur % (97,91 · 97,82 · 97,60 · 98,17)],
       CAST(100.0 * SUM(nb_livrees_a_temps) / NULLIF(SUM(nb_livrees), 0) AS DECIMAL(9,2)) AS [OTD % (85,47 · 90,43 · 85,93 · 82,67)],
       CAST(1.0 * SUM(somme_notes) / NULLIF(SUM(nb_avis_notes), 0) AS DECIMAL(9,3))  AS [Note (4,052 · 4,090 · 4,050 · 4,036)],
       CAST(SUM(ca_attribue_ttc) / NULLIF(SUM(depense_ht), 0) AS DECIMAL(9,3))       AS [ROAS (2,636 · 2,364 · 2,571 · 2,853)]
FROM tab.v_direction
WHERE annee BETWEEN 2023 AND 2025
GROUP BY ROLLUP(annee)
ORDER BY GROUPING(annee), annee;

-- Valeur du stock HT = photo du dernier mois de la période (attendu 2023 : 1 346 821,147 · 2024 : 1 652 137,207 · 2025 : 2 093 374,696)
SELECT annee, CAST(SUM(valeur_stock_ht) AS DECIMAL(18,3)) AS valeur_stock_fin_annee
FROM tab.v_direction v
WHERE source = N'Stock'
  AND date_jour = (SELECT MAX(date_jour) FROM tab.v_direction x WHERE x.source = N'Stock' AND x.annee = v.annee)
GROUP BY annee ORDER BY annee;

SELECT COALESCE(CAST(annee AS NVARCHAR(10)), N'Total') AS periode,
       CAST(SUM(ca_commande_ttc) AS DECIMAL(18,3)) AS [CA Commande TTC (18 301 310,240 · 4 048 898,725 · 5 887 757,775 · 8 364 653,740)],
       SUM(nb_commandes) AS [Commandes Passees (66 268 · 15 063 · 21 170 · 30 035)],
       CAST(SUM(ca_reconnu_ttc) - SUM(rembourse_reconnu_ttc) AS DECIMAL(18,3)) AS [CA Net TTC (14 634 897,902 · 3 205 616,812 · 4 708 825,603 · 6 720 455,487)],
       CAST(1.0 * SUM(nb_articles_reconnus) / NULLIF(SUM(nb_cmd_reconnues), 0) AS DECIMAL(9,3)) AS [Articles/cmd (2,579 · 2,517 · 2,547 · 2,633)],
       CAST(100.0 * SUM(remise_promo_reconnue_ttc) / NULLIF(SUM(brut_reconnu_ttc), 0) AS DECIMAL(9,2)) AS [Remise % (1,75 · 1,60 · 1,74 · 1,82)],
       CAST(100.0 * SUM(nb_cmd_application) / NULLIF(SUM(nb_commandes), 0) AS DECIMAL(9,2)) AS [Part appli % (40,82 · 32,42 · 39,18 · 46,19)],
       CAST(100.0 * SUM(nb_cmd_paiement_livraison) / NULLIF(SUM(nb_commandes), 0) AS DECIMAL(9,2)) AS [Part paiement livraison % (49,08 · 53,04 · 49,74 · 46,64)],
       CAST(100.0 * SUM(nb_cmd_annulees) / NULLIF(SUM(nb_commandes), 0) AS DECIMAL(9,2)) AS [Annulation % (4,78 · 5,15 · 4,82 · 4,57)],
       CAST(100.0 * SUM(nb_cmd_livraison_echouee) / NULLIF(SUM(nb_cmd_reconnues) + SUM(nb_cmd_livraison_echouee), 0) AS DECIMAL(9,2)) AS [Refus colis % (4,48 · 4,89 · 4,34 · 4,37)],
       CAST(100.0 - 100.0 * SUM(nb_paiements_reussis) / NULLIF(SUM(nb_tentatives_paiement), 0) AS DECIMAL(9,2)) AS [Echec paiement % (6,66 · 6,35 · 6,30 · 7,07)]
FROM tab.v_ventes
WHERE annee BETWEEN 2023 AND 2025
GROUP BY ROLLUP(annee)
ORDER BY GROUPING(annee), annee;
GO
