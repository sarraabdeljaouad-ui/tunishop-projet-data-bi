/* =====================================================================
   Projet      : TuniShop — Data Warehouse e-commerce (portfolio)
   Script      : 04c_Rapports_Validation_Staging.sql
   Objet       : Rapports de validation du staging dans TuniShop_ADMIN : (1) validation de STG_RAW (fichiers, volumes, anomalies techniques, décision), (2) qualité avant/après, (3) exactitude par rapport à donnees_reference, (4) décision de fin de phase.
   Cible       : Microsoft SQL Server 2019+ (SSMS) — compatibilité 150
   Exécution   : SSMS, mode SQLCMD inutile ; exécuter en entier (F5)
   Généré le   : 2026-10-17 depuis le modèle de métadonnées du projet
   ===================================================================== */
SET NOCOUNT ON;
GO
/* Prérequis : 01 à 04b exécutés, un lot complet chargé.
   Pour la comparaison avec la référence : charger d'abord donnees_reference dans le schéma ref
   (python tunishop_pipeline.py reference --dossier-ref <chemin\donnees_reference>).
   Relançable sans perte (CREATE si absent, MERGE des données de référence, CREATE OR ALTER des vues et procédures).

   Utilisation :
     EXEC TuniShop_ADMIN.audit.usp_valider_staging;                          -- dernier lot : mesures + comparaison + décision
     SELECT * FROM TuniShop_ADMIN.audit.v_validation_raw_decision        ORDER BY id_chargement DESC;
     SELECT * FROM TuniShop_ADMIN.audit.v_validation_raw_fichiers        WHERE id_chargement = 3 AND statut <> 'OK';
     SELECT * FROM TuniShop_ADMIN.audit.v_qualite_avant_apres            WHERE id_chargement = 3;
     SELECT * FROM TuniShop_ADMIN.audit.v_reference_exactitude_tables    WHERE id_chargement = 3;
     SELECT * FROM TuniShop_ADMIN.audit.v_validation_staging_decision    ORDER BY id_chargement DESC;
*/
USE [TuniShop_ADMIN];
GO
IF SCHEMA_ID(N'ref') IS NULL EXEC (N'CREATE SCHEMA ref AUTHORIZATION dbo;');   -- copie de donnees_reference (chargée par Python)
GO

/* =====================================================================
   1. VALIDATION DE STG_RAW
   ===================================================================== */
