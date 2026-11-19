/* =====================================================================
   Projet      : TuniShop — Data Warehouse e-commerce (portfolio)
   Script      : 03_Procedures_CLEAN_INTEGRATED.sql
   Objet       : Procédures INCRÉMENTALES (MERGE + empreinte SHA-256) : RAW→CLEAN (22 + orchestration) et CLEAN→INTEGRATED (22 + orchestration). Paramètre @mode_suppression = marquer (défaut) | supprimer | ignorer. Prérequis : 01_Creation_Bases.sql et 02_Audit_Logs.sql.
   Cible       : Microsoft SQL Server 2019+ (SSMS) — compatibilité 150
   Exécution   : SSMS, mode SQLCMD inutile ; exécuter en entier (F5)
   Généré le   : 2026-10-17 depuis le modèle de métadonnées du projet
   ===================================================================== */
SET NOCOUNT ON;
GO

/* =====================================================================
   PARTIE 1 — RAW → CLEAN  (base TuniShop_STG_CLEAN)  —  chargement INCRÉMENTAL
   STG_RAW est rechargé en entier (zone d'atterrissage) ; STG_CLEAN n'est
   jamais vidé : chaque procédure fusionne (MERGE) les données du lot.
   ===================================================================== */
USE [TuniShop_STG_CLEAN];
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_categories  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.categories  →  clean.categories   (Référentiel des catégories et sous-catégories produit)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_categories
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'categories';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[categorie_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[categories] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[categorie_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [categorie_id], [categorie], [sous_categorie], [taux_tva], [taux_retour_cible], [marge_brute_cible], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[categories];
    INSERT INTO #nouveau ([categorie_id], [categorie], [sous_categorie], [taux_tva], [taux_retour_cible], [marge_brute_cible], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([categorie_id]), '')) AS [categorie_id],
            NULLIF(TRIM([categorie]), '') AS [categorie],
            NULLIF(TRIM([sous_categorie]), '') AS [sous_categorie],
            TRY_CONVERT(TINYINT, NULLIF(TRIM([taux_tva]), '')) AS [taux_tva],
            TRY_CONVERT(DECIMAL(5,2), REPLACE(NULLIF(TRIM([taux_retour_cible]), ''), ',', '.')) AS [taux_retour_cible],
            TRY_CONVERT(DECIMAL(5,2), REPLACE(NULLIF(TRIM([marge_brute_cible]), ''), ',', '.')) AS [marge_brute_cible],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'categories', [categorie_id], N'categorie_id', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'categories', [categorie_id], N'taux_tva', [taux_tva], 'QR43', 'REJET', N'Valeur non convertible en TINYINT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([taux_tva]), '') IS NOT NULL AND (TRY_CONVERT(TINYINT, NULLIF(TRIM([taux_tva]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'categories', [categorie_id], N'taux_retour_cible', [taux_retour_cible], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(5,2)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([taux_retour_cible]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(5,2), REPLACE(NULLIF(TRIM([taux_retour_cible]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'categories', [categorie_id], N'marge_brute_cible', [marge_brute_cible], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(5,2)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([marge_brute_cible]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(5,2), REPLACE(NULLIF(TRIM([marge_brute_cible]), ''), ',', '.'))) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    -- aucune correction tracée pour cette table

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [categorie_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [categorie]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [sous_categorie]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [taux_tva]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [taux_retour_cible]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [marge_brute_cible]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[categories] AS c
    USING #nouveau AS n
       ON c.[categorie_id] = n.[categorie_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [categorie] = n.[categorie], [sous_categorie] = n.[sous_categorie], [taux_tva] = n.[taux_tva], [taux_retour_cible] = n.[taux_retour_cible], [marge_brute_cible] = n.[marge_brute_cible],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([categorie_id], [categorie], [sous_categorie], [taux_tva], [taux_retour_cible], [marge_brute_cible], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[categorie_id], n.[categorie], n.[sous_categorie], n.[taux_tva], n.[taux_retour_cible], n.[marge_brute_cible], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.categories',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_categories';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_fournisseurs  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.fournisseurs  →  clean.fournisseurs   (Référentiel des fournisseurs)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_fournisseurs
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'fournisseurs';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[fournisseur_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[fournisseurs] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[fournisseur_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [fournisseur_id], [nom_fournisseur], [pays], [delai_appro_moyen_j], [conditions_paiement], [fiabilite_livraison], [email_contact], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[fournisseurs];
    INSERT INTO #nouveau ([fournisseur_id], [nom_fournisseur], [pays], [delai_appro_moyen_j], [conditions_paiement], [fiabilite_livraison], [email_contact], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([fournisseur_id]), '')) AS [fournisseur_id],
            NULLIF(TRIM([nom_fournisseur]), '') AS [nom_fournisseur],
            NULLIF(TRIM([pays]), '') AS [pays],
            TRY_CONVERT(SMALLINT, NULLIF(TRIM([delai_appro_moyen_j]), '')) AS [delai_appro_moyen_j],
            NULLIF(TRIM([conditions_paiement]), '') AS [conditions_paiement],
            TRY_CONVERT(DECIMAL(5,2), REPLACE(NULLIF(TRIM([fiabilite_livraison]), ''), ',', '.')) AS [fiabilite_livraison],
            NULLIF(TRIM([email_contact]), '') AS [email_contact],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'fournisseurs', [fournisseur_id], N'fournisseur_id', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'fournisseurs', [fournisseur_id], N'delai_appro_moyen_j', [delai_appro_moyen_j], 'QR43', 'REJET', N'Valeur non convertible en SMALLINT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([delai_appro_moyen_j]), '') IS NOT NULL AND (TRY_CONVERT(SMALLINT, NULLIF(TRIM([delai_appro_moyen_j]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'fournisseurs', [fournisseur_id], N'fiabilite_livraison', [fiabilite_livraison], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(5,2)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([fiabilite_livraison]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(5,2), REPLACE(NULLIF(TRIM([fiabilite_livraison]), ''), ',', '.'))) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    -- aucune correction tracée pour cette table

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [fournisseur_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_fournisseur]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [pays]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [delai_appro_moyen_j]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [conditions_paiement]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [fiabilite_livraison]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [email_contact]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[fournisseurs] AS c
    USING #nouveau AS n
       ON c.[fournisseur_id] = n.[fournisseur_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [nom_fournisseur] = n.[nom_fournisseur], [pays] = n.[pays], [delai_appro_moyen_j] = n.[delai_appro_moyen_j], [conditions_paiement] = n.[conditions_paiement], [fiabilite_livraison] = n.[fiabilite_livraison], [email_contact] = n.[email_contact],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([fournisseur_id], [nom_fournisseur], [pays], [delai_appro_moyen_j], [conditions_paiement], [fiabilite_livraison], [email_contact], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[fournisseur_id], n.[nom_fournisseur], n.[pays], n.[delai_appro_moyen_j], n.[conditions_paiement], n.[fiabilite_livraison], n.[email_contact], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.fournisseurs',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_fournisseurs';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_produits_prix_historique  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.produits_prix_historique  →  clean.produits_prix_historique   (Historique des prix et coûts produit)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_produits_prix_historique
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'produits_prix_historique';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[prix_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[produits_prix_historique] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[prix_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [prix_id], [produit_id], [date_debut], [date_fin], [prix_catalogue_ttc], [cout_achat_unitaire_ht], [est_prix_actuel], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[produits_prix_historique];
    INSERT INTO #nouveau ([prix_id], [produit_id], [date_debut], [date_fin], [prix_catalogue_ttc], [cout_achat_unitaire_ht], [est_prix_actuel], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([prix_id]), '')) AS [prix_id],
            UPPER(NULLIF(TRIM([produit_id]), '')) AS [produit_id],
            TRY_CONVERT(DATE, NULLIF(TRIM([date_debut]), ''), 23) AS [date_debut],
            TRY_CONVERT(DATE, NULLIF(TRIM([date_fin]), ''), 23) AS [date_fin],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([prix_catalogue_ttc]), ''), ',', '.')) AS [prix_catalogue_ttc],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_achat_unitaire_ht]), ''), ',', '.')) AS [cout_achat_unitaire_ht],
            CASE UPPER(TRIM([est_prix_actuel])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END AS [est_prix_actuel],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits_prix_historique', [prix_id], N'prix_id', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits_prix_historique', [prix_id], N'date_debut', [date_debut], 'QR43', 'REJET', N'Valeur non convertible en DATE'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_debut]), '') IS NOT NULL AND (TRY_CONVERT(DATE, NULLIF(TRIM([date_debut]), ''), 23)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits_prix_historique', [prix_id], N'date_fin', [date_fin], 'QR43', 'REJET', N'Valeur non convertible en DATE'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_fin]), '') IS NOT NULL AND (TRY_CONVERT(DATE, NULLIF(TRIM([date_fin]), ''), 23)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits_prix_historique', [prix_id], N'prix_catalogue_ttc', [prix_catalogue_ttc], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([prix_catalogue_ttc]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([prix_catalogue_ttc]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits_prix_historique', [prix_id], N'cout_achat_unitaire_ht', [cout_achat_unitaire_ht], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([cout_achat_unitaire_ht]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_achat_unitaire_ht]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits_prix_historique', [prix_id], N'est_prix_actuel', [est_prix_actuel], 'QR43', 'REJET', N'Valeur non convertible en BIT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([est_prix_actuel]), '') IS NOT NULL AND (CASE UPPER(TRIM([est_prix_actuel])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    -- aucune correction tracée pour cette table

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [prix_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_debut], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_fin], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [prix_catalogue_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_achat_unitaire_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_prix_actuel]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[produits_prix_historique] AS c
    USING #nouveau AS n
       ON c.[prix_id] = n.[prix_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [produit_id] = n.[produit_id], [date_debut] = n.[date_debut], [date_fin] = n.[date_fin], [prix_catalogue_ttc] = n.[prix_catalogue_ttc], [cout_achat_unitaire_ht] = n.[cout_achat_unitaire_ht], [est_prix_actuel] = n.[est_prix_actuel],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([prix_id], [produit_id], [date_debut], [date_fin], [prix_catalogue_ttc], [cout_achat_unitaire_ht], [est_prix_actuel], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[prix_id], n.[produit_id], n.[date_debut], n.[date_fin], n.[prix_catalogue_ttc], n.[cout_achat_unitaire_ht], n.[est_prix_actuel], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.produits_prix_historique',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_produits_prix_historique';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_produits  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.produits  →  clean.produits   (Catalogue produits)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_produits
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'produits';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[produit_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[produits] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[produit_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [produit_id], [sku], [nom_produit], [categorie_id], [marque], [fournisseur_id], [prix_catalogue_ttc_actuel], [cout_achat_unitaire_ht_actuel], [taux_tva], [poids_kg], [date_lancement], [date_arret], [statut_produit], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[produits];
    INSERT INTO #nouveau ([produit_id], [sku], [nom_produit], [categorie_id], [marque], [fournisseur_id], [prix_catalogue_ttc_actuel], [cout_achat_unitaire_ht_actuel], [taux_tva], [poids_kg], [date_lancement], [date_arret], [statut_produit], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([produit_id]), '')) AS [produit_id],
            'TS-' + RIGHT(COALESCE(UPPER(NULLIF(TRIM([categorie_id]), '')), 'CAT' + SUBSTRING(TRIM([sku]), 4, 2)), 2) + '-' + RIGHT('00000' + SUBSTRING(TRIM([produit_id]), 4, 10), 5) AS [sku],
            NULLIF(TRIM([nom_produit]), '') AS [nom_produit],
            COALESCE(UPPER(NULLIF(TRIM([categorie_id]), '')), 'CAT' + SUBSTRING(TRIM([sku]), 4, 2)) AS [categorie_id],
            NULLIF(TRIM([marque]), '') AS [marque],
            UPPER(NULLIF(TRIM([fournisseur_id]), '')) AS [fournisseur_id],
            CASE WHEN TRY_CONVERT(DECIMAL(14,3), [prix_catalogue_ttc_actuel]) > 0 THEN TRY_CONVERT(DECIMAL(14,3), [prix_catalogue_ttc_actuel]) END AS [prix_catalogue_ttc_actuel],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_achat_unitaire_ht_actuel]), ''), ',', '.')) AS [cout_achat_unitaire_ht_actuel],
            TRY_CONVERT(TINYINT, NULLIF(TRIM([taux_tva]), '')) AS [taux_tva],
            TRY_CONVERT(DECIMAL(8,2), REPLACE(NULLIF(TRIM([poids_kg]), ''), ',', '.')) AS [poids_kg],
            TRY_CONVERT(DATE, NULLIF(TRIM([date_lancement]), ''), 23) AS [date_lancement],
            TRY_CONVERT(DATE, NULLIF(TRIM([date_arret]), ''), 23) AS [date_arret],
            LOWER(NULLIF(TRIM([statut_produit]), '')) AS [statut_produit],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits', [produit_id], N'produit_id', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits', [produit_id], N'prix_catalogue_ttc_actuel', [prix_catalogue_ttc_actuel], 'QR18', 'SIGNALEMENT', N'Prix ≤ 0 : remplacé par le dernier prix historique'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([prix_catalogue_ttc_actuel]), '') IS NOT NULL AND (CASE WHEN TRY_CONVERT(DECIMAL(14,3), [prix_catalogue_ttc_actuel]) > 0 THEN TRY_CONVERT(DECIMAL(14,3), [prix_catalogue_ttc_actuel]) END) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits', [produit_id], N'cout_achat_unitaire_ht_actuel', [cout_achat_unitaire_ht_actuel], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([cout_achat_unitaire_ht_actuel]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_achat_unitaire_ht_actuel]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits', [produit_id], N'taux_tva', [taux_tva], 'QR43', 'REJET', N'Valeur non convertible en TINYINT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([taux_tva]), '') IS NOT NULL AND (TRY_CONVERT(TINYINT, NULLIF(TRIM([taux_tva]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits', [produit_id], N'poids_kg', [poids_kg], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(8,2)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([poids_kg]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(8,2), REPLACE(NULLIF(TRIM([poids_kg]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits', [produit_id], N'date_lancement', [date_lancement], 'QR43', 'REJET', N'Valeur non convertible en DATE'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_lancement]), '') IS NOT NULL AND (TRY_CONVERT(DATE, NULLIF(TRIM([date_lancement]), ''), 23)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits', [produit_id], N'date_arret', [date_arret], 'QR43', 'REJET', N'Valeur non convertible en DATE'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_arret]), '') IS NOT NULL AND (TRY_CONVERT(DATE, NULLIF(TRIM([date_arret]), ''), 23)) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- Règle QR15 (calculée sur l'ensemble des lignes reçues)
    UPDATE p SET marque = r.marque_ref
    FROM #nouveau p
    JOIN (SELECT marque_cle, marque_ref FROM (
            SELECT LOWER(marque) AS marque_cle, marque COLLATE Latin1_General_CS_AS AS marque_ref,
                   ROW_NUMBER() OVER (PARTITION BY LOWER(marque) ORDER BY COUNT(*) DESC, marque COLLATE Latin1_General_CS_AS) AS rn
            FROM #nouveau GROUP BY LOWER(marque), marque COLLATE Latin1_General_CS_AS) x WHERE rn = 1) r
      ON LOWER(p.marque) = r.marque_cle
    WHERE p.marque <> r.marque_ref COLLATE Latin1_General_CS_AS;
    -- Règle QR18 (calculée sur l'ensemble des lignes reçues)
    UPDATE p SET prix_catalogue_ttc_actuel = h.prix_catalogue_ttc
    FROM #nouveau p
    CROSS APPLY (SELECT TOP (1) prix_catalogue_ttc FROM clean.v_produits_prix_historique h
                 WHERE h.produit_id = p.produit_id ORDER BY h.date_fin DESC) h
    WHERE p.prix_catalogue_ttc_actuel IS NULL;

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits', n.[produit_id], N'marque', LEFT(s.[marque], 4000), 'QR15', 'CORRECTION', CONCAT(N'Marque harmonisée : ', CONVERT(NVARCHAR(400), n.[marque]))
    FROM #src s JOIN #nouveau n ON n.[produit_id] = UPPER(TRIM(s.[produit_id]))
    WHERE s.rn = 1 AND (CONCAT(s.[marque], N'|') COLLATE Latin1_General_CS_AS <> CONCAT(n.[marque], N'|'));
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits', n.[produit_id], N'categorie_id', LEFT(s.[categorie_id], 4000), 'QR16', 'CORRECTION', CONCAT(N'Catégorie déduite du SKU : ', CONVERT(NVARCHAR(400), n.[categorie_id]))
    FROM #src s JOIN #nouveau n ON n.[produit_id] = UPPER(TRIM(s.[produit_id]))
    WHERE s.rn = 1 AND (NULLIF(TRIM(s.[categorie_id]), '') IS NULL);
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produits', n.[produit_id], N'sku', LEFT(s.[sku], 4000), 'QR17', 'CORRECTION', CONCAT(N'SKU reconstruit : ', CONVERT(NVARCHAR(400), n.[sku]))
    FROM #src s JOIN #nouveau n ON n.[produit_id] = UPPER(TRIM(s.[produit_id]))
    WHERE s.rn = 1 AND (CONCAT(TRIM(s.[sku]), N'|') COLLATE Latin1_General_CS_AS <> CONCAT(n.[sku], N'|'));

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [sku]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_produit]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [categorie_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [marque]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [fournisseur_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [prix_catalogue_ttc_actuel]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_achat_unitaire_ht_actuel]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [taux_tva]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [poids_kg]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_lancement], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_arret], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [statut_produit]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[produits] AS c
    USING #nouveau AS n
       ON c.[produit_id] = n.[produit_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [sku] = n.[sku], [nom_produit] = n.[nom_produit], [categorie_id] = n.[categorie_id], [marque] = n.[marque], [fournisseur_id] = n.[fournisseur_id], [prix_catalogue_ttc_actuel] = n.[prix_catalogue_ttc_actuel], [cout_achat_unitaire_ht_actuel] = n.[cout_achat_unitaire_ht_actuel], [taux_tva] = n.[taux_tva], [poids_kg] = n.[poids_kg], [date_lancement] = n.[date_lancement], [date_arret] = n.[date_arret], [statut_produit] = n.[statut_produit],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([produit_id], [sku], [nom_produit], [categorie_id], [marque], [fournisseur_id], [prix_catalogue_ttc_actuel], [cout_achat_unitaire_ht_actuel], [taux_tva], [poids_kg], [date_lancement], [date_arret], [statut_produit], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[produit_id], n.[sku], n.[nom_produit], n.[categorie_id], n.[marque], n.[fournisseur_id], n.[prix_catalogue_ttc_actuel], n.[cout_achat_unitaire_ht_actuel], n.[taux_tva], n.[poids_kg], n.[date_lancement], n.[date_arret], n.[statut_produit], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.produits',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_produits';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_ref_gouvernorats  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.ref_gouvernorats  →  clean.ref_gouvernorats   (Référentiel des 24 gouvernorats)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_ref_gouvernorats
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'ref_gouvernorats';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[gouvernorat_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[ref_gouvernorats] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[gouvernorat_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [gouvernorat_id], [gouvernorat], [region], [entrepot_rattachement_id], [zone_livraison], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[ref_gouvernorats];
    INSERT INTO #nouveau ([gouvernorat_id], [gouvernorat], [region], [entrepot_rattachement_id], [zone_livraison], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([gouvernorat_id]), '')) AS [gouvernorat_id],
            NULLIF(TRIM([gouvernorat]), '') AS [gouvernorat],
            NULLIF(TRIM([region]), '') AS [region],
            UPPER(NULLIF(TRIM([entrepot_rattachement_id]), '')) AS [entrepot_rattachement_id],
            UPPER(NULLIF(TRIM([zone_livraison]), '')) AS [zone_livraison],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'ref_gouvernorats', [gouvernorat_id], N'gouvernorat_id', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    -- aucune colonne typée à contrôler

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    -- aucune correction tracée pour cette table

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [gouvernorat_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [gouvernorat]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [region]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [entrepot_rattachement_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [zone_livraison]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[ref_gouvernorats] AS c
    USING #nouveau AS n
       ON c.[gouvernorat_id] = n.[gouvernorat_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [gouvernorat] = n.[gouvernorat], [region] = n.[region], [entrepot_rattachement_id] = n.[entrepot_rattachement_id], [zone_livraison] = n.[zone_livraison],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([gouvernorat_id], [gouvernorat], [region], [entrepot_rattachement_id], [zone_livraison], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[gouvernorat_id], n.[gouvernorat], n.[region], n.[entrepot_rattachement_id], n.[zone_livraison], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.ref_gouvernorats',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_ref_gouvernorats';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_entrepots  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.entrepots  →  clean.entrepots   (Référentiel des entrepôts)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_entrepots
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'entrepots';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[entrepot_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[entrepots] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[entrepot_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [entrepot_id], [nom_entrepot], [ville], [gouvernorat_id], [date_ouverture], [surface_m2], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[entrepots];
    INSERT INTO #nouveau ([entrepot_id], [nom_entrepot], [ville], [gouvernorat_id], [date_ouverture], [surface_m2], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([entrepot_id]), '')) AS [entrepot_id],
            NULLIF(TRIM([nom_entrepot]), '') AS [nom_entrepot],
            NULLIF(TRIM([ville]), '') AS [ville],
            UPPER(NULLIF(TRIM([gouvernorat_id]), '')) AS [gouvernorat_id],
            TRY_CONVERT(DATE, NULLIF(TRIM([date_ouverture]), ''), 23) AS [date_ouverture],
            TRY_CONVERT(SMALLINT, NULLIF(TRIM([surface_m2]), '')) AS [surface_m2],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'entrepots', [entrepot_id], N'entrepot_id', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'entrepots', [entrepot_id], N'date_ouverture', [date_ouverture], 'QR43', 'REJET', N'Valeur non convertible en DATE'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_ouverture]), '') IS NOT NULL AND (TRY_CONVERT(DATE, NULLIF(TRIM([date_ouverture]), ''), 23)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'entrepots', [entrepot_id], N'surface_m2', [surface_m2], 'QR43', 'REJET', N'Valeur non convertible en SMALLINT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([surface_m2]), '') IS NOT NULL AND (TRY_CONVERT(SMALLINT, NULLIF(TRIM([surface_m2]), ''))) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    -- aucune correction tracée pour cette table

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [entrepot_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_entrepot]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [ville]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [gouvernorat_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_ouverture], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [surface_m2]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[entrepots] AS c
    USING #nouveau AS n
       ON c.[entrepot_id] = n.[entrepot_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [nom_entrepot] = n.[nom_entrepot], [ville] = n.[ville], [gouvernorat_id] = n.[gouvernorat_id], [date_ouverture] = n.[date_ouverture], [surface_m2] = n.[surface_m2],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([entrepot_id], [nom_entrepot], [ville], [gouvernorat_id], [date_ouverture], [surface_m2], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[entrepot_id], n.[nom_entrepot], n.[ville], n.[gouvernorat_id], n.[date_ouverture], n.[surface_m2], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.entrepots',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_entrepots';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_transporteurs  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.transporteurs  →  clean.transporteurs   (Référentiel des transporteurs)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_transporteurs
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'transporteurs';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[transporteur_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[transporteurs] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[transporteur_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [transporteur_id], [nom_transporteur], [couverture], [cout_base_ht], [ecart_delai_moyen_j], [date_debut_contrat], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[transporteurs];
    INSERT INTO #nouveau ([transporteur_id], [nom_transporteur], [couverture], [cout_base_ht], [ecart_delai_moyen_j], [date_debut_contrat], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([transporteur_id]), '')) AS [transporteur_id],
            NULLIF(TRIM([nom_transporteur]), '') AS [nom_transporteur],
            NULLIF(TRIM([couverture]), '') AS [couverture],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_base_ht]), ''), ',', '.')) AS [cout_base_ht],
            TRY_CONVERT(DECIMAL(5,2), REPLACE(NULLIF(TRIM([ecart_delai_moyen_j]), ''), ',', '.')) AS [ecart_delai_moyen_j],
            TRY_CONVERT(DATE, NULLIF(TRIM([date_debut_contrat]), ''), 23) AS [date_debut_contrat],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'transporteurs', [transporteur_id], N'transporteur_id', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'transporteurs', [transporteur_id], N'cout_base_ht', [cout_base_ht], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([cout_base_ht]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_base_ht]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'transporteurs', [transporteur_id], N'ecart_delai_moyen_j', [ecart_delai_moyen_j], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(5,2)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([ecart_delai_moyen_j]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(5,2), REPLACE(NULLIF(TRIM([ecart_delai_moyen_j]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'transporteurs', [transporteur_id], N'date_debut_contrat', [date_debut_contrat], 'QR43', 'REJET', N'Valeur non convertible en DATE'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_debut_contrat]), '') IS NOT NULL AND (TRY_CONVERT(DATE, NULLIF(TRIM([date_debut_contrat]), ''), 23)) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    -- aucune correction tracée pour cette table

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [transporteur_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_transporteur]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [couverture]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_base_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [ecart_delai_moyen_j]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_debut_contrat], 121), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[transporteurs] AS c
    USING #nouveau AS n
       ON c.[transporteur_id] = n.[transporteur_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [nom_transporteur] = n.[nom_transporteur], [couverture] = n.[couverture], [cout_base_ht] = n.[cout_base_ht], [ecart_delai_moyen_j] = n.[ecart_delai_moyen_j], [date_debut_contrat] = n.[date_debut_contrat],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([transporteur_id], [nom_transporteur], [couverture], [cout_base_ht], [ecart_delai_moyen_j], [date_debut_contrat], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[transporteur_id], n.[nom_transporteur], n.[couverture], n.[cout_base_ht], n.[ecart_delai_moyen_j], n.[date_debut_contrat], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.transporteurs',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_transporteurs';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_dim_calendrier  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.dim_calendrier  →  clean.dim_calendrier   (Calendrier 2023-2025 avec fériés et périodes commerciales)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_dim_calendrier
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'dim_calendrier';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[date])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[dim_calendrier] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[date]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [date], [annee], [trimestre], [mois], [nom_mois], [semaine_iso], [jour_semaine], [nom_jour], [est_weekend], [est_jour_ferie], [nom_jour_ferie], [est_ramadan], [periode_commerciale], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[dim_calendrier];
    INSERT INTO #nouveau ([date], [annee], [trimestre], [mois], [nom_mois], [semaine_iso], [jour_semaine], [nom_jour], [est_weekend], [est_jour_ferie], [nom_jour_ferie], [est_ramadan], [periode_commerciale], id_chargement, date_traitement)
    SELECT  TRY_CONVERT(DATE, NULLIF(TRIM([date]), ''), 23) AS [date],
            TRY_CONVERT(SMALLINT, NULLIF(TRIM([annee]), '')) AS [annee],
            TRY_CONVERT(TINYINT, NULLIF(TRIM([trimestre]), '')) AS [trimestre],
            TRY_CONVERT(TINYINT, NULLIF(TRIM([mois]), '')) AS [mois],
            NULLIF(TRIM([nom_mois]), '') AS [nom_mois],
            TRY_CONVERT(TINYINT, NULLIF(TRIM([semaine_iso]), '')) AS [semaine_iso],
            TRY_CONVERT(TINYINT, NULLIF(TRIM([jour_semaine]), '')) AS [jour_semaine],
            LOWER(NULLIF(TRIM([nom_jour]), '')) AS [nom_jour],
            CASE UPPER(TRIM([est_weekend])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END AS [est_weekend],
            CASE UPPER(TRIM([est_jour_ferie])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END AS [est_jour_ferie],
            NULLIF(TRIM([nom_jour_ferie]), '') AS [nom_jour_ferie],
            CASE UPPER(TRIM([est_ramadan])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END AS [est_ramadan],
            LOWER(NULLIF(TRIM([periode_commerciale]), '')) AS [periode_commerciale],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'dim_calendrier', [date], N'date', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'dim_calendrier', [date], N'date', [date], 'QR43', 'REJET', N'Valeur non convertible en DATE'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date]), '') IS NOT NULL AND (TRY_CONVERT(DATE, NULLIF(TRIM([date]), ''), 23)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'dim_calendrier', [date], N'annee', [annee], 'QR43', 'REJET', N'Valeur non convertible en SMALLINT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([annee]), '') IS NOT NULL AND (TRY_CONVERT(SMALLINT, NULLIF(TRIM([annee]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'dim_calendrier', [date], N'trimestre', [trimestre], 'QR43', 'REJET', N'Valeur non convertible en TINYINT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([trimestre]), '') IS NOT NULL AND (TRY_CONVERT(TINYINT, NULLIF(TRIM([trimestre]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'dim_calendrier', [date], N'mois', [mois], 'QR43', 'REJET', N'Valeur non convertible en TINYINT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([mois]), '') IS NOT NULL AND (TRY_CONVERT(TINYINT, NULLIF(TRIM([mois]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'dim_calendrier', [date], N'semaine_iso', [semaine_iso], 'QR43', 'REJET', N'Valeur non convertible en TINYINT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([semaine_iso]), '') IS NOT NULL AND (TRY_CONVERT(TINYINT, NULLIF(TRIM([semaine_iso]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'dim_calendrier', [date], N'jour_semaine', [jour_semaine], 'QR43', 'REJET', N'Valeur non convertible en TINYINT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([jour_semaine]), '') IS NOT NULL AND (TRY_CONVERT(TINYINT, NULLIF(TRIM([jour_semaine]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'dim_calendrier', [date], N'est_weekend', [est_weekend], 'QR43', 'REJET', N'Valeur non convertible en BIT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([est_weekend]), '') IS NOT NULL AND (CASE UPPER(TRIM([est_weekend])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'dim_calendrier', [date], N'est_jour_ferie', [est_jour_ferie], 'QR43', 'REJET', N'Valeur non convertible en BIT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([est_jour_ferie]), '') IS NOT NULL AND (CASE UPPER(TRIM([est_jour_ferie])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'dim_calendrier', [date], N'est_ramadan', [est_ramadan], 'QR43', 'REJET', N'Valeur non convertible en BIT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([est_ramadan]), '') IS NOT NULL AND (CASE UPPER(TRIM([est_ramadan])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    -- aucune correction tracée pour cette table

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [date], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [annee]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [trimestre]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [mois]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_mois]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [semaine_iso]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [jour_semaine]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_jour]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_weekend]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_jour_ferie]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_jour_ferie]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_ramadan]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [periode_commerciale]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[dim_calendrier] AS c
    USING #nouveau AS n
       ON c.[date] = n.[date]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [annee] = n.[annee], [trimestre] = n.[trimestre], [mois] = n.[mois], [nom_mois] = n.[nom_mois], [semaine_iso] = n.[semaine_iso], [jour_semaine] = n.[jour_semaine], [nom_jour] = n.[nom_jour], [est_weekend] = n.[est_weekend], [est_jour_ferie] = n.[est_jour_ferie], [nom_jour_ferie] = n.[nom_jour_ferie], [est_ramadan] = n.[est_ramadan], [periode_commerciale] = n.[periode_commerciale],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([date], [annee], [trimestre], [mois], [nom_mois], [semaine_iso], [jour_semaine], [nom_jour], [est_weekend], [est_jour_ferie], [nom_jour_ferie], [est_ramadan], [periode_commerciale], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[date], n.[annee], n.[trimestre], n.[mois], n.[nom_mois], n.[semaine_iso], n.[jour_semaine], n.[nom_jour], n.[est_weekend], n.[est_jour_ferie], n.[nom_jour_ferie], n.[est_ramadan], n.[periode_commerciale], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.dim_calendrier',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_dim_calendrier';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_clients  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.clients  →  clean.clients   (Comptes clients)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_clients
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'clients';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[client_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[clients] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[client_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [client_id], [type_client], [prenom], [nom], [genre], [date_naissance], [raison_sociale], [matricule_fiscal], [email], [telephone], [gouvernorat_id], [ville], [date_inscription], [canal_inscription], [campagne_acquisition_id], [opt_in_email], [opt_in_sms], [segment_fidelite], [genre_impute], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[clients];
    INSERT INTO #nouveau ([client_id], [type_client], [prenom], [nom], [genre], [date_naissance], [raison_sociale], [matricule_fiscal], [email], [telephone], [gouvernorat_id], [ville], [date_inscription], [canal_inscription], [campagne_acquisition_id], [opt_in_email], [opt_in_sms], [segment_fidelite], [genre_impute], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([client_id]), '')) AS [client_id],
            LOWER(NULLIF(TRIM([type_client]), '')) AS [type_client],
            NULLIF(TRIM([prenom]), '') AS [prenom],
            NULLIF(TRIM([nom]), '') AS [nom],
            UPPER(NULLIF(TRIM([genre]), '')) AS [genre],
            CASE WHEN TRIM([date_naissance]) LIKE '__/__/____' THEN TRY_CONVERT(DATE, TRIM([date_naissance]), 103) ELSE TRY_CONVERT(DATE, NULLIF(TRIM([date_naissance]), ''), 23) END AS [date_naissance],
            NULLIF(TRIM([raison_sociale]), '') AS [raison_sociale],
            UPPER(NULLIF(TRIM([matricule_fiscal]), '')) AS [matricule_fiscal],
            LOWER(NULLIF(REPLACE(REPLACE(TRIM([email]), ' at ', '@'), '@@', '@'), '')) AS [email],
            clean.fn_normaliser_telephone([telephone]) AS [telephone],
            UPPER(NULLIF(TRIM([gouvernorat_id]), '')) AS [gouvernorat_id],
            NULLIF(TRIM([ville]), '') AS [ville],
            TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_inscription]), ''), 120) AS [date_inscription],
            LOWER(NULLIF(TRIM([canal_inscription]), '')) AS [canal_inscription],
            UPPER(NULLIF(TRIM([campagne_acquisition_id]), '')) AS [campagne_acquisition_id],
            CASE UPPER(TRIM([opt_in_email])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END AS [opt_in_email],
            CASE UPPER(TRIM([opt_in_sms])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END AS [opt_in_sms],
            LOWER(NULLIF(TRIM([segment_fidelite]), '')) AS [segment_fidelite],
            CAST(0 AS BIT) AS [genre_impute],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'clients', [client_id], N'client_id', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'clients', [client_id], N'telephone', [telephone], 'QR09', 'SIGNALEMENT', N'Téléphone non normalisable : mis à NULL'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([telephone]), '') IS NOT NULL AND (clean.fn_normaliser_telephone([telephone])) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'clients', [client_id], N'date_inscription', [date_inscription], 'QR43', 'REJET', N'Valeur non convertible en DATETIME2(0)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_inscription]), '') IS NOT NULL AND (TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_inscription]), ''), 120)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'clients', [client_id], N'opt_in_email', [opt_in_email], 'QR43', 'REJET', N'Valeur non convertible en BIT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([opt_in_email]), '') IS NOT NULL AND (CASE UPPER(TRIM([opt_in_email])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'clients', [client_id], N'opt_in_sms', [opt_in_sms], 'QR43', 'REJET', N'Valeur non convertible en BIT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([opt_in_sms]), '') IS NOT NULL AND (CASE UPPER(TRIM([opt_in_sms])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- Règle QR11 (calculée sur l'ensemble des lignes reçues)
    UPDATE c SET ville = r.ville_ref
    FROM #nouveau c
    JOIN (SELECT ville_cle, ville_ref FROM (
            SELECT ville COLLATE Latin1_General_CI_AI AS ville_cle, ville COLLATE Latin1_General_CS_AS AS ville_ref,
                   ROW_NUMBER() OVER (PARTITION BY ville COLLATE Latin1_General_CI_AI ORDER BY COUNT(*) DESC, ville COLLATE Latin1_General_CS_AS) AS rn
            FROM #nouveau WHERE ville IS NOT NULL
            GROUP BY ville COLLATE Latin1_General_CI_AI, ville COLLATE Latin1_General_CS_AS) x WHERE rn = 1) r
      ON c.ville COLLATE Latin1_General_CI_AI = r.ville_cle
    WHERE c.ville <> r.ville_ref COLLATE Latin1_General_CS_AS;
    -- Règle QR12 (calculée sur l'ensemble des lignes reçues)
    UPDATE c SET genre = p.genre, genre_impute = 1
    FROM #nouveau c
    JOIN (SELECT prenom, genre FROM (
            SELECT prenom, genre, COUNT(*) * 1.0 / SUM(COUNT(*)) OVER (PARTITION BY prenom) AS part
            FROM #nouveau WHERE genre IS NOT NULL GROUP BY prenom, genre) x
          WHERE part >= 0.9) p          -- prénom non ambigu uniquement (ex. « Malek » exclu)
      ON p.prenom = c.prenom
    WHERE c.genre IS NULL;
    -- Règle QR44 (calculée sur l'ensemble des lignes reçues)
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'clients', client_id, N'date_naissance', CONVERT(NVARCHAR(10), date_naissance, 23), 'QR44', 'SIGNALEMENT', N'Âge hors 16–100 ans au 31/12/2025 : mise à NULL'
    FROM #nouveau
    WHERE date_naissance > DATEADD(YEAR, -16, CAST('2025-12-31' AS DATE)) OR date_naissance < DATEADD(YEAR, -100, CAST('2025-12-31' AS DATE));
    UPDATE #nouveau SET date_naissance = NULL
    WHERE date_naissance > DATEADD(YEAR, -16, CAST('2025-12-31' AS DATE)) OR date_naissance < DATEADD(YEAR, -100, CAST('2025-12-31' AS DATE));
    -- Règle QR45 (calculée sur l'ensemble des lignes reçues)
    UPDATE c SET email = STUFF(c.email, LEN(c.email) - LEN(d.domaine) + 1, 0, '@')
    FROM #nouveau c
    JOIN (VALUES ('gmail.com'), ('hotmail.com'), ('yahoo.fr'), ('outlook.com'), ('topnet.tn'), ('gnet.tn')) d(domaine)
      ON c.email NOT LIKE '%@%' AND c.email LIKE '%' + d.domaine;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'clients', client_id, N'email', email, 'QR45', 'SIGNALEMENT', N'E-mail invalide : mis à NULL'
    FROM #nouveau WHERE email IS NOT NULL AND (email NOT LIKE '_%@_%._%' OR email LIKE '%@%@%' OR email LIKE '% %');
    UPDATE #nouveau SET email = NULL
    WHERE email IS NOT NULL AND (email NOT LIKE '_%@_%._%' OR email LIKE '%@%@%' OR email LIKE '% %');

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'clients', n.[client_id], N'date_naissance', LEFT(s.[date_naissance], 4000), 'QR07', 'CORRECTION', CONCAT(N'Date JJ/MM/AAAA convertie : ', CONVERT(NVARCHAR(400), n.[date_naissance]))
    FROM #src s JOIN #nouveau n ON n.[client_id] = UPPER(TRIM(s.[client_id]))
    WHERE s.rn = 1 AND (TRIM(s.[date_naissance]) LIKE '__/__/____');
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'clients', n.[client_id], N'telephone', LEFT(s.[telephone], 4000), 'QR09', 'CORRECTION', CONCAT(N'Téléphone normalisé : ', CONVERT(NVARCHAR(400), n.[telephone]))
    FROM #src s JOIN #nouveau n ON n.[client_id] = UPPER(TRIM(s.[client_id]))
    WHERE s.rn = 1 AND (NULLIF(TRIM(s.[telephone]), '') IS NOT NULL AND n.[telephone] IS NOT NULL AND CONCAT(s.[telephone], N'|') COLLATE Latin1_General_CS_AS <> CONCAT(n.[telephone], N'|'));
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'clients', n.[client_id], N'email', LEFT(s.[email], 4000), 'QR10', 'CORRECTION', CONCAT(N'E-mail mis en minuscules / espaces retirés : ', CONVERT(NVARCHAR(400), n.[email]))
    FROM #src s JOIN #nouveau n ON n.[client_id] = UPPER(TRIM(s.[client_id]))
    WHERE s.rn = 1 AND (NULLIF(TRIM(s.[email]), '') IS NOT NULL AND CONCAT(s.[email], N'|') COLLATE Latin1_General_CS_AS <> CONCAT(LOWER(TRIM(s.[email])), N'|'));
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'clients', n.[client_id], N'email', LEFT(s.[email], 4000), 'QR45', 'CORRECTION', CONCAT(N'E-mail réparé : ', CONVERT(NVARCHAR(400), n.[email]))
    FROM #src s JOIN #nouveau n ON n.[client_id] = UPPER(TRIM(s.[client_id]))
    WHERE s.rn = 1 AND (NULLIF(TRIM(s.[email]), '') IS NOT NULL AND n.[email] IS NOT NULL AND (LOWER(TRIM(s.[email])) LIKE '% at %' OR LOWER(TRIM(s.[email])) LIKE '%@@%' OR LOWER(TRIM(s.[email])) NOT LIKE '%@%'));
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'clients', n.[client_id], N'ville', LEFT(s.[ville], 4000), 'QR11', 'CORRECTION', CONCAT(N'Ville harmonisée : ', CONVERT(NVARCHAR(400), n.[ville]))
    FROM #src s JOIN #nouveau n ON n.[client_id] = UPPER(TRIM(s.[client_id]))
    WHERE s.rn = 1 AND (NULLIF(TRIM(s.[ville]), '') IS NOT NULL AND CONCAT(s.[ville], N'|') COLLATE Latin1_General_CS_AS <> CONCAT(n.[ville], N'|'));
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'clients', n.[client_id], N'genre', LEFT(s.[genre], 4000), 'QR12', 'CORRECTION', CONCAT(N'Genre imputé depuis le prénom : ', CONVERT(NVARCHAR(400), n.[genre]))
    FROM #src s JOIN #nouveau n ON n.[client_id] = UPPER(TRIM(s.[client_id]))
    WHERE s.rn = 1 AND (n.[genre_impute] = 1);

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [client_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [type_client]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [prenom]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [genre]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_naissance], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [raison_sociale]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [matricule_fiscal]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [email]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [telephone]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [gouvernorat_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [ville]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_inscription], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [canal_inscription]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [campagne_acquisition_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [opt_in_email]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [opt_in_sms]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [segment_fidelite]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [genre_impute]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[clients] AS c
    USING #nouveau AS n
       ON c.[client_id] = n.[client_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [type_client] = n.[type_client], [prenom] = n.[prenom], [nom] = n.[nom], [genre] = n.[genre], [date_naissance] = n.[date_naissance], [raison_sociale] = n.[raison_sociale], [matricule_fiscal] = n.[matricule_fiscal], [email] = n.[email], [telephone] = n.[telephone], [gouvernorat_id] = n.[gouvernorat_id], [ville] = n.[ville], [date_inscription] = n.[date_inscription], [canal_inscription] = n.[canal_inscription], [campagne_acquisition_id] = n.[campagne_acquisition_id], [opt_in_email] = n.[opt_in_email], [opt_in_sms] = n.[opt_in_sms], [segment_fidelite] = n.[segment_fidelite], [genre_impute] = n.[genre_impute],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([client_id], [type_client], [prenom], [nom], [genre], [date_naissance], [raison_sociale], [matricule_fiscal], [email], [telephone], [gouvernorat_id], [ville], [date_inscription], [canal_inscription], [campagne_acquisition_id], [opt_in_email], [opt_in_sms], [segment_fidelite], [genre_impute], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[client_id], n.[type_client], n.[prenom], n.[nom], n.[genre], n.[date_naissance], n.[raison_sociale], n.[matricule_fiscal], n.[email], n.[telephone], n.[gouvernorat_id], n.[ville], n.[date_inscription], n.[canal_inscription], n.[campagne_acquisition_id], n.[opt_in_email], n.[opt_in_sms], n.[segment_fidelite], n.[genre_impute], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.clients',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_clients';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_campagnes_marketing  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.campagnes_marketing  →  clean.campagnes_marketing   (Campagnes marketing)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_campagnes_marketing
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'campagnes_marketing';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[campagne_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[campagnes_marketing] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[campagne_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [campagne_id], [nom_campagne], [canal], [objectif], [theme], [categorie_ciblee_id], [code_coupon], [date_debut], [date_fin], [budget_ht], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[campagnes_marketing];
    INSERT INTO #nouveau ([campagne_id], [nom_campagne], [canal], [objectif], [theme], [categorie_ciblee_id], [code_coupon], [date_debut], [date_fin], [budget_ht], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([campagne_id]), '')) AS [campagne_id],
            NULLIF(TRIM([nom_campagne]), '') AS [nom_campagne],
            LOWER(NULLIF(TRIM([canal]), '')) AS [canal],
            LOWER(NULLIF(TRIM([objectif]), '')) AS [objectif],
            LOWER(NULLIF(TRIM([theme]), '')) AS [theme],
            UPPER(NULLIF(TRIM([categorie_ciblee_id]), '')) AS [categorie_ciblee_id],
            UPPER(NULLIF(TRIM([code_coupon]), '')) AS [code_coupon],
            TRY_CONVERT(DATE, NULLIF(TRIM([date_debut]), ''), 23) AS [date_debut],
            TRY_CONVERT(DATE, NULLIF(TRIM([date_fin]), ''), 23) AS [date_fin],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([budget_ht]), ''), ',', '.')) AS [budget_ht],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'campagnes_marketing', [campagne_id], N'campagne_id', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'campagnes_marketing', [campagne_id], N'date_debut', [date_debut], 'QR43', 'REJET', N'Valeur non convertible en DATE'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_debut]), '') IS NOT NULL AND (TRY_CONVERT(DATE, NULLIF(TRIM([date_debut]), ''), 23)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'campagnes_marketing', [campagne_id], N'date_fin', [date_fin], 'QR43', 'REJET', N'Valeur non convertible en DATE'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_fin]), '') IS NOT NULL AND (TRY_CONVERT(DATE, NULLIF(TRIM([date_fin]), ''), 23)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'campagnes_marketing', [campagne_id], N'budget_ht', [budget_ht], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([budget_ht]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([budget_ht]), ''), ',', '.'))) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    -- aucune correction tracée pour cette table

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [campagne_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_campagne]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [canal]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [objectif]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [theme]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [categorie_ciblee_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [code_coupon]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_debut], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_fin], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [budget_ht]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[campagnes_marketing] AS c
    USING #nouveau AS n
       ON c.[campagne_id] = n.[campagne_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [nom_campagne] = n.[nom_campagne], [canal] = n.[canal], [objectif] = n.[objectif], [theme] = n.[theme], [categorie_ciblee_id] = n.[categorie_ciblee_id], [code_coupon] = n.[code_coupon], [date_debut] = n.[date_debut], [date_fin] = n.[date_fin], [budget_ht] = n.[budget_ht],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([campagne_id], [nom_campagne], [canal], [objectif], [theme], [categorie_ciblee_id], [code_coupon], [date_debut], [date_fin], [budget_ht], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[campagne_id], n.[nom_campagne], n.[canal], n.[objectif], n.[theme], n.[categorie_ciblee_id], n.[code_coupon], n.[date_debut], n.[date_fin], n.[budget_ht], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.campagnes_marketing',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_campagnes_marketing';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_coupons  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.coupons  →  clean.coupons   (Codes promotionnels)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_coupons
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'coupons';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[code_coupon])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[coupons] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[code_coupon]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [code_coupon], [type_remise], [valeur], [montant_min_ttc], [plafond_remise_ttc], [date_debut], [date_fin], [campagne_id], [reserve_premiere_commande], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[coupons];
    INSERT INTO #nouveau ([code_coupon], [type_remise], [valeur], [montant_min_ttc], [plafond_remise_ttc], [date_debut], [date_fin], [campagne_id], [reserve_premiere_commande], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([code_coupon]), '')) AS [code_coupon],
            LOWER(NULLIF(TRIM([type_remise]), '')) AS [type_remise],
            TRY_CONVERT(DECIMAL(10,2), REPLACE(NULLIF(TRIM([valeur]), ''), ',', '.')) AS [valeur],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([montant_min_ttc]), ''), ',', '.')) AS [montant_min_ttc],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([plafond_remise_ttc]), ''), ',', '.')) AS [plafond_remise_ttc],
            TRY_CONVERT(DATE, NULLIF(TRIM([date_debut]), ''), 23) AS [date_debut],
            TRY_CONVERT(DATE, NULLIF(TRIM([date_fin]), ''), 23) AS [date_fin],
            UPPER(NULLIF(TRIM([campagne_id]), '')) AS [campagne_id],
            CASE UPPER(TRIM([reserve_premiere_commande])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END AS [reserve_premiere_commande],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'coupons', [code_coupon], N'code_coupon', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'coupons', [code_coupon], N'valeur', [valeur], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(10,2)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([valeur]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(10,2), REPLACE(NULLIF(TRIM([valeur]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'coupons', [code_coupon], N'montant_min_ttc', [montant_min_ttc], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([montant_min_ttc]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([montant_min_ttc]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'coupons', [code_coupon], N'plafond_remise_ttc', [plafond_remise_ttc], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([plafond_remise_ttc]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([plafond_remise_ttc]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'coupons', [code_coupon], N'date_debut', [date_debut], 'QR43', 'REJET', N'Valeur non convertible en DATE'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_debut]), '') IS NOT NULL AND (TRY_CONVERT(DATE, NULLIF(TRIM([date_debut]), ''), 23)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'coupons', [code_coupon], N'date_fin', [date_fin], 'QR43', 'REJET', N'Valeur non convertible en DATE'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_fin]), '') IS NOT NULL AND (TRY_CONVERT(DATE, NULLIF(TRIM([date_fin]), ''), 23)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'coupons', [code_coupon], N'reserve_premiere_commande', [reserve_premiere_commande], 'QR43', 'REJET', N'Valeur non convertible en BIT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([reserve_premiere_commande]), '') IS NOT NULL AND (CASE UPPER(TRIM([reserve_premiere_commande])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    -- aucune correction tracée pour cette table

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [code_coupon]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [type_remise]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [valeur]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_min_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [plafond_remise_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_debut], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_fin], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [campagne_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [reserve_premiere_commande]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[coupons] AS c
    USING #nouveau AS n
       ON c.[code_coupon] = n.[code_coupon]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [type_remise] = n.[type_remise], [valeur] = n.[valeur], [montant_min_ttc] = n.[montant_min_ttc], [plafond_remise_ttc] = n.[plafond_remise_ttc], [date_debut] = n.[date_debut], [date_fin] = n.[date_fin], [campagne_id] = n.[campagne_id], [reserve_premiere_commande] = n.[reserve_premiere_commande],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([code_coupon], [type_remise], [valeur], [montant_min_ttc], [plafond_remise_ttc], [date_debut], [date_fin], [campagne_id], [reserve_premiere_commande], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[code_coupon], n.[type_remise], n.[valeur], n.[montant_min_ttc], n.[plafond_remise_ttc], n.[date_debut], n.[date_fin], n.[campagne_id], n.[reserve_premiere_commande], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.coupons',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_coupons';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_marketing_depenses_quotidiennes  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.marketing_depenses_quotidiennes  →  clean.marketing_depenses_quotidiennes   (Dépenses et performances quotidiennes par campagne)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_marketing_depenses_quotidiennes
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'marketing_depenses_quotidiennes';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[depense_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[marketing_depenses_quotidiennes] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[depense_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [depense_id], [campagne_id], [date], [canal], [depense_ht], [impressions], [clics], [commandes_attribuees], [nouveaux_clients_attribues], [ca_attribue_ttc], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[marketing_depenses_quotidiennes];
    INSERT INTO #nouveau ([depense_id], [campagne_id], [date], [canal], [depense_ht], [impressions], [clics], [commandes_attribuees], [nouveaux_clients_attribues], [ca_attribue_ttc], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([depense_id]), '')) AS [depense_id],
            UPPER(NULLIF(TRIM([campagne_id]), '')) AS [campagne_id],
            CASE WHEN TRIM([date]) LIKE '__/__/____' THEN TRY_CONVERT(DATE, TRIM([date]), 103) ELSE TRY_CONVERT(DATE, NULLIF(TRIM([date]), ''), 23) END AS [date],
            LOWER(NULLIF(TRIM([canal]), '')) AS [canal],
            ABS(TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([depense_ht]), ''), ',', '.'))) AS [depense_ht],
            CASE WHEN TRY_CONVERT(INT,[impressions]) >= TRY_CONVERT(INT,[clics]) THEN TRY_CONVERT(INT,[impressions]) END AS [impressions],
            TRY_CONVERT(INT, NULLIF(TRIM([clics]), '')) AS [clics],
            TRY_CONVERT(INT, NULLIF(TRIM([commandes_attribuees]), '')) AS [commandes_attribuees],
            TRY_CONVERT(INT, NULLIF(TRIM([nouveaux_clients_attribues]), '')) AS [nouveaux_clients_attribues],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([ca_attribue_ttc]), ''), ',', '.')) AS [ca_attribue_ttc],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'marketing_depenses_quotidiennes', [depense_id], N'depense_id', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'marketing_depenses_quotidiennes', [depense_id], N'impressions', [impressions], 'QR30', 'SIGNALEMENT', N'Impressions < clics : mise à NULL'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([impressions]), '') IS NOT NULL AND (CASE WHEN TRY_CONVERT(INT,[impressions]) >= TRY_CONVERT(INT,[clics]) THEN TRY_CONVERT(INT,[impressions]) END) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'marketing_depenses_quotidiennes', [depense_id], N'clics', [clics], 'QR43', 'REJET', N'Valeur non convertible en INT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([clics]), '') IS NOT NULL AND (TRY_CONVERT(INT, NULLIF(TRIM([clics]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'marketing_depenses_quotidiennes', [depense_id], N'commandes_attribuees', [commandes_attribuees], 'QR43', 'REJET', N'Valeur non convertible en INT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([commandes_attribuees]), '') IS NOT NULL AND (TRY_CONVERT(INT, NULLIF(TRIM([commandes_attribuees]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'marketing_depenses_quotidiennes', [depense_id], N'nouveaux_clients_attribues', [nouveaux_clients_attribues], 'QR43', 'REJET', N'Valeur non convertible en INT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([nouveaux_clients_attribues]), '') IS NOT NULL AND (TRY_CONVERT(INT, NULLIF(TRIM([nouveaux_clients_attribues]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'marketing_depenses_quotidiennes', [depense_id], N'ca_attribue_ttc', [ca_attribue_ttc], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([ca_attribue_ttc]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([ca_attribue_ttc]), ''), ',', '.'))) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'marketing_depenses_quotidiennes', n.[depense_id], N'date', LEFT(s.[date], 4000), 'QR08', 'CORRECTION', CONCAT(N'Date JJ/MM/AAAA convertie : ', CONVERT(NVARCHAR(400), n.[date]))
    FROM #src s JOIN #nouveau n ON n.[depense_id] = UPPER(TRIM(s.[depense_id]))
    WHERE s.rn = 1 AND (TRIM(s.[date]) LIKE '__/__/____');
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'marketing_depenses_quotidiennes', n.[depense_id], N'depense_ht', LEFT(s.[depense_ht], 4000), 'QR46', 'CORRECTION', CONCAT(N'Dépense négative → valeur absolue : ', CONVERT(NVARCHAR(400), n.[depense_ht]))
    FROM #src s JOIN #nouveau n ON n.[depense_id] = UPPER(TRIM(s.[depense_id]))
    WHERE s.rn = 1 AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM(s.[depense_ht]), ''), ',', '.')) < 0);

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [depense_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [campagne_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [canal]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [depense_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [impressions]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [clics]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commandes_attribuees]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nouveaux_clients_attribues]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [ca_attribue_ttc]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[marketing_depenses_quotidiennes] AS c
    USING #nouveau AS n
       ON c.[depense_id] = n.[depense_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [campagne_id] = n.[campagne_id], [date] = n.[date], [canal] = n.[canal], [depense_ht] = n.[depense_ht], [impressions] = n.[impressions], [clics] = n.[clics], [commandes_attribuees] = n.[commandes_attribuees], [nouveaux_clients_attribues] = n.[nouveaux_clients_attribues], [ca_attribue_ttc] = n.[ca_attribue_ttc],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([depense_id], [campagne_id], [date], [canal], [depense_ht], [impressions], [clics], [commandes_attribuees], [nouveaux_clients_attribues], [ca_attribue_ttc], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[depense_id], n.[campagne_id], n.[date], n.[canal], n.[depense_ht], n.[impressions], n.[clics], n.[commandes_attribuees], n.[nouveaux_clients_attribues], n.[ca_attribue_ttc], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.marketing_depenses_quotidiennes',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_marketing_depenses_quotidiennes';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_commandes  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.commandes  →  clean.commandes   (En-têtes de commandes clients)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_commandes
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'commandes';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[commande_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[commandes] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[commande_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [commande_id], [client_id], [date_commande], [canal], [appareil], [gouvernorat_livraison_id], [ville_livraison], [entrepot_id], [campagne_id], [code_coupon], [mode_paiement], [nb_lignes], [nb_articles], [sous_total_ttc], [remise_coupon_ttc], [frais_livraison_ttc], [montant_total_ttc], [statut_commande], [motif_annulation], [date_annulation], [est_premiere_commande], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[commandes];
    INSERT INTO #nouveau ([commande_id], [client_id], [date_commande], [canal], [appareil], [gouvernorat_livraison_id], [ville_livraison], [entrepot_id], [campagne_id], [code_coupon], [mode_paiement], [nb_lignes], [nb_articles], [sous_total_ttc], [remise_coupon_ttc], [frais_livraison_ttc], [montant_total_ttc], [statut_commande], [motif_annulation], [date_annulation], [est_premiere_commande], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([commande_id]), '')) AS [commande_id],
            UPPER(NULLIF(TRIM([client_id]), '')) AS [client_id],
            CASE WHEN TRIM([date_commande]) LIKE '__/__/____ __:__' THEN TRY_CONVERT(DATETIME2(0), SUBSTRING(TRIM([date_commande]),7,4)+'-'+SUBSTRING(TRIM([date_commande]),4,2)+'-'+LEFT(TRIM([date_commande]),2)+' '+SUBSTRING(TRIM([date_commande]),12,5)+':00', 120) ELSE TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_commande]),''), 120) END AS [date_commande],
            COALESCE(LOWER(NULLIF(TRIM([canal]), '')), CASE WHEN LOWER(TRIM([appareil])) IN ('ordinateur','tablette') THEN 'site_web' ELSE 'non_renseigne' END) AS [canal],
            LOWER(NULLIF(TRIM([appareil]), '')) AS [appareil],
            UPPER(NULLIF(TRIM([gouvernorat_livraison_id]), '')) AS [gouvernorat_livraison_id],
            NULLIF(TRIM([ville_livraison]), '') AS [ville_livraison],
            UPPER(NULLIF(TRIM([entrepot_id]), '')) AS [entrepot_id],
            UPPER(NULLIF(TRIM([campagne_id]), '')) AS [campagne_id],
            UPPER(NULLIF(TRIM([code_coupon]), '')) AS [code_coupon],
            LOWER(NULLIF(TRIM([mode_paiement]), '')) AS [mode_paiement],
            TRY_CONVERT(TINYINT, NULLIF(TRIM([nb_lignes]), '')) AS [nb_lignes],
            TRY_CONVERT(INT, NULLIF(TRIM([nb_articles]), '')) AS [nb_articles],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([sous_total_ttc]), ''), ',', '.')) AS [sous_total_ttc],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([remise_coupon_ttc]), ''), ',', '.')) AS [remise_coupon_ttc],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([frais_livraison_ttc]), ''), ',', '.')) AS [frais_livraison_ttc],
            TRY_CONVERT(DECIMAL(14,3), [sous_total_ttc]) - TRY_CONVERT(DECIMAL(14,3), [remise_coupon_ttc]) + TRY_CONVERT(DECIMAL(14,3), [frais_livraison_ttc]) AS [montant_total_ttc],
            clean.fn_sans_accent(LOWER(NULLIF(TRIM([statut_commande]), ''))) AS [statut_commande],
            LOWER(NULLIF(TRIM([motif_annulation]), '')) AS [motif_annulation],
            TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_annulation]), ''), 120) AS [date_annulation],
            CASE UPPER(TRIM([est_premiere_commande])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END AS [est_premiere_commande],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes', [commande_id], N'commande_id', NULL, 'QR01', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes', [commande_id], N'nb_lignes', [nb_lignes], 'QR43', 'REJET', N'Valeur non convertible en TINYINT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([nb_lignes]), '') IS NOT NULL AND (TRY_CONVERT(TINYINT, NULLIF(TRIM([nb_lignes]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes', [commande_id], N'nb_articles', [nb_articles], 'QR43', 'REJET', N'Valeur non convertible en INT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([nb_articles]), '') IS NOT NULL AND (TRY_CONVERT(INT, NULLIF(TRIM([nb_articles]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes', [commande_id], N'sous_total_ttc', [sous_total_ttc], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([sous_total_ttc]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([sous_total_ttc]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes', [commande_id], N'remise_coupon_ttc', [remise_coupon_ttc], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([remise_coupon_ttc]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([remise_coupon_ttc]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes', [commande_id], N'frais_livraison_ttc', [frais_livraison_ttc], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([frais_livraison_ttc]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([frais_livraison_ttc]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes', [commande_id], N'date_annulation', [date_annulation], 'QR43', 'REJET', N'Valeur non convertible en DATETIME2(0)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_annulation]), '') IS NOT NULL AND (TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_annulation]), ''), 120)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes', [commande_id], N'est_premiere_commande', [est_premiere_commande], 'QR43', 'REJET', N'Valeur non convertible en BIT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([est_premiere_commande]), '') IS NOT NULL AND (CASE UPPER(TRIM([est_premiere_commande])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes', n.[commande_id], N'date_commande', LEFT(s.[date_commande], 4000), 'QR06', 'CORRECTION', CONCAT(N'Date JJ/MM/AAAA HH:MI convertie : ', CONVERT(NVARCHAR(400), n.[date_commande]))
    FROM #src s JOIN #nouveau n ON n.[commande_id] = UPPER(TRIM(s.[commande_id]))
    WHERE s.rn = 1 AND (TRIM(s.[date_commande]) LIKE '__/__/____ __:__');
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes', n.[commande_id], N'statut_commande', LEFT(s.[statut_commande], 4000), 'QR13', 'CORRECTION', CONCAT(N'Statut harmonisé : ', CONVERT(NVARCHAR(400), n.[statut_commande]))
    FROM #src s JOIN #nouveau n ON n.[commande_id] = UPPER(TRIM(s.[commande_id]))
    WHERE s.rn = 1 AND (CONCAT(s.[statut_commande], N'|') COLLATE Latin1_General_CS_AS <> CONCAT(n.[statut_commande], N'|'));
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes', n.[commande_id], N'canal', LEFT(s.[canal], 4000), 'QR19', 'CORRECTION', CONCAT(N'Canal imputé depuis l''appareil : ', CONVERT(NVARCHAR(400), n.[canal]))
    FROM #src s JOIN #nouveau n ON n.[commande_id] = UPPER(TRIM(s.[commande_id]))
    WHERE s.rn = 1 AND (NULLIF(TRIM(s.[canal]), '') IS NULL);
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes', n.[commande_id], N'montant_total_ttc', LEFT(s.[montant_total_ttc], 4000), 'QR20', 'CORRECTION', CONCAT(N'Total recalculé : ', CONVERT(NVARCHAR(400), n.[montant_total_ttc]))
    FROM #src s JOIN #nouveau n ON n.[commande_id] = UPPER(TRIM(s.[commande_id]))
    WHERE s.rn = 1 AND (ABS(TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM(s.[montant_total_ttc]), ''), ',', '.')) - n.[montant_total_ttc]) > 0.001);

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [client_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_commande], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [canal]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [appareil]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [gouvernorat_livraison_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [ville_livraison]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [entrepot_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [campagne_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [code_coupon]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [mode_paiement]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nb_lignes]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nb_articles]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [sous_total_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [remise_coupon_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [frais_livraison_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_total_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [statut_commande]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [motif_annulation]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_annulation], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_premiere_commande]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[commandes] AS c
    USING #nouveau AS n
       ON c.[commande_id] = n.[commande_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [client_id] = n.[client_id], [date_commande] = n.[date_commande], [canal] = n.[canal], [appareil] = n.[appareil], [gouvernorat_livraison_id] = n.[gouvernorat_livraison_id], [ville_livraison] = n.[ville_livraison], [entrepot_id] = n.[entrepot_id], [campagne_id] = n.[campagne_id], [code_coupon] = n.[code_coupon], [mode_paiement] = n.[mode_paiement], [nb_lignes] = n.[nb_lignes], [nb_articles] = n.[nb_articles], [sous_total_ttc] = n.[sous_total_ttc], [remise_coupon_ttc] = n.[remise_coupon_ttc], [frais_livraison_ttc] = n.[frais_livraison_ttc], [montant_total_ttc] = n.[montant_total_ttc], [statut_commande] = n.[statut_commande], [motif_annulation] = n.[motif_annulation], [date_annulation] = n.[date_annulation], [est_premiere_commande] = n.[est_premiere_commande],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([commande_id], [client_id], [date_commande], [canal], [appareil], [gouvernorat_livraison_id], [ville_livraison], [entrepot_id], [campagne_id], [code_coupon], [mode_paiement], [nb_lignes], [nb_articles], [sous_total_ttc], [remise_coupon_ttc], [frais_livraison_ttc], [montant_total_ttc], [statut_commande], [motif_annulation], [date_annulation], [est_premiere_commande], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[commande_id], n.[client_id], n.[date_commande], n.[canal], n.[appareil], n.[gouvernorat_livraison_id], n.[ville_livraison], n.[entrepot_id], n.[campagne_id], n.[code_coupon], n.[mode_paiement], n.[nb_lignes], n.[nb_articles], n.[sous_total_ttc], n.[remise_coupon_ttc], n.[frais_livraison_ttc], n.[montant_total_ttc], n.[statut_commande], n.[motif_annulation], n.[date_annulation], n.[est_premiere_commande], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.commandes',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_commandes';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_lignes_commande  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.lignes_commande  →  clean.lignes_commande   (Lignes de commandes clients)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_lignes_commande
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'lignes_commande';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[ligne_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[lignes_commande] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[ligne_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [ligne_id], [commande_id], [num_ligne], [produit_id], [quantite], [prix_catalogue_ttc], [remise_promo_unitaire_ttc], [prix_unitaire_ttc], [taux_tva], [montant_ligne_ttc], [montant_ligne_ht], [montant_tva], [cout_achat_unitaire_ht], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[lignes_commande];
    INSERT INTO #nouveau ([ligne_id], [commande_id], [num_ligne], [produit_id], [quantite], [prix_catalogue_ttc], [remise_promo_unitaire_ttc], [prix_unitaire_ttc], [taux_tva], [montant_ligne_ttc], [montant_ligne_ht], [montant_tva], [cout_achat_unitaire_ht], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([ligne_id]), '')) AS [ligne_id],
            UPPER(NULLIF(TRIM([commande_id]), '')) AS [commande_id],
            TRY_CONVERT(TINYINT, NULLIF(TRIM([num_ligne]), '')) AS [num_ligne],
            UPPER(NULLIF(TRIM([produit_id]), '')) AS [produit_id],
            CASE WHEN TRY_CONVERT(INT,[quantite]) > 0 AND ABS(TRY_CONVERT(INT,[quantite])*TRY_CONVERT(DECIMAL(14,3),[prix_unitaire_ttc]) - TRY_CONVERT(DECIMAL(14,3),[montant_ligne_ht])*(1+TRY_CONVERT(DECIMAL(14,3),[taux_tva])/100)) < 0.05 THEN TRY_CONVERT(INT,[quantite]) ELSE CAST(ROUND(TRY_CONVERT(DECIMAL(14,3),[montant_ligne_ht])*(1+TRY_CONVERT(DECIMAL(14,3),[taux_tva])/100)/NULLIF(TRY_CONVERT(DECIMAL(14,3),[prix_unitaire_ttc]),0),0) AS INT) END AS [quantite],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([prix_catalogue_ttc]), ''), ',', '.')) AS [prix_catalogue_ttc],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([remise_promo_unitaire_ttc]), ''), ',', '.')) AS [remise_promo_unitaire_ttc],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([prix_unitaire_ttc]), ''), ',', '.')) AS [prix_unitaire_ttc],
            TRY_CONVERT(TINYINT, NULLIF(TRIM([taux_tva]), '')) AS [taux_tva],
            NULL /* calculé en post-traitement : quantite × prix_unitaire_ttc */ AS [montant_ligne_ttc],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([montant_ligne_ht]), ''), ',', '.')) AS [montant_ligne_ht],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([montant_tva]), ''), ',', '.')) AS [montant_tva],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_achat_unitaire_ht]), ''), ',', '.')) AS [cout_achat_unitaire_ht],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande', [ligne_id], N'ligne_id', NULL, 'QR02', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande', [ligne_id], N'num_ligne', [num_ligne], 'QR43', 'REJET', N'Valeur non convertible en TINYINT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([num_ligne]), '') IS NOT NULL AND (TRY_CONVERT(TINYINT, NULLIF(TRIM([num_ligne]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande', [ligne_id], N'prix_catalogue_ttc', [prix_catalogue_ttc], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([prix_catalogue_ttc]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([prix_catalogue_ttc]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande', [ligne_id], N'remise_promo_unitaire_ttc', [remise_promo_unitaire_ttc], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([remise_promo_unitaire_ttc]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([remise_promo_unitaire_ttc]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande', [ligne_id], N'prix_unitaire_ttc', [prix_unitaire_ttc], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([prix_unitaire_ttc]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([prix_unitaire_ttc]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande', [ligne_id], N'taux_tva', [taux_tva], 'QR43', 'REJET', N'Valeur non convertible en TINYINT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([taux_tva]), '') IS NOT NULL AND (TRY_CONVERT(TINYINT, NULLIF(TRIM([taux_tva]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande', [ligne_id], N'montant_ligne_ht', [montant_ligne_ht], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([montant_ligne_ht]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([montant_ligne_ht]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande', [ligne_id], N'montant_tva', [montant_tva], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([montant_tva]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([montant_tva]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande', [ligne_id], N'cout_achat_unitaire_ht', [cout_achat_unitaire_ht], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([cout_achat_unitaire_ht]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_achat_unitaire_ht]), ''), ',', '.'))) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- Règle QR22 (calculée sur l'ensemble des lignes reçues)
    UPDATE #nouveau
    SET montant_ligne_ttc = quantite * prix_unitaire_ttc
    WHERE montant_ligne_ttc IS NULL OR montant_ligne_ttc <> quantite * prix_unitaire_ttc;

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande', n.[ligne_id], N'quantite', LEFT(s.[quantite], 4000), 'QR21', 'CORRECTION', CONCAT(N'Quantité recalculée depuis le montant HT : ', CONVERT(NVARCHAR(400), n.[quantite]))
    FROM #src s JOIN #nouveau n ON n.[ligne_id] = UPPER(TRIM(s.[ligne_id]))
    WHERE s.rn = 1 AND (ISNULL(TRY_CONVERT(INT, s.[quantite]), -999999) <> n.[quantite]);
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande', n.[ligne_id], N'montant_ligne_ttc', LEFT(s.[montant_ligne_ttc], 4000), 'QR22', 'CORRECTION', CONCAT(N'Montant TTC recalculé (quantité × prix) : ', CONVERT(NVARCHAR(400), n.[montant_ligne_ttc]))
    FROM #src s JOIN #nouveau n ON n.[ligne_id] = UPPER(TRIM(s.[ligne_id]))
    WHERE s.rn = 1 AND (ABS(ISNULL(TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM(s.[montant_ligne_ttc]), ''), ',', '.')), 0) - n.[montant_ligne_ttc]) > 0.001);

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [ligne_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [num_ligne]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [quantite]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [prix_catalogue_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [remise_promo_unitaire_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [prix_unitaire_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [taux_tva]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_ligne_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_ligne_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_tva]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_achat_unitaire_ht]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[lignes_commande] AS c
    USING #nouveau AS n
       ON c.[ligne_id] = n.[ligne_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [commande_id] = n.[commande_id], [num_ligne] = n.[num_ligne], [produit_id] = n.[produit_id], [quantite] = n.[quantite], [prix_catalogue_ttc] = n.[prix_catalogue_ttc], [remise_promo_unitaire_ttc] = n.[remise_promo_unitaire_ttc], [prix_unitaire_ttc] = n.[prix_unitaire_ttc], [taux_tva] = n.[taux_tva], [montant_ligne_ttc] = n.[montant_ligne_ttc], [montant_ligne_ht] = n.[montant_ligne_ht], [montant_tva] = n.[montant_tva], [cout_achat_unitaire_ht] = n.[cout_achat_unitaire_ht],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([ligne_id], [commande_id], [num_ligne], [produit_id], [quantite], [prix_catalogue_ttc], [remise_promo_unitaire_ttc], [prix_unitaire_ttc], [taux_tva], [montant_ligne_ttc], [montant_ligne_ht], [montant_tva], [cout_achat_unitaire_ht], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[ligne_id], n.[commande_id], n.[num_ligne], n.[produit_id], n.[quantite], n.[prix_catalogue_ttc], n.[remise_promo_unitaire_ttc], n.[prix_unitaire_ttc], n.[taux_tva], n.[montant_ligne_ttc], n.[montant_ligne_ht], n.[montant_tva], n.[cout_achat_unitaire_ht], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.lignes_commande',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_lignes_commande';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_paiements  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.paiements  →  clean.paiements   (Tentatives de paiement (JSON aplati))
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_paiements
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'paiements';
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'paiements', CONCAT('ligne ', num_ligne_fichier), N'ligne_json', LEFT(ligne_json, 4000), 'QR43', 'REJET', N'JSON invalide'
    FROM [TuniShop_STG_RAW].raw.paiements_api WHERE id_chargement = @id_chargement AND ISJSON(ligne_json) = 0;

    SELECT r.num_ligne_fichier, x.*,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(x.payment_id)) ORDER BY r.num_ligne_fichier) AS rn
    INTO #d
    FROM [TuniShop_STG_RAW].raw.paiements_api AS r
    CROSS APPLY OPENJSON(r.ligne_json) WITH (
        payment_id VARCHAR(20) '$.payment_id', order_ref VARCHAR(20) '$.order_ref', attempt INT '$.attempt',
        method VARCHAR(30) '$.method', amount_value DECIMAL(14,3) '$.amount.value', amount_currency VARCHAR(5) '$.amount.currency',
        status VARCHAR(20) '$.status', error_code VARCHAR(40) '$.error_code', created_at VARCHAR(30) '$.created_at',
        provider NVARCHAR(50) '$.provider', transaction_ref VARCHAR(30) '$.transaction_ref', settlement_date VARCHAR(10) '$.settlement_date') AS x
    WHERE r.id_chargement = @id_chargement AND ISJSON(r.ligne_json) = 1 AND NULLIF(TRIM(x.payment_id), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    SELECT TOP (0) [paiement_id], [commande_id], [num_tentative], [mode_paiement], [montant_ttc], [devise], [statut_paiement], [code_erreur], [date_paiement], [prestataire], [reference_transaction], [date_reversement], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.paiements;
    INSERT INTO #nouveau (paiement_id, commande_id, num_tentative, mode_paiement, montant_ttc, devise, statut_paiement, code_erreur, date_paiement, prestataire, reference_transaction, date_reversement, id_chargement, date_traitement)
    SELECT  UPPER(TRIM(payment_id)), UPPER(TRIM(order_ref)), attempt,
            CASE UPPER(TRIM(method)) WHEN 'COD' THEN 'paiement_a_la_livraison' WHEN 'CARD' THEN 'carte_bancaire' WHEN 'WALLET' THEN 'portefeuille_mobile'
                                     WHEN 'PREPAID_CARD' THEN 'carte_prepayee' WHEN 'BANK_TRANSFER' THEN 'virement' END,
            amount_value, UPPER(TRIM(amount_currency)),
            CASE UPPER(TRIM(status)) WHEN 'SUCCESS' THEN 'reussi' WHEN 'COLLECTED' THEN 'encaisse' WHEN 'FAILED' THEN 'echoue' END,
            LOWER(NULLIF(TRIM(error_code), '')),
            CAST((TRY_CONVERT(DATETIME2(0), created_at, 127) AT TIME ZONE 'UTC') AT TIME ZONE 'W. Central Africa Standard Time' AS DATETIME2(0)),
            NULLIF(TRIM(provider), N''), UPPER(TRIM(transaction_ref)), TRY_CONVERT(DATE, settlement_date, 23),
            @id_chargement, SYSDATETIME()
    FROM #d WHERE rn = 1;

    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'paiements', payment_id, N'payment_id', NULL, 'QR05', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #d WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'paiements', paiement_id, N'mode_paiement/statut_paiement', NULL, 'QR39', 'SIGNALEMENT', N'Code de paiement inconnu'
    FROM #nouveau WHERE mode_paiement IS NULL OR statut_paiement IS NULL;

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [paiement_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [num_tentative]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [mode_paiement]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [devise]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [statut_paiement]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [code_erreur]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_paiement], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [prestataire]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [reference_transaction]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_reversement], 121), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[paiements] AS c
    USING #nouveau AS n
       ON c.[paiement_id] = n.[paiement_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [commande_id] = n.[commande_id], [num_tentative] = n.[num_tentative], [mode_paiement] = n.[mode_paiement], [montant_ttc] = n.[montant_ttc], [devise] = n.[devise], [statut_paiement] = n.[statut_paiement], [code_erreur] = n.[code_erreur], [date_paiement] = n.[date_paiement], [prestataire] = n.[prestataire], [reference_transaction] = n.[reference_transaction], [date_reversement] = n.[date_reversement],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([paiement_id], [commande_id], [num_tentative], [mode_paiement], [montant_ttc], [devise], [statut_paiement], [code_erreur], [date_paiement], [prestataire], [reference_transaction], [date_reversement], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[paiement_id], n.[commande_id], n.[num_tentative], n.[mode_paiement], n.[montant_ttc], n.[devise], n.[statut_paiement], n.[code_erreur], n.[date_paiement], n.[prestataire], n.[reference_transaction], n.[date_reversement], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.paiements',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_paiements';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_livraisons  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.livraisons  →  clean.livraisons   (Expéditions et suivi de livraison)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_livraisons
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'livraisons';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[livraison_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[livraisons] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[livraison_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [livraison_id], [commande_id], [entrepot_id], [transporteur_id], [gouvernorat_destination_id], [date_expedition], [date_livraison_prevue], [date_livraison_reelle], [date_dernier_evenement], [statut_livraison], [nb_tentatives], [poids_kg], [cout_transport_ht], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[livraisons];
    INSERT INTO #nouveau ([livraison_id], [commande_id], [entrepot_id], [transporteur_id], [gouvernorat_destination_id], [date_expedition], [date_livraison_prevue], [date_livraison_reelle], [date_dernier_evenement], [statut_livraison], [nb_tentatives], [poids_kg], [cout_transport_ht], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([livraison_id]), '')) AS [livraison_id],
            UPPER(NULLIF(TRIM([commande_id]), '')) AS [commande_id],
            UPPER(NULLIF(TRIM([entrepot_id]), '')) AS [entrepot_id],
            UPPER(NULLIF(TRIM([transporteur_id]), '')) AS [transporteur_id],
            UPPER(NULLIF(TRIM([gouvernorat_destination_id]), '')) AS [gouvernorat_destination_id],
            TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_expedition]), ''), 120) AS [date_expedition],
            TRY_CONVERT(DATE, NULLIF(TRIM([date_livraison_prevue]), ''), 23) AS [date_livraison_prevue],
            CASE WHEN TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_livraison_reelle]),''), 120) < TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_expedition]),''), 120) THEN TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_dernier_evenement]),''), 120) ELSE TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_livraison_reelle]),''), 120) END AS [date_livraison_reelle],
            TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_dernier_evenement]), ''), 120) AS [date_dernier_evenement],
            COALESCE(LOWER(NULLIF(TRIM([statut_livraison]), '')), CASE WHEN NULLIF(TRIM([date_livraison_reelle]),'') IS NOT NULL THEN 'livree' WHEN NULLIF(TRIM([date_expedition]),'') IS NOT NULL THEN 'en_transit' ELSE 'en_preparation' END) AS [statut_livraison],
            TRY_CONVERT(TINYINT, NULLIF(TRIM([nb_tentatives]), '')) AS [nb_tentatives],
            TRY_CONVERT(DECIMAL(8,2), REPLACE(NULLIF(TRIM([poids_kg]), ''), ',', '.')) AS [poids_kg],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_transport_ht]), ''), ',', '.')) AS [cout_transport_ht],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'livraisons', [livraison_id], N'livraison_id', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'livraisons', [livraison_id], N'date_expedition', [date_expedition], 'QR43', 'REJET', N'Valeur non convertible en DATETIME2(0)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_expedition]), '') IS NOT NULL AND (TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_expedition]), ''), 120)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'livraisons', [livraison_id], N'date_livraison_prevue', [date_livraison_prevue], 'QR43', 'REJET', N'Valeur non convertible en DATE'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_livraison_prevue]), '') IS NOT NULL AND (TRY_CONVERT(DATE, NULLIF(TRIM([date_livraison_prevue]), ''), 23)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'livraisons', [livraison_id], N'date_dernier_evenement', [date_dernier_evenement], 'QR43', 'REJET', N'Valeur non convertible en DATETIME2(0)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_dernier_evenement]), '') IS NOT NULL AND (TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_dernier_evenement]), ''), 120)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'livraisons', [livraison_id], N'nb_tentatives', [nb_tentatives], 'QR43', 'REJET', N'Valeur non convertible en TINYINT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([nb_tentatives]), '') IS NOT NULL AND (TRY_CONVERT(TINYINT, NULLIF(TRIM([nb_tentatives]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'livraisons', [livraison_id], N'poids_kg', [poids_kg], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(8,2)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([poids_kg]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(8,2), REPLACE(NULLIF(TRIM([poids_kg]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'livraisons', [livraison_id], N'cout_transport_ht', [cout_transport_ht], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([cout_transport_ht]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_transport_ht]), ''), ',', '.'))) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'livraisons', n.[livraison_id], N'transporteur_id', LEFT(s.[transporteur_id], 4000), 'QR14', 'CORRECTION', CONCAT(N'Identifiant mis en majuscules : ', CONVERT(NVARCHAR(400), n.[transporteur_id]))
    FROM #src s JOIN #nouveau n ON n.[livraison_id] = UPPER(TRIM(s.[livraison_id]))
    WHERE s.rn = 1 AND (CONCAT(s.[transporteur_id], N'|') COLLATE Latin1_General_CS_AS <> CONCAT(n.[transporteur_id], N'|'));
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'livraisons', n.[livraison_id], N'date_livraison_reelle', LEFT(s.[date_livraison_reelle], 4000), 'QR34', 'CORRECTION', CONCAT(N'Livraison antérieure à l''expédition : date du dernier événement : ', CONVERT(NVARCHAR(400), n.[date_livraison_reelle]))
    FROM #src s JOIN #nouveau n ON n.[livraison_id] = UPPER(TRIM(s.[livraison_id]))
    WHERE s.rn = 1 AND (ISNULL(TRY_CONVERT(DATETIME2(0), NULLIF(TRIM(s.[date_livraison_reelle]), ''), 120), '19000101') <> ISNULL(n.[date_livraison_reelle], '19000101'));
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'livraisons', n.[livraison_id], N'statut_livraison', LEFT(s.[statut_livraison], 4000), 'QR35', 'CORRECTION', CONCAT(N'Statut imputé depuis les dates : ', CONVERT(NVARCHAR(400), n.[statut_livraison]))
    FROM #src s JOIN #nouveau n ON n.[livraison_id] = UPPER(TRIM(s.[livraison_id]))
    WHERE s.rn = 1 AND (NULLIF(TRIM(s.[statut_livraison]), '') IS NULL);

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [livraison_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [entrepot_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [transporteur_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [gouvernorat_destination_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_expedition], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_livraison_prevue], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_livraison_reelle], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_dernier_evenement], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [statut_livraison]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nb_tentatives]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [poids_kg]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_transport_ht]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[livraisons] AS c
    USING #nouveau AS n
       ON c.[livraison_id] = n.[livraison_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [commande_id] = n.[commande_id], [entrepot_id] = n.[entrepot_id], [transporteur_id] = n.[transporteur_id], [gouvernorat_destination_id] = n.[gouvernorat_destination_id], [date_expedition] = n.[date_expedition], [date_livraison_prevue] = n.[date_livraison_prevue], [date_livraison_reelle] = n.[date_livraison_reelle], [date_dernier_evenement] = n.[date_dernier_evenement], [statut_livraison] = n.[statut_livraison], [nb_tentatives] = n.[nb_tentatives], [poids_kg] = n.[poids_kg], [cout_transport_ht] = n.[cout_transport_ht],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([livraison_id], [commande_id], [entrepot_id], [transporteur_id], [gouvernorat_destination_id], [date_expedition], [date_livraison_prevue], [date_livraison_reelle], [date_dernier_evenement], [statut_livraison], [nb_tentatives], [poids_kg], [cout_transport_ht], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[livraison_id], n.[commande_id], n.[entrepot_id], n.[transporteur_id], n.[gouvernorat_destination_id], n.[date_expedition], n.[date_livraison_prevue], n.[date_livraison_reelle], n.[date_dernier_evenement], n.[statut_livraison], n.[nb_tentatives], n.[poids_kg], n.[cout_transport_ht], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.livraisons',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_livraisons';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_remboursements  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.remboursements  →  clean.remboursements   (Retours, annulations et gestes commerciaux)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_remboursements
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'remboursements';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[remboursement_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[remboursements] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[remboursement_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [remboursement_id], [commande_id], [ligne_id], [type_remboursement], [motif], [quantite], [montant_rembourse_ttc], [montant_demande_ttc], [date_demande], [date_reception_retour], [date_remboursement], [mode_remboursement], [statut], [etat_article], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[remboursements];
    INSERT INTO #nouveau ([remboursement_id], [commande_id], [ligne_id], [type_remboursement], [motif], [quantite], [montant_rembourse_ttc], [montant_demande_ttc], [date_demande], [date_reception_retour], [date_remboursement], [mode_remboursement], [statut], [etat_article], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([remboursement_id]), '')) AS [remboursement_id],
            UPPER(NULLIF(TRIM([commande_id]), '')) AS [commande_id],
            UPPER(NULLIF(TRIM([ligne_id]), '')) AS [ligne_id],
            LOWER(NULLIF(TRIM([type_remboursement]), '')) AS [type_remboursement],
            LOWER(NULLIF(TRIM([motif]), '')) AS [motif],
            TRY_CONVERT(INT, NULLIF(TRIM([quantite]), '')) AS [quantite],
            CASE WHEN TRY_CONVERT(DECIMAL(14,3),[montant_rembourse_ttc]) > TRY_CONVERT(DECIMAL(14,3),[montant_demande_ttc]) THEN TRY_CONVERT(DECIMAL(14,3),[montant_demande_ttc]) ELSE TRY_CONVERT(DECIMAL(14,3),[montant_rembourse_ttc]) END AS [montant_rembourse_ttc],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([montant_demande_ttc]), ''), ',', '.')) AS [montant_demande_ttc],
            TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_demande]), ''), 120) AS [date_demande],
            TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_reception_retour]), ''), 120) AS [date_reception_retour],
            CASE WHEN TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_remboursement]),''), 120) >= TRY_CONVERT(DATETIME2(0), [date_demande], 120) THEN TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_remboursement]),''), 120) END AS [date_remboursement],
            LOWER(NULLIF(TRIM([mode_remboursement]), '')) AS [mode_remboursement],
            LOWER(NULLIF(TRIM([statut]), '')) AS [statut],
            LOWER(NULLIF(TRIM([etat_article]), '')) AS [etat_article],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'remboursements', [remboursement_id], N'remboursement_id', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'remboursements', [remboursement_id], N'quantite', [quantite], 'QR43', 'REJET', N'Valeur non convertible en INT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([quantite]), '') IS NOT NULL AND (TRY_CONVERT(INT, NULLIF(TRIM([quantite]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'remboursements', [remboursement_id], N'montant_demande_ttc', [montant_demande_ttc], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([montant_demande_ttc]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([montant_demande_ttc]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'remboursements', [remboursement_id], N'date_demande', [date_demande], 'QR43', 'REJET', N'Valeur non convertible en DATETIME2(0)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_demande]), '') IS NOT NULL AND (TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_demande]), ''), 120)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'remboursements', [remboursement_id], N'date_reception_retour', [date_reception_retour], 'QR43', 'REJET', N'Valeur non convertible en DATETIME2(0)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_reception_retour]), '') IS NOT NULL AND (TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_reception_retour]), ''), 120)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'remboursements', [remboursement_id], N'date_remboursement', [date_remboursement], 'QR33', 'SIGNALEMENT', N'Date de remboursement antérieure à la demande : mise à NULL'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_remboursement]), '') IS NOT NULL AND (CASE WHEN TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_remboursement]),''), 120) >= TRY_CONVERT(DATETIME2(0), [date_demande], 120) THEN TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_remboursement]),''), 120) END) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'remboursements', n.[remboursement_id], N'montant_rembourse_ttc', LEFT(s.[montant_rembourse_ttc], 4000), 'QR32', 'CORRECTION', CONCAT(N'Montant plafonné au montant demandé : ', CONVERT(NVARCHAR(400), n.[montant_rembourse_ttc]))
    FROM #src s JOIN #nouveau n ON n.[remboursement_id] = UPPER(TRIM(s.[remboursement_id]))
    WHERE s.rn = 1 AND (ABS(TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM(s.[montant_rembourse_ttc]), ''), ',', '.')) - n.[montant_rembourse_ttc]) > 0.001);

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [remboursement_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [ligne_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [type_remboursement]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [motif]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [quantite]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_rembourse_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_demande_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_demande], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_reception_retour], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_remboursement], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [mode_remboursement]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [statut]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [etat_article]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[remboursements] AS c
    USING #nouveau AS n
       ON c.[remboursement_id] = n.[remboursement_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [commande_id] = n.[commande_id], [ligne_id] = n.[ligne_id], [type_remboursement] = n.[type_remboursement], [motif] = n.[motif], [quantite] = n.[quantite], [montant_rembourse_ttc] = n.[montant_rembourse_ttc], [montant_demande_ttc] = n.[montant_demande_ttc], [date_demande] = n.[date_demande], [date_reception_retour] = n.[date_reception_retour], [date_remboursement] = n.[date_remboursement], [mode_remboursement] = n.[mode_remboursement], [statut] = n.[statut], [etat_article] = n.[etat_article],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([remboursement_id], [commande_id], [ligne_id], [type_remboursement], [motif], [quantite], [montant_rembourse_ttc], [montant_demande_ttc], [date_demande], [date_reception_retour], [date_remboursement], [mode_remboursement], [statut], [etat_article], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[remboursement_id], n.[commande_id], n.[ligne_id], n.[type_remboursement], n.[motif], n.[quantite], n.[montant_rembourse_ttc], n.[montant_demande_ttc], n.[date_demande], n.[date_reception_retour], n.[date_remboursement], n.[mode_remboursement], n.[statut], n.[etat_article], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.remboursements',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_remboursements';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_avis_clients  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.avis_clients  →  clean.avis_clients   (Avis et notes clients)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_avis_clients
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'avis_clients';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[avis_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[avis_clients] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[avis_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [avis_id], [commande_id], [ligne_id], [produit_id], [client_id], [date_avis], [note], [commentaire], [achat_verifie], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[avis_clients];
    INSERT INTO #nouveau ([avis_id], [commande_id], [ligne_id], [produit_id], [client_id], [date_avis], [note], [commentaire], [achat_verifie], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([avis_id]), '')) AS [avis_id],
            UPPER(NULLIF(TRIM([commande_id]), '')) AS [commande_id],
            UPPER(NULLIF(TRIM([ligne_id]), '')) AS [ligne_id],
            UPPER(NULLIF(TRIM([produit_id]), '')) AS [produit_id],
            UPPER(NULLIF(TRIM([client_id]), '')) AS [client_id],
            TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_avis]), ''), 120) AS [date_avis],
            CASE WHEN TRY_CONVERT(TINYINT, [note]) BETWEEN 1 AND 5 THEN TRY_CONVERT(TINYINT, [note]) END AS [note],
            NULLIF(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE([commentaire], '<p>', ''), '</p>', ''), '<br/>', ''), '<br />', ''), '<br>', '')), '') AS [commentaire],
            CASE UPPER(TRIM([achat_verifie])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END AS [achat_verifie],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'avis_clients', [avis_id], N'avis_id', NULL, 'QR04', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'avis_clients', [avis_id], N'date_avis', [date_avis], 'QR43', 'REJET', N'Valeur non convertible en DATETIME2(0)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_avis]), '') IS NOT NULL AND (TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_avis]), ''), 120)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'avis_clients', [avis_id], N'note', [note], 'QR28', 'SIGNALEMENT', N'Note hors 1–5 : mise à NULL'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([note]), '') IS NOT NULL AND (CASE WHEN TRY_CONVERT(TINYINT, [note]) BETWEEN 1 AND 5 THEN TRY_CONVERT(TINYINT, [note]) END) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'avis_clients', [avis_id], N'achat_verifie', [achat_verifie], 'QR43', 'REJET', N'Valeur non convertible en BIT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([achat_verifie]), '') IS NOT NULL AND (CASE UPPER(TRIM([achat_verifie])) WHEN 'TRUE' THEN 1 WHEN '1' THEN 1 WHEN 'FALSE' THEN 0 WHEN '0' THEN 0 END) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'avis_clients', n.[avis_id], N'commentaire', LEFT(s.[commentaire], 4000), 'QR29', 'CORRECTION', CONCAT(N'Commentaire nettoyé (espaces, balises HTML) : ', CONVERT(NVARCHAR(400), n.[commentaire]))
    FROM #src s JOIN #nouveau n ON n.[avis_id] = UPPER(TRIM(s.[avis_id]))
    WHERE s.rn = 1 AND (NULLIF(TRIM(s.[commentaire]), '') IS NOT NULL AND (n.[commentaire] IS NULL OR CONCAT(s.[commentaire], N'|') COLLATE Latin1_General_CS_AS <> CONCAT(n.[commentaire], N'|')));

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [avis_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [ligne_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [client_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_avis], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [note]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commentaire]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [achat_verifie]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[avis_clients] AS c
    USING #nouveau AS n
       ON c.[avis_id] = n.[avis_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [commande_id] = n.[commande_id], [ligne_id] = n.[ligne_id], [produit_id] = n.[produit_id], [client_id] = n.[client_id], [date_avis] = n.[date_avis], [note] = n.[note], [commentaire] = n.[commentaire], [achat_verifie] = n.[achat_verifie],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([avis_id], [commande_id], [ligne_id], [produit_id], [client_id], [date_avis], [note], [commentaire], [achat_verifie], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[avis_id], n.[commande_id], n.[ligne_id], n.[produit_id], n.[client_id], n.[date_avis], n.[note], n.[commentaire], n.[achat_verifie], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.avis_clients',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_avis_clients';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_commandes_fournisseurs  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.commandes_fournisseurs  →  clean.commandes_fournisseurs   (En-têtes de commandes fournisseurs)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_commandes_fournisseurs
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'commandes_fournisseurs';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[commande_fournisseur_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[commandes_fournisseurs] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[commande_fournisseur_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [commande_fournisseur_id], [fournisseur_id], [entrepot_id], [date_commande], [date_livraison_prevue], [date_reception], [statut], [montant_total_ht], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[commandes_fournisseurs];
    INSERT INTO #nouveau ([commande_fournisseur_id], [fournisseur_id], [entrepot_id], [date_commande], [date_livraison_prevue], [date_reception], [statut], [montant_total_ht], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([commande_fournisseur_id]), '')) AS [commande_fournisseur_id],
            UPPER(NULLIF(TRIM([fournisseur_id]), '')) AS [fournisseur_id],
            UPPER(NULLIF(TRIM([entrepot_id]), '')) AS [entrepot_id],
            TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_commande]), ''), 120) AS [date_commande],
            TRY_CONVERT(DATE, NULLIF(TRIM([date_livraison_prevue]), ''), 23) AS [date_livraison_prevue],
            TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_reception]), ''), 120) AS [date_reception],
            LOWER(NULLIF(TRIM([statut]), '')) AS [statut],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([montant_total_ht]), ''), ',', '.')) AS [montant_total_ht],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes_fournisseurs', [commande_fournisseur_id], N'commande_fournisseur_id', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes_fournisseurs', [commande_fournisseur_id], N'date_commande', [date_commande], 'QR43', 'REJET', N'Valeur non convertible en DATETIME2(0)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_commande]), '') IS NOT NULL AND (TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_commande]), ''), 120)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes_fournisseurs', [commande_fournisseur_id], N'date_livraison_prevue', [date_livraison_prevue], 'QR43', 'REJET', N'Valeur non convertible en DATE'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_livraison_prevue]), '') IS NOT NULL AND (TRY_CONVERT(DATE, NULLIF(TRIM([date_livraison_prevue]), ''), 23)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes_fournisseurs', [commande_fournisseur_id], N'date_reception', [date_reception], 'QR43', 'REJET', N'Valeur non convertible en DATETIME2(0)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_reception]), '') IS NOT NULL AND (TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_reception]), ''), 120)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commandes_fournisseurs', [commande_fournisseur_id], N'montant_total_ht', [montant_total_ht], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([montant_total_ht]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([montant_total_ht]), ''), ',', '.'))) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    -- aucune correction tracée pour cette table

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_fournisseur_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [fournisseur_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [entrepot_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_commande], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_livraison_prevue], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_reception], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [statut]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_total_ht]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[commandes_fournisseurs] AS c
    USING #nouveau AS n
       ON c.[commande_fournisseur_id] = n.[commande_fournisseur_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [fournisseur_id] = n.[fournisseur_id], [entrepot_id] = n.[entrepot_id], [date_commande] = n.[date_commande], [date_livraison_prevue] = n.[date_livraison_prevue], [date_reception] = n.[date_reception], [statut] = n.[statut], [montant_total_ht] = n.[montant_total_ht],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([commande_fournisseur_id], [fournisseur_id], [entrepot_id], [date_commande], [date_livraison_prevue], [date_reception], [statut], [montant_total_ht], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[commande_fournisseur_id], n.[fournisseur_id], n.[entrepot_id], n.[date_commande], n.[date_livraison_prevue], n.[date_reception], n.[statut], n.[montant_total_ht], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.commandes_fournisseurs',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_commandes_fournisseurs';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_lignes_commande_fournisseur  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.lignes_commande_fournisseur  →  clean.lignes_commande_fournisseur   (Lignes de commandes fournisseurs)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_lignes_commande_fournisseur
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'lignes_commande_fournisseur';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[ligne_cf_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[lignes_commande_fournisseur] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[ligne_cf_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [ligne_cf_id], [commande_fournisseur_id], [produit_id], [quantite_commandee], [quantite_recue], [cout_unitaire_ht], [montant_ligne_ht], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[lignes_commande_fournisseur];
    INSERT INTO #nouveau ([ligne_cf_id], [commande_fournisseur_id], [produit_id], [quantite_commandee], [quantite_recue], [cout_unitaire_ht], [montant_ligne_ht], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([ligne_cf_id]), '')) AS [ligne_cf_id],
            UPPER(NULLIF(TRIM([commande_fournisseur_id]), '')) AS [commande_fournisseur_id],
            UPPER(NULLIF(TRIM([produit_id]), '')) AS [produit_id],
            TRY_CONVERT(INT, NULLIF(TRIM([quantite_commandee]), '')) AS [quantite_commandee],
            CASE WHEN TRY_CONVERT(INT,[quantite_recue]) > TRY_CONVERT(INT,[quantite_commandee]) THEN CASE WHEN TRY_CONVERT(INT,[quantite_recue]) % 10 = 0 AND TRY_CONVERT(INT,[quantite_recue]) / 10 <= TRY_CONVERT(INT,[quantite_commandee]) THEN TRY_CONVERT(INT,[quantite_recue]) / 10 ELSE TRY_CONVERT(INT,[quantite_commandee]) END ELSE TRY_CONVERT(INT, NULLIF(TRIM([quantite_recue]),'')) END AS [quantite_recue],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_unitaire_ht]), ''), ',', '.')) AS [cout_unitaire_ht],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([montant_ligne_ht]), ''), ',', '.')) AS [montant_ligne_ht],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande_fournisseur', [ligne_cf_id], N'ligne_cf_id', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande_fournisseur', [ligne_cf_id], N'quantite_commandee', [quantite_commandee], 'QR43', 'REJET', N'Valeur non convertible en INT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([quantite_commandee]), '') IS NOT NULL AND (TRY_CONVERT(INT, NULLIF(TRIM([quantite_commandee]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande_fournisseur', [ligne_cf_id], N'cout_unitaire_ht', [cout_unitaire_ht], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([cout_unitaire_ht]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_unitaire_ht]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande_fournisseur', [ligne_cf_id], N'montant_ligne_ht', [montant_ligne_ht], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([montant_ligne_ht]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([montant_ligne_ht]), ''), ',', '.'))) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'lignes_commande_fournisseur', n.[ligne_cf_id], N'quantite_recue', LEFT(s.[quantite_recue], 4000), 'QR31', 'CORRECTION', CONCAT(N'Quantité reçue corrigée : ', CONVERT(NVARCHAR(400), n.[quantite_recue]))
    FROM #src s JOIN #nouveau n ON n.[ligne_cf_id] = UPPER(TRIM(s.[ligne_cf_id]))
    WHERE s.rn = 1 AND (NULLIF(TRIM(s.[quantite_recue]), '') IS NOT NULL AND TRY_CONVERT(INT, s.[quantite_recue]) <> n.[quantite_recue]);

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [ligne_cf_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_fournisseur_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [quantite_commandee]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [quantite_recue]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_unitaire_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_ligne_ht]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[lignes_commande_fournisseur] AS c
    USING #nouveau AS n
       ON c.[ligne_cf_id] = n.[ligne_cf_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [commande_fournisseur_id] = n.[commande_fournisseur_id], [produit_id] = n.[produit_id], [quantite_commandee] = n.[quantite_commandee], [quantite_recue] = n.[quantite_recue], [cout_unitaire_ht] = n.[cout_unitaire_ht], [montant_ligne_ht] = n.[montant_ligne_ht],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([ligne_cf_id], [commande_fournisseur_id], [produit_id], [quantite_commandee], [quantite_recue], [cout_unitaire_ht], [montant_ligne_ht], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[ligne_cf_id], n.[commande_fournisseur_id], n.[produit_id], n.[quantite_commandee], n.[quantite_recue], n.[cout_unitaire_ht], n.[montant_ligne_ht], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.lignes_commande_fournisseur',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_lignes_commande_fournisseur';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_mouvements_stock  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.mouvements_stock  →  clean.mouvements_stock   (Journal des mouvements de stock)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_mouvements_stock
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'mouvements_stock';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[mouvement_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[mouvements_stock] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[mouvement_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [mouvement_id], [date_mouvement], [produit_id], [entrepot_id], [type_mouvement], [quantite], [reference_id], [cout_unitaire_ht], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[mouvements_stock];
    INSERT INTO #nouveau ([mouvement_id], [date_mouvement], [produit_id], [entrepot_id], [type_mouvement], [quantite], [reference_id], [cout_unitaire_ht], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([mouvement_id]), '')) AS [mouvement_id],
            TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_mouvement]), ''), 120) AS [date_mouvement],
            UPPER(NULLIF(TRIM([produit_id]), '')) AS [produit_id],
            UPPER(NULLIF(TRIM([entrepot_id]), '')) AS [entrepot_id],
            LOWER(NULLIF(TRIM([type_mouvement]), '')) AS [type_mouvement],
            CASE WHEN LOWER(TRIM([type_mouvement])) IN ('vente','mise_au_rebut') THEN -ABS(TRY_CONVERT(INT,[quantite])) WHEN LOWER(TRIM([type_mouvement])) = 'ajustement_inventaire' THEN TRY_CONVERT(INT,[quantite]) ELSE ABS(TRY_CONVERT(INT,[quantite])) END AS [quantite],
            UPPER(NULLIF(TRIM([reference_id]), '')) AS [reference_id],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_unitaire_ht]), ''), ',', '.')) AS [cout_unitaire_ht],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'mouvements_stock', [mouvement_id], N'mouvement_id', NULL, 'QR03', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'mouvements_stock', [mouvement_id], N'date_mouvement', [date_mouvement], 'QR43', 'REJET', N'Valeur non convertible en DATETIME2(0)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_mouvement]), '') IS NOT NULL AND (TRY_CONVERT(DATETIME2(0), NULLIF(TRIM([date_mouvement]), ''), 120)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'mouvements_stock', [mouvement_id], N'cout_unitaire_ht', [cout_unitaire_ht], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([cout_unitaire_ht]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_unitaire_ht]), ''), ',', '.'))) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'mouvements_stock', n.[mouvement_id], N'quantite', LEFT(s.[quantite], 4000), 'QR36', 'CORRECTION', CONCAT(N'Signe imposé par le type de mouvement : ', CONVERT(NVARCHAR(400), n.[quantite]))
    FROM #src s JOIN #nouveau n ON n.[mouvement_id] = UPPER(TRIM(s.[mouvement_id]))
    WHERE s.rn = 1 AND (TRY_CONVERT(INT, s.[quantite]) <> n.[quantite]);

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [mouvement_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_mouvement], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [entrepot_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [type_mouvement]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [quantite]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [reference_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_unitaire_ht]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[mouvements_stock] AS c
    USING #nouveau AS n
       ON c.[mouvement_id] = n.[mouvement_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [date_mouvement] = n.[date_mouvement], [produit_id] = n.[produit_id], [entrepot_id] = n.[entrepot_id], [type_mouvement] = n.[type_mouvement], [quantite] = n.[quantite], [reference_id] = n.[reference_id], [cout_unitaire_ht] = n.[cout_unitaire_ht],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([mouvement_id], [date_mouvement], [produit_id], [entrepot_id], [type_mouvement], [quantite], [reference_id], [cout_unitaire_ht], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[mouvement_id], n.[date_mouvement], n.[produit_id], n.[entrepot_id], n.[type_mouvement], n.[quantite], n.[reference_id], n.[cout_unitaire_ht], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.mouvements_stock',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_mouvements_stock';
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   clean.usp_charger_stocks_mensuels  —  INCRÉMENTAL
   TuniShop_STG_RAW.raw.stocks_mensuels  →  clean.stocks_mensuels   (Inventaires de fin de mois)
   Nouvelles lignes insérées, lignes modifiées mises à jour (empreinte hash_ligne),
   lignes disparues selon @mode_suppression ; lignes inchangées non touchées.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE clean.usp_charger_stocks_mensuels
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM clean.rejets WHERE id_chargement = @id_chargement AND table_source = N'stocks_mensuels';
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.[inventaire_id])) ORDER BY r.num_ligne_fichier) AS rn
    INTO #src
    FROM [TuniShop_STG_RAW].raw.[stocks_mensuels] AS r
    WHERE r.id_chargement = @id_chargement AND NULLIF(TRIM(r.[inventaire_id]), '') IS NOT NULL;
    SET @nb_lus = @@ROWCOUNT;

    -- 1. Données nettoyées dans une table de travail (#nouveau), même structure que la cible
    SELECT TOP (0) [inventaire_id], [date_inventaire], [produit_id], [entrepot_id], [stock_fin_mois], [quantite_en_commande], [cout_unitaire_ht], [valeur_stock_ht], id_chargement, date_traitement, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM clean.[stocks_mensuels];
    INSERT INTO #nouveau ([inventaire_id], [date_inventaire], [produit_id], [entrepot_id], [stock_fin_mois], [quantite_en_commande], [cout_unitaire_ht], [valeur_stock_ht], id_chargement, date_traitement)
    SELECT  UPPER(NULLIF(TRIM([inventaire_id]), '')) AS [inventaire_id],
            TRY_CONVERT(DATE, NULLIF(TRIM([date_inventaire]), ''), 23) AS [date_inventaire],
            UPPER(NULLIF(TRIM([produit_id]), '')) AS [produit_id],
            UPPER(NULLIF(TRIM([entrepot_id]), '')) AS [entrepot_id],
            ABS(TRY_CONVERT(INT, [stock_fin_mois])) AS [stock_fin_mois],
            TRY_CONVERT(INT, NULLIF(TRIM([quantite_en_commande]), '')) AS [quantite_en_commande],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_unitaire_ht]), ''), ',', '.')) AS [cout_unitaire_ht],
            TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([valeur_stock_ht]), ''), ',', '.')) AS [valeur_stock_ht],
            @id_chargement, SYSDATETIME()
    FROM #src WHERE rn = 1;

    -- 2. Quarantaine : doublons de clé et valeurs invalidées
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'stocks_mensuels', [inventaire_id], N'inventaire_id', NULL, 'QR43', 'REJET', N'Doublon sur la clé : occurrence écartée'
    FROM #src WHERE rn > 1;
    SET @nb_doublons = @@ROWCOUNT;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'stocks_mensuels', [inventaire_id], N'date_inventaire', [date_inventaire], 'QR43', 'REJET', N'Valeur non convertible en DATE'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([date_inventaire]), '') IS NOT NULL AND (TRY_CONVERT(DATE, NULLIF(TRIM([date_inventaire]), ''), 23)) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'stocks_mensuels', [inventaire_id], N'quantite_en_commande', [quantite_en_commande], 'QR43', 'REJET', N'Valeur non convertible en INT'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([quantite_en_commande]), '') IS NOT NULL AND (TRY_CONVERT(INT, NULLIF(TRIM([quantite_en_commande]), ''))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'stocks_mensuels', [inventaire_id], N'cout_unitaire_ht', [cout_unitaire_ht], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([cout_unitaire_ht]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([cout_unitaire_ht]), ''), ',', '.'))) IS NULL;
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'stocks_mensuels', [inventaire_id], N'valeur_stock_ht', [valeur_stock_ht], 'QR43', 'REJET', N'Valeur non convertible en DECIMAL(14,3)'
    FROM #src WHERE rn = 1 AND NULLIF(TRIM([valeur_stock_ht]), '') IS NOT NULL AND (TRY_CONVERT(DECIMAL(14,3), REPLACE(NULLIF(TRIM([valeur_stock_ht]), ''), ',', '.'))) IS NULL;

    -- 3. Règles calculées sur l'ensemble des lignes reçues
    -- aucune

    -- 3b. Corrections tracées (niveau CORRECTION : valeur reçue → valeur retenue)
    INSERT INTO clean.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'stocks_mensuels', n.[inventaire_id], N'stock_fin_mois', LEFT(s.[stock_fin_mois], 4000), 'QR37', 'CORRECTION', CONCAT(N'Stock négatif → valeur absolue : ', CONVERT(NVARCHAR(400), n.[stock_fin_mois]))
    FROM #src s JOIN #nouveau n ON n.[inventaire_id] = UPPER(TRIM(s.[inventaire_id]))
    WHERE s.rn = 1 AND (TRY_CONVERT(INT, s.[stock_fin_mois]) <> n.[stock_fin_mois]);

    -- 4. Empreinte des colonnes métier
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [inventaire_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_inventaire], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [entrepot_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [stock_fin_mois]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [quantite_en_commande]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_unitaire_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [valeur_stock_ht]), N'∅')));

    -- 5. Fusion dans la table cible
    MERGE clean.[stocks_mensuels] AS c
    USING #nouveau AS n
       ON c.[inventaire_id] = n.[inventaire_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [date_inventaire] = n.[date_inventaire], [produit_id] = n.[produit_id], [entrepot_id] = n.[entrepot_id], [stock_fin_mois] = n.[stock_fin_mois], [quantite_en_commande] = n.[quantite_en_commande], [cout_unitaire_ht] = n.[cout_unitaire_ht], [valeur_stock_ht] = n.[valeur_stock_ht],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([inventaire_id], [date_inventaire], [produit_id], [entrepot_id], [stock_fin_mois], [quantite_en_commande], [cout_unitaire_ht], [valeur_stock_ht], hash_ligne, est_supprime, date_creation, id_chargement, [date_traitement])
        VALUES (n.[inventaire_id], n.[date_inventaire], n.[produit_id], n.[entrepot_id], n.[stock_fin_mois], n.[quantite_en_commande], n.[cout_unitaire_ht], n.[valeur_stock_ht], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_traitement] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;

    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_CLEAN', @objet = N'clean.stocks_mensuels',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = @nb_doublons;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'clean.usp_charger_stocks_mensuels';
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE clean.usp_charger_tout
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    EXEC clean.usp_charger_categories @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_fournisseurs @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_produits_prix_historique @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_produits @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_ref_gouvernorats @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_entrepots @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_transporteurs @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_dim_calendrier @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_clients @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_campagnes_marketing @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_coupons @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_marketing_depenses_quotidiennes @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_commandes @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_lignes_commande @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_paiements @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_livraisons @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_remboursements @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_avis_clients @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_commandes_fournisseurs @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_lignes_commande_fournisseur @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_mouvements_stock @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
    EXEC clean.usp_charger_stocks_mensuels @id_chargement = @id_chargement, @mode_suppression = @mode_suppression;
END;
GO

/* =====================================================================
   PARTIE 2 — CLEAN → INTEGRATED  (base TuniShop_STG_INTEGRATED)  —  chargement INCRÉMENTAL
   Lecture des vues clean.v_* (lignes actives) ; fusion (MERGE) table par table
   dans l'ordre des clés étrangères. En mode « supprimer », les lignes disparues
   sont d'abord marquées puis supprimées en fin de traitement, dans l'ordre inverse.
   ===================================================================== */
USE [TuniShop_STG_INTEGRATED];
GO

/* integ.usp_integrer_calendrier — Calendrier conformé (grain : 1 ligne par jour) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_calendrier
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [date], [annee], [trimestre], [mois], [nom_mois], [semaine_iso], [jour_semaine], [nom_jour], [est_weekend], [est_jour_ferie], [nom_jour_ferie], [est_ramadan], [periode_commerciale], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[calendrier];

    INSERT INTO #nouveau ([date], annee, trimestre, mois, nom_mois, semaine_iso, jour_semaine, nom_jour, est_weekend, est_jour_ferie,
                                  nom_jour_ferie, est_ramadan, periode_commerciale, id_chargement, date_integration)
    SELECT [date], annee, trimestre, mois, nom_mois, semaine_iso, jour_semaine, nom_jour, est_weekend, est_jour_ferie,
           nom_jour_ferie, est_ramadan, periode_commerciale, @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_dim_calendrier;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [date], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [annee]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [trimestre]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [mois]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_mois]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [semaine_iso]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [jour_semaine]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_jour]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_weekend]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_jour_ferie]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_jour_ferie]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_ramadan]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [periode_commerciale]), N'∅')));
    MERGE integ.[calendrier] AS c
    USING #nouveau AS n
       ON c.[date] = n.[date]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [annee] = n.[annee], [trimestre] = n.[trimestre], [mois] = n.[mois], [nom_mois] = n.[nom_mois], [semaine_iso] = n.[semaine_iso], [jour_semaine] = n.[jour_semaine], [nom_jour] = n.[nom_jour], [est_weekend] = n.[est_weekend], [est_jour_ferie] = n.[est_jour_ferie], [nom_jour_ferie] = n.[nom_jour_ferie], [est_ramadan] = n.[est_ramadan], [periode_commerciale] = n.[periode_commerciale],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([date], [annee], [trimestre], [mois], [nom_mois], [semaine_iso], [jour_semaine], [nom_jour], [est_weekend], [est_jour_ferie], [nom_jour_ferie], [est_ramadan], [periode_commerciale], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[date], n.[annee], n.[trimestre], n.[mois], n.[nom_mois], n.[semaine_iso], n.[jour_semaine], n.[nom_jour], n.[est_weekend], n.[est_jour_ferie], n.[nom_jour_ferie], n.[est_ramadan], n.[periode_commerciale], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)
    -- aucun
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.calendrier',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_geographie — Gouvernorats, régions, zones et entrepôt de rattachement (grain : 1 ligne par gouvernorat) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_geographie
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [gouvernorat_id], [gouvernorat], [region], [zone_livraison], [entrepot_rattachement_id], [nom_entrepot_rattachement], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[geographie];

    INSERT INTO #nouveau (gouvernorat_id, gouvernorat, region, zone_livraison, entrepot_rattachement_id, nom_entrepot_rattachement, id_chargement, date_integration)
    SELECT g.gouvernorat_id, g.gouvernorat, g.region, g.zone_livraison, g.entrepot_rattachement_id, e.nom_entrepot, @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_ref_gouvernorats g
    JOIN [TuniShop_STG_CLEAN].clean.v_entrepots e ON e.entrepot_id = g.entrepot_rattachement_id;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [gouvernorat_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [gouvernorat]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [region]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [zone_livraison]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [entrepot_rattachement_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_entrepot_rattachement]), N'∅')));
    MERGE integ.[geographie] AS c
    USING #nouveau AS n
       ON c.[gouvernorat_id] = n.[gouvernorat_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [gouvernorat] = n.[gouvernorat], [region] = n.[region], [zone_livraison] = n.[zone_livraison], [entrepot_rattachement_id] = n.[entrepot_rattachement_id], [nom_entrepot_rattachement] = n.[nom_entrepot_rattachement],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([gouvernorat_id], [gouvernorat], [region], [zone_livraison], [entrepot_rattachement_id], [nom_entrepot_rattachement], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[gouvernorat_id], n.[gouvernorat], n.[region], n.[zone_livraison], n.[entrepot_rattachement_id], n.[nom_entrepot_rattachement], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)
    -- aucun
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.geographie',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_entrepot — Entrepôts (grain : 1 ligne par entrepôt) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_entrepot
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [entrepot_id], [nom_entrepot], [ville], [gouvernorat_id], [region], [date_ouverture], [surface_m2], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[entrepot];

    INSERT INTO #nouveau (entrepot_id, nom_entrepot, ville, gouvernorat_id, region, date_ouverture, surface_m2, id_chargement, date_integration)
    SELECT e.entrepot_id, e.nom_entrepot, e.ville, e.gouvernorat_id, g.region, e.date_ouverture, e.surface_m2, @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_entrepots e
    JOIN [TuniShop_STG_CLEAN].clean.v_ref_gouvernorats g ON g.gouvernorat_id = e.gouvernorat_id;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [entrepot_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_entrepot]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [ville]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [gouvernorat_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [region]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_ouverture], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [surface_m2]), N'∅')));
    MERGE integ.[entrepot] AS c
    USING #nouveau AS n
       ON c.[entrepot_id] = n.[entrepot_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [nom_entrepot] = n.[nom_entrepot], [ville] = n.[ville], [gouvernorat_id] = n.[gouvernorat_id], [region] = n.[region], [date_ouverture] = n.[date_ouverture], [surface_m2] = n.[surface_m2],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([entrepot_id], [nom_entrepot], [ville], [gouvernorat_id], [region], [date_ouverture], [surface_m2], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[entrepot_id], n.[nom_entrepot], n.[ville], n.[gouvernorat_id], n.[region], n.[date_ouverture], n.[surface_m2], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)
    -- aucun
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.entrepot',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_transporteur — Transporteurs (grain : 1 ligne par transporteur) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_transporteur
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [transporteur_id], [nom_transporteur], [couverture], [cout_base_ht], [ecart_delai_moyen_j], [date_debut_contrat], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[transporteur];

    INSERT INTO #nouveau (transporteur_id, nom_transporteur, couverture, cout_base_ht, ecart_delai_moyen_j, date_debut_contrat, id_chargement, date_integration)
    SELECT transporteur_id, nom_transporteur, couverture, cout_base_ht, ecart_delai_moyen_j, date_debut_contrat, @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_transporteurs;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [transporteur_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_transporteur]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [couverture]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_base_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [ecart_delai_moyen_j]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_debut_contrat], 121), N'∅')));
    MERGE integ.[transporteur] AS c
    USING #nouveau AS n
       ON c.[transporteur_id] = n.[transporteur_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [nom_transporteur] = n.[nom_transporteur], [couverture] = n.[couverture], [cout_base_ht] = n.[cout_base_ht], [ecart_delai_moyen_j] = n.[ecart_delai_moyen_j], [date_debut_contrat] = n.[date_debut_contrat],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([transporteur_id], [nom_transporteur], [couverture], [cout_base_ht], [ecart_delai_moyen_j], [date_debut_contrat], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[transporteur_id], n.[nom_transporteur], n.[couverture], n.[cout_base_ht], n.[ecart_delai_moyen_j], n.[date_debut_contrat], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)
    -- aucun
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.transporteur',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_fournisseur — Fournisseurs (grain : 1 ligne par fournisseur) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_fournisseur
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [fournisseur_id], [nom_fournisseur], [pays], [est_local], [delai_appro_moyen_j], [conditions_paiement], [fiabilite_livraison], [email_contact], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[fournisseur];

    INSERT INTO #nouveau (fournisseur_id, nom_fournisseur, pays, est_local, delai_appro_moyen_j, conditions_paiement, fiabilite_livraison, email_contact, id_chargement, date_integration)
    SELECT fournisseur_id, nom_fournisseur, pays, CASE WHEN pays = N'Tunisie' THEN 1 ELSE 0 END, delai_appro_moyen_j, conditions_paiement,
           fiabilite_livraison, LOWER(email_contact), @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_fournisseurs;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [fournisseur_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_fournisseur]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [pays]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_local]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [delai_appro_moyen_j]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [conditions_paiement]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [fiabilite_livraison]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [email_contact]), N'∅')));
    MERGE integ.[fournisseur] AS c
    USING #nouveau AS n
       ON c.[fournisseur_id] = n.[fournisseur_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [nom_fournisseur] = n.[nom_fournisseur], [pays] = n.[pays], [est_local] = n.[est_local], [delai_appro_moyen_j] = n.[delai_appro_moyen_j], [conditions_paiement] = n.[conditions_paiement], [fiabilite_livraison] = n.[fiabilite_livraison], [email_contact] = n.[email_contact],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([fournisseur_id], [nom_fournisseur], [pays], [est_local], [delai_appro_moyen_j], [conditions_paiement], [fiabilite_livraison], [email_contact], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[fournisseur_id], n.[nom_fournisseur], n.[pays], n.[est_local], n.[delai_appro_moyen_j], n.[conditions_paiement], n.[fiabilite_livraison], n.[email_contact], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)
    -- aucun
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.fournisseur',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_coupon — Coupons (grain : 1 ligne par code) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_coupon
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [code_coupon], [type_remise], [valeur], [montant_min_ttc], [plafond_remise_ttc], [date_debut], [date_fin], [campagne_id], [reserve_premiere_commande], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[coupon];

    INSERT INTO #nouveau (code_coupon, type_remise, valeur, montant_min_ttc, plafond_remise_ttc, date_debut, date_fin, campagne_id, reserve_premiere_commande, id_chargement, date_integration)
    SELECT code_coupon, type_remise, valeur, montant_min_ttc, plafond_remise_ttc, date_debut, date_fin, NULL /* renseigné après integ.v_campagne */, reserve_premiere_commande, @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_coupons;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [code_coupon]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [type_remise]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [valeur]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_min_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [plafond_remise_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_debut], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_fin], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [campagne_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [reserve_premiere_commande]), N'∅')));
    MERGE integ.[coupon] AS c
    USING #nouveau AS n
       ON c.[code_coupon] = n.[code_coupon]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [type_remise] = n.[type_remise], [valeur] = n.[valeur], [montant_min_ttc] = n.[montant_min_ttc], [plafond_remise_ttc] = n.[plafond_remise_ttc], [date_debut] = n.[date_debut], [date_fin] = n.[date_fin], [campagne_id] = n.[campagne_id], [reserve_premiere_commande] = n.[reserve_premiere_commande],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([code_coupon], [type_remise], [valeur], [montant_min_ttc], [plafond_remise_ttc], [date_debut], [date_fin], [campagne_id], [reserve_premiere_commande], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[code_coupon], n.[type_remise], n.[valeur], n.[montant_min_ttc], n.[plafond_remise_ttc], n.[date_debut], n.[date_fin], n.[campagne_id], n.[reserve_premiere_commande], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)
    -- aucun
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.coupon',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_campagne — Campagnes marketing (grain : 1 ligne par campagne) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_campagne
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [campagne_id], [nom_campagne], [canal], [type_canal], [objectif], [theme], [categorie_ciblee_id], [code_coupon], [date_debut], [date_fin], [duree_jours], [budget_ht], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[campagne];

    INSERT INTO #nouveau (campagne_id, nom_campagne, canal, type_canal, objectif, theme, categorie_ciblee_id, code_coupon, date_debut, date_fin, duree_jours, budget_ht, id_chargement, date_integration)
    SELECT c.campagne_id, c.nom_campagne, c.canal,
           CASE WHEN c.canal IN ('emailing','sms') THEN 'owned' ELSE 'payant' END,
           c.objectif, c.theme, c.categorie_ciblee_id,
           CASE WHEN EXISTS (SELECT 1 FROM integ.v_coupon k WHERE k.code_coupon = c.code_coupon) THEN c.code_coupon END,
           c.date_debut, c.date_fin, DATEDIFF(DAY, c.date_debut, c.date_fin) + 1, c.budget_ht, @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_campagnes_marketing c;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [campagne_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_campagne]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [canal]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [type_canal]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [objectif]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [theme]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [categorie_ciblee_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [code_coupon]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_debut], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_fin], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [duree_jours]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [budget_ht]), N'∅')));
    MERGE integ.[campagne] AS c
    USING #nouveau AS n
       ON c.[campagne_id] = n.[campagne_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [nom_campagne] = n.[nom_campagne], [canal] = n.[canal], [type_canal] = n.[type_canal], [objectif] = n.[objectif], [theme] = n.[theme], [categorie_ciblee_id] = n.[categorie_ciblee_id], [code_coupon] = n.[code_coupon], [date_debut] = n.[date_debut], [date_fin] = n.[date_fin], [duree_jours] = n.[duree_jours], [budget_ht] = n.[budget_ht],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([campagne_id], [nom_campagne], [canal], [type_canal], [objectif], [theme], [categorie_ciblee_id], [code_coupon], [date_debut], [date_fin], [duree_jours], [budget_ht], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[campagne_id], n.[nom_campagne], n.[canal], n.[type_canal], n.[objectif], n.[theme], n.[categorie_ciblee_id], n.[code_coupon], n.[date_debut], n.[date_fin], n.[duree_jours], n.[budget_ht], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)

    -- Rattachement retour coupon → campagne (FK circulaire résolue en deux temps)
    UPDATE k SET campagne_id = s.campagne_id
    FROM integ.v_coupon k
    JOIN [TuniShop_STG_CLEAN].clean.v_coupons s ON s.code_coupon = k.code_coupon
    WHERE EXISTS (SELECT 1 FROM integ.v_campagne c WHERE c.campagne_id = s.campagne_id);
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.campagne',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_client_correspondance — Table de correspondance identifiant source → client maître (résolution d'identité) (grain : 1 ligne par client_id source) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_client_correspondance
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [client_id_source], [client_id_maitre], [methode_rapprochement], [est_doublon], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[client_correspondance];

    -- QR27 : paires de particuliers de même prénom + nom, même téléphone normalisé,
    --        et même date de naissance (ou absente d'un côté). Maître = identifiant hors plage CLI9xxxxx, sinon le plus petit.
    ;WITH c AS (
        SELECT client_id, prenom, nom, date_naissance, telephone,
               CASE WHEN client_id LIKE 'CLI9[0-9][0-9][0-9][0-9][0-9]' THEN 1 ELSE 0 END AS est_plage_suspecte
        FROM [TuniShop_STG_CLEAN].clean.v_clients
        WHERE type_client = 'particulier' AND telephone IS NOT NULL
    ), paires AS (
        SELECT a.client_id AS id_a, b.client_id AS id_b, a.est_plage_suspecte AS sus_a, b.est_plage_suspecte AS sus_b
        FROM c a
        JOIN c b ON b.prenom = a.prenom AND b.nom = a.nom AND b.telephone = a.telephone AND a.client_id < b.client_id
               AND (a.date_naissance = b.date_naissance OR a.date_naissance IS NULL OR b.date_naissance IS NULL)
    ), doublons AS (
        SELECT CASE WHEN sus_a <= sus_b THEN id_b ELSE id_a END AS doublon,
               CASE WHEN sus_a <= sus_b THEN id_a ELSE id_b END AS maitre
        FROM paires
    ), d1 AS (   -- un doublon n'est rattaché qu'à un seul maître (le plus petit)
        SELECT doublon, MIN(maitre) AS maitre FROM doublons GROUP BY doublon
    )
    INSERT INTO #nouveau (client_id_source, client_id_maitre, methode_rapprochement, est_doublon, id_chargement, date_integration)
    SELECT s.client_id,
           COALESCE(d1.maitre, s.client_id),
           CASE WHEN d1.maitre IS NULL THEN 'identite' ELSE 'prenom_nom_telephone' END,
           CASE WHEN d1.maitre IS NULL THEN 0 ELSE 1 END,
           @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_clients s
    LEFT JOIN d1 ON d1.doublon = s.client_id
    -- un maître ne peut pas être lui-même doublon d'un autre (chaîne) : contrôle Q-06
    ;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [client_id_source]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [client_id_maitre]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [methode_rapprochement]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_doublon]), N'∅')));
    MERGE integ.[client_correspondance] AS c
    USING #nouveau AS n
       ON c.[client_id_source] = n.[client_id_source]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [client_id_maitre] = n.[client_id_maitre], [methode_rapprochement] = n.[methode_rapprochement], [est_doublon] = n.[est_doublon],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([client_id_source], [client_id_maitre], [methode_rapprochement], [est_doublon], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[client_id_source], n.[client_id_maitre], n.[methode_rapprochement], n.[est_doublon], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)

    INSERT INTO integ.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'client', client_id_source, N'client_id', client_id_source, 'QR27', 'SIGNALEMENT', CONCAT(N'Doublon fusionné dans ', client_id_maitre)
    FROM integ.v_client_correspondance WHERE est_doublon = 1;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.client_correspondance',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_client — Clients maîtres dédoublonnés et enrichis (grain : 1 ligne par client maître) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_client
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [client_id], [type_client], [prenom], [nom], [nom_complet], [genre], [genre_impute], [date_naissance], [raison_sociale], [matricule_fiscal], [email], [telephone], [gouvernorat_id], [ville], [date_inscription], [canal_inscription], [campagne_acquisition_id], [opt_in_email], [opt_in_sms], [segment_fidelite], [tranche_age], [nb_identifiants_fusionnes], [date_premiere_commande], [date_derniere_commande], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[client];

    ;WITH m AS (   -- attributs du maître, complétés par ceux du doublon (survivance)
        SELECT cc.client_id_maitre AS client_id,
               MAX(CASE WHEN cc.est_doublon = 0 THEN s.email END)     AS email_m,  MAX(CASE WHEN cc.est_doublon = 1 THEN s.email END)     AS email_d,
               MAX(CASE WHEN cc.est_doublon = 0 THEN s.telephone END) AS tel_m,    MAX(CASE WHEN cc.est_doublon = 1 THEN s.telephone END) AS tel_d,
               COUNT(*) AS nb_ids
        FROM integ.v_client_correspondance cc
        JOIN [TuniShop_STG_CLEAN].clean.v_clients s ON s.client_id = cc.client_id_source
        GROUP BY cc.client_id_maitre
    ), cmd AS (
        SELECT cc.client_id_maitre AS client_id, MIN(o.date_commande) AS premiere, MAX(o.date_commande) AS derniere
        FROM [TuniShop_STG_CLEAN].clean.v_commandes o JOIN integ.v_client_correspondance cc ON cc.client_id_source = o.client_id
        GROUP BY cc.client_id_maitre
    )
    INSERT INTO #nouveau (client_id, type_client, prenom, nom, nom_complet, genre, genre_impute, date_naissance, raison_sociale, matricule_fiscal,
                              email, telephone, gouvernorat_id, ville, date_inscription, canal_inscription, campagne_acquisition_id, opt_in_email,
                              opt_in_sms, segment_fidelite, tranche_age, nb_identifiants_fusionnes, date_premiere_commande, date_derniere_commande,
                              id_chargement, date_integration)
    SELECT s.client_id, s.type_client, s.prenom, s.nom,
           COALESCE(s.raison_sociale, CONCAT(s.prenom, N' ', s.nom)),
           s.genre, s.genre_impute, s.date_naissance, s.raison_sociale, s.matricule_fiscal,
           COALESCE(m.email_m, m.email_d), COALESCE(m.tel_m, m.tel_d),
           s.gouvernorat_id, s.ville, s.date_inscription, s.canal_inscription,
           CASE WHEN EXISTS (SELECT 1 FROM integ.v_campagne k WHERE k.campagne_id = s.campagne_acquisition_id) THEN s.campagne_acquisition_id END,
           s.opt_in_email, s.opt_in_sms, s.segment_fidelite,
           CASE WHEN s.date_naissance IS NULL THEN NULL
                ELSE CASE WHEN a.age < 25 THEN '<25' WHEN a.age < 35 THEN '25-34' WHEN a.age < 45 THEN '35-44'
                          WHEN a.age < 55 THEN '45-54' WHEN a.age < 65 THEN '55-64' ELSE '65+' END END,
           m.nb_ids, cmd.premiere, cmd.derniere, @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_clients s
    JOIN m ON m.client_id = s.client_id
    LEFT JOIN cmd ON cmd.client_id = s.client_id
    CROSS APPLY (SELECT DATEDIFF(YEAR, s.date_naissance, '2025-12-31')
                        - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, s.date_naissance, '2025-12-31'), s.date_naissance) > '2025-12-31' THEN 1 ELSE 0 END AS age) a;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [client_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [type_client]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [prenom]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_complet]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [genre]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [genre_impute]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_naissance], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [raison_sociale]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [matricule_fiscal]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [email]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [telephone]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [gouvernorat_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [ville]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_inscription], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [canal_inscription]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [campagne_acquisition_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [opt_in_email]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [opt_in_sms]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [segment_fidelite]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [tranche_age]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nb_identifiants_fusionnes]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_premiere_commande], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_derniere_commande], 121), N'∅')));
    MERGE integ.[client] AS c
    USING #nouveau AS n
       ON c.[client_id] = n.[client_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [type_client] = n.[type_client], [prenom] = n.[prenom], [nom] = n.[nom], [nom_complet] = n.[nom_complet], [genre] = n.[genre], [genre_impute] = n.[genre_impute], [date_naissance] = n.[date_naissance], [raison_sociale] = n.[raison_sociale], [matricule_fiscal] = n.[matricule_fiscal], [email] = n.[email], [telephone] = n.[telephone], [gouvernorat_id] = n.[gouvernorat_id], [ville] = n.[ville], [date_inscription] = n.[date_inscription], [canal_inscription] = n.[canal_inscription], [campagne_acquisition_id] = n.[campagne_acquisition_id], [opt_in_email] = n.[opt_in_email], [opt_in_sms] = n.[opt_in_sms], [segment_fidelite] = n.[segment_fidelite], [tranche_age] = n.[tranche_age], [nb_identifiants_fusionnes] = n.[nb_identifiants_fusionnes], [date_premiere_commande] = n.[date_premiere_commande], [date_derniere_commande] = n.[date_derniere_commande],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([client_id], [type_client], [prenom], [nom], [nom_complet], [genre], [genre_impute], [date_naissance], [raison_sociale], [matricule_fiscal], [email], [telephone], [gouvernorat_id], [ville], [date_inscription], [canal_inscription], [campagne_acquisition_id], [opt_in_email], [opt_in_sms], [segment_fidelite], [tranche_age], [nb_identifiants_fusionnes], [date_premiere_commande], [date_derniere_commande], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[client_id], n.[type_client], n.[prenom], n.[nom], n.[nom_complet], n.[genre], n.[genre_impute], n.[date_naissance], n.[raison_sociale], n.[matricule_fiscal], n.[email], n.[telephone], n.[gouvernorat_id], n.[ville], n.[date_inscription], n.[canal_inscription], n.[campagne_acquisition_id], n.[opt_in_email], n.[opt_in_sms], n.[segment_fidelite], n.[tranche_age], n.[nb_identifiants_fusionnes], n.[date_premiere_commande], n.[date_derniere_commande], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)

    -- QR38 : date d'inscription future résiduelle
    INSERT INTO integ.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'client', client_id, N'date_inscription', CONVERT(NVARCHAR(30), date_inscription, 120), 'QR38', 'SIGNALEMENT', N'Date d''inscription postérieure au chargement'
    FROM integ.v_client WHERE date_inscription > SYSDATETIME();
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.client',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_produit — Produits conformés avec leur catégorie (grain : 1 ligne par produit) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_produit
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [produit_id], [sku], [nom_produit], [marque], [categorie_id], [categorie], [sous_categorie], [taux_retour_cible], [marge_brute_cible], [fournisseur_id], [taux_tva], [poids_kg], [date_lancement], [date_arret], [statut_produit], [prix_catalogue_ttc_actuel], [cout_achat_unitaire_ht_actuel], [gamme_prix], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[produit];

    INSERT INTO #nouveau (produit_id, sku, nom_produit, marque, categorie_id, categorie, sous_categorie, taux_retour_cible, marge_brute_cible, fournisseur_id,
                               taux_tva, poids_kg, date_lancement, date_arret, statut_produit, prix_catalogue_ttc_actuel, cout_achat_unitaire_ht_actuel, gamme_prix,
                               id_chargement, date_integration)
    SELECT p.produit_id, p.sku, p.nom_produit, p.marque, p.categorie_id, c.categorie, c.sous_categorie, c.taux_retour_cible, c.marge_brute_cible, p.fournisseur_id,
           p.taux_tva, p.poids_kg, p.date_lancement, p.date_arret, p.statut_produit, p.prix_catalogue_ttc_actuel, p.cout_achat_unitaire_ht_actuel,
           CASE WHEN p.prix_catalogue_ttc_actuel < 50 THEN 'entree' WHEN p.prix_catalogue_ttc_actuel < 200 THEN 'moyenne'
                WHEN p.prix_catalogue_ttc_actuel < 1000 THEN 'haute' ELSE 'premium' END,
           @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_produits p
    JOIN [TuniShop_STG_CLEAN].clean.v_categories c ON c.categorie_id = p.categorie_id;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [sku]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nom_produit]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [marque]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [categorie_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [categorie]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [sous_categorie]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [taux_retour_cible]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [marge_brute_cible]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [fournisseur_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [taux_tva]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [poids_kg]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_lancement], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_arret], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [statut_produit]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [prix_catalogue_ttc_actuel]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_achat_unitaire_ht_actuel]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [gamme_prix]), N'∅')));
    MERGE integ.[produit] AS c
    USING #nouveau AS n
       ON c.[produit_id] = n.[produit_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [sku] = n.[sku], [nom_produit] = n.[nom_produit], [marque] = n.[marque], [categorie_id] = n.[categorie_id], [categorie] = n.[categorie], [sous_categorie] = n.[sous_categorie], [taux_retour_cible] = n.[taux_retour_cible], [marge_brute_cible] = n.[marge_brute_cible], [fournisseur_id] = n.[fournisseur_id], [taux_tva] = n.[taux_tva], [poids_kg] = n.[poids_kg], [date_lancement] = n.[date_lancement], [date_arret] = n.[date_arret], [statut_produit] = n.[statut_produit], [prix_catalogue_ttc_actuel] = n.[prix_catalogue_ttc_actuel], [cout_achat_unitaire_ht_actuel] = n.[cout_achat_unitaire_ht_actuel], [gamme_prix] = n.[gamme_prix],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([produit_id], [sku], [nom_produit], [marque], [categorie_id], [categorie], [sous_categorie], [taux_retour_cible], [marge_brute_cible], [fournisseur_id], [taux_tva], [poids_kg], [date_lancement], [date_arret], [statut_produit], [prix_catalogue_ttc_actuel], [cout_achat_unitaire_ht_actuel], [gamme_prix], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[produit_id], n.[sku], n.[nom_produit], n.[marque], n.[categorie_id], n.[categorie], n.[sous_categorie], n.[taux_retour_cible], n.[marge_brute_cible], n.[fournisseur_id], n.[taux_tva], n.[poids_kg], n.[date_lancement], n.[date_arret], n.[statut_produit], n.[prix_catalogue_ttc_actuel], n.[cout_achat_unitaire_ht_actuel], n.[gamme_prix], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)

    INSERT INTO integ.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'produit', p.produit_id, N'categorie_id', p.categorie_id, 'QR16', 'REJET', N'Catégorie inconnue : produit exclu'
    FROM [TuniShop_STG_CLEAN].clean.v_produits p WHERE NOT EXISTS (SELECT 1 FROM [TuniShop_STG_CLEAN].clean.v_categories c WHERE c.categorie_id = p.categorie_id);
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.produit',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_produit_version_prix — Versions de prix datées (préparation SCD2) (grain : 1 ligne par produit et période de prix) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_produit_version_prix
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [prix_id], [produit_id], [date_debut], [date_fin], [prix_catalogue_ttc], [prix_catalogue_ht], [cout_achat_unitaire_ht], [taux_marge_theorique], [num_version], [est_prix_actuel], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[produit_version_prix];

    INSERT INTO #nouveau (prix_id, produit_id, date_debut, date_fin, prix_catalogue_ttc, prix_catalogue_ht, cout_achat_unitaire_ht,
                                            taux_marge_theorique, num_version, est_prix_actuel, id_chargement, date_integration)
    SELECT h.prix_id, h.produit_id, h.date_debut, h.date_fin, h.prix_catalogue_ttc,
           ROUND(h.prix_catalogue_ttc / (1 + p.taux_tva / 100.0), 3), h.cout_achat_unitaire_ht,
           ROUND((h.prix_catalogue_ttc / (1 + p.taux_tva / 100.0) - h.cout_achat_unitaire_ht) / NULLIF(h.prix_catalogue_ttc / (1 + p.taux_tva / 100.0), 0), 4),
           ROW_NUMBER() OVER (PARTITION BY h.produit_id ORDER BY h.date_debut),
           CASE WHEN h.date_fin = MAX(h.date_fin) OVER (PARTITION BY h.produit_id) THEN 1 ELSE 0 END,   -- QR40
           @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_produits_prix_historique h
    JOIN integ.v_produit p ON p.produit_id = h.produit_id;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [prix_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_debut], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_fin], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [prix_catalogue_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [prix_catalogue_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_achat_unitaire_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [taux_marge_theorique]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [num_version]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_prix_actuel]), N'∅')));
    MERGE integ.[produit_version_prix] AS c
    USING #nouveau AS n
       ON c.[prix_id] = n.[prix_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [produit_id] = n.[produit_id], [date_debut] = n.[date_debut], [date_fin] = n.[date_fin], [prix_catalogue_ttc] = n.[prix_catalogue_ttc], [prix_catalogue_ht] = n.[prix_catalogue_ht], [cout_achat_unitaire_ht] = n.[cout_achat_unitaire_ht], [taux_marge_theorique] = n.[taux_marge_theorique], [num_version] = n.[num_version], [est_prix_actuel] = n.[est_prix_actuel],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([prix_id], [produit_id], [date_debut], [date_fin], [prix_catalogue_ttc], [prix_catalogue_ht], [cout_achat_unitaire_ht], [taux_marge_theorique], [num_version], [est_prix_actuel], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[prix_id], n.[produit_id], n.[date_debut], n.[date_fin], n.[prix_catalogue_ttc], n.[prix_catalogue_ht], n.[cout_achat_unitaire_ht], n.[taux_marge_theorique], n.[num_version], n.[est_prix_actuel], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)
    -- aucun
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.produit_version_prix',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_depense_marketing — Dépenses et performances quotidiennes rattachées (grain : 1 ligne par campagne et jour) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_depense_marketing
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [depense_id], [campagne_id], [campagne_id_source], [date], [canal], [depense_ht], [impressions], [clics], [commandes_attribuees], [nouveaux_clients_attribues], [ca_attribue_ttc], [est_rattachement_corrige], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[depense_marketing];

    ;WITH res AS (   -- QR25 : résolution des campagnes orphelines par canal + date
        SELECT d.depense_id,
               CASE WHEN EXISTS (SELECT 1 FROM integ.v_campagne c WHERE c.campagne_id = d.campagne_id) THEN d.campagne_id
                    ELSE (SELECT CASE WHEN COUNT(*) = 1 THEN MIN(c.campagne_id) END
                          FROM integ.v_campagne c
                          WHERE c.canal = d.canal AND d.[date] BETWEEN c.date_debut AND c.date_fin) END AS campagne_resolue
        FROM [TuniShop_STG_CLEAN].clean.v_marketing_depenses_quotidiennes d
    )
    INSERT INTO #nouveau (depense_id, campagne_id, campagne_id_source, [date], canal, depense_ht, impressions, clics, commandes_attribuees,
                                         nouveaux_clients_attribues, ca_attribue_ttc, est_rattachement_corrige, id_chargement, date_integration)
    SELECT d.depense_id, r.campagne_resolue, d.campagne_id, d.[date], d.canal, d.depense_ht, d.impressions, d.clics, d.commandes_attribuees,
           d.nouveaux_clients_attribues, d.ca_attribue_ttc,
           CASE WHEN r.campagne_resolue IS NOT NULL AND r.campagne_resolue <> d.campagne_id THEN 1 ELSE 0 END,
           @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_marketing_depenses_quotidiennes d
    JOIN res r ON r.depense_id = d.depense_id;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [depense_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [campagne_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [campagne_id_source]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [canal]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [depense_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [impressions]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [clics]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commandes_attribuees]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nouveaux_clients_attribues]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [ca_attribue_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_rattachement_corrige]), N'∅')));
    MERGE integ.[depense_marketing] AS c
    USING #nouveau AS n
       ON c.[depense_id] = n.[depense_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [campagne_id] = n.[campagne_id], [campagne_id_source] = n.[campagne_id_source], [date] = n.[date], [canal] = n.[canal], [depense_ht] = n.[depense_ht], [impressions] = n.[impressions], [clics] = n.[clics], [commandes_attribuees] = n.[commandes_attribuees], [nouveaux_clients_attribues] = n.[nouveaux_clients_attribues], [ca_attribue_ttc] = n.[ca_attribue_ttc], [est_rattachement_corrige] = n.[est_rattachement_corrige],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([depense_id], [campagne_id], [campagne_id_source], [date], [canal], [depense_ht], [impressions], [clics], [commandes_attribuees], [nouveaux_clients_attribues], [ca_attribue_ttc], [est_rattachement_corrige], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[depense_id], n.[campagne_id], n.[campagne_id_source], n.[date], n.[canal], n.[depense_ht], n.[impressions], n.[clics], n.[commandes_attribuees], n.[nouveaux_clients_attribues], n.[ca_attribue_ttc], n.[est_rattachement_corrige], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)

    INSERT INTO integ.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'depense_marketing', depense_id, N'campagne_id', campagne_id_source, 'QR25', 'SIGNALEMENT',
           CASE WHEN campagne_id IS NULL THEN N'Campagne inconnue, rattachement ambigu : membre inconnu' ELSE CONCAT(N'Campagne corrigée en ', campagne_id) END
    FROM integ.v_depense_marketing WHERE campagne_id IS NULL OR est_rattachement_corrige = 1;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.depense_marketing',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_commande — Commandes conformées (client maître, intégrité, indicateurs) (grain : 1 ligne par commande) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_commande
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [commande_id], [client_id], [client_id_source], [date_commande], [canal], [appareil], [gouvernorat_livraison_id], [ville_livraison], [entrepot_id], [campagne_id], [code_coupon], [mode_paiement], [nb_lignes], [nb_articles], [sous_total_ttc], [sous_total_ht], [remise_coupon_ttc], [frais_livraison_ttc], [montant_total_ttc], [cout_achat_total_ht], [statut_commande], [motif_annulation], [date_annulation], [est_premiere_commande], [est_ca_reconnu], [est_client_orphelin], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[commande];

    ;WITH l AS (
        SELECT commande_id, COUNT(*) AS nb_lignes, SUM(quantite) AS nb_articles, SUM(montant_ligne_ttc) AS st_ttc,
               SUM(montant_ligne_ht) AS st_ht, SUM(quantite * cout_achat_unitaire_ht) AS cout
        FROM [TuniShop_STG_CLEAN].clean.v_lignes_commande GROUP BY commande_id
    )
    INSERT INTO #nouveau (commande_id, client_id, client_id_source, date_commande, canal, appareil, gouvernorat_livraison_id, ville_livraison, entrepot_id,
                                campagne_id, code_coupon, mode_paiement, nb_lignes, nb_articles, sous_total_ttc, sous_total_ht, remise_coupon_ttc,
                                frais_livraison_ttc, montant_total_ttc, cout_achat_total_ht, statut_commande, motif_annulation, date_annulation,
                                est_premiere_commande, est_ca_reconnu, est_client_orphelin, id_chargement, date_integration)
    SELECT o.commande_id, cc.client_id_maitre, o.client_id, o.date_commande, o.canal, o.appareil, o.gouvernorat_livraison_id, o.ville_livraison,
           o.entrepot_id,
           CASE WHEN EXISTS (SELECT 1 FROM integ.v_campagne k WHERE k.campagne_id = o.campagne_id) THEN o.campagne_id END,
           CASE WHEN EXISTS (SELECT 1 FROM integ.v_coupon k WHERE k.code_coupon = o.code_coupon) THEN o.code_coupon END,
           o.mode_paiement,
           COALESCE(l.nb_lignes, o.nb_lignes), COALESCE(l.nb_articles, o.nb_articles),                        -- QR41
           COALESCE(l.st_ttc, o.sous_total_ttc), COALESCE(l.st_ht, 0),
           o.remise_coupon_ttc, o.frais_livraison_ttc,
           COALESCE(l.st_ttc, o.sous_total_ttc) - o.remise_coupon_ttc + o.frais_livraison_ttc,
           COALESCE(l.cout, 0),
           o.statut_commande, o.motif_annulation, o.date_annulation, o.est_premiere_commande,
           CASE WHEN o.statut_commande IN ('livree','partiellement_retournee','retournee','expediee') THEN 1 ELSE 0 END,
           CASE WHEN cc.client_id_maitre IS NULL THEN 1 ELSE 0 END,                                         -- QR23
           @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_commandes o
    LEFT JOIN integ.v_client_correspondance cc ON cc.client_id_source = o.client_id
    LEFT JOIN l ON l.commande_id = o.commande_id;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [client_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [client_id_source]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_commande], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [canal]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [appareil]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [gouvernorat_livraison_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [ville_livraison]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [entrepot_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [campagne_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [code_coupon]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [mode_paiement]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nb_lignes]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nb_articles]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [sous_total_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [sous_total_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [remise_coupon_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [frais_livraison_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_total_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_achat_total_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [statut_commande]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [motif_annulation]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_annulation], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_premiere_commande]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_ca_reconnu]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_client_orphelin]), N'∅')));
    MERGE integ.[commande] AS c
    USING #nouveau AS n
       ON c.[commande_id] = n.[commande_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [client_id] = n.[client_id], [client_id_source] = n.[client_id_source], [date_commande] = n.[date_commande], [canal] = n.[canal], [appareil] = n.[appareil], [gouvernorat_livraison_id] = n.[gouvernorat_livraison_id], [ville_livraison] = n.[ville_livraison], [entrepot_id] = n.[entrepot_id], [campagne_id] = n.[campagne_id], [code_coupon] = n.[code_coupon], [mode_paiement] = n.[mode_paiement], [nb_lignes] = n.[nb_lignes], [nb_articles] = n.[nb_articles], [sous_total_ttc] = n.[sous_total_ttc], [sous_total_ht] = n.[sous_total_ht], [remise_coupon_ttc] = n.[remise_coupon_ttc], [frais_livraison_ttc] = n.[frais_livraison_ttc], [montant_total_ttc] = n.[montant_total_ttc], [cout_achat_total_ht] = n.[cout_achat_total_ht], [statut_commande] = n.[statut_commande], [motif_annulation] = n.[motif_annulation], [date_annulation] = n.[date_annulation], [est_premiere_commande] = n.[est_premiere_commande], [est_ca_reconnu] = n.[est_ca_reconnu], [est_client_orphelin] = n.[est_client_orphelin],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([commande_id], [client_id], [client_id_source], [date_commande], [canal], [appareil], [gouvernorat_livraison_id], [ville_livraison], [entrepot_id], [campagne_id], [code_coupon], [mode_paiement], [nb_lignes], [nb_articles], [sous_total_ttc], [sous_total_ht], [remise_coupon_ttc], [frais_livraison_ttc], [montant_total_ttc], [cout_achat_total_ht], [statut_commande], [motif_annulation], [date_annulation], [est_premiere_commande], [est_ca_reconnu], [est_client_orphelin], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[commande_id], n.[client_id], n.[client_id_source], n.[date_commande], n.[canal], n.[appareil], n.[gouvernorat_livraison_id], n.[ville_livraison], n.[entrepot_id], n.[campagne_id], n.[code_coupon], n.[mode_paiement], n.[nb_lignes], n.[nb_articles], n.[sous_total_ttc], n.[sous_total_ht], n.[remise_coupon_ttc], n.[frais_livraison_ttc], n.[montant_total_ttc], n.[cout_achat_total_ht], n.[statut_commande], n.[motif_annulation], n.[date_annulation], n.[est_premiere_commande], n.[est_ca_reconnu], n.[est_client_orphelin], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)

    INSERT INTO integ.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commande', commande_id, N'client_id', client_id_source, 'QR23', 'SIGNALEMENT', N'Client inconnu : membre inconnu en DWH'
    FROM integ.v_commande WHERE est_client_orphelin = 1
    UNION ALL
    SELECT @id_chargement, N'commande', o.commande_id, N'sous_total_ttc', CONVERT(NVARCHAR(30), o.sous_total_ttc), 'QR41', 'SIGNALEMENT', N'En-tête recalculé depuis les lignes'
    FROM [TuniShop_STG_CLEAN].clean.v_commandes o JOIN integ.v_commande i ON i.commande_id = o.commande_id
    WHERE ABS(o.sous_total_ttc - i.sous_total_ttc) > 0.01 OR o.nb_lignes <> i.nb_lignes OR o.nb_articles <> i.nb_articles;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.commande',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_ligne_commande — Lignes de commande conformées avec marge (grain : 1 ligne par ligne de commande) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_ligne_commande
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [ligne_id], [commande_id], [num_ligne], [produit_id], [produit_id_source], [quantite], [prix_catalogue_ttc], [remise_promo_unitaire_ttc], [prix_unitaire_ttc], [taux_tva], [montant_ligne_ttc], [montant_ligne_ht], [montant_tva], [montant_remise_promo_ttc], [cout_achat_unitaire_ht], [cout_achat_total_ht], [marge_brute_ht], [est_produit_orphelin], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[ligne_commande];

    INSERT INTO #nouveau (ligne_id, commande_id, num_ligne, produit_id, produit_id_source, quantite, prix_catalogue_ttc, remise_promo_unitaire_ttc,
                                      prix_unitaire_ttc, taux_tva, montant_ligne_ttc, montant_ligne_ht, montant_tva, montant_remise_promo_ttc,
                                      cout_achat_unitaire_ht, cout_achat_total_ht, marge_brute_ht, est_produit_orphelin, id_chargement, date_integration)
    SELECT l.ligne_id, l.commande_id, l.num_ligne, p.produit_id, l.produit_id, l.quantite, l.prix_catalogue_ttc, l.remise_promo_unitaire_ttc,
           l.prix_unitaire_ttc, l.taux_tva, l.montant_ligne_ttc, l.montant_ligne_ht, l.montant_tva, l.quantite * l.remise_promo_unitaire_ttc,
           l.cout_achat_unitaire_ht, l.quantite * l.cout_achat_unitaire_ht, l.montant_ligne_ht - l.quantite * l.cout_achat_unitaire_ht,
           CASE WHEN p.produit_id IS NULL THEN 1 ELSE 0 END,                                                 -- QR24
           @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_lignes_commande l
    JOIN integ.v_commande c ON c.commande_id = l.commande_id
    LEFT JOIN integ.v_produit p ON p.produit_id = l.produit_id;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [ligne_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [num_ligne]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id_source]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [quantite]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [prix_catalogue_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [remise_promo_unitaire_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [prix_unitaire_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [taux_tva]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_ligne_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_ligne_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_tva]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_remise_promo_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_achat_unitaire_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_achat_total_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [marge_brute_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_produit_orphelin]), N'∅')));
    MERGE integ.[ligne_commande] AS c
    USING #nouveau AS n
       ON c.[ligne_id] = n.[ligne_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [commande_id] = n.[commande_id], [num_ligne] = n.[num_ligne], [produit_id] = n.[produit_id], [produit_id_source] = n.[produit_id_source], [quantite] = n.[quantite], [prix_catalogue_ttc] = n.[prix_catalogue_ttc], [remise_promo_unitaire_ttc] = n.[remise_promo_unitaire_ttc], [prix_unitaire_ttc] = n.[prix_unitaire_ttc], [taux_tva] = n.[taux_tva], [montant_ligne_ttc] = n.[montant_ligne_ttc], [montant_ligne_ht] = n.[montant_ligne_ht], [montant_tva] = n.[montant_tva], [montant_remise_promo_ttc] = n.[montant_remise_promo_ttc], [cout_achat_unitaire_ht] = n.[cout_achat_unitaire_ht], [cout_achat_total_ht] = n.[cout_achat_total_ht], [marge_brute_ht] = n.[marge_brute_ht], [est_produit_orphelin] = n.[est_produit_orphelin],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([ligne_id], [commande_id], [num_ligne], [produit_id], [produit_id_source], [quantite], [prix_catalogue_ttc], [remise_promo_unitaire_ttc], [prix_unitaire_ttc], [taux_tva], [montant_ligne_ttc], [montant_ligne_ht], [montant_tva], [montant_remise_promo_ttc], [cout_achat_unitaire_ht], [cout_achat_total_ht], [marge_brute_ht], [est_produit_orphelin], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[ligne_id], n.[commande_id], n.[num_ligne], n.[produit_id], n.[produit_id_source], n.[quantite], n.[prix_catalogue_ttc], n.[remise_promo_unitaire_ttc], n.[prix_unitaire_ttc], n.[taux_tva], n.[montant_ligne_ttc], n.[montant_ligne_ht], n.[montant_tva], n.[montant_remise_promo_ttc], n.[cout_achat_unitaire_ht], n.[cout_achat_total_ht], n.[marge_brute_ht], n.[est_produit_orphelin], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)

    INSERT INTO integ.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'ligne_commande', ligne_id, N'produit_id', produit_id_source, 'QR24', 'SIGNALEMENT', N'Produit inconnu : membre inconnu en DWH'
    FROM integ.v_ligne_commande WHERE est_produit_orphelin = 1;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.ligne_commande',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_paiement — Tentatives de paiement rattachées (grain : 1 ligne par tentative) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_paiement
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [paiement_id], [commande_id], [num_tentative], [mode_paiement], [montant_ttc], [statut_paiement], [code_erreur], [date_paiement], [prestataire], [reference_transaction], [date_reversement], [delai_reversement_j], [est_reussi], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[paiement];

    -- QR26 : rattachement des paiements orphelins ; QR47 : montants multipliés par 1 000
    ;WITH orph AS (
        SELECT p.* FROM [TuniShop_STG_CLEAN].clean.v_paiements p
        WHERE NOT EXISTS (SELECT 1 FROM integ.v_commande c WHERE c.commande_id = p.commande_id)
    ), cand AS (
        SELECT o.paiement_id, c.commande_id, COUNT(*) OVER (PARTITION BY o.paiement_id) AS nb
        FROM orph o
        JOIN integ.v_commande c
          ON (ABS(c.montant_total_ttc - o.montant_ttc) < 0.01 OR ABS(c.montant_total_ttc - o.montant_ttc / 1000) < 0.01)
         AND c.mode_paiement = o.mode_paiement
         AND c.date_commande <= o.date_paiement AND c.date_commande >= DATEADD(DAY, -15, o.date_paiement)
         AND NOT EXISTS (SELECT 1 FROM [TuniShop_STG_CLEAN].clean.v_paiements p2 WHERE p2.commande_id = c.commande_id)
    ), res AS (
        SELECT p.paiement_id, COALESCE(k.commande_id, ca.commande_id) AS commande_id,
               CASE WHEN k.commande_id IS NULL AND ca.commande_id IS NOT NULL THEN 1 ELSE 0 END AS rattache
        FROM [TuniShop_STG_CLEAN].clean.v_paiements p
        LEFT JOIN integ.v_commande k ON k.commande_id = p.commande_id
        LEFT JOIN cand ca ON ca.paiement_id = p.paiement_id AND ca.nb = 1
    )
    INSERT INTO #nouveau (paiement_id, commande_id, num_tentative, mode_paiement, montant_ttc, statut_paiement, code_erreur, date_paiement, prestataire,
                                reference_transaction, date_reversement, delai_reversement_j, est_reussi, id_chargement, date_integration)
    SELECT p.paiement_id, r.commande_id, p.num_tentative, p.mode_paiement,
           CASE WHEN ABS(p.montant_ttc / 1000 - c.montant_total_ttc) < 0.01 THEN p.montant_ttc / 1000 ELSE p.montant_ttc END,
           p.statut_paiement, p.code_erreur, p.date_paiement, p.prestataire,
           p.reference_transaction, p.date_reversement, DATEDIFF(DAY, p.date_paiement, p.date_reversement),
           CASE WHEN p.statut_paiement IN ('reussi','encaisse') THEN 1 ELSE 0 END, @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_paiements p
    JOIN res r ON r.paiement_id = p.paiement_id
    JOIN integ.v_commande c ON c.commande_id = r.commande_id;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [paiement_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [num_tentative]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [mode_paiement]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [statut_paiement]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [code_erreur]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_paiement], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [prestataire]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [reference_transaction]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_reversement], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [delai_reversement_j]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_reussi]), N'∅')));
    MERGE integ.[paiement] AS c
    USING #nouveau AS n
       ON c.[paiement_id] = n.[paiement_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [commande_id] = n.[commande_id], [num_tentative] = n.[num_tentative], [mode_paiement] = n.[mode_paiement], [montant_ttc] = n.[montant_ttc], [statut_paiement] = n.[statut_paiement], [code_erreur] = n.[code_erreur], [date_paiement] = n.[date_paiement], [prestataire] = n.[prestataire], [reference_transaction] = n.[reference_transaction], [date_reversement] = n.[date_reversement], [delai_reversement_j] = n.[delai_reversement_j], [est_reussi] = n.[est_reussi],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([paiement_id], [commande_id], [num_tentative], [mode_paiement], [montant_ttc], [statut_paiement], [code_erreur], [date_paiement], [prestataire], [reference_transaction], [date_reversement], [delai_reversement_j], [est_reussi], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[paiement_id], n.[commande_id], n.[num_tentative], n.[mode_paiement], n.[montant_ttc], n.[statut_paiement], n.[code_erreur], n.[date_paiement], n.[prestataire], n.[reference_transaction], n.[date_reversement], n.[delai_reversement_j], n.[est_reussi], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)


    INSERT INTO integ.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'paiement', p.paiement_id, N'commande_id', p.commande_id, 'QR26',
           CASE WHEN i.paiement_id IS NULL THEN 'REJET' ELSE 'SIGNALEMENT' END,
           CASE WHEN i.paiement_id IS NULL THEN N'Paiement sans commande, rapprochement impossible : exclu'
                ELSE CONCAT(N'Paiement rattaché par rapprochement à ', i.commande_id) END
    FROM [TuniShop_STG_CLEAN].clean.v_paiements p
    LEFT JOIN integ.v_paiement i ON i.paiement_id = p.paiement_id
    WHERE NOT EXISTS (SELECT 1 FROM integ.v_commande c WHERE c.commande_id = p.commande_id)
    UNION ALL
    SELECT @id_chargement, N'paiement', i.paiement_id, N'montant_ttc', CONVERT(NVARCHAR(30), p.montant_ttc), 'QR47', 'SIGNALEMENT',
           CASE WHEN i.montant_ttc <> p.montant_ttc THEN N'Montant divisé par 1 000' ELSE N'Montant différent du total de la commande' END
    FROM integ.v_paiement i
    JOIN [TuniShop_STG_CLEAN].clean.v_paiements p ON p.paiement_id = i.paiement_id
    JOIN integ.v_commande c ON c.commande_id = i.commande_id
    WHERE i.montant_ttc <> p.montant_ttc OR ABS(i.montant_ttc - c.montant_total_ttc) > 0.01;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.paiement',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_livraison — Expéditions avec délais calculés (grain : 1 ligne par expédition) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_livraison
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [livraison_id], [commande_id], [entrepot_id], [transporteur_id], [gouvernorat_destination_id], [date_expedition], [date_livraison_prevue], [date_livraison_reelle], [date_dernier_evenement], [statut_livraison], [nb_tentatives], [poids_kg], [cout_transport_ht], [delai_preparation_h], [delai_livraison_j], [retard_j], [est_livree_a_temps], [est_premiere_tentative], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[livraison];

    INSERT INTO #nouveau (livraison_id, commande_id, entrepot_id, transporteur_id, gouvernorat_destination_id, date_expedition, date_livraison_prevue,
                                 date_livraison_reelle, date_dernier_evenement, statut_livraison, nb_tentatives, poids_kg, cout_transport_ht,
                                 delai_preparation_h, delai_livraison_j, retard_j, est_livree_a_temps, est_premiere_tentative, id_chargement, date_integration)
    SELECT v.livraison_id, v.commande_id, v.entrepot_id, v.transporteur_id, v.gouvernorat_destination_id, v.date_expedition, v.date_livraison_prevue,
           v.date_livraison_reelle, v.date_dernier_evenement, v.statut_livraison, v.nb_tentatives, v.poids_kg, v.cout_transport_ht,
           DATEDIFF(MINUTE, c.date_commande, v.date_expedition) / 60.0,
           DATEDIFF(MINUTE, c.date_commande, v.date_livraison_reelle) / 1440.0,
           CASE WHEN v.date_livraison_reelle IS NULL THEN NULL
                WHEN DATEDIFF(DAY, v.date_livraison_prevue, v.date_livraison_reelle) > 0 THEN DATEDIFF(DAY, v.date_livraison_prevue, v.date_livraison_reelle) ELSE 0 END,
           CASE WHEN v.date_livraison_reelle IS NULL THEN NULL WHEN CAST(v.date_livraison_reelle AS DATE) <= v.date_livraison_prevue THEN 1 ELSE 0 END,
           CASE WHEN v.statut_livraison <> 'livree' THEN NULL WHEN v.nb_tentatives = 1 THEN 1 ELSE 0 END,
           @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_livraisons v
    JOIN integ.v_commande c ON c.commande_id = v.commande_id;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [livraison_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [entrepot_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [transporteur_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [gouvernorat_destination_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_expedition], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_livraison_prevue], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_livraison_reelle], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_dernier_evenement], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [statut_livraison]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [nb_tentatives]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [poids_kg]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_transport_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [delai_preparation_h]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [delai_livraison_j]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [retard_j]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_livree_a_temps]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_premiere_tentative]), N'∅')));
    MERGE integ.[livraison] AS c
    USING #nouveau AS n
       ON c.[livraison_id] = n.[livraison_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [commande_id] = n.[commande_id], [entrepot_id] = n.[entrepot_id], [transporteur_id] = n.[transporteur_id], [gouvernorat_destination_id] = n.[gouvernorat_destination_id], [date_expedition] = n.[date_expedition], [date_livraison_prevue] = n.[date_livraison_prevue], [date_livraison_reelle] = n.[date_livraison_reelle], [date_dernier_evenement] = n.[date_dernier_evenement], [statut_livraison] = n.[statut_livraison], [nb_tentatives] = n.[nb_tentatives], [poids_kg] = n.[poids_kg], [cout_transport_ht] = n.[cout_transport_ht], [delai_preparation_h] = n.[delai_preparation_h], [delai_livraison_j] = n.[delai_livraison_j], [retard_j] = n.[retard_j], [est_livree_a_temps] = n.[est_livree_a_temps], [est_premiere_tentative] = n.[est_premiere_tentative],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([livraison_id], [commande_id], [entrepot_id], [transporteur_id], [gouvernorat_destination_id], [date_expedition], [date_livraison_prevue], [date_livraison_reelle], [date_dernier_evenement], [statut_livraison], [nb_tentatives], [poids_kg], [cout_transport_ht], [delai_preparation_h], [delai_livraison_j], [retard_j], [est_livree_a_temps], [est_premiere_tentative], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[livraison_id], n.[commande_id], n.[entrepot_id], n.[transporteur_id], n.[gouvernorat_destination_id], n.[date_expedition], n.[date_livraison_prevue], n.[date_livraison_reelle], n.[date_dernier_evenement], n.[statut_livraison], n.[nb_tentatives], n.[poids_kg], n.[cout_transport_ht], n.[delai_preparation_h], n.[delai_livraison_j], n.[retard_j], n.[est_livree_a_temps], n.[est_premiere_tentative], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)
    -- aucun
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.livraison',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_remboursement — Remboursements conformés (grain : 1 ligne par remboursement) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_remboursement
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [remboursement_id], [commande_id], [ligne_id], [produit_id], [type_remboursement], [motif], [quantite], [montant_demande_ttc], [montant_rembourse_ttc], [date_demande], [date_reception_retour], [date_remboursement], [delai_traitement_j], [mode_remboursement], [statut], [etat_article], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[remboursement];

    INSERT INTO #nouveau (remboursement_id, commande_id, ligne_id, produit_id, type_remboursement, motif, quantite, montant_demande_ttc,
                                     montant_rembourse_ttc, date_demande, date_reception_retour, date_remboursement, delai_traitement_j,
                                     mode_remboursement, statut, etat_article, id_chargement, date_integration)
    SELECT r.remboursement_id, r.commande_id, l.ligne_id, l.produit_id, r.type_remboursement, r.motif, r.quantite, r.montant_demande_ttc,
           r.montant_rembourse_ttc, r.date_demande, r.date_reception_retour, r.date_remboursement,
           DATEDIFF(MINUTE, r.date_demande, r.date_remboursement) / 1440.0,
           r.mode_remboursement, r.statut, r.etat_article, @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_remboursements r
    JOIN integ.v_commande c ON c.commande_id = r.commande_id
    LEFT JOIN integ.v_ligne_commande l ON l.ligne_id = r.ligne_id;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [remboursement_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [ligne_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [type_remboursement]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [motif]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [quantite]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_demande_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_rembourse_ttc]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_demande], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_reception_retour], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_remboursement], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [delai_traitement_j]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [mode_remboursement]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [statut]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [etat_article]), N'∅')));
    MERGE integ.[remboursement] AS c
    USING #nouveau AS n
       ON c.[remboursement_id] = n.[remboursement_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [commande_id] = n.[commande_id], [ligne_id] = n.[ligne_id], [produit_id] = n.[produit_id], [type_remboursement] = n.[type_remboursement], [motif] = n.[motif], [quantite] = n.[quantite], [montant_demande_ttc] = n.[montant_demande_ttc], [montant_rembourse_ttc] = n.[montant_rembourse_ttc], [date_demande] = n.[date_demande], [date_reception_retour] = n.[date_reception_retour], [date_remboursement] = n.[date_remboursement], [delai_traitement_j] = n.[delai_traitement_j], [mode_remboursement] = n.[mode_remboursement], [statut] = n.[statut], [etat_article] = n.[etat_article],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([remboursement_id], [commande_id], [ligne_id], [produit_id], [type_remboursement], [motif], [quantite], [montant_demande_ttc], [montant_rembourse_ttc], [date_demande], [date_reception_retour], [date_remboursement], [delai_traitement_j], [mode_remboursement], [statut], [etat_article], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[remboursement_id], n.[commande_id], n.[ligne_id], n.[produit_id], n.[type_remboursement], n.[motif], n.[quantite], n.[montant_demande_ttc], n.[montant_rembourse_ttc], n.[date_demande], n.[date_reception_retour], n.[date_remboursement], n.[delai_traitement_j], n.[mode_remboursement], n.[statut], n.[etat_article], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)
    -- aucun
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.remboursement',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_avis — Avis clients rattachés au client maître (grain : 1 ligne par avis) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_avis
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [avis_id], [commande_id], [ligne_id], [produit_id], [client_id], [date_avis], [note], [commentaire], [a_commentaire], [sentiment], [achat_verifie], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[avis];

    INSERT INTO #nouveau (avis_id, commande_id, ligne_id, produit_id, client_id, date_avis, note, commentaire, a_commentaire, sentiment, achat_verifie,
                            id_chargement, date_integration)
    SELECT a.avis_id, a.commande_id, a.ligne_id, a.produit_id, cc.client_id_maitre, a.date_avis, a.note, a.commentaire,
           CASE WHEN a.commentaire IS NULL THEN 0 ELSE 1 END,
           CASE WHEN a.note IS NULL THEN NULL WHEN a.note <= 2 THEN 'negatif' WHEN a.note = 3 THEN 'neutre' ELSE 'positif' END,
           a.achat_verifie, @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_avis_clients a
    JOIN integ.v_client_correspondance cc ON cc.client_id_source = a.client_id
    JOIN integ.v_ligne_commande l ON l.ligne_id = a.ligne_id
    JOIN integ.v_produit p ON p.produit_id = a.produit_id;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [avis_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [ligne_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [client_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_avis], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [note]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commentaire]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [a_commentaire]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [sentiment]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [achat_verifie]), N'∅')));
    MERGE integ.[avis] AS c
    USING #nouveau AS n
       ON c.[avis_id] = n.[avis_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [commande_id] = n.[commande_id], [ligne_id] = n.[ligne_id], [produit_id] = n.[produit_id], [client_id] = n.[client_id], [date_avis] = n.[date_avis], [note] = n.[note], [commentaire] = n.[commentaire], [a_commentaire] = n.[a_commentaire], [sentiment] = n.[sentiment], [achat_verifie] = n.[achat_verifie],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([avis_id], [commande_id], [ligne_id], [produit_id], [client_id], [date_avis], [note], [commentaire], [a_commentaire], [sentiment], [achat_verifie], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[avis_id], n.[commande_id], n.[ligne_id], n.[produit_id], n.[client_id], n.[date_avis], n.[note], n.[commentaire], n.[a_commentaire], n.[sentiment], n.[achat_verifie], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)
    -- aucun
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.avis',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_commande_fournisseur — Commandes fournisseurs (grain : 1 ligne par commande fournisseur) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_commande_fournisseur
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [commande_fournisseur_id], [fournisseur_id], [entrepot_id], [date_commande], [date_livraison_prevue], [date_reception], [statut], [montant_total_ht], [delai_appro_reel_j], [retard_appro_j], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[commande_fournisseur];

    INSERT INTO #nouveau (commande_fournisseur_id, fournisseur_id, entrepot_id, date_commande, date_livraison_prevue, date_reception, statut,
                                            montant_total_ht, delai_appro_reel_j, retard_appro_j, id_chargement, date_integration)
    SELECT f.commande_fournisseur_id, f.fournisseur_id, f.entrepot_id, f.date_commande, f.date_livraison_prevue, r.date_reception, f.statut, f.montant_total_ht,
           DATEDIFF(DAY, f.date_commande, r.date_reception),
           CASE WHEN r.date_reception IS NULL THEN NULL WHEN DATEDIFF(DAY, f.date_livraison_prevue, r.date_reception) > 0
                THEN DATEDIFF(DAY, f.date_livraison_prevue, r.date_reception) ELSE 0 END,
           @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_commandes_fournisseurs f
    -- QR48 : réception antérieure à la commande → date de la dernière entrée en stock rattachée à la commande fournisseur
    OUTER APPLY (SELECT MAX(m.date_mouvement) AS date_mvt FROM [TuniShop_STG_CLEAN].clean.v_mouvements_stock m
                 WHERE m.reference_id = f.commande_fournisseur_id AND m.type_mouvement = 'reception_fournisseur') mv
    CROSS APPLY (SELECT CASE WHEN f.date_reception < f.date_commande THEN mv.date_mvt ELSE f.date_reception END AS date_reception) r;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_fournisseur_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [fournisseur_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [entrepot_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_commande], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_livraison_prevue], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_reception], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [statut]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_total_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [delai_appro_reel_j]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [retard_appro_j]), N'∅')));
    MERGE integ.[commande_fournisseur] AS c
    USING #nouveau AS n
       ON c.[commande_fournisseur_id] = n.[commande_fournisseur_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [fournisseur_id] = n.[fournisseur_id], [entrepot_id] = n.[entrepot_id], [date_commande] = n.[date_commande], [date_livraison_prevue] = n.[date_livraison_prevue], [date_reception] = n.[date_reception], [statut] = n.[statut], [montant_total_ht] = n.[montant_total_ht], [delai_appro_reel_j] = n.[delai_appro_reel_j], [retard_appro_j] = n.[retard_appro_j],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([commande_fournisseur_id], [fournisseur_id], [entrepot_id], [date_commande], [date_livraison_prevue], [date_reception], [statut], [montant_total_ht], [delai_appro_reel_j], [retard_appro_j], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[commande_fournisseur_id], n.[fournisseur_id], n.[entrepot_id], n.[date_commande], n.[date_livraison_prevue], n.[date_reception], n.[statut], n.[montant_total_ht], n.[delai_appro_reel_j], n.[retard_appro_j], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)

    INSERT INTO integ.rejets (id_chargement, table_source, cle_enregistrement, colonne, valeur_recue, regle_id, niveau, message)
    SELECT @id_chargement, N'commande_fournisseur', f.commande_fournisseur_id, N'date_reception', CONVERT(NVARCHAR(30), f.date_reception, 120), 'QR48', 'SIGNALEMENT',
           CONCAT(N'Réception antérieure à la commande : remplacée par ', CONVERT(NVARCHAR(30), i.date_reception, 120))
    FROM [TuniShop_STG_CLEAN].clean.v_commandes_fournisseurs f JOIN integ.v_commande_fournisseur i ON i.commande_fournisseur_id = f.commande_fournisseur_id
    WHERE f.date_reception < f.date_commande;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.commande_fournisseur',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_ligne_commande_fournisseur — Lignes de commandes fournisseurs (grain : 1 ligne par ligne fournisseur) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_ligne_commande_fournisseur
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [ligne_cf_id], [commande_fournisseur_id], [produit_id], [quantite_commandee], [quantite_recue], [taux_service], [cout_unitaire_ht], [montant_ligne_ht], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[ligne_commande_fournisseur];

    INSERT INTO #nouveau (ligne_cf_id, commande_fournisseur_id, produit_id, quantite_commandee, quantite_recue, taux_service,
                                                  cout_unitaire_ht, montant_ligne_ht, id_chargement, date_integration)
    SELECT l.ligne_cf_id, l.commande_fournisseur_id, l.produit_id, l.quantite_commandee, l.quantite_recue,
           CAST(l.quantite_recue AS DECIMAL(12,4)) / NULLIF(l.quantite_commandee, 0), l.cout_unitaire_ht, l.montant_ligne_ht, @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_lignes_commande_fournisseur l
    JOIN integ.v_produit p ON p.produit_id = l.produit_id;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [ligne_cf_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [commande_fournisseur_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [quantite_commandee]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [quantite_recue]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [taux_service]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_unitaire_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [montant_ligne_ht]), N'∅')));
    MERGE integ.[ligne_commande_fournisseur] AS c
    USING #nouveau AS n
       ON c.[ligne_cf_id] = n.[ligne_cf_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [commande_fournisseur_id] = n.[commande_fournisseur_id], [produit_id] = n.[produit_id], [quantite_commandee] = n.[quantite_commandee], [quantite_recue] = n.[quantite_recue], [taux_service] = n.[taux_service], [cout_unitaire_ht] = n.[cout_unitaire_ht], [montant_ligne_ht] = n.[montant_ligne_ht],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([ligne_cf_id], [commande_fournisseur_id], [produit_id], [quantite_commandee], [quantite_recue], [taux_service], [cout_unitaire_ht], [montant_ligne_ht], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[ligne_cf_id], n.[commande_fournisseur_id], n.[produit_id], n.[quantite_commandee], n.[quantite_recue], n.[taux_service], n.[cout_unitaire_ht], n.[montant_ligne_ht], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)
    -- aucun
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.ligne_commande_fournisseur',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_mouvement_stock — Mouvements de stock signés (grain : 1 ligne par mouvement) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_mouvement_stock
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [mouvement_id], [date_mouvement], [produit_id], [entrepot_id], [type_mouvement], [sens], [quantite], [reference_id], [cout_unitaire_ht], [valeur_mouvement_ht], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[mouvement_stock];

    INSERT INTO #nouveau (mouvement_id, date_mouvement, produit_id, entrepot_id, type_mouvement, sens, quantite, reference_id, cout_unitaire_ht,
                                       valeur_mouvement_ht, id_chargement, date_integration)
    SELECT m.mouvement_id, m.date_mouvement, m.produit_id, m.entrepot_id, m.type_mouvement, CASE WHEN m.quantite < 0 THEN 'S' ELSE 'E' END,
           m.quantite, m.reference_id, m.cout_unitaire_ht, m.quantite * m.cout_unitaire_ht, @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_mouvements_stock m
    JOIN integ.v_produit p ON p.produit_id = m.produit_id;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [mouvement_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_mouvement], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [entrepot_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [type_mouvement]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [sens]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [quantite]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [reference_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_unitaire_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [valeur_mouvement_ht]), N'∅')));
    MERGE integ.[mouvement_stock] AS c
    USING #nouveau AS n
       ON c.[mouvement_id] = n.[mouvement_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [date_mouvement] = n.[date_mouvement], [produit_id] = n.[produit_id], [entrepot_id] = n.[entrepot_id], [type_mouvement] = n.[type_mouvement], [sens] = n.[sens], [quantite] = n.[quantite], [reference_id] = n.[reference_id], [cout_unitaire_ht] = n.[cout_unitaire_ht], [valeur_mouvement_ht] = n.[valeur_mouvement_ht],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([mouvement_id], [date_mouvement], [produit_id], [entrepot_id], [type_mouvement], [sens], [quantite], [reference_id], [cout_unitaire_ht], [valeur_mouvement_ht], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[mouvement_id], n.[date_mouvement], n.[produit_id], n.[entrepot_id], n.[type_mouvement], n.[sens], n.[quantite], n.[reference_id], n.[cout_unitaire_ht], n.[valeur_mouvement_ht], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)
    -- aucun
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.mouvement_stock',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

/* integ.usp_integrer_stock_mensuel — Inventaires de fin de mois (grain : 1 ligne par produit, entrepôt et mois) — INCRÉMENTAL */
CREATE OR ALTER PROCEDURE integ.usp_integrer_stock_mensuel
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @nb_lus INT, @nb_ins INT, @nb_maj INT, @nb_sup INT, @nb_doublons INT;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    IF @mode_suppression NOT IN ('marquer','supprimer','ignorer')
        THROW 50030, N'@mode_suppression doit valoir marquer, supprimer ou ignorer', 1;
    BEGIN TRY
    -- 1. Données intégrées dans une table de travail (#nouveau)
    SELECT TOP (0) [inventaire_id], [date_inventaire], [produit_id], [entrepot_id], [stock_fin_mois], [quantite_en_commande], [cout_unitaire_ht], [valeur_stock_ht], [est_rupture], id_chargement, date_integration, CAST(NULL AS BINARY(32)) AS hash_ligne INTO #nouveau FROM integ.[stock_mensuel];

    INSERT INTO #nouveau (inventaire_id, date_inventaire, produit_id, entrepot_id, stock_fin_mois, quantite_en_commande, cout_unitaire_ht,
                                     valeur_stock_ht, est_rupture, id_chargement, date_integration)
    SELECT s.inventaire_id, s.date_inventaire, s.produit_id, s.entrepot_id, s.stock_fin_mois, s.quantite_en_commande, s.cout_unitaire_ht,
           s.stock_fin_mois * s.cout_unitaire_ht, CASE WHEN s.stock_fin_mois = 0 THEN 1 ELSE 0 END, @id_chargement, SYSDATETIME()
    FROM [TuniShop_STG_CLEAN].clean.v_stocks_mensuels s
    JOIN integ.v_produit p ON p.produit_id = s.produit_id;
    SET @nb_lus = (SELECT COUNT(*) FROM #nouveau);
    -- 2. Empreinte puis fusion dans la table cible
    UPDATE #nouveau SET hash_ligne = HASHBYTES('SHA2_256', CONCAT_WS(N'|',
                 COALESCE(CONVERT(NVARCHAR(4000), [inventaire_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [date_inventaire], 121), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [produit_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [entrepot_id]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [stock_fin_mois]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [quantite_en_commande]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [cout_unitaire_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [valeur_stock_ht]), N'∅'),
                 COALESCE(CONVERT(NVARCHAR(4000), [est_rupture]), N'∅')));
    MERGE integ.[stock_mensuel] AS c
    USING #nouveau AS n
       ON c.[inventaire_id] = n.[inventaire_id]
    WHEN MATCHED AND (c.hash_ligne IS NULL OR c.hash_ligne <> n.hash_ligne OR c.est_supprime = 1) THEN      -- ligne modifiée (ou réapparue)
        UPDATE SET [date_inventaire] = n.[date_inventaire], [produit_id] = n.[produit_id], [entrepot_id] = n.[entrepot_id], [stock_fin_mois] = n.[stock_fin_mois], [quantite_en_commande] = n.[quantite_en_commande], [cout_unitaire_ht] = n.[cout_unitaire_ht], [valeur_stock_ht] = n.[valeur_stock_ht], [est_rupture] = n.[est_rupture],
                   hash_ligne = n.hash_ligne, est_supprime = 0, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN                                                                    -- ligne nouvelle
        INSERT ([inventaire_id], [date_inventaire], [produit_id], [entrepot_id], [stock_fin_mois], [quantite_en_commande], [cout_unitaire_ht], [valeur_stock_ht], [est_rupture], hash_ligne, est_supprime, date_creation, id_chargement, [date_integration])
        VALUES (n.[inventaire_id], n.[date_inventaire], n.[produit_id], n.[entrepot_id], n.[stock_fin_mois], n.[quantite_en_commande], n.[cout_unitaire_ht], n.[valeur_stock_ht], n.[est_rupture], n.hash_ligne, 0, SYSDATETIME(), @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'marquer' AND c.est_supprime = 0 THEN           -- ligne disparue : marquée
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, [date_integration] = SYSDATETIME()
    WHEN NOT MATCHED BY SOURCE AND @mode_suppression = 'supprimer' THEN                                -- ligne disparue : supprimée
        DELETE
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;   -- colonnes de @actions dans le même ordre
    SELECT @nb_ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @nb_maj = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 0 THEN 1 END),
           @nb_sup = COUNT(CASE WHEN action = 'DELETE' OR (action = 'UPDATE' AND supp_apres = 1 AND supp_avant = 0) THEN 1 END)
    FROM @actions;
    -- 3. Contrôles et signalements (sur les lignes actives)
    -- aucun
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'STG_INTEGRATED', @objet = N'integ.stock_mensuel',
         @nb_lus = @nb_lus, @nb_inseres = @nb_ins, @nb_maj = @nb_maj, @nb_supprimes = @nb_sup, @nb_rejetes = NULL;
    END TRY
    BEGIN CATCH
        THROW;   -- journalisé par integ.usp_integrer_tout après ROLLBACK (une écriture est impossible dans une transaction condamnée)
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE integ.usp_integrer_tout
    @id_chargement INT,
    @mode_suppression VARCHAR(10) = 'marquer'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @mode_merge VARCHAR(10) = CASE WHEN @mode_suppression = 'supprimer' THEN 'marquer' ELSE @mode_suppression END;
    BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM integ.rejets WHERE id_chargement = @id_chargement;
    EXEC integ.usp_integrer_calendrier @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_geographie @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_entrepot @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_transporteur @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_fournisseur @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_coupon @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_campagne @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_client_correspondance @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_client @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_produit @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_produit_version_prix @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_depense_marketing @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_commande @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_ligne_commande @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_paiement @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_livraison @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_remboursement @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_avis @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_commande_fournisseur @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_ligne_commande_fournisseur @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_mouvement_stock @id_chargement = @id_chargement, @mode_suppression = @mode_merge;
    EXEC integ.usp_integrer_stock_mensuel @id_chargement = @id_chargement, @mode_suppression = @mode_merge;

    IF @mode_suppression = 'supprimer'
    BEGIN
        -- références circulaires vers des campagnes supprimées
        UPDATE integ.coupon SET campagne_id = NULL WHERE campagne_id IN (SELECT campagne_id FROM integ.campagne WHERE est_supprime = 1);
        UPDATE integ.campagne SET code_coupon = NULL WHERE code_coupon IN (SELECT code_coupon FROM integ.coupon WHERE est_supprime = 1);
        DELETE FROM integ.[stock_mensuel] WHERE est_supprime = 1;
        DELETE FROM integ.[mouvement_stock] WHERE est_supprime = 1;
        DELETE FROM integ.[ligne_commande_fournisseur] WHERE est_supprime = 1;
        DELETE FROM integ.[commande_fournisseur] WHERE est_supprime = 1;
        DELETE FROM integ.[avis] WHERE est_supprime = 1;
        DELETE FROM integ.[remboursement] WHERE est_supprime = 1;
        DELETE FROM integ.[livraison] WHERE est_supprime = 1;
        DELETE FROM integ.[paiement] WHERE est_supprime = 1;
        DELETE FROM integ.[ligne_commande] WHERE est_supprime = 1;
        DELETE FROM integ.[commande] WHERE est_supprime = 1;
        DELETE FROM integ.[depense_marketing] WHERE est_supprime = 1;
        DELETE FROM integ.[produit_version_prix] WHERE est_supprime = 1;
        DELETE FROM integ.[produit] WHERE est_supprime = 1;
        DELETE FROM integ.[client] WHERE est_supprime = 1;
        DELETE FROM integ.[client_correspondance] WHERE est_supprime = 1;
        DELETE FROM integ.[campagne] WHERE est_supprime = 1;
        DELETE FROM integ.[coupon] WHERE est_supprime = 1;
        DELETE FROM integ.[fournisseur] WHERE est_supprime = 1;
        DELETE FROM integ.[transporteur] WHERE est_supprime = 1;
        DELETE FROM integ.[entrepot] WHERE est_supprime = 1;
        DELETE FROM integ.[geographie] WHERE est_supprime = 1;
        DELETE FROM integ.[calendrier] WHERE est_supprime = 1;
    END
    COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @proc NVARCHAR(200) = CONCAT(N'integ.usp_integrer_tout > ', ERROR_PROCEDURE());
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = @proc;
        THROW;
    END CATCH
END;
GO
