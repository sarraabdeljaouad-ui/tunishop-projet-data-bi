/* =====================================================================
   Projet      : TuniShop — Data Warehouse e-commerce (portfolio)
   Script      : 02_Procedures_DWH.sql
   Objet       : Procédures de chargement du DWH : 13 dimensions (SCD1, SCD2 client, versions de prix produit) et 10 faits (MERGE), plus l'orchestration dw.usp_charger_dwh. Lecture des vues integ.v_* ; journalisation dans TuniShop_ADMIN.audit.
   Cible       : Microsoft SQL Server 2019+ (SSMS) — compatibilité 150
   Exécution   : SSMS, mode SQLCMD inutile ; exécuter en entier (F5)
   Généré le   : 2026-10-17 depuis le modèle de métadonnées du projet
   ===================================================================== */
SET NOCOUNT ON;
GO
/* Prérequis : kit Étape 2 (01 à 04) exécuté et staging chargé ; 05_Creation_DWH.sql exécuté. */

/* =====================================================================
   PARTIE 3 — INTEGRATED → DWH  (base TuniShop_DWH)
   Dimensions : MERGE SCD1 ; dim_client en SCD2 (hash) ; dim_produit par version de prix.
   Faits : MERGE sur la clé naturelle (rejouable), lookups vers les clés de substitution,
   -1 = inconnu, -2 = non applicable.
   ===================================================================== */
USE [TuniShop_DWH];
GO