IF OBJECT_ID(N'audit.fichier_attendu', N'U') IS NULL
CREATE TABLE audit.fichier_attendu (
    chemin_fichier   NVARCHAR(400) NOT NULL CONSTRAINT PK_fichier_attendu PRIMARY KEY,
    table_cible      SYSNAME       NOT NULL,
    lignes_attendues INT           NOT NULL
);
GO
MERGE audit.fichier_attendu AS t
USING (VALUES
    (N'categories', N'catalogue/categories.csv', 19),
    (N'fournisseurs', N'catalogue/fournisseurs.csv', 40),
    (N'produits', N'catalogue/produits.csv', 596),
    (N'produits_prix_historique', N'catalogue/produits_prix_historique.csv', 1601),
    (N'clients', N'crm/clients.csv', 16150),
    (N'entrepots', N'logistique/entrepots.csv', 3),
    (N'transporteurs', N'logistique/transporteurs.csv', 4),
    (N'livraisons', N'logistique/livraisons.csv', 61793),
    (N'campagnes_marketing', N'marketing/campagnes_marketing.csv', 152),
    (N'coupons', N'marketing/coupons.csv', 68),
    (N'marketing_depenses_quotidiennes', N'marketing/marketing_depenses_quotidiennes.csv', 3427),
    (N'dim_calendrier', N'referentiels/dim_calendrier.csv', 1096),
    (N'ref_gouvernorats', N'referentiels/ref_gouvernorats.csv', 24),
    (N'remboursements', N'sav/remboursements.csv', 8815),
    (N'mouvements_stock', N'stocks/mouvements_stock.csv', 140284),
    (N'stocks_mensuels', N'stocks/stocks_mensuels.csv', 56562),
    (N'commandes_fournisseurs', N'achats/commandes_fournisseurs.csv', 10370),
    (N'lignes_commande_fournisseur', N'achats/lignes_commande_fournisseur.csv', 11793),
    (N'avis_clients', N'avis/avis_clients.csv', 9344),
    (N'commandes', N'ventes/commandes/commandes_2023_01.csv', 769),
    (N'commandes', N'ventes/commandes/commandes_2023_02.csv', 1240),
    (N'commandes', N'ventes/commandes/commandes_2023_03.csv', 1160),
    (N'commandes', N'ventes/commandes/commandes_2023_04.csv', 1733),
    (N'commandes', N'ventes/commandes/commandes_2023_05.csv', 949),
    (N'commandes', N'ventes/commandes/commandes_2023_06.csv', 992),
    (N'commandes', N'ventes/commandes/commandes_2023_07.csv', 897),
    (N'commandes', N'ventes/commandes/commandes_2023_08.csv', 1703),
    (N'commandes', N'ventes/commandes/commandes_2023_09.csv', 1514),
    (N'commandes', N'ventes/commandes/commandes_2023_10.csv', 1225),
    (N'commandes', N'ventes/commandes/commandes_2023_11.csv', 1583),
    (N'commandes', N'ventes/commandes/commandes_2023_12.csv', 1363),
    (N'commandes', N'ventes/commandes/commandes_2024_01.csv', 1105),
    (N'commandes', N'ventes/commandes/commandes_2024_02.csv', 1912),
    (N'commandes', N'ventes/commandes/commandes_2024_03.csv', 1879),
    (N'commandes', N'ventes/commandes/commandes_2024_04.csv', 2150),
    (N'commandes', N'ventes/commandes/commandes_2024_05.csv', 1223),
    (N'commandes', N'ventes/commandes/commandes_2024_06.csv', 1316),
    (N'commandes', N'ventes/commandes/commandes_2024_07.csv', 1396),
    (N'commandes', N'ventes/commandes/commandes_2024_08.csv', 2442),
    (N'commandes', N'ventes/commandes/commandes_2024_09.csv', 2082),
    (N'commandes', N'ventes/commandes/commandes_2024_10.csv', 1467),
    (N'commandes', N'ventes/commandes/commandes_2024_11.csv', 2206),
    (N'commandes', N'ventes/commandes/commandes_2024_12.csv', 2084),
    (N'commandes', N'ventes/commandes/commandes_2025_01.csv', 1618),
    (N'commandes', N'ventes/commandes/commandes_2025_02.csv', 2290),
    (N'commandes', N'ventes/commandes/commandes_2025_03.csv', 4261),
    (N'commandes', N'ventes/commandes/commandes_2025_04.csv', 1834),
    (N'commandes', N'ventes/commandes/commandes_2025_05.csv', 1845),
    (N'commandes', N'ventes/commandes/commandes_2025_06.csv', 1701),
    (N'commandes', N'ventes/commandes/commandes_2025_07.csv', 1682),
    (N'commandes', N'ventes/commandes/commandes_2025_08.csv', 3250),
    (N'commandes', N'ventes/commandes/commandes_2025_09.csv', 3383),
    (N'commandes', N'ventes/commandes/commandes_2025_10.csv', 2388),
    (N'commandes', N'ventes/commandes/commandes_2025_11.csv', 3306),
    (N'commandes', N'ventes/commandes/commandes_2025_12.csv', 2620),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2023_01.csv', 1356),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2023_02.csv', 2152),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2023_03.csv', 2059),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2023_04.csv', 3038),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2023_05.csv', 1633),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2023_06.csv', 1777),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2023_07.csv', 1583),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2023_08.csv', 2983),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2023_09.csv', 2699),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2023_10.csv', 2124),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2023_11.csv', 2758),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2023_12.csv', 2346),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2024_01.csv', 1916),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2024_02.csv', 3390),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2024_03.csv', 3361),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2024_04.csv', 3783),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2024_05.csv', 2165),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2024_06.csv', 2351),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2024_07.csv', 2501),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2024_08.csv', 4138),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2024_09.csv', 3489),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2024_10.csv', 2539),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2024_11.csv', 3840),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2024_12.csv', 3515),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2025_01.csv', 2779),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2025_02.csv', 4089),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2025_03.csv', 7314),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2025_04.csv', 3187),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2025_05.csv', 3205),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2025_06.csv', 2998),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2025_07.csv', 2984),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2025_08.csv', 5684),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2025_09.csv', 5854),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2025_10.csv', 4209),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2025_11.csv', 5715),
    (N'lignes_commande', N'ventes/lignes_commande/lignes_commande_2025_12.csv', 4509),
    (N'paiements_api', N'paiements_api/paiements.jsonl', 65137)
) AS s (table_cible, chemin_fichier, lignes_attendues)
ON t.chemin_fichier = s.chemin_fichier
WHEN MATCHED THEN UPDATE SET table_cible = s.table_cible, lignes_attendues = s.lignes_attendues
WHEN NOT MATCHED BY TARGET THEN INSERT (chemin_fichier, table_cible, lignes_attendues) VALUES (s.chemin_fichier, s.table_cible, s.lignes_attendues)
WHEN NOT MATCHED BY SOURCE THEN DELETE;
GO
-- 1.1 Par fichier : présent ? lignes lues = lignes chargées = lignes attendues ?
CREATE OR ALTER VIEW audit.v_validation_raw_fichiers AS
WITH lots AS (SELECT DISTINCT id_chargement FROM audit.fichier_source)
SELECT COALESCE(a.id_chargement, f.id_chargement) AS id_chargement,
       COALESCE(a.table_cible, f.table_cible)     AS table_cible,
       COALESCE(a.chemin_fichier, f.chemin_fichier) AS chemin_fichier,
       a.lignes_attendues, f.nb_lignes_fichier, f.nb_lignes_chargees, f.taille_octets, f.empreinte_sha256,
       CASE WHEN f.chemin_fichier IS NULL THEN 'MANQUANT'
            WHEN a.chemin_fichier IS NULL THEN 'NON ATTENDU'
            WHEN f.nb_lignes_fichier <> f.nb_lignes_chargees THEN 'CHARGEMENT INCOMPLET'
            WHEN f.nb_lignes_fichier <> a.lignes_attendues THEN 'VOLUME DIFFERENT'
            ELSE 'OK' END AS statut
FROM (SELECT l.id_chargement, x.* FROM lots l CROSS JOIN audit.fichier_attendu x) a
FULL OUTER JOIN audit.fichier_source f ON f.id_chargement = a.id_chargement AND f.chemin_fichier = a.chemin_fichier;
GO
-- 1.2 Par table RAW
CREATE OR ALTER VIEW audit.v_validation_raw_tables AS
SELECT v.id_chargement, v.table_cible,
       SUM(CASE WHEN v.statut <> 'MANQUANT' THEN 1 ELSE 0 END) AS fichiers_charges,
       SUM(CASE WHEN v.lignes_attendues IS NOT NULL THEN 1 ELSE 0 END) AS fichiers_attendus,
       SUM(v.nb_lignes_fichier) AS lignes_lues, SUM(v.nb_lignes_chargees) AS lignes_chargees, SUM(v.lignes_attendues) AS lignes_attendues,
       t.nb_inseres AS lignes_en_base,
       CASE WHEN SUM(CASE WHEN v.statut <> 'OK' THEN 1 ELSE 0 END) = 0 AND t.nb_inseres = SUM(v.lignes_attendues) THEN 'OK' ELSE 'A VERIFIER' END AS statut
