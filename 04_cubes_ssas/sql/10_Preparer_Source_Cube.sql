/* =====================================================================
   10_Preparer_Source_Cube.sql — TuniShop
   Prépare TuniShop_DWH pour le cube SSAS (à exécuter sur ton instance Express, celle du DWH)
   ---------------------------------------------------------------------
   Ce que fait le script :
     1. crée le schéma olap : la « couche sémantique » que lit le cube ;
     2. crée 24 vues olap.v_* au-dessus des vues bi.v_* : mêmes lignes,
        plus des colonnes 0/1 et des libellés faciles à agréger dans le cube ;
     3. donne au compte de service SSAS le droit de LIRE ce schéma, et rien d'autre ;
     4. vérifie le résultat.
   Il ne modifie aucune table et ne touche pas au staging. Réexécutable (CREATE OR ALTER).
   v1.1 (28/10/2026) : note, retard_j, delai_appro_j et retard_appro_j convertis en INT
   (les mesures du cube ont le même type que leur colonne : un TINYINT ou SMALLINT débordait à l'addition).
   v1.2 (28/10/2026) : nb_delais_rembourses (remboursements dont le délai est renseigné), dénominateur du délai moyen.
   Avant d'exécuter : vérifie le nom du compte SSAS dans la section 3 (instance DEV par défaut).
   ===================================================================== */
USE TuniShop_DWH;
GO
IF SCHEMA_ID('olap') IS NULL EXEC ('CREATE SCHEMA olap AUTHORIZATION dbo');
GO

