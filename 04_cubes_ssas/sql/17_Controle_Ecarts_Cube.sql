/* =====================================================================
   17_Controle_Ecarts_Cube.sql — TuniShop — preuve des 4 petits écarts de la recette du cube
   ---------------------------------------------------------------------
   Où l'exécuter : SSMS, Moteur de base de données localhost (ton instance Express), F5.
   Principe : le cube doit donner EXACTEMENT les chiffres du DWH, sa source.
   Chaque requête recalcule l'indicateur en SQL sur les vues olap (les mêmes que lit le cube).
     - si la ligne SQL = la valeur du cube : le cube est juste ; l'écart avec la valeur attendue
       (calculée sur donnees_reference) vient du DWH lui-même (règles de qualité du staging),
       déjà tracé dans la validation du DWH ;
     - si la ligne SQL est différente du cube : c'est le cube qu'il faut corriger.
   Lecture seule : ce script ne modifie rien.
   ===================================================================== */
USE TuniShop_DWH;
GO

-- 1. Taux d'échec de paiement (cube Ventes, mesure Taux Echec Paiement)
--    Référence donnees_reference : 64 493 tentatives, 4 300 échecs, 6,667 %
SELECT COALESCE(CAST(d.annee AS VARCHAR(4)), 'All') AS annee,
       SUM(p.nb_tentatives) AS tentatives,
       SUM(p.nb_reussies) AS reussies,
       SUM(p.nb_tentatives) - SUM(p.nb_reussies) AS echecs,
       CAST(100.0 * (SUM(p.nb_tentatives) - SUM(p.nb_reussies)) / SUM(p.nb_tentatives) AS DECIMAL(9,4)) AS taux_echec_pct
FROM olap.v_fact_paiements p
JOIN olap.v_dim_date d ON d.date_sk = p.date_paiement_sk
GROUP BY GROUPING SETS ((d.annee), ())
ORDER BY GROUPING(d.annee), d.annee;

-- 2. Délai moyen de remboursement (cube Livraisons, mesure Delai Moyen Remboursement J)
--    Référence donnees_reference : 8 261 remboursements, tous avec un délai, 6,670 jours
SELECT COALESCE(CAST(d.annee AS VARCHAR(4)), 'All') AS annee,
       SUM(r.nb_rembourses) AS rembourses,
       SUM(r.nb_delais_rembourses) AS rembourses_avec_delai,
       CAST(SUM(r.delai_traitement_j) / NULLIF(SUM(r.nb_delais_rembourses), 0) AS DECIMAL(9,4)) AS delai_moyen_j
FROM olap.v_fact_remboursements r
JOIN olap.v_dim_date d ON d.date_sk = r.date_demande_sk
GROUP BY GROUPING SETS ((d.annee), ())
ORDER BY GROUPING(d.annee), d.annee;

-- 3. Clients actifs (cube Marketing Clients, mesure Clients Actifs)
--    Le cube compte les versions de client (client_sk) ; l'identifiant métier est client_id.
SELECT COALESCE(CAST(d.annee AS VARCHAR(4)), 'All') AS annee,
       COUNT(DISTINCT c.client_sk) AS clients_par_version_cube,
       COUNT(DISTINCT dc.client_id) AS clients_par_identifiant,
       COUNT(DISTINCT CASE WHEN c.client_sk < 0 THEN c.client_sk END) AS dont_membres_techniques
FROM olap.v_fact_commandes c
JOIN olap.v_dim_date d ON d.date_sk = c.date_commande_sk
JOIN olap.v_dim_statut_commande s ON s.statut_commande_sk = c.statut_commande_sk
JOIN olap.v_dim_client dc ON dc.client_sk = c.client_sk
WHERE s.statut_commande <> 'paiement_echoue'
GROUP BY GROUPING SETS ((d.annee), ())
ORDER BY GROUPING(d.annee), d.annee;

-- 4. Note moyenne (cube Livraisons, mesure Note Moyenne) — référence 4,053
SELECT COALESCE(CAST(d.annee AS VARCHAR(4)), 'All') AS annee,
       COUNT(a.note) AS avis_notes,
       CAST(AVG(CAST(a.note AS DECIMAL(10,4))) AS DECIMAL(9,4)) AS note_moyenne
FROM olap.v_fact_avis a
JOIN olap.v_dim_date d ON d.date_sk = a.date_avis_sk
GROUP BY GROUPING SETS ((d.annee), ())
ORDER BY GROUPING(d.annee), d.annee;
GO