FROM audit.v_validation_raw_fichiers v
LEFT JOIN audit.execution_tache t ON t.id_chargement = v.id_chargement AND t.couche = 'STG_RAW' AND t.objet = CONCAT(N'raw.', v.table_cible)
GROUP BY v.id_chargement, v.table_cible, t.nb_inseres;
GO
-- 1.3 Anomalies techniques du chargement RAW
CREATE OR ALTER VIEW audit.v_validation_raw_anomalies AS
SELECT id_chargement, 'ERREUR' AS type_anomalie, objet, message, date_erreur AS date_evenement
FROM audit.journal_erreur WHERE objet LIKE N'raw.%' OR source = 'PYTHON'
UNION ALL
SELECT id_chargement, statut, chemin_fichier, CONCAT(N'Table ', table_cible, N' : attendu ', lignes_attendues, N', lu ', nb_lignes_fichier, N', chargé ', nb_lignes_chargees), NULL
FROM audit.v_validation_raw_fichiers WHERE statut <> 'OK'
UNION ALL
SELECT f.id_chargement, 'FICHIER EN DOUBLE', f.chemin_fichier, N'Même empreinte SHA-256 qu''un autre fichier du lot', f.date_chargement
FROM audit.fichier_source f
WHERE EXISTS (SELECT 1 FROM audit.fichier_source g WHERE g.id_chargement = f.id_chargement AND g.empreinte_sha256 = f.empreinte_sha256 AND g.id_fichier <> f.id_fichier);
GO
-- 1.4 Décision « RAW prêt »
CREATE OR ALTER VIEW audit.v_validation_raw_decision AS
SELECT v.id_chargement,
       SUM(CASE WHEN v.lignes_attendues IS NOT NULL THEN 1 ELSE 0 END) AS fichiers_attendus,
       SUM(CASE WHEN v.statut <> 'MANQUANT' AND v.lignes_attendues IS NOT NULL THEN 1 ELSE 0 END) AS fichiers_presents,
       SUM(CASE WHEN v.statut = 'MANQUANT' THEN 1 ELSE 0 END) AS fichiers_manquants,
       SUM(v.nb_lignes_chargees) AS lignes_chargees, SUM(v.lignes_attendues) AS lignes_attendues,
       (SELECT COUNT(*) FROM audit.v_validation_raw_anomalies a WHERE a.id_chargement = v.id_chargement) AS anomalies_techniques,
       CASE WHEN SUM(CASE WHEN v.statut <> 'OK' THEN 1 ELSE 0 END) = 0
             AND (SELECT COUNT(*) FROM audit.v_validation_raw_anomalies a WHERE a.id_chargement = v.id_chargement) = 0
            THEN N'RAW PRÊT' ELSE N'CHARGEMENT À CORRIGER' END AS decision
FROM audit.v_validation_raw_fichiers v
GROUP BY v.id_chargement;
GO

/* =====================================================================
   2. QUALITÉ AVANT / APRÈS
   « Avant » mesuré dans STG_RAW (ou STG_CLEAN pour les règles d'intégration), « après » dans STG_CLEAN / STG_INTEGRATED.
   ===================================================================== */