/* ---------------------------------------------------------------------
   1. Dimensions : mêmes colonnes que bi, plus quelques libellés
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW olap.v_dim_date AS
SELECT date_sk, [date], annee, trimestre, libelle_trimestre, mois, nom_mois, annee_mois,
       CASE WHEN date_sk > 0 THEN CONCAT(nom_mois, N' ', annee) ELSE nom_mois END AS libelle_mois,
       CASE WHEN date_sk > 0 THEN CONCAT(annee, N'-S', CASE WHEN mois <= 6 THEN 1 ELSE 2 END) ELSE libelle_trimestre END AS libelle_semestre,
       semaine_iso, jour_mois, jour_semaine, nom_jour,
       CASE WHEN date_sk > 0 THEN CONVERT(NVARCHAR(10), [date], 103) ELSE nom_mois END AS libelle_jour,
       CAST(est_weekend AS INT) AS est_weekend, CAST(est_jour_ferie AS INT) AS est_jour_ferie,
       COALESCE(nom_jour_ferie, N'—') AS nom_jour_ferie,
       CASE WHEN est_ramadan = 1 THEN N'Ramadan' ELSE N'Hors Ramadan' END AS periode_ramadan,
       periode_commerciale
FROM bi.v_dim_date;
GO
CREATE OR ALTER VIEW olap.v_dim_client AS
SELECT client_sk, client_id, type_client, nom_complet, genre, tranche_age, gouvernorat, region, ville,
       canal_inscription, cohorte_inscription, segment_fidelite, est_courant
FROM bi.v_dim_client;
GO
CREATE OR ALTER VIEW olap.v_dim_produit AS
SELECT produit_sk, produit_id, sku, nom_produit, marque, categorie, sous_categorie, gamme_prix, statut_produit,
       prix_catalogue_ttc, date_debut_validite, date_fin_validite, est_courant
FROM bi.v_dim_produit;
GO
CREATE OR ALTER VIEW olap.v_dim_fournisseur AS
SELECT fournisseur_sk, fournisseur_id, nom_fournisseur, pays,
       CASE WHEN est_local = 1 THEN N'Local' ELSE N'Étranger' END AS origine
FROM bi.v_dim_fournisseur;
GO
CREATE OR ALTER VIEW olap.v_dim_geographie AS
SELECT geographie_sk, gouvernorat_id, gouvernorat, region, zone_livraison FROM bi.v_dim_geographie;
GO
CREATE OR ALTER VIEW olap.v_dim_entrepot AS
SELECT entrepot_sk, entrepot_id, nom_entrepot, ville, region FROM bi.v_dim_entrepot;
GO
CREATE OR ALTER VIEW olap.v_dim_transporteur AS
SELECT transporteur_sk, transporteur_id, nom_transporteur, couverture FROM bi.v_dim_transporteur;
GO
CREATE OR ALTER VIEW olap.v_dim_campagne AS
SELECT campagne_sk, campagne_id, nom_campagne, canal_media, type_canal, objectif, theme FROM bi.v_dim_campagne;
GO
CREATE OR ALTER VIEW olap.v_dim_coupon AS
SELECT coupon_sk, code_coupon, type_remise FROM bi.v_dim_coupon;
GO
CREATE OR ALTER VIEW olap.v_dim_canal AS
SELECT canal_sk, canal, appareil, libelle_canal FROM bi.v_dim_canal;
GO
CREATE OR ALTER VIEW olap.v_dim_mode_paiement AS
SELECT mode_paiement_sk, mode_paiement, libelle_mode_paiement FROM bi.v_dim_mode_paiement;
GO
CREATE OR ALTER VIEW olap.v_dim_statut_commande AS
SELECT statut_commande_sk, statut_commande, libelle_statut, famille_statut FROM bi.v_dim_statut_commande;
GO
CREATE OR ALTER VIEW olap.v_dim_motif_retour AS
SELECT motif_retour_sk, type_remboursement, motif, libelle_motif, responsabilite FROM bi.v_dim_motif_retour;
GO
-- Dimension « Type de mouvement » (cube Stock) : construite à partir des valeurs présentes dans les mouvements
CREATE OR ALTER VIEW olap.v_dim_type_mouvement AS
SELECT DISTINCT type_mouvement,
       CASE WHEN type_mouvement IN ('reception_fournisseur','retour_client','retour_client_non_revendable','retour_echec_livraison','annulation_commande','stock_initial')
            THEN N'Entrée' WHEN type_mouvement IN ('vente','mise_au_rebut') THEN N'Sortie'
            ELSE N'Ajustement' END AS famille_mouvement   -- d'après le signe des quantités du jeu de données
FROM bi.v_fact_mouvements_stock;
GO

/* ---------------------------------------------------------------------
   2. Faits : les colonnes 0/1 (BIT) deviennent des entiers additionnables,
      et chaque fait reçoit un compteur « nb_… = 1 » (une ligne = 1)
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW olap.v_fact_ventes AS
SELECT ligne_id, commande_id, date_commande_sk, client_sk, produit_sk, geographie_sk, entrepot_sk, canal_sk,
       campagne_sk, coupon_sk, statut_commande_sk,
       1 AS nb_lignes, quantite, montant_brut_ttc, montant_remise_promo_ttc, montant_ttc, montant_ht, montant_tva,
       cout_achat_ht, marge_brute_ht
FROM bi.v_fact_ventes;
GO
CREATE OR ALTER VIEW olap.v_fact_commandes AS
SELECT commande_id, date_commande_sk, date_livraison_sk, client_sk, geographie_sk, entrepot_sk, canal_sk,
       campagne_sk, coupon_sk, mode_paiement_sk, statut_commande_sk,
       1 AS nb_commandes, nb_articles, sous_total_ttc, remise_coupon_ttc, frais_livraison_ttc, montant_total_ttc,
       cout_achat_ht, cout_transport_ht, montant_rembourse_ttc,
       CAST(est_premiere_commande AS INT) AS nb_premieres_commandes
FROM bi.v_fact_commandes;
GO
CREATE OR ALTER VIEW olap.v_fact_paiements AS
SELECT paiement_id, commande_id, date_paiement_sk, client_sk, mode_paiement_sk,
       1 AS nb_tentatives, CAST(est_reussi AS INT) AS nb_reussies, montant_ttc
FROM bi.v_fact_paiements;
GO
CREATE OR ALTER VIEW olap.v_fact_livraisons AS
SELECT livraison_id, commande_id, date_expedition_sk, date_livraison_sk, client_sk, entrepot_sk, transporteur_sk, geographie_sk,
       1 AS nb_livraisons,
       CAST(est_livree AS INT) AS nb_livrees,
       CASE WHEN est_livree = 1 AND est_livree_a_temps = 1 THEN 1 ELSE 0 END AS nb_livrees_a_temps,
       CASE WHEN est_livree = 1 AND retard_j > 0 THEN 1 ELSE 0 END AS nb_livrees_en_retard,
       CASE WHEN est_livree = 1 AND est_premiere_tentative = 1 THEN 1 ELSE 0 END AS nb_livrees_1er_passage,
       CASE WHEN est_livree = 1 THEN delai_livraison_j END AS delai_livraison_j,
       CAST(CASE WHEN est_livree = 1 AND retard_j > 0 THEN retard_j END AS INT) AS retard_j,
       cout_transport_ht, poids_kg
FROM bi.v_fact_livraisons;
GO
CREATE OR ALTER VIEW olap.v_fact_remboursements AS
SELECT r.remboursement_id, r.commande_id, r.date_demande_sk, r.client_sk, r.produit_sk, r.motif_retour_sk,
       1 AS nb_demandes,
       CASE WHEN m.type_remboursement = 'retour' AND r.statut <> 'refuse' THEN 1 ELSE 0 END AS nb_retours,
       CASE WHEN r.statut = 'rembourse' THEN 1 ELSE 0 END AS nb_rembourses,
       CASE WHEN r.statut = 'rembourse' AND r.delai_traitement_j IS NOT NULL THEN 1 ELSE 0 END AS nb_delais_rembourses,
       r.quantite, r.montant_demande_ttc,
       CASE WHEN r.statut = 'rembourse' THEN r.montant_rembourse_ttc ELSE 0 END AS montant_rembourse_ttc,
       CASE WHEN r.statut = 'rembourse' THEN r.delai_traitement_j END AS delai_traitement_j
FROM bi.v_fact_remboursements r
LEFT JOIN bi.v_dim_motif_retour m ON m.motif_retour_sk = r.motif_retour_sk;
GO
CREATE OR ALTER VIEW olap.v_fact_avis AS
SELECT avis_id, commande_id, date_avis_sk, client_sk, produit_sk,
       1 AS nb_avis,
       CASE WHEN note IS NOT NULL THEN 1 ELSE 0 END AS nb_avis_notes,
       CASE WHEN note <= 2 THEN 1 ELSE 0 END AS nb_avis_negatifs,
       CAST(note AS INT) AS note
FROM bi.v_fact_avis;
GO
CREATE OR ALTER VIEW olap.v_fact_marketing_quotidien AS
SELECT depense_id, date_sk, campagne_sk,
       depense_ht, impressions, clics, commandes_attribuees, nouveaux_clients_attribues, ca_attribue_ttc
FROM bi.v_fact_marketing_quotidien;
GO
CREATE OR ALTER VIEW olap.v_fact_achats_fournisseur AS
SELECT ligne_cf_id, commande_fournisseur_id, date_commande_sk, fournisseur_sk, produit_sk, entrepot_sk,
       1 AS nb_lignes_cf,
       CASE WHEN date_reception_sk > 0 THEN 1 ELSE 0 END AS nb_lignes_recues,
       CASE WHEN date_reception_sk > 0 AND quantite_recue < quantite_commandee THEN 1 ELSE 0 END AS nb_receptions_partielles,
       quantite_commandee,
       CASE WHEN date_reception_sk > 0 THEN quantite_commandee ELSE 0 END AS quantite_commandee_recue,
       COALESCE(quantite_recue, 0) AS quantite_recue,
       montant_ht,
       CAST(CASE WHEN date_reception_sk > 0 THEN delai_appro_reel_j END AS INT) AS delai_appro_j,
       CAST(CASE WHEN date_reception_sk > 0 THEN retard_appro_j END AS INT) AS retard_appro_j
FROM bi.v_fact_achats_fournisseur;
GO
CREATE OR ALTER VIEW olap.v_fact_mouvements_stock AS
SELECT mouvement_id, date_sk, produit_sk, entrepot_sk, type_mouvement, sens,
       1 AS nb_mouvements, quantite, valeur_ht,
       CASE WHEN type_mouvement = 'vente' THEN ABS(quantite) ELSE 0 END AS quantite_vendue,
       CASE WHEN type_mouvement = 'vente' THEN ABS(valeur_ht) ELSE 0 END AS cout_des_ventes_ht
FROM bi.v_fact_mouvements_stock;
GO
CREATE OR ALTER VIEW olap.v_fact_stock_mensuel AS
SELECT inventaire_id, date_sk, produit_sk, entrepot_sk,
       1 AS nb_inventaires, CAST(est_rupture AS INT) AS nb_ruptures,
       stock_fin_mois, quantite_en_commande, valeur_stock_ht
FROM bi.v_fact_stock_mensuel;
GO

/* ---------------------------------------------------------------------
   3. Droits du compte de service SSAS : lecture du schéma olap uniquement
      Instance SSAS « DEV » → compte NT Service\MSOLAP$DEV
      (instance par défaut → NT Service\MSSQLServerOLAPService)
   --------------------------------------------------------------------- */