/* usp_charger_dim_date — Génère tous les jours de la plage couverte par le staging (+1 an) ; attributs fériés/Ramadan/période pris dans le calendrier source quand disponibles */
CREATE OR ALTER PROCEDURE dw.usp_charger_dim_date
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    -- Plage calculée : du 1er janvier de la plus ancienne date du staging au 31 décembre de l'année suivant la plus récente
    DECLARE @dmin DATE, @dmax DATE, @debut DATE, @fin DATE;
    SELECT @dmin = MIN(dmin), @dmax = MAX(dmax) FROM (
        SELECT MIN(CAST(date_commande AS DATE)), MAX(CAST(date_commande AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_commande
        UNION ALL SELECT MIN(CAST(date_annulation AS DATE)), MAX(CAST(date_annulation AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_commande
        UNION ALL SELECT MIN(CAST(date_expedition AS DATE)), MAX(CAST(date_expedition AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_livraison
        UNION ALL SELECT MIN(CAST(date_livraison_prevue AS DATE)), MAX(CAST(date_livraison_prevue AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_livraison
        UNION ALL SELECT MIN(CAST(date_livraison_reelle AS DATE)), MAX(CAST(date_livraison_reelle AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_livraison
        UNION ALL SELECT MIN(CAST(date_paiement AS DATE)), MAX(CAST(date_paiement AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_paiement
        UNION ALL SELECT MIN(CAST(date_reversement AS DATE)), MAX(CAST(date_reversement AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_paiement
        UNION ALL SELECT MIN(CAST(date_demande AS DATE)), MAX(CAST(date_demande AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_remboursement
        UNION ALL SELECT MIN(CAST(date_remboursement AS DATE)), MAX(CAST(date_remboursement AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_remboursement
        UNION ALL SELECT MIN(CAST(date_avis AS DATE)), MAX(CAST(date_avis AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_avis
        UNION ALL SELECT MIN(CAST([date] AS DATE)), MAX(CAST([date] AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_depense_marketing
        UNION ALL SELECT MIN(CAST(date_commande AS DATE)), MAX(CAST(date_commande AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_commande_fournisseur
        UNION ALL SELECT MIN(CAST(date_livraison_prevue AS DATE)), MAX(CAST(date_livraison_prevue AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_commande_fournisseur
        UNION ALL SELECT MIN(CAST(date_reception AS DATE)), MAX(CAST(date_reception AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_commande_fournisseur
        UNION ALL SELECT MIN(CAST(date_mouvement AS DATE)), MAX(CAST(date_mouvement AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_mouvement_stock
        UNION ALL SELECT MIN(CAST(date_inventaire AS DATE)), MAX(CAST(date_inventaire AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_stock_mensuel
        UNION ALL SELECT MIN(CAST([date] AS DATE)), MAX(CAST([date] AS DATE)) FROM [TuniShop_STG_INTEGRATED].integ.v_calendrier
    ) x (dmin, dmax);
    SET @debut = DATEFROMPARTS(YEAR(COALESCE(@dmin, '2023-01-01')), 1, 1);
    SET @fin   = DATEFROMPARTS(YEAR(COALESCE(@dmax, '2025-12-31')) + 1, 12, 31);
    ;WITH n AS (SELECT TOP (DATEDIFF(DAY, @debut, @fin) + 1) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
               FROM sys.all_objects a CROSS JOIN sys.all_objects b),
          d AS (SELECT DATEADD(DAY, i, @debut) AS dt FROM n)
    MERGE dw.dim_date AS t
    USING (
        SELECT YEAR(d.dt) * 10000 + MONTH(d.dt) * 100 + DAY(d.dt) AS date_sk, d.dt AS [date],
               YEAR(d.dt) AS annee, DATEPART(QUARTER, d.dt) AS trimestre,
               CONCAT(YEAR(d.dt), '-T', DATEPART(QUARTER, d.dt)) AS libelle_trimestre,
               MONTH(d.dt) AS mois,
               COALESCE(c.nom_mois, CHOOSE(MONTH(d.dt), N'janvier',N'février',N'mars',N'avril',N'mai',N'juin',N'juillet',N'août',N'septembre',N'octobre',N'novembre',N'décembre')) AS nom_mois,
               CONVERT(CHAR(7), d.dt, 126) AS annee_mois,
               DATEPART(ISO_WEEK, d.dt) AS semaine_iso, DAY(d.dt) AS jour_mois,
               w.jiso AS jour_semaine,
               CHOOSE(w.jiso, N'lundi',N'mardi',N'mercredi',N'jeudi',N'vendredi',N'samedi',N'dimanche') AS nom_jour,
               CASE WHEN w.jiso IN (6,7) THEN 1 ELSE 0 END AS est_weekend,
               COALESCE(c.est_jour_ferie, 0) AS est_jour_ferie, c.nom_jour_ferie,
               COALESCE(c.est_ramadan, 0) AS est_ramadan,
               COALESCE(c.periode_commerciale, 'hors_referentiel') AS periode_commerciale
        FROM d
        CROSS APPLY (SELECT (DATEPART(WEEKDAY, d.dt) + @@DATEFIRST - 2) % 7 + 1 AS jiso) w
        LEFT JOIN [TuniShop_STG_INTEGRATED].integ.v_calendrier c ON c.[date] = d.dt
    ) AS s
    ON t.date_sk = s.date_sk
    WHEN MATCHED AND (EXISTS (SELECT t.est_jour_ferie, t.nom_jour_ferie, t.est_ramadan, t.periode_commerciale
                              EXCEPT SELECT s.est_jour_ferie, s.nom_jour_ferie, s.est_ramadan, s.periode_commerciale)) THEN
        UPDATE SET est_jour_ferie = s.est_jour_ferie, nom_jour_ferie = s.nom_jour_ferie, est_ramadan = s.est_ramadan, periode_commerciale = s.periode_commerciale
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (date_sk, [date], annee, trimestre, libelle_trimestre, mois, nom_mois, annee_mois, semaine_iso, jour_mois, jour_semaine, nom_jour,
                est_weekend, est_jour_ferie, nom_jour_ferie, est_ramadan, periode_commerciale)
        VALUES (s.date_sk, s.[date], s.annee, s.trimestre, s.libelle_trimestre, s.mois, s.nom_mois, s.annee_mois, s.semaine_iso, s.jour_mois, s.jour_semaine,
                s.nom_jour, s.est_weekend, s.est_jour_ferie, s.nom_jour_ferie, s.est_ramadan, s.periode_commerciale)
    OUTPUT $action, NULL, NULL INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.dim_date',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_dim_date';
        THROW;
    END CATCH
END;
GO

/* usp_charger_dim_fournisseur — Fournisseurs — SCD1 (MERGE) */
CREATE OR ALTER PROCEDURE dw.usp_charger_dim_fournisseur
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    MERGE dw.[dim_fournisseur] AS t
    USING (SELECT fournisseur_id AS [fournisseur_id],
                nom_fournisseur AS [nom_fournisseur],
                pays AS [pays],
                est_local AS [est_local],
                delai_appro_moyen_j AS [delai_appro_moyen_j],
                conditions_paiement AS [conditions_paiement],
                fiabilite_livraison AS [fiabilite_livraison]
           FROM [TuniShop_STG_INTEGRATED].integ.v_fournisseur) AS s
    ON t.[fournisseur_id] = s.[fournisseur_id]
    WHEN MATCHED AND (EXISTS (SELECT t.[nom_fournisseur] EXCEPT SELECT s.[nom_fournisseur]) OR EXISTS (SELECT t.[pays] EXCEPT SELECT s.[pays]) OR EXISTS (SELECT t.[est_local] EXCEPT SELECT s.[est_local]) OR EXISTS (SELECT t.[delai_appro_moyen_j] EXCEPT SELECT s.[delai_appro_moyen_j]) OR EXISTS (SELECT t.[conditions_paiement] EXCEPT SELECT s.[conditions_paiement]) OR EXISTS (SELECT t.[fiabilite_livraison] EXCEPT SELECT s.[fiabilite_livraison]) OR t.est_supprime = 1) THEN
        UPDATE SET [nom_fournisseur] = s.[nom_fournisseur], [pays] = s.[pays], [est_local] = s.[est_local], [delai_appro_moyen_j] = s.[delai_appro_moyen_j], [conditions_paiement] = s.[conditions_paiement], [fiabilite_livraison] = s.[fiabilite_livraison], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([fournisseur_id], [nom_fournisseur], [pays], [est_local], [delai_appro_moyen_j], [conditions_paiement], [fiabilite_livraison], id_chargement, date_maj)
        VALUES (s.[fournisseur_id], s.[nom_fournisseur], s.[pays], s.[est_local], s.[delai_appro_moyen_j], s.[conditions_paiement], s.[fiabilite_livraison], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.[fournisseur_sk] > 0 AND t.est_supprime = 0 THEN          -- disparue du staging (membres -1/-2 protégés)
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.dim_fournisseur',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_dim_fournisseur';
        THROW;
    END CATCH
END;
GO

/* usp_charger_dim_geographie — Gouvernorats — SCD1 (MERGE) */
CREATE OR ALTER PROCEDURE dw.usp_charger_dim_geographie
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    MERGE dw.[dim_geographie] AS t
    USING (SELECT gouvernorat_id AS [gouvernorat_id],
                gouvernorat AS [gouvernorat],
                region AS [region],
                zone_livraison AS [zone_livraison],
                nom_entrepot_rattachement AS [entrepot_rattachement],
                N'Tunisie' AS [pays]
           FROM [TuniShop_STG_INTEGRATED].integ.v_geographie) AS s
    ON t.[gouvernorat_id] = s.[gouvernorat_id]
    WHEN MATCHED AND (EXISTS (SELECT t.[gouvernorat] EXCEPT SELECT s.[gouvernorat]) OR EXISTS (SELECT t.[region] EXCEPT SELECT s.[region]) OR EXISTS (SELECT t.[zone_livraison] EXCEPT SELECT s.[zone_livraison]) OR EXISTS (SELECT t.[entrepot_rattachement] EXCEPT SELECT s.[entrepot_rattachement]) OR EXISTS (SELECT t.[pays] EXCEPT SELECT s.[pays]) OR t.est_supprime = 1) THEN
        UPDATE SET [gouvernorat] = s.[gouvernorat], [region] = s.[region], [zone_livraison] = s.[zone_livraison], [entrepot_rattachement] = s.[entrepot_rattachement], [pays] = s.[pays], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([gouvernorat_id], [gouvernorat], [region], [zone_livraison], [entrepot_rattachement], [pays], id_chargement, date_maj)
        VALUES (s.[gouvernorat_id], s.[gouvernorat], s.[region], s.[zone_livraison], s.[entrepot_rattachement], s.[pays], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.[geographie_sk] > 0 AND t.est_supprime = 0 THEN          -- disparue du staging (membres -1/-2 protégés)
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.dim_geographie',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_dim_geographie';
        THROW;
    END CATCH
END;
GO

/* usp_charger_dim_entrepot — Entrepôts — SCD1 (MERGE) */
CREATE OR ALTER PROCEDURE dw.usp_charger_dim_entrepot
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    MERGE dw.[dim_entrepot] AS t
    USING (SELECT entrepot_id AS [entrepot_id],
                nom_entrepot AS [nom_entrepot],
                ville AS [ville],
                region AS [region],
                surface_m2 AS [surface_m2],
                date_ouverture AS [date_ouverture]
           FROM [TuniShop_STG_INTEGRATED].integ.v_entrepot) AS s
    ON t.[entrepot_id] = s.[entrepot_id]
    WHEN MATCHED AND (EXISTS (SELECT t.[nom_entrepot] EXCEPT SELECT s.[nom_entrepot]) OR EXISTS (SELECT t.[ville] EXCEPT SELECT s.[ville]) OR EXISTS (SELECT t.[region] EXCEPT SELECT s.[region]) OR EXISTS (SELECT t.[surface_m2] EXCEPT SELECT s.[surface_m2]) OR EXISTS (SELECT t.[date_ouverture] EXCEPT SELECT s.[date_ouverture]) OR t.est_supprime = 1) THEN
        UPDATE SET [nom_entrepot] = s.[nom_entrepot], [ville] = s.[ville], [region] = s.[region], [surface_m2] = s.[surface_m2], [date_ouverture] = s.[date_ouverture], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([entrepot_id], [nom_entrepot], [ville], [region], [surface_m2], [date_ouverture], id_chargement, date_maj)
        VALUES (s.[entrepot_id], s.[nom_entrepot], s.[ville], s.[region], s.[surface_m2], s.[date_ouverture], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.[entrepot_sk] > 0 AND t.est_supprime = 0 THEN          -- disparue du staging (membres -1/-2 protégés)
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.dim_entrepot',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_dim_entrepot';
        THROW;
    END CATCH
END;
GO

/* usp_charger_dim_transporteur — Transporteurs — SCD1 (MERGE) */
CREATE OR ALTER PROCEDURE dw.usp_charger_dim_transporteur
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    MERGE dw.[dim_transporteur] AS t
    USING (SELECT transporteur_id AS [transporteur_id],
                nom_transporteur AS [nom_transporteur],
                couverture AS [couverture],
                cout_base_ht AS [cout_base_ht]
           FROM [TuniShop_STG_INTEGRATED].integ.v_transporteur) AS s
    ON t.[transporteur_id] = s.[transporteur_id]
    WHEN MATCHED AND (EXISTS (SELECT t.[nom_transporteur] EXCEPT SELECT s.[nom_transporteur]) OR EXISTS (SELECT t.[couverture] EXCEPT SELECT s.[couverture]) OR EXISTS (SELECT t.[cout_base_ht] EXCEPT SELECT s.[cout_base_ht]) OR t.est_supprime = 1) THEN
        UPDATE SET [nom_transporteur] = s.[nom_transporteur], [couverture] = s.[couverture], [cout_base_ht] = s.[cout_base_ht], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([transporteur_id], [nom_transporteur], [couverture], [cout_base_ht], id_chargement, date_maj)
        VALUES (s.[transporteur_id], s.[nom_transporteur], s.[couverture], s.[cout_base_ht], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.[transporteur_sk] > 0 AND t.est_supprime = 0 THEN          -- disparue du staging (membres -1/-2 protégés)
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.dim_transporteur',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_dim_transporteur';
        THROW;
    END CATCH
END;
GO

/* usp_charger_dim_campagne — Campagnes marketing — SCD1 (MERGE) */
CREATE OR ALTER PROCEDURE dw.usp_charger_dim_campagne
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    MERGE dw.[dim_campagne] AS t
    USING (SELECT campagne_id AS [campagne_id],
                nom_campagne AS [nom_campagne],
                canal AS [canal_media],
                type_canal AS [type_canal],
                objectif AS [objectif],
                theme AS [theme],
                date_debut AS [date_debut],
                date_fin AS [date_fin],
                budget_ht AS [budget_ht]
           FROM [TuniShop_STG_INTEGRATED].integ.v_campagne) AS s
    ON t.[campagne_id] = s.[campagne_id]
    WHEN MATCHED AND (EXISTS (SELECT t.[nom_campagne] EXCEPT SELECT s.[nom_campagne]) OR EXISTS (SELECT t.[canal_media] EXCEPT SELECT s.[canal_media]) OR EXISTS (SELECT t.[type_canal] EXCEPT SELECT s.[type_canal]) OR EXISTS (SELECT t.[objectif] EXCEPT SELECT s.[objectif]) OR EXISTS (SELECT t.[theme] EXCEPT SELECT s.[theme]) OR EXISTS (SELECT t.[date_debut] EXCEPT SELECT s.[date_debut]) OR EXISTS (SELECT t.[date_fin] EXCEPT SELECT s.[date_fin]) OR EXISTS (SELECT t.[budget_ht] EXCEPT SELECT s.[budget_ht]) OR t.est_supprime = 1) THEN
        UPDATE SET [nom_campagne] = s.[nom_campagne], [canal_media] = s.[canal_media], [type_canal] = s.[type_canal], [objectif] = s.[objectif], [theme] = s.[theme], [date_debut] = s.[date_debut], [date_fin] = s.[date_fin], [budget_ht] = s.[budget_ht], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([campagne_id], [nom_campagne], [canal_media], [type_canal], [objectif], [theme], [date_debut], [date_fin], [budget_ht], id_chargement, date_maj)
        VALUES (s.[campagne_id], s.[nom_campagne], s.[canal_media], s.[type_canal], s.[objectif], s.[theme], s.[date_debut], s.[date_fin], s.[budget_ht], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.[campagne_sk] > 0 AND t.est_supprime = 0 THEN          -- disparue du staging (membres -1/-2 protégés)
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.dim_campagne',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_dim_campagne';
        THROW;
    END CATCH
END;
GO

/* usp_charger_dim_coupon — Coupons — SCD1 (MERGE) */
CREATE OR ALTER PROCEDURE dw.usp_charger_dim_coupon
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    MERGE dw.[dim_coupon] AS t
    USING (SELECT code_coupon AS [code_coupon],
                type_remise AS [type_remise],
                valeur AS [valeur],
                montant_min_ttc AS [montant_min_ttc],
                reserve_premiere_commande AS [reserve_premiere_commande]
           FROM [TuniShop_STG_INTEGRATED].integ.v_coupon) AS s
    ON t.[code_coupon] = s.[code_coupon]
    WHEN MATCHED AND (EXISTS (SELECT t.[type_remise] EXCEPT SELECT s.[type_remise]) OR EXISTS (SELECT t.[valeur] EXCEPT SELECT s.[valeur]) OR EXISTS (SELECT t.[montant_min_ttc] EXCEPT SELECT s.[montant_min_ttc]) OR EXISTS (SELECT t.[reserve_premiere_commande] EXCEPT SELECT s.[reserve_premiere_commande]) OR t.est_supprime = 1) THEN
        UPDATE SET [type_remise] = s.[type_remise], [valeur] = s.[valeur], [montant_min_ttc] = s.[montant_min_ttc], [reserve_premiere_commande] = s.[reserve_premiere_commande], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([code_coupon], [type_remise], [valeur], [montant_min_ttc], [reserve_premiere_commande], id_chargement, date_maj)
        VALUES (s.[code_coupon], s.[type_remise], s.[valeur], s.[montant_min_ttc], s.[reserve_premiere_commande], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.[coupon_sk] > 0 AND t.est_supprime = 0 THEN          -- disparue du staging (membres -1/-2 protégés)
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.dim_coupon',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_dim_coupon';
        THROW;
    END CATCH
END;
GO

/* usp_charger_dim_canal — Combinaisons canal × appareil observées — SCD1 */
CREATE OR ALTER PROCEDURE dw.usp_charger_dim_canal
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    MERGE dw.[dim_canal] AS t
    USING (SELECT canal AS [canal],
                appareil AS [appareil],
                CONCAT(CASE canal WHEN 'site_web' THEN N'Site web' WHEN 'application_mobile' THEN N'Application mobile' WHEN 'reseaux_sociaux' THEN N'Réseaux sociaux' WHEN 'non_renseigne' THEN N'Non renseigné' ELSE canal END, N' / ', appareil) AS [libelle_canal]
           FROM (SELECT DISTINCT canal, appareil FROM [TuniShop_STG_INTEGRATED].integ.v_commande) x) AS s
    ON t.[canal] = s.[canal] AND t.[appareil] = s.[appareil]
    WHEN MATCHED AND (EXISTS (SELECT t.[libelle_canal] EXCEPT SELECT s.[libelle_canal]) OR t.est_supprime = 1) THEN
        UPDATE SET [libelle_canal] = s.[libelle_canal], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([canal], [appareil], [libelle_canal], id_chargement, date_maj)
        VALUES (s.[canal], s.[appareil], s.[libelle_canal], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.[canal_sk] > 0 AND t.est_supprime = 0 THEN          -- disparue du staging (membres -1/-2 protégés)
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.dim_canal',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_dim_canal';
        THROW;
    END CATCH
END;
GO

/* usp_charger_dim_mode_paiement — Modes de paiement observés (commandes et paiements) — SCD1 */
CREATE OR ALTER PROCEDURE dw.usp_charger_dim_mode_paiement
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    MERGE dw.[dim_mode_paiement] AS t
    USING (SELECT mode_paiement AS [mode_paiement],
                CASE mode_paiement WHEN 'paiement_a_la_livraison' THEN N'Paiement à la livraison' WHEN 'carte_bancaire' THEN N'Carte bancaire' WHEN 'portefeuille_mobile' THEN N'Portefeuille mobile' WHEN 'carte_prepayee' THEN N'Carte prépayée' WHEN 'virement' THEN N'Virement' ELSE mode_paiement END AS [libelle_mode_paiement],
                CAST(CASE WHEN mode_paiement = 'paiement_a_la_livraison' THEN 1 ELSE 0 END AS BIT) AS [est_paiement_differe]
           FROM (SELECT mode_paiement FROM [TuniShop_STG_INTEGRATED].integ.v_commande UNION SELECT mode_paiement FROM [TuniShop_STG_INTEGRATED].integ.v_paiement) x) AS s
    ON t.[mode_paiement] = s.[mode_paiement]
    WHEN MATCHED AND (EXISTS (SELECT t.[libelle_mode_paiement] EXCEPT SELECT s.[libelle_mode_paiement]) OR EXISTS (SELECT t.[est_paiement_differe] EXCEPT SELECT s.[est_paiement_differe]) OR t.est_supprime = 1) THEN
        UPDATE SET [libelle_mode_paiement] = s.[libelle_mode_paiement], [est_paiement_differe] = s.[est_paiement_differe], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([mode_paiement], [libelle_mode_paiement], [est_paiement_differe], id_chargement, date_maj)
        VALUES (s.[mode_paiement], s.[libelle_mode_paiement], s.[est_paiement_differe], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.[mode_paiement_sk] > 0 AND t.est_supprime = 0 THEN          -- disparue du staging (membres -1/-2 protégés)
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.dim_mode_paiement',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_dim_mode_paiement';
        THROW;
    END CATCH
END;
GO

/* usp_charger_dim_statut_commande — Statuts de commande — SCD1 */
CREATE OR ALTER PROCEDURE dw.usp_charger_dim_statut_commande
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    MERGE dw.[dim_statut_commande] AS t
    USING (SELECT statut_commande AS [statut_commande],
                CASE statut_commande WHEN 'livree' THEN N'Livrée' WHEN 'partiellement_retournee' THEN N'Partiellement retournée' WHEN 'retournee' THEN N'Retournée' WHEN 'annulee' THEN N'Annulée' WHEN 'livraison_echouee' THEN N'Livraison échouée' WHEN 'paiement_echoue' THEN N'Paiement échoué' WHEN 'expediee' THEN N'Expédiée' WHEN 'en_preparation' THEN N'En préparation' ELSE statut_commande END AS [libelle_statut],
                CASE WHEN statut_commande IN ('livree','partiellement_retournee','retournee') THEN 'aboutie' WHEN statut_commande IN ('expediee','en_preparation') THEN 'en_cours' ELSE 'echouee' END AS [famille_statut],
                CAST(CASE WHEN statut_commande IN ('livree','partiellement_retournee','retournee') THEN 1 ELSE 0 END AS BIT) AS [est_ca_reconnu]   -- CA reconnu à la livraison (règle de gestion DWH ; « expediee » exclu)
           FROM (SELECT DISTINCT statut_commande FROM [TuniShop_STG_INTEGRATED].integ.v_commande) x) AS s
    ON t.[statut_commande] = s.[statut_commande]
    WHEN MATCHED AND (EXISTS (SELECT t.[libelle_statut] EXCEPT SELECT s.[libelle_statut]) OR EXISTS (SELECT t.[famille_statut] EXCEPT SELECT s.[famille_statut]) OR EXISTS (SELECT t.[est_ca_reconnu] EXCEPT SELECT s.[est_ca_reconnu]) OR t.est_supprime = 1) THEN
        UPDATE SET [libelle_statut] = s.[libelle_statut], [famille_statut] = s.[famille_statut], [est_ca_reconnu] = s.[est_ca_reconnu], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([statut_commande], [libelle_statut], [famille_statut], [est_ca_reconnu], id_chargement, date_maj)
        VALUES (s.[statut_commande], s.[libelle_statut], s.[famille_statut], s.[est_ca_reconnu], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.[statut_commande_sk] > 0 AND t.est_supprime = 0 THEN          -- disparue du staging (membres -1/-2 protégés)
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.dim_statut_commande',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_dim_statut_commande';
        THROW;
    END CATCH
END;
GO

/* usp_charger_dim_motif_retour — Type × motif de remboursement — SCD1 */
CREATE OR ALTER PROCEDURE dw.usp_charger_dim_motif_retour
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    MERGE dw.[dim_motif_retour] AS t
    USING (SELECT type_remboursement AS [type_remboursement],
                motif AS [motif],
                UPPER(LEFT(REPLACE(motif, '_', ' '), 1)) + SUBSTRING(REPLACE(motif, '_', ' '), 2, 60) AS [libelle_motif],
                CASE WHEN motif IN ('taille_inadaptee','changement_d_avis','annulation_client') THEN 'client' WHEN motif IN ('colis_endommage','echec_livraison','retard_livraison','livraison_trop_tardive') THEN 'transporteur' ELSE 'tunishop' END AS [responsabilite]
           FROM (SELECT DISTINCT type_remboursement, motif FROM [TuniShop_STG_INTEGRATED].integ.v_remboursement) x) AS s
    ON t.[type_remboursement] = s.[type_remboursement] AND t.[motif] = s.[motif]
    WHEN MATCHED AND (EXISTS (SELECT t.[libelle_motif] EXCEPT SELECT s.[libelle_motif]) OR EXISTS (SELECT t.[responsabilite] EXCEPT SELECT s.[responsabilite]) OR t.est_supprime = 1) THEN
        UPDATE SET [libelle_motif] = s.[libelle_motif], [responsabilite] = s.[responsabilite], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([type_remboursement], [motif], [libelle_motif], [responsabilite], id_chargement, date_maj)
        VALUES (s.[type_remboursement], s.[motif], s.[libelle_motif], s.[responsabilite], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.[motif_retour_sk] > 0 AND t.est_supprime = 0 THEN          -- disparue du staging (membres -1/-2 protégés)
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.dim_motif_retour',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_dim_motif_retour';
        THROW;
    END CATCH
END;
GO

/* usp_charger_dim_client — Clients — SCD2 sur segment_fidelite, gouvernorat_id, ville ; SCD1 sur les autres attributs */
CREATE OR ALTER PROCEDURE dw.usp_charger_dim_client
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @date_lot DATE = CAST(SYSDATETIME() AS DATE);
    SELECT c.client_id, c.type_client, c.nom_complet, c.genre, c.tranche_age, c.gouvernorat_id, g.gouvernorat, g.region, c.ville,
           c.canal_inscription, CAST(c.date_inscription AS DATE) AS date_inscription, CONVERT(CHAR(7), c.date_inscription, 126) AS cohorte_inscription,
           c.opt_in_email, c.opt_in_sms, c.segment_fidelite,
           HASHBYTES('SHA2_256', CONCAT(c.segment_fidelite, '|', c.gouvernorat_id, '|', c.ville)) AS hash_scd2
    INTO #src
    FROM [TuniShop_STG_INTEGRATED].integ.v_client c JOIN [TuniShop_STG_INTEGRATED].integ.v_geographie g ON g.gouvernorat_id = c.gouvernorat_id;

    -- 1a) Version ouverte aujourd'hui et déjà modifiée : mise à jour sur place (évite une fin de validité antérieure au début)
    UPDATE d SET segment_fidelite = s.segment_fidelite, gouvernorat_id = s.gouvernorat_id, gouvernorat = s.gouvernorat, region = s.region,
                 ville = s.ville, hash_scd2 = s.hash_scd2, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT 'UPDATE', deleted.est_supprime, inserted.est_supprime INTO @actions
    FROM dw.dim_client d JOIN #src s ON s.client_id = d.client_id
    WHERE d.est_courant = 1 AND d.hash_scd2 <> s.hash_scd2 AND d.date_debut_validite = @date_lot;

    -- 1b) Clôture des versions plus anciennes dont un attribut SCD2 a changé
    UPDATE d SET date_fin_validite = DATEADD(DAY, -1, @date_lot), est_courant = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT 'UPDATE', deleted.est_supprime, inserted.est_supprime INTO @actions
    FROM dw.dim_client d JOIN #src s ON s.client_id = d.client_id
    WHERE d.est_courant = 1 AND d.hash_scd2 <> s.hash_scd2 AND d.date_debut_validite < @date_lot;

    -- 2) Nouvelle version (clients nouveaux : validité depuis 1900-01-01 pour couvrir l'historique des faits)
    INSERT INTO dw.dim_client (client_id, type_client, nom_complet, genre, tranche_age, gouvernorat_id, gouvernorat, region, ville, canal_inscription,
                               date_inscription, cohorte_inscription, opt_in_email, opt_in_sms, segment_fidelite, hash_scd2,
                               date_debut_validite, date_fin_validite, est_courant, id_chargement, date_maj)
    OUTPUT 'INSERT', NULL, inserted.est_supprime INTO @actions
    SELECT s.client_id, s.type_client, s.nom_complet, s.genre, s.tranche_age, s.gouvernorat_id, s.gouvernorat, s.region, s.ville, s.canal_inscription,
           s.date_inscription, s.cohorte_inscription, s.opt_in_email, s.opt_in_sms, s.segment_fidelite, s.hash_scd2,
           CASE WHEN EXISTS (SELECT 1 FROM dw.dim_client x WHERE x.client_id = s.client_id) THEN @date_lot ELSE '1900-01-01' END,
           '9999-12-31', 1, @id_chargement, SYSDATETIME()
    FROM #src s
    WHERE NOT EXISTS (SELECT 1 FROM dw.dim_client d WHERE d.client_id = s.client_id AND d.est_courant = 1);

    -- 3) SCD1 : mise à jour des attributs non historisés sur toutes les versions
    UPDATE d SET type_client = s.type_client, nom_complet = s.nom_complet, genre = s.genre, tranche_age = s.tranche_age,
                 canal_inscription = s.canal_inscription, opt_in_email = s.opt_in_email, opt_in_sms = s.opt_in_sms,
                 gouvernorat = s.gouvernorat, region = s.region, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT 'UPDATE', deleted.est_supprime, inserted.est_supprime INTO @actions
    FROM dw.dim_client d JOIN #src s ON s.client_id = d.client_id
    WHERE EXISTS (SELECT d.type_client, d.nom_complet, d.genre, d.tranche_age, d.canal_inscription, d.opt_in_email, d.opt_in_sms
                  EXCEPT SELECT s.type_client, s.nom_complet, s.genre, s.tranche_age, s.canal_inscription, s.opt_in_email, s.opt_in_sms);

    -- 4) Suppressions répercutées : client absent du staging → toutes ses versions marquées ; réapparu → réactivé
    UPDATE d SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT 'UPDATE', deleted.est_supprime, inserted.est_supprime INTO @actions
    FROM dw.dim_client d
    WHERE d.client_sk > 0 AND d.est_supprime = 0 AND NOT EXISTS (SELECT 1 FROM #src s WHERE s.client_id = d.client_id);
    UPDATE d SET est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT 'UPDATE', deleted.est_supprime, inserted.est_supprime INTO @actions
    FROM dw.dim_client d
    WHERE d.est_supprime = 1 AND EXISTS (SELECT 1 FROM #src s WHERE s.client_id = d.client_id);
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.dim_client',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_dim_client';
        THROW;
    END CATCH
END;
GO

/* usp_charger_dim_produit — Produits — une version par période de prix (SCD2 alimenté par integ.produit_version_prix), attributs descriptifs en SCD1 */
CREATE OR ALTER PROCEDURE dw.usp_charger_dim_produit
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    SELECT p.produit_id, v.prix_id, p.sku, p.nom_produit, p.marque, p.categorie, p.sous_categorie, p.fournisseur_id, p.taux_tva, p.gamme_prix,
           p.statut_produit, v.prix_catalogue_ttc, v.cout_achat_unitaire_ht, p.taux_retour_cible, p.marge_brute_cible,
           v.date_debut AS date_debut_validite,
           CASE WHEN v.est_prix_actuel = 1 THEN CAST('9999-12-31' AS DATE) ELSE v.date_fin END AS date_fin_validite,
           v.est_prix_actuel AS est_courant
    INTO #src
    FROM [TuniShop_STG_INTEGRATED].integ.v_produit p JOIN [TuniShop_STG_INTEGRATED].integ.v_produit_version_prix v ON v.produit_id = p.produit_id;

    MERGE dw.dim_produit AS t
    USING #src AS s
    ON t.produit_id = s.produit_id AND t.prix_id = s.prix_id
    WHEN MATCHED AND EXISTS (SELECT t.sku, t.nom_produit, t.marque, t.categorie, t.sous_categorie, t.fournisseur_id, t.taux_tva, t.gamme_prix, t.statut_produit,
                                    t.prix_catalogue_ttc, t.cout_achat_unitaire_ht, t.taux_retour_cible, t.marge_brute_cible, t.date_fin_validite, t.est_courant
                             EXCEPT
                             SELECT s.sku, s.nom_produit, s.marque, s.categorie, s.sous_categorie, s.fournisseur_id, s.taux_tva, s.gamme_prix, s.statut_produit,
                                    s.prix_catalogue_ttc, s.cout_achat_unitaire_ht, s.taux_retour_cible, s.marge_brute_cible, s.date_fin_validite, s.est_courant)
                    OR t.est_supprime = 1 THEN
        UPDATE SET sku = s.sku, nom_produit = s.nom_produit, marque = s.marque, categorie = s.categorie, sous_categorie = s.sous_categorie,
                   fournisseur_id = s.fournisseur_id, taux_tva = s.taux_tva, gamme_prix = s.gamme_prix, statut_produit = s.statut_produit,
                   prix_catalogue_ttc = s.prix_catalogue_ttc, cout_achat_unitaire_ht = s.cout_achat_unitaire_ht, taux_retour_cible = s.taux_retour_cible,
                   marge_brute_cible = s.marge_brute_cible, date_fin_validite = s.date_fin_validite, est_courant = s.est_courant,
                   est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (produit_id, prix_id, sku, nom_produit, marque, categorie, sous_categorie, fournisseur_id, taux_tva, gamme_prix, statut_produit,
                prix_catalogue_ttc, cout_achat_unitaire_ht, taux_retour_cible, marge_brute_cible, date_debut_validite, date_fin_validite, est_courant,
                id_chargement, date_maj)
        VALUES (s.produit_id, s.prix_id, s.sku, s.nom_produit, s.marque, s.categorie, s.sous_categorie, s.fournisseur_id, s.taux_tva, s.gamme_prix,
                s.statut_produit, s.prix_catalogue_ttc, s.cout_achat_unitaire_ht, s.taux_retour_cible, s.marge_brute_cible, s.date_debut_validite,
                s.date_fin_validite, s.est_courant, @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.produit_sk > 0 AND t.est_supprime = 0 THEN
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.dim_produit',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_dim_produit';
        THROW;
    END CATCH
END;
GO

/* usp_charger_fact_ventes — Ventes (grain ligne de commande) — MERGE sur ligne_id */
CREATE OR ALTER PROCEDURE dw.usp_charger_fact_ventes
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    SELECT l.ligne_id AS [ligne_id],
               l.commande_id AS [commande_id],
               COALESCE(YEAR(c.date_commande) * 10000 + MONTH(c.date_commande) * 100 + DAY(c.date_commande), -2) AS [date_commande_sk],
               COALESCE(kcl.client_sk, -1) AS [client_sk],
               COALESCE(kpr.produit_sk, -1) AS [produit_sk],
               COALESCE(g.geographie_sk, -1) AS [geographie_sk],
               CASE WHEN c.entrepot_id IS NULL THEN -2 ELSE COALESCE(e.entrepot_sk, -1) END AS [entrepot_sk],
               COALESCE(ca.canal_sk, -1) AS [canal_sk],
               CASE WHEN c.campagne_id IS NULL THEN -2 ELSE COALESCE(cp.campagne_sk, -1) END AS [campagne_sk],
               CASE WHEN c.code_coupon IS NULL THEN -2 ELSE COALESCE(co.coupon_sk, -1) END AS [coupon_sk],
               COALESCE(st.statut_commande_sk, -1) AS [statut_commande_sk],
               l.quantite AS [quantite],
               l.prix_catalogue_ttc AS [prix_catalogue_ttc],
               l.prix_unitaire_ttc AS [prix_unitaire_ttc],
               l.quantite * l.prix_catalogue_ttc AS [montant_brut_ttc],
               l.montant_remise_promo_ttc AS [montant_remise_promo_ttc],
               l.montant_ligne_ttc AS [montant_ttc],
               l.montant_ligne_ht AS [montant_ht],
               l.montant_tva AS [montant_tva],
               l.cout_achat_total_ht AS [cout_achat_ht],
               l.marge_brute_ht AS [marge_brute_ht],
               COALESCE(st.est_ca_reconnu, CAST(0 AS BIT)) AS [est_ca_reconnu]   -- règle portée par dw.dim_statut_commande (indépendante du staging)
    INTO #src
    FROM [TuniShop_STG_INTEGRATED].integ.v_ligne_commande l
    JOIN [TuniShop_STG_INTEGRATED].integ.v_commande c ON c.commande_id = l.commande_id
    OUTER APPLY (SELECT TOP (1) dc.client_sk FROM dw.dim_client dc
                 WHERE dc.client_id = c.client_id AND dc.date_debut_validite <= CAST(c.date_commande AS DATE)
                 ORDER BY dc.date_debut_validite DESC) kcl
    OUTER APPLY (SELECT TOP (1) dp.produit_sk FROM dw.dim_produit dp
                 WHERE dp.produit_id = l.produit_id
                 ORDER BY CASE WHEN CAST(c.date_commande AS DATE) BETWEEN dp.date_debut_validite AND dp.date_fin_validite THEN 0 ELSE 1 END,
                          ABS(DATEDIFF(DAY, dp.date_debut_validite, CAST(c.date_commande AS DATE)))) kpr
    LEFT JOIN dw.dim_geographie g ON g.gouvernorat_id = c.gouvernorat_livraison_id
    LEFT JOIN dw.dim_entrepot e ON e.entrepot_id = c.entrepot_id
    LEFT JOIN dw.dim_canal ca ON ca.canal = c.canal AND ca.appareil = c.appareil
    LEFT JOIN dw.dim_campagne cp ON cp.campagne_id = c.campagne_id
    LEFT JOIN dw.dim_coupon co ON co.code_coupon = c.code_coupon
    LEFT JOIN dw.dim_statut_commande st ON st.statut_commande = c.statut_commande;

    MERGE dw.[fact_ventes] AS t
    USING #src AS s
    ON t.[ligne_id] = s.[ligne_id]
    WHEN MATCHED AND (EXISTS (SELECT t.[commande_id], t.[date_commande_sk], t.[client_sk], t.[produit_sk], t.[geographie_sk], t.[entrepot_sk], t.[canal_sk], t.[campagne_sk], t.[coupon_sk], t.[statut_commande_sk], t.[quantite], t.[prix_catalogue_ttc], t.[prix_unitaire_ttc], t.[montant_brut_ttc], t.[montant_remise_promo_ttc], t.[montant_ttc], t.[montant_ht], t.[montant_tva], t.[cout_achat_ht], t.[marge_brute_ht], t.[est_ca_reconnu] EXCEPT SELECT s.[commande_id], s.[date_commande_sk], s.[client_sk], s.[produit_sk], s.[geographie_sk], s.[entrepot_sk], s.[canal_sk], s.[campagne_sk], s.[coupon_sk], s.[statut_commande_sk], s.[quantite], s.[prix_catalogue_ttc], s.[prix_unitaire_ttc], s.[montant_brut_ttc], s.[montant_remise_promo_ttc], s.[montant_ttc], s.[montant_ht], s.[montant_tva], s.[cout_achat_ht], s.[marge_brute_ht], s.[est_ca_reconnu]) OR t.est_supprime = 1) THEN
        UPDATE SET [commande_id] = s.[commande_id], [date_commande_sk] = s.[date_commande_sk], [client_sk] = s.[client_sk], [produit_sk] = s.[produit_sk], [geographie_sk] = s.[geographie_sk], [entrepot_sk] = s.[entrepot_sk], [canal_sk] = s.[canal_sk], [campagne_sk] = s.[campagne_sk], [coupon_sk] = s.[coupon_sk], [statut_commande_sk] = s.[statut_commande_sk], [quantite] = s.[quantite], [prix_catalogue_ttc] = s.[prix_catalogue_ttc], [prix_unitaire_ttc] = s.[prix_unitaire_ttc], [montant_brut_ttc] = s.[montant_brut_ttc], [montant_remise_promo_ttc] = s.[montant_remise_promo_ttc], [montant_ttc] = s.[montant_ttc], [montant_ht] = s.[montant_ht], [montant_tva] = s.[montant_tva], [cout_achat_ht] = s.[cout_achat_ht], [marge_brute_ht] = s.[marge_brute_ht], [est_ca_reconnu] = s.[est_ca_reconnu], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([ligne_id], [commande_id], [date_commande_sk], [client_sk], [produit_sk], [geographie_sk], [entrepot_sk], [canal_sk], [campagne_sk], [coupon_sk], [statut_commande_sk], [quantite], [prix_catalogue_ttc], [prix_unitaire_ttc], [montant_brut_ttc], [montant_remise_promo_ttc], [montant_ttc], [montant_ht], [montant_tva], [cout_achat_ht], [marge_brute_ht], [est_ca_reconnu], id_chargement, date_maj)
        VALUES (s.[ligne_id], s.[commande_id], s.[date_commande_sk], s.[client_sk], s.[produit_sk], s.[geographie_sk], s.[entrepot_sk], s.[canal_sk], s.[campagne_sk], s.[coupon_sk], s.[statut_commande_sk], s.[quantite], s.[prix_catalogue_ttc], s.[prix_unitaire_ttc], s.[montant_brut_ttc], s.[montant_remise_promo_ttc], s.[montant_ttc], s.[montant_ht], s.[montant_tva], s.[cout_achat_ht], s.[marge_brute_ht], s.[est_ca_reconnu], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.est_supprime = 0 THEN                      -- disparue du staging : marquée, exclue des vues bi
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.fact_ventes',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_fact_ventes';
        THROW;
    END CATCH
END;
GO

/* usp_charger_fact_commandes — Commandes (snapshot accumulé) — MERGE sur commande_id, mis à jour à chaque étape du cycle de vie */
CREATE OR ALTER PROCEDURE dw.usp_charger_fact_commandes
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    SELECT c.commande_id AS [commande_id],
               COALESCE(YEAR(c.date_commande) * 10000 + MONTH(c.date_commande) * 100 + DAY(c.date_commande), -2) AS [date_commande_sk],
               COALESCE(YEAR(v.date_expedition) * 10000 + MONTH(v.date_expedition) * 100 + DAY(v.date_expedition), -2) AS [date_expedition_sk],
               COALESCE(YEAR(v.date_livraison_reelle) * 10000 + MONTH(v.date_livraison_reelle) * 100 + DAY(v.date_livraison_reelle), -2) AS [date_livraison_sk],
               COALESCE(YEAR(c.date_annulation) * 10000 + MONTH(c.date_annulation) * 100 + DAY(c.date_annulation), -2) AS [date_annulation_sk],
               COALESCE(kcl.client_sk, -1) AS [client_sk],
               COALESCE(g.geographie_sk, -1) AS [geographie_sk],
               CASE WHEN c.entrepot_id IS NULL THEN -2 ELSE COALESCE(e.entrepot_sk, -1) END AS [entrepot_sk],
               COALESCE(ca.canal_sk, -1) AS [canal_sk],
               CASE WHEN c.campagne_id IS NULL THEN -2 ELSE COALESCE(cp.campagne_sk, -1) END AS [campagne_sk],
               CASE WHEN c.code_coupon IS NULL THEN -2 ELSE COALESCE(co.coupon_sk, -1) END AS [coupon_sk],
               COALESCE(mp.mode_paiement_sk, -1) AS [mode_paiement_sk],
               COALESCE(st.statut_commande_sk, -1) AS [statut_commande_sk],
               c.nb_lignes AS [nb_lignes],
               c.nb_articles AS [nb_articles],
               c.sous_total_ttc AS [sous_total_ttc],
               c.remise_coupon_ttc AS [remise_coupon_ttc],
               c.frais_livraison_ttc AS [frais_livraison_ttc],
               c.montant_total_ttc AS [montant_total_ttc],
               c.cout_achat_total_ht AS [cout_achat_ht],
               v.cout_transport_ht AS [cout_transport_ht],
               COALESCE(rb.rembourse, 0) AS [montant_rembourse_ttc],
               pa.nb AS [nb_tentatives_paiement],
               v.delai_livraison_j AS [delai_livraison_j],
               c.est_premiere_commande AS [est_premiere_commande],
               v.est_livree_a_temps AS [est_livree_a_temps],
               COALESCE(st.est_ca_reconnu, CAST(0 AS BIT)) AS [est_ca_reconnu]   -- règle portée par dw.dim_statut_commande (indépendante du staging)
    INTO #src
    FROM [TuniShop_STG_INTEGRATED].integ.v_commande c
    LEFT JOIN [TuniShop_STG_INTEGRATED].integ.v_livraison v ON v.commande_id = c.commande_id
    OUTER APPLY (SELECT SUM(r.montant_rembourse_ttc) AS rembourse FROM [TuniShop_STG_INTEGRATED].integ.v_remboursement r WHERE r.commande_id = c.commande_id AND r.statut = 'rembourse') rb
    OUTER APPLY (SELECT COUNT(*) AS nb FROM [TuniShop_STG_INTEGRATED].integ.v_paiement p WHERE p.commande_id = c.commande_id) pa
    OUTER APPLY (SELECT TOP (1) dc.client_sk FROM dw.dim_client dc
                 WHERE dc.client_id = c.client_id AND dc.date_debut_validite <= CAST(c.date_commande AS DATE)
                 ORDER BY dc.date_debut_validite DESC) kcl
    LEFT JOIN dw.dim_geographie g ON g.gouvernorat_id = c.gouvernorat_livraison_id
    LEFT JOIN dw.dim_entrepot e ON e.entrepot_id = c.entrepot_id
    LEFT JOIN dw.dim_canal ca ON ca.canal = c.canal AND ca.appareil = c.appareil
    LEFT JOIN dw.dim_campagne cp ON cp.campagne_id = c.campagne_id
    LEFT JOIN dw.dim_coupon co ON co.code_coupon = c.code_coupon
    LEFT JOIN dw.dim_mode_paiement mp ON mp.mode_paiement = c.mode_paiement
    LEFT JOIN dw.dim_statut_commande st ON st.statut_commande = c.statut_commande;

    MERGE dw.[fact_commandes] AS t
    USING #src AS s
    ON t.[commande_id] = s.[commande_id]
    WHEN MATCHED AND (EXISTS (SELECT t.[date_commande_sk], t.[date_expedition_sk], t.[date_livraison_sk], t.[date_annulation_sk], t.[client_sk], t.[geographie_sk], t.[entrepot_sk], t.[canal_sk], t.[campagne_sk], t.[coupon_sk], t.[mode_paiement_sk], t.[statut_commande_sk], t.[nb_lignes], t.[nb_articles], t.[sous_total_ttc], t.[remise_coupon_ttc], t.[frais_livraison_ttc], t.[montant_total_ttc], t.[cout_achat_ht], t.[cout_transport_ht], t.[montant_rembourse_ttc], t.[nb_tentatives_paiement], t.[delai_livraison_j], t.[est_premiere_commande], t.[est_livree_a_temps], t.[est_ca_reconnu] EXCEPT SELECT s.[date_commande_sk], s.[date_expedition_sk], s.[date_livraison_sk], s.[date_annulation_sk], s.[client_sk], s.[geographie_sk], s.[entrepot_sk], s.[canal_sk], s.[campagne_sk], s.[coupon_sk], s.[mode_paiement_sk], s.[statut_commande_sk], s.[nb_lignes], s.[nb_articles], s.[sous_total_ttc], s.[remise_coupon_ttc], s.[frais_livraison_ttc], s.[montant_total_ttc], s.[cout_achat_ht], s.[cout_transport_ht], s.[montant_rembourse_ttc], s.[nb_tentatives_paiement], s.[delai_livraison_j], s.[est_premiere_commande], s.[est_livree_a_temps], s.[est_ca_reconnu]) OR t.est_supprime = 1) THEN
        UPDATE SET [date_commande_sk] = s.[date_commande_sk], [date_expedition_sk] = s.[date_expedition_sk], [date_livraison_sk] = s.[date_livraison_sk], [date_annulation_sk] = s.[date_annulation_sk], [client_sk] = s.[client_sk], [geographie_sk] = s.[geographie_sk], [entrepot_sk] = s.[entrepot_sk], [canal_sk] = s.[canal_sk], [campagne_sk] = s.[campagne_sk], [coupon_sk] = s.[coupon_sk], [mode_paiement_sk] = s.[mode_paiement_sk], [statut_commande_sk] = s.[statut_commande_sk], [nb_lignes] = s.[nb_lignes], [nb_articles] = s.[nb_articles], [sous_total_ttc] = s.[sous_total_ttc], [remise_coupon_ttc] = s.[remise_coupon_ttc], [frais_livraison_ttc] = s.[frais_livraison_ttc], [montant_total_ttc] = s.[montant_total_ttc], [cout_achat_ht] = s.[cout_achat_ht], [cout_transport_ht] = s.[cout_transport_ht], [montant_rembourse_ttc] = s.[montant_rembourse_ttc], [nb_tentatives_paiement] = s.[nb_tentatives_paiement], [delai_livraison_j] = s.[delai_livraison_j], [est_premiere_commande] = s.[est_premiere_commande], [est_livree_a_temps] = s.[est_livree_a_temps], [est_ca_reconnu] = s.[est_ca_reconnu], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([commande_id], [date_commande_sk], [date_expedition_sk], [date_livraison_sk], [date_annulation_sk], [client_sk], [geographie_sk], [entrepot_sk], [canal_sk], [campagne_sk], [coupon_sk], [mode_paiement_sk], [statut_commande_sk], [nb_lignes], [nb_articles], [sous_total_ttc], [remise_coupon_ttc], [frais_livraison_ttc], [montant_total_ttc], [cout_achat_ht], [cout_transport_ht], [montant_rembourse_ttc], [nb_tentatives_paiement], [delai_livraison_j], [est_premiere_commande], [est_livree_a_temps], [est_ca_reconnu], id_chargement, date_maj)
        VALUES (s.[commande_id], s.[date_commande_sk], s.[date_expedition_sk], s.[date_livraison_sk], s.[date_annulation_sk], s.[client_sk], s.[geographie_sk], s.[entrepot_sk], s.[canal_sk], s.[campagne_sk], s.[coupon_sk], s.[mode_paiement_sk], s.[statut_commande_sk], s.[nb_lignes], s.[nb_articles], s.[sous_total_ttc], s.[remise_coupon_ttc], s.[frais_livraison_ttc], s.[montant_total_ttc], s.[cout_achat_ht], s.[cout_transport_ht], s.[montant_rembourse_ttc], s.[nb_tentatives_paiement], s.[delai_livraison_j], s.[est_premiere_commande], s.[est_livree_a_temps], s.[est_ca_reconnu], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.est_supprime = 0 THEN                      -- disparue du staging : marquée, exclue des vues bi
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.fact_commandes',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_fact_commandes';
        THROW;
    END CATCH
END;
GO

/* usp_charger_fact_paiements — Tentatives de paiement — MERGE sur paiement_id */
CREATE OR ALTER PROCEDURE dw.usp_charger_fact_paiements
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    SELECT p.paiement_id AS [paiement_id],
               p.commande_id AS [commande_id],
               COALESCE(YEAR(p.date_paiement) * 10000 + MONTH(p.date_paiement) * 100 + DAY(p.date_paiement), -2) AS [date_paiement_sk],
               COALESCE(YEAR(p.date_reversement) * 10000 + MONTH(p.date_reversement) * 100 + DAY(p.date_reversement), -2) AS [date_reversement_sk],
               COALESCE(kcl.client_sk, -1) AS [client_sk],
               COALESCE(mp.mode_paiement_sk, -1) AS [mode_paiement_sk],
               p.num_tentative AS [num_tentative],
               p.statut_paiement AS [statut_paiement],
               p.code_erreur AS [code_erreur],
               p.prestataire AS [prestataire],
               p.montant_ttc AS [montant_ttc],
               p.est_reussi AS [est_reussi],
               p.delai_reversement_j AS [delai_reversement_j]
    INTO #src
    FROM [TuniShop_STG_INTEGRATED].integ.v_paiement p
    JOIN [TuniShop_STG_INTEGRATED].integ.v_commande c ON c.commande_id = p.commande_id
    OUTER APPLY (SELECT TOP (1) dc.client_sk FROM dw.dim_client dc
                 WHERE dc.client_id = c.client_id AND dc.date_debut_validite <= CAST(p.date_paiement AS DATE)
                 ORDER BY dc.date_debut_validite DESC) kcl
    LEFT JOIN dw.dim_mode_paiement mp ON mp.mode_paiement = p.mode_paiement;

    MERGE dw.[fact_paiements] AS t
    USING #src AS s
    ON t.[paiement_id] = s.[paiement_id]
    WHEN MATCHED AND (EXISTS (SELECT t.[commande_id], t.[date_paiement_sk], t.[date_reversement_sk], t.[client_sk], t.[mode_paiement_sk], t.[num_tentative], t.[statut_paiement], t.[code_erreur], t.[prestataire], t.[montant_ttc], t.[est_reussi], t.[delai_reversement_j] EXCEPT SELECT s.[commande_id], s.[date_paiement_sk], s.[date_reversement_sk], s.[client_sk], s.[mode_paiement_sk], s.[num_tentative], s.[statut_paiement], s.[code_erreur], s.[prestataire], s.[montant_ttc], s.[est_reussi], s.[delai_reversement_j]) OR t.est_supprime = 1) THEN
        UPDATE SET [commande_id] = s.[commande_id], [date_paiement_sk] = s.[date_paiement_sk], [date_reversement_sk] = s.[date_reversement_sk], [client_sk] = s.[client_sk], [mode_paiement_sk] = s.[mode_paiement_sk], [num_tentative] = s.[num_tentative], [statut_paiement] = s.[statut_paiement], [code_erreur] = s.[code_erreur], [prestataire] = s.[prestataire], [montant_ttc] = s.[montant_ttc], [est_reussi] = s.[est_reussi], [delai_reversement_j] = s.[delai_reversement_j], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([paiement_id], [commande_id], [date_paiement_sk], [date_reversement_sk], [client_sk], [mode_paiement_sk], [num_tentative], [statut_paiement], [code_erreur], [prestataire], [montant_ttc], [est_reussi], [delai_reversement_j], id_chargement, date_maj)
        VALUES (s.[paiement_id], s.[commande_id], s.[date_paiement_sk], s.[date_reversement_sk], s.[client_sk], s.[mode_paiement_sk], s.[num_tentative], s.[statut_paiement], s.[code_erreur], s.[prestataire], s.[montant_ttc], s.[est_reussi], s.[delai_reversement_j], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.est_supprime = 0 THEN                      -- disparue du staging : marquée, exclue des vues bi
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.fact_paiements',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_fact_paiements';
        THROW;
    END CATCH
END;
GO

/* usp_charger_fact_livraisons — Expéditions — MERGE sur livraison_id */
CREATE OR ALTER PROCEDURE dw.usp_charger_fact_livraisons
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    SELECT v.livraison_id AS [livraison_id],
               v.commande_id AS [commande_id],
               COALESCE(YEAR(v.date_expedition) * 10000 + MONTH(v.date_expedition) * 100 + DAY(v.date_expedition), -2) AS [date_expedition_sk],
               COALESCE(YEAR(v.date_livraison_prevue) * 10000 + MONTH(v.date_livraison_prevue) * 100 + DAY(v.date_livraison_prevue), -2) AS [date_prevue_sk],
               COALESCE(YEAR(v.date_livraison_reelle) * 10000 + MONTH(v.date_livraison_reelle) * 100 + DAY(v.date_livraison_reelle), -2) AS [date_livraison_sk],
               COALESCE(kcl.client_sk, -1) AS [client_sk],
               COALESCE(e.entrepot_sk, -1) AS [entrepot_sk],
               COALESCE(tr.transporteur_sk, -1) AS [transporteur_sk],
               COALESCE(g.geographie_sk, -1) AS [geographie_sk],
               v.statut_livraison AS [statut_livraison],
               v.nb_tentatives AS [nb_tentatives],
               v.poids_kg AS [poids_kg],
               v.cout_transport_ht AS [cout_transport_ht],
               v.delai_preparation_h AS [delai_preparation_h],
               v.delai_livraison_j AS [delai_livraison_j],
               v.retard_j AS [retard_j],
               CAST(CASE WHEN v.statut_livraison = 'livree' THEN 1 ELSE 0 END AS BIT) AS [est_livree],
               v.est_livree_a_temps AS [est_livree_a_temps],
               v.est_premiere_tentative AS [est_premiere_tentative]
    INTO #src
    FROM [TuniShop_STG_INTEGRATED].integ.v_livraison v
    JOIN [TuniShop_STG_INTEGRATED].integ.v_commande c ON c.commande_id = v.commande_id
    OUTER APPLY (SELECT TOP (1) dc.client_sk FROM dw.dim_client dc
                 WHERE dc.client_id = c.client_id AND dc.date_debut_validite <= CAST(c.date_commande AS DATE)
                 ORDER BY dc.date_debut_validite DESC) kcl
    LEFT JOIN dw.dim_entrepot e ON e.entrepot_id = v.entrepot_id
    LEFT JOIN dw.dim_transporteur tr ON tr.transporteur_id = v.transporteur_id
    LEFT JOIN dw.dim_geographie g ON g.gouvernorat_id = v.gouvernorat_destination_id;

    MERGE dw.[fact_livraisons] AS t
    USING #src AS s
    ON t.[livraison_id] = s.[livraison_id]
    WHEN MATCHED AND (EXISTS (SELECT t.[commande_id], t.[date_expedition_sk], t.[date_prevue_sk], t.[date_livraison_sk], t.[client_sk], t.[entrepot_sk], t.[transporteur_sk], t.[geographie_sk], t.[statut_livraison], t.[nb_tentatives], t.[poids_kg], t.[cout_transport_ht], t.[delai_preparation_h], t.[delai_livraison_j], t.[retard_j], t.[est_livree], t.[est_livree_a_temps], t.[est_premiere_tentative] EXCEPT SELECT s.[commande_id], s.[date_expedition_sk], s.[date_prevue_sk], s.[date_livraison_sk], s.[client_sk], s.[entrepot_sk], s.[transporteur_sk], s.[geographie_sk], s.[statut_livraison], s.[nb_tentatives], s.[poids_kg], s.[cout_transport_ht], s.[delai_preparation_h], s.[delai_livraison_j], s.[retard_j], s.[est_livree], s.[est_livree_a_temps], s.[est_premiere_tentative]) OR t.est_supprime = 1) THEN
        UPDATE SET [commande_id] = s.[commande_id], [date_expedition_sk] = s.[date_expedition_sk], [date_prevue_sk] = s.[date_prevue_sk], [date_livraison_sk] = s.[date_livraison_sk], [client_sk] = s.[client_sk], [entrepot_sk] = s.[entrepot_sk], [transporteur_sk] = s.[transporteur_sk], [geographie_sk] = s.[geographie_sk], [statut_livraison] = s.[statut_livraison], [nb_tentatives] = s.[nb_tentatives], [poids_kg] = s.[poids_kg], [cout_transport_ht] = s.[cout_transport_ht], [delai_preparation_h] = s.[delai_preparation_h], [delai_livraison_j] = s.[delai_livraison_j], [retard_j] = s.[retard_j], [est_livree] = s.[est_livree], [est_livree_a_temps] = s.[est_livree_a_temps], [est_premiere_tentative] = s.[est_premiere_tentative], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([livraison_id], [commande_id], [date_expedition_sk], [date_prevue_sk], [date_livraison_sk], [client_sk], [entrepot_sk], [transporteur_sk], [geographie_sk], [statut_livraison], [nb_tentatives], [poids_kg], [cout_transport_ht], [delai_preparation_h], [delai_livraison_j], [retard_j], [est_livree], [est_livree_a_temps], [est_premiere_tentative], id_chargement, date_maj)
        VALUES (s.[livraison_id], s.[commande_id], s.[date_expedition_sk], s.[date_prevue_sk], s.[date_livraison_sk], s.[client_sk], s.[entrepot_sk], s.[transporteur_sk], s.[geographie_sk], s.[statut_livraison], s.[nb_tentatives], s.[poids_kg], s.[cout_transport_ht], s.[delai_preparation_h], s.[delai_livraison_j], s.[retard_j], s.[est_livree], s.[est_livree_a_temps], s.[est_premiere_tentative], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.est_supprime = 0 THEN                      -- disparue du staging : marquée, exclue des vues bi
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.fact_livraisons',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_fact_livraisons';
        THROW;
    END CATCH
END;
GO

/* usp_charger_fact_remboursements — Remboursements — MERGE sur remboursement_id */
CREATE OR ALTER PROCEDURE dw.usp_charger_fact_remboursements
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    SELECT r.remboursement_id AS [remboursement_id],
               r.commande_id AS [commande_id],
               COALESCE(YEAR(r.date_demande) * 10000 + MONTH(r.date_demande) * 100 + DAY(r.date_demande), -2) AS [date_demande_sk],
               COALESCE(YEAR(r.date_remboursement) * 10000 + MONTH(r.date_remboursement) * 100 + DAY(r.date_remboursement), -2) AS [date_remboursement_sk],
               COALESCE(kcl.client_sk, -1) AS [client_sk],
               CASE WHEN r.produit_id IS NULL THEN -2 ELSE COALESCE(kpr.produit_sk, -1) END AS [produit_sk],
               COALESCE(mr.motif_retour_sk, -1) AS [motif_retour_sk],
               r.mode_remboursement AS [mode_remboursement],
               r.statut AS [statut],
               r.etat_article AS [etat_article],
               r.quantite AS [quantite],
               r.montant_demande_ttc AS [montant_demande_ttc],
               r.montant_rembourse_ttc AS [montant_rembourse_ttc],
               r.delai_traitement_j AS [delai_traitement_j]
    INTO #src
    FROM [TuniShop_STG_INTEGRATED].integ.v_remboursement r
    JOIN [TuniShop_STG_INTEGRATED].integ.v_commande c ON c.commande_id = r.commande_id
    OUTER APPLY (SELECT TOP (1) dc.client_sk FROM dw.dim_client dc
                 WHERE dc.client_id = c.client_id AND dc.date_debut_validite <= CAST(c.date_commande AS DATE)
                 ORDER BY dc.date_debut_validite DESC) kcl
    OUTER APPLY (SELECT TOP (1) dp.produit_sk FROM dw.dim_produit dp
                 WHERE dp.produit_id = r.produit_id
                 ORDER BY CASE WHEN CAST(c.date_commande AS DATE) BETWEEN dp.date_debut_validite AND dp.date_fin_validite THEN 0 ELSE 1 END,
                          ABS(DATEDIFF(DAY, dp.date_debut_validite, CAST(c.date_commande AS DATE)))) kpr
    LEFT JOIN dw.dim_motif_retour mr ON mr.type_remboursement = r.type_remboursement AND mr.motif = r.motif;

    MERGE dw.[fact_remboursements] AS t
    USING #src AS s
    ON t.[remboursement_id] = s.[remboursement_id]
    WHEN MATCHED AND (EXISTS (SELECT t.[commande_id], t.[date_demande_sk], t.[date_remboursement_sk], t.[client_sk], t.[produit_sk], t.[motif_retour_sk], t.[mode_remboursement], t.[statut], t.[etat_article], t.[quantite], t.[montant_demande_ttc], t.[montant_rembourse_ttc], t.[delai_traitement_j] EXCEPT SELECT s.[commande_id], s.[date_demande_sk], s.[date_remboursement_sk], s.[client_sk], s.[produit_sk], s.[motif_retour_sk], s.[mode_remboursement], s.[statut], s.[etat_article], s.[quantite], s.[montant_demande_ttc], s.[montant_rembourse_ttc], s.[delai_traitement_j]) OR t.est_supprime = 1) THEN
        UPDATE SET [commande_id] = s.[commande_id], [date_demande_sk] = s.[date_demande_sk], [date_remboursement_sk] = s.[date_remboursement_sk], [client_sk] = s.[client_sk], [produit_sk] = s.[produit_sk], [motif_retour_sk] = s.[motif_retour_sk], [mode_remboursement] = s.[mode_remboursement], [statut] = s.[statut], [etat_article] = s.[etat_article], [quantite] = s.[quantite], [montant_demande_ttc] = s.[montant_demande_ttc], [montant_rembourse_ttc] = s.[montant_rembourse_ttc], [delai_traitement_j] = s.[delai_traitement_j], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([remboursement_id], [commande_id], [date_demande_sk], [date_remboursement_sk], [client_sk], [produit_sk], [motif_retour_sk], [mode_remboursement], [statut], [etat_article], [quantite], [montant_demande_ttc], [montant_rembourse_ttc], [delai_traitement_j], id_chargement, date_maj)
        VALUES (s.[remboursement_id], s.[commande_id], s.[date_demande_sk], s.[date_remboursement_sk], s.[client_sk], s.[produit_sk], s.[motif_retour_sk], s.[mode_remboursement], s.[statut], s.[etat_article], s.[quantite], s.[montant_demande_ttc], s.[montant_rembourse_ttc], s.[delai_traitement_j], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.est_supprime = 0 THEN                      -- disparue du staging : marquée, exclue des vues bi
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.fact_remboursements',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_fact_remboursements';
        THROW;
    END CATCH
END;
GO

/* usp_charger_fact_avis — Avis — MERGE sur avis_id */
CREATE OR ALTER PROCEDURE dw.usp_charger_fact_avis
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    SELECT a.avis_id AS [avis_id],
               a.commande_id AS [commande_id],
               COALESCE(YEAR(a.date_avis) * 10000 + MONTH(a.date_avis) * 100 + DAY(a.date_avis), -2) AS [date_avis_sk],
               COALESCE(kcl.client_sk, -1) AS [client_sk],
               COALESCE(kpr.produit_sk, -1) AS [produit_sk],
               a.note AS [note],
               a.sentiment AS [sentiment],
               a.a_commentaire AS [a_commentaire],
               a.commentaire AS [commentaire]
    INTO #src
    FROM [TuniShop_STG_INTEGRATED].integ.v_avis a
    OUTER APPLY (SELECT TOP (1) dc.client_sk FROM dw.dim_client dc
                 WHERE dc.client_id = a.client_id AND dc.date_debut_validite <= CAST(a.date_avis AS DATE)
                 ORDER BY dc.date_debut_validite DESC) kcl
    OUTER APPLY (SELECT TOP (1) dp.produit_sk FROM dw.dim_produit dp
                 WHERE dp.produit_id = a.produit_id
                 ORDER BY CASE WHEN CAST(a.date_avis AS DATE) BETWEEN dp.date_debut_validite AND dp.date_fin_validite THEN 0 ELSE 1 END,
                          ABS(DATEDIFF(DAY, dp.date_debut_validite, CAST(a.date_avis AS DATE)))) kpr;

    MERGE dw.[fact_avis] AS t
    USING #src AS s
    ON t.[avis_id] = s.[avis_id]
    WHEN MATCHED AND (EXISTS (SELECT t.[commande_id], t.[date_avis_sk], t.[client_sk], t.[produit_sk], t.[note], t.[sentiment], t.[a_commentaire], t.[commentaire] EXCEPT SELECT s.[commande_id], s.[date_avis_sk], s.[client_sk], s.[produit_sk], s.[note], s.[sentiment], s.[a_commentaire], s.[commentaire]) OR t.est_supprime = 1) THEN
        UPDATE SET [commande_id] = s.[commande_id], [date_avis_sk] = s.[date_avis_sk], [client_sk] = s.[client_sk], [produit_sk] = s.[produit_sk], [note] = s.[note], [sentiment] = s.[sentiment], [a_commentaire] = s.[a_commentaire], [commentaire] = s.[commentaire], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([avis_id], [commande_id], [date_avis_sk], [client_sk], [produit_sk], [note], [sentiment], [a_commentaire], [commentaire], id_chargement, date_maj)
        VALUES (s.[avis_id], s.[commande_id], s.[date_avis_sk], s.[client_sk], s.[produit_sk], s.[note], s.[sentiment], s.[a_commentaire], s.[commentaire], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.est_supprime = 0 THEN                      -- disparue du staging : marquée, exclue des vues bi
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.fact_avis',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_fact_avis';
        THROW;
    END CATCH
END;
GO

/* usp_charger_fact_marketing_quotidien — Dépenses marketing quotidiennes — MERGE sur depense_id */
CREATE OR ALTER PROCEDURE dw.usp_charger_fact_marketing_quotidien
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    SELECT d.depense_id AS [depense_id],
               COALESCE(YEAR(d.[date]) * 10000 + MONTH(d.[date]) * 100 + DAY(d.[date]), -2) AS [date_sk],
               COALESCE(cp.campagne_sk, -1) AS [campagne_sk],
               d.depense_ht AS [depense_ht],
               d.impressions AS [impressions],
               d.clics AS [clics],
               d.commandes_attribuees AS [commandes_attribuees],
               d.nouveaux_clients_attribues AS [nouveaux_clients_attribues],
               d.ca_attribue_ttc AS [ca_attribue_ttc]
    INTO #src
    FROM [TuniShop_STG_INTEGRATED].integ.v_depense_marketing d
    LEFT JOIN dw.dim_campagne cp ON cp.campagne_id = d.campagne_id;

    MERGE dw.[fact_marketing_quotidien] AS t
    USING #src AS s
    ON t.[depense_id] = s.[depense_id]
    WHEN MATCHED AND (EXISTS (SELECT t.[date_sk], t.[campagne_sk], t.[depense_ht], t.[impressions], t.[clics], t.[commandes_attribuees], t.[nouveaux_clients_attribues], t.[ca_attribue_ttc] EXCEPT SELECT s.[date_sk], s.[campagne_sk], s.[depense_ht], s.[impressions], s.[clics], s.[commandes_attribuees], s.[nouveaux_clients_attribues], s.[ca_attribue_ttc]) OR t.est_supprime = 1) THEN
        UPDATE SET [date_sk] = s.[date_sk], [campagne_sk] = s.[campagne_sk], [depense_ht] = s.[depense_ht], [impressions] = s.[impressions], [clics] = s.[clics], [commandes_attribuees] = s.[commandes_attribuees], [nouveaux_clients_attribues] = s.[nouveaux_clients_attribues], [ca_attribue_ttc] = s.[ca_attribue_ttc], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([depense_id], [date_sk], [campagne_sk], [depense_ht], [impressions], [clics], [commandes_attribuees], [nouveaux_clients_attribues], [ca_attribue_ttc], id_chargement, date_maj)
        VALUES (s.[depense_id], s.[date_sk], s.[campagne_sk], s.[depense_ht], s.[impressions], s.[clics], s.[commandes_attribuees], s.[nouveaux_clients_attribues], s.[ca_attribue_ttc], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.est_supprime = 0 THEN                      -- disparue du staging : marquée, exclue des vues bi
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.fact_marketing_quotidien',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_fact_marketing_quotidien';
        THROW;
    END CATCH
END;
GO

/* usp_charger_fact_achats_fournisseur — Achats fournisseurs — MERGE sur ligne_cf_id */
CREATE OR ALTER PROCEDURE dw.usp_charger_fact_achats_fournisseur
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    SELECT l.ligne_cf_id AS [ligne_cf_id],
               l.commande_fournisseur_id AS [commande_fournisseur_id],
               COALESCE(YEAR(cf.date_commande) * 10000 + MONTH(cf.date_commande) * 100 + DAY(cf.date_commande), -2) AS [date_commande_sk],
               COALESCE(YEAR(cf.date_livraison_prevue) * 10000 + MONTH(cf.date_livraison_prevue) * 100 + DAY(cf.date_livraison_prevue), -2) AS [date_prevue_sk],
               COALESCE(YEAR(cf.date_reception) * 10000 + MONTH(cf.date_reception) * 100 + DAY(cf.date_reception), -2) AS [date_reception_sk],
               COALESCE(f.fournisseur_sk, -1) AS [fournisseur_sk],
               COALESCE(kpr.produit_sk, -1) AS [produit_sk],
               COALESCE(e.entrepot_sk, -1) AS [entrepot_sk],
               cf.statut AS [statut],
               l.quantite_commandee AS [quantite_commandee],
               l.quantite_recue AS [quantite_recue],
               l.cout_unitaire_ht AS [cout_unitaire_ht],
               l.montant_ligne_ht AS [montant_ht],
               cf.delai_appro_reel_j AS [delai_appro_reel_j],
               cf.retard_appro_j AS [retard_appro_j]
    INTO #src
    FROM [TuniShop_STG_INTEGRATED].integ.v_ligne_commande_fournisseur l
    JOIN [TuniShop_STG_INTEGRATED].integ.v_commande_fournisseur cf ON cf.commande_fournisseur_id = l.commande_fournisseur_id
    LEFT JOIN dw.dim_fournisseur f ON f.fournisseur_id = cf.fournisseur_id
    OUTER APPLY (SELECT TOP (1) dp.produit_sk FROM dw.dim_produit dp
                 WHERE dp.produit_id = l.produit_id
                 ORDER BY CASE WHEN CAST(cf.date_commande AS DATE) BETWEEN dp.date_debut_validite AND dp.date_fin_validite THEN 0 ELSE 1 END,
                          ABS(DATEDIFF(DAY, dp.date_debut_validite, CAST(cf.date_commande AS DATE)))) kpr
    LEFT JOIN dw.dim_entrepot e ON e.entrepot_id = cf.entrepot_id;

    MERGE dw.[fact_achats_fournisseur] AS t
    USING #src AS s
    ON t.[ligne_cf_id] = s.[ligne_cf_id]
    WHEN MATCHED AND (EXISTS (SELECT t.[commande_fournisseur_id], t.[date_commande_sk], t.[date_prevue_sk], t.[date_reception_sk], t.[fournisseur_sk], t.[produit_sk], t.[entrepot_sk], t.[statut], t.[quantite_commandee], t.[quantite_recue], t.[cout_unitaire_ht], t.[montant_ht], t.[delai_appro_reel_j], t.[retard_appro_j] EXCEPT SELECT s.[commande_fournisseur_id], s.[date_commande_sk], s.[date_prevue_sk], s.[date_reception_sk], s.[fournisseur_sk], s.[produit_sk], s.[entrepot_sk], s.[statut], s.[quantite_commandee], s.[quantite_recue], s.[cout_unitaire_ht], s.[montant_ht], s.[delai_appro_reel_j], s.[retard_appro_j]) OR t.est_supprime = 1) THEN
        UPDATE SET [commande_fournisseur_id] = s.[commande_fournisseur_id], [date_commande_sk] = s.[date_commande_sk], [date_prevue_sk] = s.[date_prevue_sk], [date_reception_sk] = s.[date_reception_sk], [fournisseur_sk] = s.[fournisseur_sk], [produit_sk] = s.[produit_sk], [entrepot_sk] = s.[entrepot_sk], [statut] = s.[statut], [quantite_commandee] = s.[quantite_commandee], [quantite_recue] = s.[quantite_recue], [cout_unitaire_ht] = s.[cout_unitaire_ht], [montant_ht] = s.[montant_ht], [delai_appro_reel_j] = s.[delai_appro_reel_j], [retard_appro_j] = s.[retard_appro_j], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([ligne_cf_id], [commande_fournisseur_id], [date_commande_sk], [date_prevue_sk], [date_reception_sk], [fournisseur_sk], [produit_sk], [entrepot_sk], [statut], [quantite_commandee], [quantite_recue], [cout_unitaire_ht], [montant_ht], [delai_appro_reel_j], [retard_appro_j], id_chargement, date_maj)
        VALUES (s.[ligne_cf_id], s.[commande_fournisseur_id], s.[date_commande_sk], s.[date_prevue_sk], s.[date_reception_sk], s.[fournisseur_sk], s.[produit_sk], s.[entrepot_sk], s.[statut], s.[quantite_commandee], s.[quantite_recue], s.[cout_unitaire_ht], s.[montant_ht], s.[delai_appro_reel_j], s.[retard_appro_j], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.est_supprime = 0 THEN                      -- disparue du staging : marquée, exclue des vues bi
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.fact_achats_fournisseur',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_fact_achats_fournisseur';
        THROW;
    END CATCH
END;
GO

/* usp_charger_fact_mouvements_stock — Mouvements de stock — MERGE sur mouvement_id */
CREATE OR ALTER PROCEDURE dw.usp_charger_fact_mouvements_stock
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    SELECT m.mouvement_id AS [mouvement_id],
               COALESCE(YEAR(m.date_mouvement) * 10000 + MONTH(m.date_mouvement) * 100 + DAY(m.date_mouvement), -2) AS [date_sk],
               COALESCE(kpr.produit_sk, -1) AS [produit_sk],
               COALESCE(e.entrepot_sk, -1) AS [entrepot_sk],
               m.type_mouvement AS [type_mouvement],
               m.sens AS [sens],
               m.reference_id AS [reference_id],
               m.quantite AS [quantite],
               m.valeur_mouvement_ht AS [valeur_ht]
    INTO #src
    FROM [TuniShop_STG_INTEGRATED].integ.v_mouvement_stock m
    OUTER APPLY (SELECT TOP (1) dp.produit_sk FROM dw.dim_produit dp
                 WHERE dp.produit_id = m.produit_id
                 ORDER BY CASE WHEN CAST(m.date_mouvement AS DATE) BETWEEN dp.date_debut_validite AND dp.date_fin_validite THEN 0 ELSE 1 END,
                          ABS(DATEDIFF(DAY, dp.date_debut_validite, CAST(m.date_mouvement AS DATE)))) kpr
    LEFT JOIN dw.dim_entrepot e ON e.entrepot_id = m.entrepot_id;

    MERGE dw.[fact_mouvements_stock] AS t
    USING #src AS s
    ON t.[mouvement_id] = s.[mouvement_id]
    WHEN MATCHED AND (EXISTS (SELECT t.[date_sk], t.[produit_sk], t.[entrepot_sk], t.[type_mouvement], t.[sens], t.[reference_id], t.[quantite], t.[valeur_ht] EXCEPT SELECT s.[date_sk], s.[produit_sk], s.[entrepot_sk], s.[type_mouvement], s.[sens], s.[reference_id], s.[quantite], s.[valeur_ht]) OR t.est_supprime = 1) THEN
        UPDATE SET [date_sk] = s.[date_sk], [produit_sk] = s.[produit_sk], [entrepot_sk] = s.[entrepot_sk], [type_mouvement] = s.[type_mouvement], [sens] = s.[sens], [reference_id] = s.[reference_id], [quantite] = s.[quantite], [valeur_ht] = s.[valeur_ht], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([mouvement_id], [date_sk], [produit_sk], [entrepot_sk], [type_mouvement], [sens], [reference_id], [quantite], [valeur_ht], id_chargement, date_maj)
        VALUES (s.[mouvement_id], s.[date_sk], s.[produit_sk], s.[entrepot_sk], s.[type_mouvement], s.[sens], s.[reference_id], s.[quantite], s.[valeur_ht], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.est_supprime = 0 THEN                      -- disparue du staging : marquée, exclue des vues bi
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.fact_mouvements_stock',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_fact_mouvements_stock';
        THROW;
    END CATCH
END;
GO

/* usp_charger_fact_stock_mensuel — Stock de fin de mois — MERGE sur inventaire_id */
CREATE OR ALTER PROCEDURE dw.usp_charger_fact_stock_mensuel
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @ins INT = 0, @maj INT = 0, @sup INT = 0;
    DECLARE @actions TABLE (action NVARCHAR(10), supp_avant BIT, supp_apres BIT);
    BEGIN TRY
    BEGIN TRANSACTION;
    SELECT COALESCE(YEAR(s0.date_inventaire) * 10000 + MONTH(s0.date_inventaire) * 100 + DAY(s0.date_inventaire), -2) AS [date_sk],
               COALESCE(kpr.produit_sk, -1) AS [produit_sk],
               COALESCE(e.entrepot_sk, -1) AS [entrepot_sk],
               s0.inventaire_id AS [inventaire_id],
               s0.stock_fin_mois AS [stock_fin_mois],
               s0.quantite_en_commande AS [quantite_en_commande],
               s0.valeur_stock_ht AS [valeur_stock_ht],
               s0.est_rupture AS [est_rupture]
    INTO #src
    FROM [TuniShop_STG_INTEGRATED].integ.v_stock_mensuel s0
    OUTER APPLY (SELECT TOP (1) dp.produit_sk FROM dw.dim_produit dp
                 WHERE dp.produit_id = s0.produit_id
                 ORDER BY CASE WHEN CAST(s0.date_inventaire AS DATE) BETWEEN dp.date_debut_validite AND dp.date_fin_validite THEN 0 ELSE 1 END,
                          ABS(DATEDIFF(DAY, dp.date_debut_validite, CAST(s0.date_inventaire AS DATE)))) kpr
    LEFT JOIN dw.dim_entrepot e ON e.entrepot_id = s0.entrepot_id;

    MERGE dw.[fact_stock_mensuel] AS t
    USING #src AS s
    ON t.[inventaire_id] = s.[inventaire_id]
    WHEN MATCHED AND (EXISTS (SELECT t.[date_sk], t.[produit_sk], t.[entrepot_sk], t.[stock_fin_mois], t.[quantite_en_commande], t.[valeur_stock_ht], t.[est_rupture] EXCEPT SELECT s.[date_sk], s.[produit_sk], s.[entrepot_sk], s.[stock_fin_mois], s.[quantite_en_commande], s.[valeur_stock_ht], s.[est_rupture]) OR t.est_supprime = 1) THEN
        UPDATE SET [date_sk] = s.[date_sk], [produit_sk] = s.[produit_sk], [entrepot_sk] = s.[entrepot_sk], [stock_fin_mois] = s.[stock_fin_mois], [quantite_en_commande] = s.[quantite_en_commande], [valeur_stock_ht] = s.[valeur_stock_ht], [est_rupture] = s.[est_rupture], est_supprime = 0, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([date_sk], [produit_sk], [entrepot_sk], [inventaire_id], [stock_fin_mois], [quantite_en_commande], [valeur_stock_ht], [est_rupture], id_chargement, date_maj)
        VALUES (s.[date_sk], s.[produit_sk], s.[entrepot_sk], s.[inventaire_id], s.[stock_fin_mois], s.[quantite_en_commande], s.[valeur_stock_ht], s.[est_rupture], @id_chargement, SYSDATETIME())
    WHEN NOT MATCHED BY SOURCE AND t.est_supprime = 0 THEN                      -- disparue du staging : marquée, exclue des vues bi
        UPDATE SET est_supprime = 1, id_chargement = @id_chargement, date_maj = SYSDATETIME()
    OUTPUT $action, deleted.est_supprime, inserted.est_supprime INTO @actions;
    SELECT @ins = COUNT(CASE WHEN action = 'INSERT' THEN 1 END),
           @sup = COUNT(CASE WHEN action = 'UPDATE' AND supp_apres = 1 AND ISNULL(supp_avant, 0) = 0 THEN 1 END),
           @maj = COUNT(CASE WHEN action = 'UPDATE' AND NOT (supp_apres = 1 AND ISNULL(supp_avant, 0) = 0) THEN 1 END)
    FROM @actions;
    COMMIT TRANSACTION;
    EXEC [TuniShop_ADMIN].audit.usp_journaliser_tache @id_chargement = @id_chargement, @couche = 'DWH', @objet = N'dw.fact_stock_mensuel',
         @nb_lus = NULL, @nb_inseres = @ins, @nb_rejetes = NULL, @nb_maj = @maj, @nb_supprimes = @sup;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_fact_stock_mensuel';
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dw.usp_charger_dimensions @id_chargement INT AS
BEGIN
    SET NOCOUNT ON;
    EXEC dw.usp_charger_dim_date @id_chargement = @id_chargement;
    EXEC dw.usp_charger_dim_geographie @id_chargement = @id_chargement;
    EXEC dw.usp_charger_dim_entrepot @id_chargement = @id_chargement;
    EXEC dw.usp_charger_dim_transporteur @id_chargement = @id_chargement;
    EXEC dw.usp_charger_dim_fournisseur @id_chargement = @id_chargement;
    EXEC dw.usp_charger_dim_campagne @id_chargement = @id_chargement;
    EXEC dw.usp_charger_dim_coupon @id_chargement = @id_chargement;
    EXEC dw.usp_charger_dim_canal @id_chargement = @id_chargement;
    EXEC dw.usp_charger_dim_mode_paiement @id_chargement = @id_chargement;
    EXEC dw.usp_charger_dim_statut_commande @id_chargement = @id_chargement;
    EXEC dw.usp_charger_dim_motif_retour @id_chargement = @id_chargement;
    EXEC dw.usp_charger_dim_client @id_chargement = @id_chargement;
    EXEC dw.usp_charger_dim_produit @id_chargement = @id_chargement;
END;
GO
CREATE OR ALTER PROCEDURE dw.usp_charger_faits @id_chargement INT AS
BEGIN
    SET NOCOUNT ON;
    EXEC dw.usp_charger_fact_ventes @id_chargement = @id_chargement;
    EXEC dw.usp_charger_fact_commandes @id_chargement = @id_chargement;
    EXEC dw.usp_charger_fact_paiements @id_chargement = @id_chargement;
    EXEC dw.usp_charger_fact_livraisons @id_chargement = @id_chargement;
    EXEC dw.usp_charger_fact_remboursements @id_chargement = @id_chargement;
    EXEC dw.usp_charger_fact_avis @id_chargement = @id_chargement;
    EXEC dw.usp_charger_fact_marketing_quotidien @id_chargement = @id_chargement;
    EXEC dw.usp_charger_fact_achats_fournisseur @id_chargement = @id_chargement;
    EXEC dw.usp_charger_fact_mouvements_stock @id_chargement = @id_chargement;
    EXEC dw.usp_charger_fact_stock_mensuel @id_chargement = @id_chargement;
END;
GO

/* =====================================================================
   Orchestration complète : dimensions → faits → contrôles → clôture du lot
   @id_chargement = 0 (ou NULL) : dernier lot de TuniShop_ADMIN.audit.execution_lot
   ===================================================================== */
CREATE OR ALTER PROCEDURE dw.usp_charger_dwh
    @id_chargement INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF ISNULL(@id_chargement, 0) = 0
        SELECT @id_chargement = MAX(id_chargement) FROM [TuniShop_ADMIN].audit.execution_lot;
    BEGIN TRY
        EXEC dw.usp_charger_dimensions                           @id_chargement = @id_chargement;
        EXEC dw.usp_charger_faits                                @id_chargement = @id_chargement;
        EXEC [TuniShop_ADMIN].audit.usp_controles_qualite        @id_chargement = @id_chargement;
        EXEC [TuniShop_ADMIN].audit.usp_fermer_lot               @id_chargement = @id_chargement;
    END TRY
    BEGIN CATCH
        EXEC [TuniShop_ADMIN].audit.usp_journaliser_erreur @id_chargement = @id_chargement, @objet = N'dw.usp_charger_dwh';
        EXEC [TuniShop_ADMIN].audit.usp_fermer_lot @id_chargement = @id_chargement, @statut = 'ECHEC';
        THROW;
    END CATCH
    SELECT * FROM [TuniShop_ADMIN].audit.v_supervision_lots WHERE id_chargement = @id_chargement;
END;
GO
/* =====================================================================
   Mise à jour des contrôles qualité (base de contrôle) : les lignes marquées
   est_supprime = 1 sont exclues des réconciliations. Remplace la version de 02_Audit_Logs.sql.
   ===================================================================== */
USE [TuniShop_ADMIN];
GO
CREATE OR ALTER PROCEDURE audit.usp_controles_qualite
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @v DECIMAL(18,4), @inc_max DECIMAL(18,4) = (SELECT valeur FROM audit.parametre WHERE cle = 'taux_inconnu_max'),
            @ca_max DECIMAL(18,4) = (SELECT valeur FROM audit.parametre WHERE cle = 'ecart_ca_max');
    -- Q-01 Unicité des clés naturelles en STG_CLEAN (garantie par PK, contrôle de sécurité)
    SELECT @v = COUNT(*) FROM (SELECT commande_id FROM [TuniShop_STG_CLEAN].clean.v_commandes GROUP BY commande_id HAVING COUNT(*) > 1) x;
    EXEC audit.usp_enregistrer_controle @id_chargement, 'Q-01', 'QUALITE', N'clean.commandes', N'Doublons de commande_id', @v, 0, 1;
    -- Q-02 Statuts hors liste après harmonisation (QR13)
    SELECT @v = COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_commandes
    WHERE statut_commande NOT IN ('livree','partiellement_retournee','annulee','livraison_echouee','retournee','paiement_echoue','expediee','en_preparation');
    EXEC audit.usp_enregistrer_controle @id_chargement, 'Q-02', 'QUALITE', N'clean.commandes', N'Statuts de commande non conformes', @v, 0, 1;
    -- Q-03 Cohérence montant total (QR20)
    SELECT @v = COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_commandes WHERE ABS(sous_total_ttc - remise_coupon_ttc + frais_livraison_ttc - montant_total_ttc) > 0.01;
    EXEC audit.usp_enregistrer_controle @id_chargement, 'Q-03', 'QUALITE', N'clean.commandes', N'Total TTC incohérent', @v, 0, 1;
    -- Q-04 Cohérence des lignes (QR21/QR22)
    SELECT @v = COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_lignes_commande WHERE quantite <= 0 OR ABS(quantite * prix_unitaire_ttc - montant_ligne_ttc) > 0.01;
    EXEC audit.usp_enregistrer_controle @id_chargement, 'Q-04', 'QUALITE', N'clean.lignes_commande', N'Quantité ≤ 0 ou montant ≠ quantité × prix', @v, 0, 1;
    -- Q-05 Téléphones non normalisés
    SELECT @v = COUNT(*) FROM [TuniShop_STG_CLEAN].clean.v_clients WHERE telephone IS NOT NULL AND telephone NOT LIKE '+216[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]';
    EXEC audit.usp_enregistrer_controle @id_chargement, 'Q-05', 'QUALITE', N'clean.clients', N'Téléphones hors format +216XXXXXXXX', @v, 0, 0;
    -- Q-06 Doublons clients résiduels (QR27)
    SELECT @v = COUNT(*) FROM (SELECT prenom, nom, telephone FROM [TuniShop_STG_INTEGRATED].integ.v_client
                               WHERE type_client = 'particulier' AND telephone IS NOT NULL GROUP BY prenom, nom, telephone HAVING COUNT(*) > 1) x;
    EXEC audit.usp_enregistrer_controle @id_chargement, 'Q-06', 'QUALITE', N'integ.client', N'Clients en double résiduels', @v, 0, 0;
    -- R-01 / R-02 Part de membres inconnus dans les faits
    SELECT @v = AVG(CASE WHEN client_sk = -1 THEN 1.0 ELSE 0 END) FROM [TuniShop_DWH].dw.fact_commandes WHERE est_supprime = 0;
    EXEC audit.usp_enregistrer_controle @id_chargement, 'R-01', 'REFERENTIEL', N'[TuniShop_DWH].dw.fact_commandes', N'Part de commandes à client inconnu', @v, @inc_max, 0;
    SELECT @v = AVG(CASE WHEN produit_sk = -1 THEN 1.0 ELSE 0 END) FROM [TuniShop_DWH].dw.fact_ventes WHERE est_supprime = 0;
    EXEC audit.usp_enregistrer_controle @id_chargement, 'R-02', 'REFERENTIEL', N'[TuniShop_DWH].dw.fact_ventes', N'Part de lignes à produit inconnu', @v, @inc_max, 0;
    -- C-01 Réconciliation du CA TTC integ ↔ DWH
    SELECT @v = ABS((SELECT SUM(montant_ligne_ttc) FROM [TuniShop_STG_INTEGRATED].integ.v_ligne_commande) - (SELECT SUM(montant_ttc) FROM [TuniShop_DWH].dw.fact_ventes WHERE est_supprime = 0));
    EXEC audit.usp_enregistrer_controle @id_chargement, 'C-01', 'RECONCILIATION', N'[TuniShop_DWH].dw.fact_ventes', N'Écart de CA TTC entre STG_INTEGRATED et DWH', @v, @ca_max, 1;
    -- C-02 Réconciliation du nombre de commandes
    SELECT @v = ABS((SELECT COUNT(*) FROM [TuniShop_STG_INTEGRATED].integ.v_commande) - (SELECT COUNT(*) FROM [TuniShop_DWH].dw.fact_commandes WHERE est_supprime = 0));
    EXEC audit.usp_enregistrer_controle @id_chargement, 'C-02', 'RECONCILIATION', N'[TuniShop_DWH].dw.fact_commandes', N'Écart du nombre de commandes', @v, 0, 1;
    -- C-03 Une seule version courante par client
    SELECT @v = COUNT(*) FROM (SELECT client_id FROM [TuniShop_DWH].dw.dim_client WHERE est_courant = 1 AND est_supprime = 0 GROUP BY client_id HAVING COUNT(*) > 1) x;
    EXEC audit.usp_enregistrer_controle @id_chargement, 'C-03', 'QUALITE', N'[TuniShop_DWH].dw.dim_client', N'Clients avec plusieurs versions courantes (SCD2)', @v, 0, 1;
    -- C-04 Chevauchement de versions produit
    SELECT @v = COUNT(*) FROM [TuniShop_DWH].dw.dim_produit a JOIN [TuniShop_DWH].dw.dim_produit b
        ON a.produit_id = b.produit_id AND a.produit_sk < b.produit_sk AND a.produit_sk > 0
       AND a.date_debut_validite <= b.date_fin_validite AND b.date_debut_validite <= a.date_fin_validite;
    EXEC audit.usp_enregistrer_controle @id_chargement, 'C-04', 'QUALITE', N'[TuniShop_DWH].dw.dim_produit', N'Versions de prix qui se chevauchent', @v, 0, 1;
END;
GO
USE [TuniShop_DWH];
GO

/* Test dans SSMS :
   EXEC TuniShop_DWH.dw.usp_charger_dwh;                       -- dernier lot
   SELECT * FROM TuniShop_ADMIN.audit.execution_tache WHERE couche = 'DWH' ORDER BY id_tache DESC;
   SELECT * FROM TuniShop_ADMIN.audit.v_controles_en_echec;
*/