IF OBJECT_ID(N'audit.indicateur_qualite', N'U') IS NULL
CREATE TABLE audit.indicateur_qualite (
    indicateur_id  VARCHAR(5)    NOT NULL CONSTRAINT PK_indicateur_qualite PRIMARY KEY,
    regle_id       VARCHAR(10)   NOT NULL,
    table_cible    NVARCHAR(100) NOT NULL,
    libelle        NVARCHAR(200) NOT NULL,
    avant_attendu  INT           NOT NULL,
    apres_attendu  INT           NOT NULL      -- résidu accepté après traitement (0 en général)
);
GO
MERGE audit.indicateur_qualite AS t
USING (VALUES
    (N'I01', N'QR01', N'commandes', N'Commandes en double', 300, 0),
    (N'I02', N'QR02', N'lignes_commande', N'Lignes de commande en double', 120, 0),
    (N'I03', N'QR03', N'mouvements_stock', N'Mouvements de stock en double', 100, 0),
    (N'I04', N'QR04', N'avis_clients', N'Avis en double', 30, 0),
    (N'I05', N'QR05', N'paiements', N'Paiements en double', 644, 0),
    (N'I06', N'QR06', N'commandes', N'Dates de commande au format JJ/MM/AAAA', 2650, 0),
    (N'I07', N'QR07', N'clients', N'Dates de naissance au format JJ/MM/AAAA', 1262, 0),
    (N'I08', N'QR09', N'clients', N'Téléphones hors format +216XXXXXXXX', 1379, 0),
    (N'I09', N'QR10', N'clients', N'E-mails non normalisés (casse, espaces)', 365, 0),
    (N'I10', N'QR45', N'clients', N'E-mails malformés ('' at '', ''@@'', ''@'' absent)', 80, 0),
    (N'I11', N'QR12', N'clients', N'Genre manquant (13 restent vides : prénom mixte ou client professionnel)', 243, 13),
    (N'I12', N'QR13', N'commandes', N'Statuts de commande non conformes', 333, 0),
    (N'I13', N'QR14', N'livraisons', N'Transporteurs en minuscules', 100, 0),
    (N'I14', N'QR16', N'produits', N'Catégorie produit manquante', 6, 0),
    (N'I15', N'QR17', N'produits', N'SKU partagés par plusieurs produits', 3, 0),
    (N'I16', N'QR18', N'produits', N'Prix catalogue ≤ 0', 6, 0),
    (N'I17', N'QR19', N'commandes', N'Canal de vente manquant', 662, 0),
    (N'I18', N'QR20', N'commandes', N'Totaux de commande incohérents', 55, 0),
    (N'I19', N'QR21', N'lignes_commande', N'Quantités ≤ 0', 45, 0),
    (N'I20', N'QR22', N'lignes_commande', N'Montant ≠ quantité × prix (hors quantités ≤ 0)', 40, 0),
    (N'I21', N'QR28', N'avis_clients', N'Notes hors 1–5', 10, 0),
    (N'I22', N'QR30', N'marketing_depenses_quotidiennes', N'Impressions < clics', 15, 0),
    (N'I23', N'QR31', N'lignes_commande_fournisseur', N'Quantité reçue > commandée', 10, 0),
    (N'I24', N'QR32', N'remboursements', N'Remboursé > demandé', 20, 0),
    (N'I25', N'QR34', N'livraisons', N'Livraison avant l''expédition', 25, 0),
    (N'I26', N'QR35', N'livraisons', N'Statut de livraison manquant', 30, 0),
    (N'I27', N'QR36', N'mouvements_stock', N'Signe incohérent avec le type de mouvement', 40, 0),
    (N'I28', N'QR37', N'stocks_mensuels', N'Stocks de fin de mois négatifs', 10, 0),
    (N'I29', N'QR46', N'marketing_depenses_quotidiennes', N'Dépenses négatives', 10, 0),
    (N'I30', N'QR27', N'clients', N'Clients en double (prénom + nom + téléphone)', 150, 0),
    (N'I31', N'QR26', N'paiements', N'Paiements sans commande', 15, 0),
    (N'I32', N'QR47', N'paiements', N'Montants de paiement × 1 000', 50, 0),
    (N'I33', N'QR48', N'commandes_fournisseurs', N'Réception avant la commande fournisseur', 8, 0)
) AS s (indicateur_id, regle_id, table_cible, libelle, avant_attendu, apres_attendu)
ON t.indicateur_id = s.indicateur_id
WHEN MATCHED THEN UPDATE SET regle_id = s.regle_id, table_cible = s.table_cible, libelle = s.libelle, avant_attendu = s.avant_attendu, apres_attendu = s.apres_attendu
WHEN NOT MATCHED BY TARGET THEN INSERT VALUES (s.indicateur_id, s.regle_id, s.table_cible, s.libelle, s.avant_attendu, s.apres_attendu)
WHEN NOT MATCHED BY SOURCE THEN DELETE;
GO
IF OBJECT_ID(N'audit.qualite_mesure', N'U') IS NULL
CREATE TABLE audit.qualite_mesure (
    id_chargement  INT          NOT NULL,
    indicateur_id  VARCHAR(5)   NOT NULL,
    avant          INT          NULL,
    apres          INT          NULL,
    date_mesure    DATETIME2(0) NOT NULL CONSTRAINT DF_qualite_mesure_date DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_qualite_mesure PRIMARY KEY (id_chargement, indicateur_id)
);
GO
CREATE OR ALTER PROCEDURE audit.usp_mesurer_qualite
    @lot INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @lot IS NULL SELECT @lot = MAX(id_chargement) FROM audit.execution_lot;
    IF NOT EXISTS (SELECT 1 FROM [TuniShop_STG_RAW].raw.commandes WHERE id_chargement = @lot)
        THROW 50040, N'STG_RAW ne contient pas ce lot (seul le dernier lot chargé est conservé dans RAW).', 1;
    DELETE FROM audit.qualite_mesure WHERE id_chargement = @lot;
    DECLARE @a INT, @p INT;
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) - COUNT(DISTINCT UPPER(TRIM(commande_id))) FROM [TuniShop_STG_RAW].raw.commandes WHERE id_chargement = @lot); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) - COUNT(DISTINCT commande_id) FROM [TuniShop_STG_CLEAN].clean.v_commandes); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I01', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) - COUNT(DISTINCT UPPER(TRIM(ligne_id))) FROM [TuniShop_STG_RAW].raw.lignes_commande WHERE id_chargement = @lot); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) - COUNT(DISTINCT ligne_id) FROM [TuniShop_STG_CLEAN].clean.v_lignes_commande); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I02', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) - COUNT(DISTINCT UPPER(TRIM(mouvement_id))) FROM [TuniShop_STG_RAW].raw.mouvements_stock WHERE id_chargement = @lot); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) - COUNT(DISTINCT mouvement_id) FROM [TuniShop_STG_CLEAN].clean.v_mouvements_stock); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I03', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) - COUNT(DISTINCT UPPER(TRIM(avis_id))) FROM [TuniShop_STG_RAW].raw.avis_clients WHERE id_chargement = @lot); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) - COUNT(DISTINCT avis_id) FROM [TuniShop_STG_CLEAN].clean.v_avis_clients); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I04', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) - COUNT(DISTINCT JSON_VALUE(ligne_json, '$.payment_id')) FROM [TuniShop_STG_RAW].raw.paiements_api WHERE id_chargement = @lot); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) - COUNT(DISTINCT paiement_id) FROM [TuniShop_STG_CLEAN].clean.v_paiements); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I05', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(DISTINCT commande_id) FROM [TuniShop_STG_RAW].raw.commandes WHERE id_chargement = @lot AND TRIM(date_commande) LIKE '__/__/____%'); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_commandes WHERE date_commande IS NULL); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I06', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_RAW].raw.clients WHERE id_chargement = @lot AND TRIM(date_naissance) LIKE '__/__/____'); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT 0); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I07', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_RAW].raw.clients WHERE id_chargement = @lot AND telephone NOT LIKE '+216[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_clients WHERE telephone IS NOT NULL AND telephone NOT LIKE '+216[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I08', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_RAW].raw.clients WHERE id_chargement = @lot AND NULLIF(TRIM(email), '') IS NOT NULL AND CONCAT(email, N'|') COLLATE Latin1_General_CS_AS <> CONCAT(LOWER(TRIM(email)), N'|')); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_clients WHERE CONCAT(email, N'|') COLLATE Latin1_General_CS_AS <> CONCAT(LOWER(TRIM(email)), N'|')); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I09', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_RAW].raw.clients WHERE id_chargement = @lot AND NULLIF(TRIM(email), '') IS NOT NULL AND (email LIKE '% at %' OR email LIKE '%@@%' OR email NOT LIKE '%@%')); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_clients WHERE email LIKE '% at %' OR email LIKE '%@@%' OR email NOT LIKE '%@%'); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I10', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_RAW].raw.clients WHERE id_chargement = @lot AND NULLIF(TRIM(genre), '') IS NULL); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_clients WHERE genre IS NULL); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I11', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(DISTINCT commande_id) FROM [TuniShop_STG_RAW].raw.commandes WHERE id_chargement = @lot AND statut_commande COLLATE Latin1_General_CS_AS NOT IN ('livree','partiellement_retournee','annulee','livraison_echouee','retournee','paiement_echoue','expediee','en_preparation')); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_commandes WHERE statut_commande NOT IN ('livree','partiellement_retournee','annulee','livraison_echouee','retournee','paiement_echoue','expediee','en_preparation')); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I12', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_RAW].raw.livraisons WHERE id_chargement = @lot AND transporteur_id COLLATE Latin1_General_CS_AS <> UPPER(transporteur_id)); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_livraisons WHERE transporteur_id COLLATE Latin1_General_CS_AS <> UPPER(transporteur_id)); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I13', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_RAW].raw.produits WHERE id_chargement = @lot AND NULLIF(TRIM(categorie_id), '') IS NULL); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_produits WHERE categorie_id IS NULL); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I14', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) - COUNT(DISTINCT TRIM(sku)) FROM [TuniShop_STG_RAW].raw.produits WHERE id_chargement = @lot); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) - COUNT(DISTINCT sku) FROM [TuniShop_STG_CLEAN].clean.v_produits); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I15', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_RAW].raw.produits WHERE id_chargement = @lot AND TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM(prix_catalogue_ttc_actuel), ''), ',', '.')) <= 0); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_produits WHERE prix_catalogue_ttc_actuel <= 0 OR prix_catalogue_ttc_actuel IS NULL); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I16', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(DISTINCT commande_id) FROM [TuniShop_STG_RAW].raw.commandes WHERE id_chargement = @lot AND NULLIF(TRIM(canal), '') IS NULL); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_commandes WHERE canal IS NULL); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I17', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM (SELECT DISTINCT commande_id, sous_total_ttc, remise_coupon_ttc, frais_livraison_ttc, montant_total_ttc FROM [TuniShop_STG_RAW].raw.commandes WHERE id_chargement = @lot) r WHERE ABS(TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM(sous_total_ttc), ''), ',', '.')) - TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM(remise_coupon_ttc), ''), ',', '.')) + TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM(frais_livraison_ttc), ''), ',', '.')) - TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM(montant_total_ttc), ''), ',', '.'))) > 0.01); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_commandes WHERE ABS(sous_total_ttc - remise_coupon_ttc + frais_livraison_ttc - montant_total_ttc) > 0.01); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I18', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(DISTINCT ligne_id) FROM [TuniShop_STG_RAW].raw.lignes_commande WHERE id_chargement = @lot AND TRY_CONVERT(INT, quantite) <= 0); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_lignes_commande WHERE quantite <= 0); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I19', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(DISTINCT ligne_id) FROM [TuniShop_STG_RAW].raw.lignes_commande WHERE id_chargement = @lot AND TRY_CONVERT(INT, quantite) > 0 AND ABS(TRY_CONVERT(INT, quantite) * TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM(prix_unitaire_ttc), ''), ',', '.')) - TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM(montant_ligne_ttc), ''), ',', '.'))) > 0.01); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_lignes_commande WHERE ABS(quantite * prix_unitaire_ttc - montant_ligne_ttc) > 0.01); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I20', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(DISTINCT avis_id) FROM [TuniShop_STG_RAW].raw.avis_clients WHERE id_chargement = @lot AND TRY_CONVERT(INT, note) NOT BETWEEN 1 AND 5); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_avis_clients WHERE note NOT BETWEEN 1 AND 5); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I21', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_RAW].raw.marketing_depenses_quotidiennes WHERE id_chargement = @lot AND TRY_CONVERT(INT, impressions) < TRY_CONVERT(INT, clics)); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_marketing_depenses_quotidiennes WHERE impressions < clics); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I22', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_RAW].raw.lignes_commande_fournisseur WHERE id_chargement = @lot AND TRY_CONVERT(INT, quantite_recue) > TRY_CONVERT(INT, quantite_commandee)); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_lignes_commande_fournisseur WHERE quantite_recue > quantite_commandee); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I23', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_RAW].raw.remboursements WHERE id_chargement = @lot AND TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM(montant_rembourse_ttc), ''), ',', '.')) > TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM(montant_demande_ttc), ''), ',', '.'))); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_remboursements WHERE montant_rembourse_ttc > montant_demande_ttc); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I24', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_RAW].raw.livraisons WHERE id_chargement = @lot AND TRY_CONVERT(DATETIME2(0), NULLIF(TRIM(date_livraison_reelle), ''), 120) < TRY_CONVERT(DATETIME2(0), NULLIF(TRIM(date_expedition), ''), 120)); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_livraisons WHERE date_livraison_reelle < date_expedition); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I25', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_RAW].raw.livraisons WHERE id_chargement = @lot AND NULLIF(TRIM(statut_livraison), '') IS NULL); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_livraisons WHERE statut_livraison IS NULL); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I26', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(DISTINCT mouvement_id) FROM [TuniShop_STG_RAW].raw.mouvements_stock WHERE id_chargement = @lot AND ((LOWER(TRIM(type_mouvement)) IN ('vente','mise_au_rebut') AND TRY_CONVERT(INT, quantite) > 0) OR (LOWER(TRIM(type_mouvement)) NOT IN ('vente','mise_au_rebut','ajustement_inventaire') AND TRY_CONVERT(INT, quantite) < 0))); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_mouvements_stock WHERE (type_mouvement IN ('vente','mise_au_rebut') AND quantite > 0) OR (type_mouvement NOT IN ('vente','mise_au_rebut','ajustement_inventaire') AND quantite < 0)); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I27', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_RAW].raw.stocks_mensuels WHERE id_chargement = @lot AND TRY_CONVERT(INT, stock_fin_mois) < 0); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_stocks_mensuels WHERE stock_fin_mois < 0); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I28', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_RAW].raw.marketing_depenses_quotidiennes WHERE id_chargement = @lot AND TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM(depense_ht), ''), ',', '.')) < 0); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_marketing_depenses_quotidiennes WHERE depense_ht < 0); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I29', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_clients a WHERE a.client_id LIKE 'CLI9[0-9][0-9][0-9][0-9][0-9]' AND EXISTS (SELECT 1 FROM [TuniShop_STG_CLEAN].clean.v_clients b WHERE b.prenom = a.prenom AND b.nom = a.nom AND b.telephone = a.telephone AND b.client_id <> a.client_id)); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM (SELECT prenom, nom, telephone FROM [TuniShop_STG_INTEGRATED].integ.v_client WHERE type_client = 'particulier' AND telephone IS NOT NULL GROUP BY prenom, nom, telephone HAVING COUNT(*) > 1) x); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I30', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_paiements p WHERE NOT EXISTS (SELECT 1 FROM [TuniShop_STG_CLEAN].clean.v_commandes c WHERE c.commande_id = p.commande_id)); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_INTEGRATED].integ.v_paiement p WHERE NOT EXISTS (SELECT 1 FROM [TuniShop_STG_INTEGRATED].integ.v_commande c WHERE c.commande_id = p.commande_id)); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I31', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_paiements p JOIN [TuniShop_STG_CLEAN].clean.v_commandes c ON c.commande_id = p.commande_id WHERE ABS(p.montant_ttc / 1000 - c.montant_total_ttc) < 0.01); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_INTEGRATED].integ.v_paiement p JOIN [TuniShop_STG_INTEGRATED].integ.v_commande c ON c.commande_id = p.commande_id WHERE ABS(p.montant_ttc - c.montant_total_ttc) > 0.01); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I32', @a, @p);
    SET @a = NULL; SET @p = NULL;
    BEGIN TRY SET @a = (SELECT COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_commandes_fournisseurs WHERE date_reception < date_commande); END TRY BEGIN CATCH SET @a = NULL; END CATCH
    BEGIN TRY SET @p = (SELECT COUNT(*) FROM [TuniShop_STG_INTEGRATED].integ.v_commande_fournisseur WHERE date_reception < date_commande); END TRY BEGIN CATCH SET @p = NULL; END CATCH
    INSERT INTO audit.qualite_mesure (id_chargement, indicateur_id, avant, apres) VALUES (@lot, 'I33', @a, @p);
    SELECT * FROM audit.v_qualite_avant_apres WHERE id_chargement = @lot ORDER BY indicateur_id;