USE master;
GO
IF SUSER_ID(N'NT Service\MSOLAP$DEV') IS NULL
    CREATE LOGIN [NT Service\MSOLAP$DEV] FROM WINDOWS WITH DEFAULT_DATABASE = TuniShop_DWH;
GO
USE TuniShop_DWH;
GO
IF USER_ID(N'NT Service\MSOLAP$DEV') IS NULL
    CREATE USER [NT Service\MSOLAP$DEV] FOR LOGIN [NT Service\MSOLAP$DEV];
GRANT SELECT ON SCHEMA::olap TO [NT Service\MSOLAP$DEV];
GO

/* ---------------------------------------------------------------------
   4. Vérifications
   --------------------------------------------------------------------- */
-- 4a. 24 vues attendues (14 dimensions, dont Type de mouvement, + 10 faits)
SELECT COUNT(*) AS vues_olap FROM sys.views WHERE SCHEMA_NAME(schema_id) = 'olap';

-- 4b. Les volumes doivent être ceux du rapport de validation du DWH
SELECT 'olap.v_fact_ventes' AS vue, COUNT(*) AS lignes FROM olap.v_fact_ventes           -- 115 903
UNION ALL SELECT 'olap.v_fact_commandes', COUNT(*) FROM olap.v_fact_commandes             -- 66 268
UNION ALL SELECT 'olap.v_fact_livraisons', COUNT(*) FROM olap.v_fact_livraisons           -- 61 793
UNION ALL SELECT 'olap.v_fact_stock_mensuel', COUNT(*) FROM olap.v_fact_stock_mensuel     -- 56 562
UNION ALL SELECT 'olap.v_dim_date', COUNT(*) FROM olap.v_dim_date                         -- 1 828
UNION ALL SELECT 'olap.v_dim_client', COUNT(*) FROM olap.v_dim_client;                    -- 16 002

-- 4c. Le compte SSAS a bien le droit de lecture sur olap (une ligne SELECT attendue)
SELECT pr.name AS compte, pe.permission_name, pe.class_desc, SCHEMA_NAME(pe.major_id) AS schema_
FROM sys.database_permissions pe JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name = N'NT Service\MSOLAP$DEV';

-- 4d. Contrôle rapide : CA reconnu 2025 attendu = 7 134 752,765
SELECT d.annee, SUM(c.montant_total_ttc) AS ca_reconnu_ttc
FROM olap.v_fact_commandes c
JOIN olap.v_dim_date d ON d.date_sk = c.date_commande_sk
JOIN olap.v_dim_statut_commande s ON s.statut_commande_sk = c.statut_commande_sk
WHERE s.famille_statut = 'aboutie'
GROUP BY d.annee ORDER BY d.annee;
GO