END;
GO
CREATE OR ALTER VIEW audit.v_qualite_avant_apres AS
SELECT m.id_chargement, i.indicateur_id, i.regle_id, i.table_cible, i.libelle,
       m.avant, i.avant_attendu, m.apres, i.apres_attendu,
       CASE WHEN m.avant IS NULL OR m.apres IS NULL THEN 'MESURE IMPOSSIBLE'
            WHEN m.apres = i.apres_attendu AND m.avant = i.avant_attendu THEN 'CORRIGÉ'
            WHEN m.apres = i.apres_attendu THEN 'CORRIGÉ (volume avant différent)'
            ELSE 'RESTE A TRAITER' END AS statut
FROM audit.qualite_mesure m
JOIN audit.indicateur_qualite i ON i.indicateur_id = m.indicateur_id;
GO

/* =====================================================================
   3. EXACTITUDE PAR RAPPORT À donnees_reference
   Comparaison colonne par colonne de STG_CLEAN (vues v_*) avec ref.<table> (copie texte des CSV de référence),
   sur les clés présentes des deux côtés. Les écarts attendus et expliqués sont listés dans audit.reference_ecart_attendu.
   ===================================================================== */
IF OBJECT_ID(N'audit.reference_ecart_attendu', N'U') IS NULL
CREATE TABLE audit.reference_ecart_attendu (
    table_cible    NVARCHAR(100) NOT NULL,
    colonne        NVARCHAR(100) NOT NULL,
    ecarts_attendus INT          NOT NULL,
    explication    NVARCHAR(400) NOT NULL,
    CONSTRAINT PK_reference_ecart_attendu PRIMARY KEY (table_cible, colonne)
);
GO
MERGE audit.reference_ecart_attendu AS t
USING (VALUES
    (N'commandes', N'client_id', 25, N'QR23 : client inexistant (CLI0999xxx), conservé tel quel ; rattaché au membre inconnu (-1) en DWH'),
    (N'commandes', N'date_commande', 2598, N'QR06 : format JJ/MM/AAAA HH:MI reçu, secondes perdues à la source (non récupérables)'),
    (N'commandes', N'canal', 507, N'QR19 : canal manquant sur mobile, non déductible → « non_renseigne »'),
    (N'lignes_commande', N'produit_id', 20, N'QR24 : produit inexistant (PRD9xxx) ; membre inconnu (-1) en DWH'),
    (N'clients', N'genre', 12, N'QR12 : prénom mixte (« Malek ») : genre laissé vide plutôt qu''imputé au hasard'),
    (N'clients', N'date_naissance', 35, N'QR44 : date aberrante mise à NULL (valeur d''origine non récupérable)'),
    (N'remboursements', N'date_remboursement', 15, N'QR33 : date antérieure à la demande mise à NULL'),
    (N'avis_clients', N'note', 10, N'QR28 : note hors 1–5 mise à NULL'),
    (N'lignes_commande_fournisseur', N'quantite_recue', 1, N'QR31 : réception partielle non déductible (plafonnée à la quantité commandée)'),
    (N'marketing_depenses_quotidiennes', N'campagne_id', 5, N'QR25 : campagne inexistante ; 3 rattachées en STG_INTEGRATED, 2 ambiguës → membre inconnu'),
    (N'marketing_depenses_quotidiennes', N'impressions', 15, N'QR30 : impressions < clics mises à NULL'),
    (N'paiements', N'commande_id', 15, N'QR26 : paiement sans commande ; 13 rattachés en STG_INTEGRATED, 2 rejetés'),
    (N'paiements', N'montant_ttc', 50, N'QR47 : montant × 1 000 corrigé en STG_INTEGRATED'),
    (N'commandes_fournisseurs', N'date_reception', 8, N'QR48 : réception antérieure à la commande, corrigée en STG_INTEGRATED'),
    (N'clients', N'(lignes en trop)', 150, N'QR27 : identifiants doublons (CLI9xxxxx) présents en STG_CLEAN, fusionnés en STG_INTEGRATED')
) AS s (table_cible, colonne, ecarts_attendus, explication)
ON t.table_cible = s.table_cible AND t.colonne = s.colonne
WHEN MATCHED THEN UPDATE SET ecarts_attendus = s.ecarts_attendus, explication = s.explication
WHEN NOT MATCHED BY TARGET THEN INSERT VALUES (s.table_cible, s.colonne, s.ecarts_attendus, s.explication)
WHEN NOT MATCHED BY SOURCE THEN DELETE;
GO
IF OBJECT_ID(N'audit.reference_comparaison', N'U') IS NULL
CREATE TABLE audit.reference_comparaison (
    id_chargement   INT           NOT NULL,
    table_cible     NVARCHAR(100) NOT NULL,
    colonne         NVARCHAR(100) NOT NULL,      -- '(lignes en trop)' / '(lignes absentes)' pour les écarts de clés
    lignes_comparees INT          NULL,
    ecarts          INT           NOT NULL,
    date_mesure     DATETIME2(0)  NOT NULL CONSTRAINT DF_reference_comparaison_date DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_reference_comparaison PRIMARY KEY (id_chargement, table_cible, colonne)
);
GO
CREATE OR ALTER PROCEDURE audit.usp_comparer_reference
    @lot INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @lot IS NULL SELECT @lot = MAX(id_chargement) FROM audit.execution_lot;
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE schema_id = SCHEMA_ID('ref'))
        THROW 50041, N'Schéma ref vide : charger donnees_reference (python tunishop_pipeline.py reference --dossier-ref ...).', 1;
    DELETE FROM audit.reference_comparaison WHERE id_chargement = @lot;
    DECLARE @tables TABLE (t SYSNAME, pk SYSNAME);
    INSERT INTO @tables VALUES
    (N'avis_clients', N'avis_id'),
    (N'campagnes_marketing', N'campagne_id'),
    (N'categories', N'categorie_id'),
    (N'clients', N'client_id'),
    (N'commandes', N'commande_id'),
    (N'commandes_fournisseurs', N'commande_fournisseur_id'),
    (N'coupons', N'code_coupon'),
    (N'dim_calendrier', N'date'),
    (N'entrepots', N'entrepot_id'),
    (N'fournisseurs', N'fournisseur_id'),
    (N'lignes_commande', N'ligne_id'),
    (N'lignes_commande_fournisseur', N'ligne_cf_id'),
    (N'livraisons', N'livraison_id'),
    (N'marketing_depenses_quotidiennes', N'depense_id'),
    (N'mouvements_stock', N'mouvement_id'),
    (N'paiements', N'paiement_id'),
    (N'produits', N'produit_id'),
    (N'produits_prix_historique', N'prix_id'),
    (N'ref_gouvernorats', N'gouvernorat_id'),
    (N'remboursements', N'remboursement_id'),
    (N'stocks_mensuels', N'inventaire_id'),
    (N'transporteurs', N'transporteur_id');
    DECLARE @t SYSNAME, @pk SYSNAME, @c SYSNAME, @type SYSNAME, @cond NVARCHAR(MAX), @sql NVARCHAR(MAX), @n INT, @e INT, @cle NVARCHAR(300);
    DECLARE ct CURSOR LOCAL FAST_FORWARD FOR
        SELECT tb.t, tb.pk FROM @tables tb WHERE OBJECT_ID(CONCAT(N'ref.', QUOTENAME(tb.t))) IS NOT NULL;
    OPEN ct; FETCH NEXT FROM ct INTO @t, @pk;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- clé de la vue nettoyée convertie en texte comme dans le CSV de référence (style 23 pour une clé de type DATE)
        SET @cle = CASE WHEN (SELECT TYPE_NAME(user_type_id) FROM [TuniShop_STG_CLEAN].sys.columns
                              WHERE object_id = OBJECT_ID(CONCAT(N'[TuniShop_STG_CLEAN].clean.', QUOTENAME(@t))) AND name = @pk) = 'date'
                        THEN CONCAT(N'CONVERT(NVARCHAR(100), c.', QUOTENAME(@pk), N', 23)')
                        ELSE CONCAT(N'CONVERT(NVARCHAR(100), c.', QUOTENAME(@pk), N')') END;
        -- clés présentes d'un seul côté
        SET @sql = CONCAT(N'SELECT @e = COUNT(*) FROM [TuniShop_STG_CLEAN].clean.', QUOTENAME('v_' + @t), N' c WHERE NOT EXISTS (SELECT 1 FROM ref.', QUOTENAME(@t),
                          N' r WHERE r.', QUOTENAME(@pk), N' = ', @cle, N')');
        EXEC sp_executesql @sql, N'@e INT OUTPUT', @e = @e OUTPUT;
        INSERT INTO audit.reference_comparaison (id_chargement, table_cible, colonne, lignes_comparees, ecarts) VALUES (@lot, @t, N'(lignes en trop)', NULL, @e);
        SET @sql = CONCAT(N'SELECT @e = COUNT(*) FROM ref.', QUOTENAME(@t), N' r WHERE NOT EXISTS (SELECT 1 FROM [TuniShop_STG_CLEAN].clean.', QUOTENAME('v_' + @t),
                          N' c WHERE ', @cle, N' = r.', QUOTENAME(@pk), N')');
        EXEC sp_executesql @sql, N'@e INT OUTPUT', @e = @e OUTPUT;
        INSERT INTO audit.reference_comparaison (id_chargement, table_cible, colonne, lignes_comparees, ecarts) VALUES (@lot, @t, N'(lignes absentes)', NULL, @e);
        -- colonnes communes, comparées selon le type de la colonne nettoyée
        DECLARE cc CURSOR LOCAL FAST_FORWARD FOR
            SELECT c.name, TYPE_NAME(c.user_type_id)
            FROM [TuniShop_STG_CLEAN].sys.columns c
            WHERE c.object_id = OBJECT_ID(CONCAT(N'[TuniShop_STG_CLEAN].clean.', QUOTENAME(@t)))
              AND c.name <> @pk
              AND EXISTS (SELECT 1 FROM sys.columns r WHERE r.object_id = OBJECT_ID(CONCAT(N'ref.', QUOTENAME(@t))) AND r.name = c.name);
        OPEN cc; FETCH NEXT FROM cc INTO @c, @type;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @rv NVARCHAR(400) = CONCAT(N'NULLIF(r.', QUOTENAME(@c), N', N'''')'), @cv NVARCHAR(200) = CONCAT(N'c.', QUOTENAME(@c));
            -- un seul côté NULL = écart ; les deux NULL = identique ; sinon comparaison selon le type
            SET @cond = CONCAT(N'CASE WHEN ', @rv, N' IS NULL AND ', @cv, N' IS NULL THEN 0 WHEN ', @rv, N' IS NULL OR ', @cv, N' IS NULL THEN 1 WHEN ', CASE
                WHEN @type IN ('decimal','numeric','float','real','money') THEN CONCAT(N'ABS(TRY_CONVERT(DECIMAL(18,4), ', @rv, N') - ', @cv, N') < 0.0005')
                WHEN @type IN ('int','smallint','tinyint','bigint') THEN CONCAT(N'TRY_CONVERT(BIGINT, TRY_CONVERT(DECIMAL(18,4), ', @rv, N')) = ', @cv)
                WHEN @type = 'bit' THEN CONCAT(N'(CASE UPPER(', @rv, N') WHEN ''TRUE'' THEN 1 WHEN ''FALSE'' THEN 0 ELSE TRY_CONVERT(INT, ', @rv, N') END) = ', @cv)
                WHEN @type = 'date' THEN CONCAT(N'TRY_CONVERT(DATE, ', @rv, N', 23) = ', @cv)
                WHEN @type IN ('datetime2','datetime','smalldatetime') THEN CONCAT(N'TRY_CONVERT(DATETIME2(0), ', @rv, N', 120) = ', @cv)
                ELSE CONCAT(N'CONCAT(', @rv, N', N''|'') COLLATE Latin1_General_CS_AS = CONCAT(', @cv, N', N''|'')') END,
                N' THEN 0 ELSE 1 END');
            SET @sql = CONCAT(N'SELECT @n = COUNT(*), @e = SUM(', @cond, N') FROM [TuniShop_STG_CLEAN].clean.', QUOTENAME('v_' + @t),
                              N' c JOIN ref.', QUOTENAME(@t), N' r ON r.', QUOTENAME(@pk), N' = ', @cle);
            EXEC sp_executesql @sql, N'@n INT OUTPUT, @e INT OUTPUT', @n = @n OUTPUT, @e = @e OUTPUT;
            INSERT INTO audit.reference_comparaison (id_chargement, table_cible, colonne, lignes_comparees, ecarts) VALUES (@lot, @t, @c, @n, ISNULL(@e, 0));
            FETCH NEXT FROM cc INTO @c, @type;
        END
        CLOSE cc; DEALLOCATE cc;
        FETCH NEXT FROM ct INTO @t, @pk;
    END
    CLOSE ct; DEALLOCATE ct;
    SELECT * FROM audit.v_reference_exactitude_tables WHERE id_chargement = @lot ORDER BY table_cible;
END;
GO
CREATE OR ALTER VIEW audit.v_reference_exactitude_colonnes AS
SELECT c.id_chargement, c.table_cible, c.colonne, c.lignes_comparees, c.ecarts, a.ecarts_attendus, a.explication,
       CASE WHEN c.lignes_comparees > 0 THEN CAST(100.0 * (c.lignes_comparees - c.ecarts) / c.lignes_comparees AS DECIMAL(6,2)) END AS exactitude_pct,
       CASE WHEN c.ecarts = 0 AND a.table_cible IS NULL THEN 'IDENTIQUE'
            WHEN c.ecarts = ISNULL(a.ecarts_attendus, -1) THEN 'ECART EXPLIQUE'
            ELSE 'ECART NON EXPLIQUE' END AS statut
FROM audit.reference_comparaison c
LEFT JOIN audit.reference_ecart_attendu a ON a.table_cible = c.table_cible AND a.colonne = c.colonne;
GO
CREATE OR ALTER VIEW audit.v_reference_exactitude_tables AS
SELECT id_chargement, table_cible,
       MAX(lignes_comparees) AS lignes_comparees,
       SUM(CASE WHEN lignes_comparees IS NOT NULL THEN 1 ELSE 0 END) AS colonnes_comparees,
       SUM(CASE WHEN lignes_comparees IS NOT NULL THEN lignes_comparees ELSE 0 END) AS valeurs_comparees,
       SUM(CASE WHEN lignes_comparees IS NOT NULL THEN ecarts ELSE 0 END) AS valeurs_differentes,
       CAST(100.0 * (SUM(CASE WHEN lignes_comparees IS NOT NULL THEN lignes_comparees - ecarts ELSE 0 END))
            / NULLIF(SUM(CASE WHEN lignes_comparees IS NOT NULL THEN lignes_comparees ELSE 0 END), 0) AS DECIMAL(7,3)) AS exactitude_pct,
       SUM(CASE WHEN statut = 'ECART NON EXPLIQUE' THEN 1 ELSE 0 END) AS ecarts_non_expliques
FROM audit.v_reference_exactitude_colonnes
GROUP BY id_chargement, table_cible;
GO

/* =====================================================================
   4. DÉCISION DE FIN DE PHASE STAGING
   ===================================================================== */
CREATE OR ALTER VIEW audit.v_validation_staging_decision AS
SELECT d.id_chargement, d.decision AS decision_raw, d.fichiers_presents, d.fichiers_attendus, d.lignes_chargees,
       j.combinaisons_conformes, j.combinaisons_total,
       (SELECT COUNT(*) FROM audit.v_qualite_avant_apres q WHERE q.id_chargement = d.id_chargement) AS indicateurs_mesures,
       (SELECT COUNT(*) FROM audit.v_qualite_avant_apres q WHERE q.id_chargement = d.id_chargement AND q.statut LIKE 'CORRIGÉ%') AS indicateurs_corriges,
       (SELECT CAST(AVG(e.exactitude_pct) AS DECIMAL(7,3)) FROM audit.v_reference_exactitude_tables e WHERE e.id_chargement = d.id_chargement) AS exactitude_moyenne_pct,
       (SELECT SUM(e.ecarts_non_expliques) FROM audit.v_reference_exactitude_tables e WHERE e.id_chargement = d.id_chargement) AS ecarts_non_expliques,
       CASE WHEN d.decision = N'RAW PRÊT'
             AND j.combinaisons_conformes = j.combinaisons_total
             AND NOT EXISTS (SELECT 1 FROM audit.v_qualite_avant_apres q WHERE q.id_chargement = d.id_chargement AND q.statut NOT LIKE 'CORRIGÉ%')
             AND EXISTS (SELECT 1 FROM audit.v_qualite_avant_apres q WHERE q.id_chargement = d.id_chargement)
             AND EXISTS (SELECT 1 FROM audit.v_reference_exactitude_tables e WHERE e.id_chargement = d.id_chargement)
             AND NOT EXISTS (SELECT 1 FROM audit.v_reference_exactitude_tables e WHERE e.id_chargement = d.id_chargement AND e.ecarts_non_expliques > 0)
            THEN N'STAGING VALIDÉ : passage à la phase DWH'
            ELSE N'STAGING NON VALIDÉ : voir les vues de détail' END AS decision
FROM audit.v_validation_raw_decision d
LEFT JOIN audit.v_journal_rejets_bilan j ON j.id_chargement = d.id_chargement;
GO
-- Exécution complète pour un lot : mesures avant/après + comparaison avec la référence + décision
CREATE OR ALTER PROCEDURE audit.usp_valider_staging
    @lot INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @lot IS NULL SELECT @lot = MAX(id_chargement) FROM audit.execution_lot;
    EXEC audit.usp_mesurer_qualite @lot = @lot;
    IF EXISTS (SELECT 1 FROM sys.tables WHERE schema_id = SCHEMA_ID('ref')) EXEC audit.usp_comparer_reference @lot = @lot;
    SELECT * FROM audit.v_validation_staging_decision WHERE id_chargement = @lot;
END;
GO
PRINT N'Rapports de validation du staging créés dans TuniShop_ADMIN.audit.';
GO
