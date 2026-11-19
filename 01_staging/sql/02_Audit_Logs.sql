/* =====================================================================
   Projet      : TuniShop — Data Warehouse e-commerce (portfolio)
   Script      : Scripts_Audit_Logs.sql
   Objet       : Journalisation des exécutions (lots, tâches, erreurs), contrôles de volumétrie et de qualité, vues de supervision. Schéma audit dans la base de contrôle TuniShop_ADMIN, utilisé par Python, SSIS et toutes les procédures.
   Cible       : Microsoft SQL Server 2019+ (SSMS) — compatibilité 150
   Exécution   : SSMS, mode SQLCMD inutile ; exécuter en entier (F5)
   Généré le   : 2026-10-17 depuis le modèle de métadonnées du projet
   ===================================================================== */
SET NOCOUNT ON;
GO
USE [TuniShop_ADMIN];
GO
IF SCHEMA_ID(N'audit') IS NULL EXEC (N'CREATE SCHEMA audit AUTHORIZATION dbo;');
GO
DROP VIEW  IF EXISTS audit.v_supervision_lots, audit.v_taches_dernier_lot, audit.v_rejets_par_regle, audit.v_controles_en_echec, audit.v_erreurs_recentes;
DROP TABLE IF EXISTS audit.controle_resultat, audit.journal_erreur, audit.execution_tache, audit.fichier_source, audit.execution_lot, audit.parametre;
GO
/* ---------------------------------------------------------------------
   1. Tables
   --------------------------------------------------------------------- */
-- Un lot = une exécution complète de la chaîne (Python + SSIS)
CREATE TABLE audit.execution_lot (
    id_chargement      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_execution_lot PRIMARY KEY,
    nom_chaine         NVARCHAR(100)  NOT NULL CONSTRAINT DF_execution_lot_nom DEFAULT (N'TuniShop_ETL'),
    declencheur        NVARCHAR(50)   NOT NULL,          -- python, ssis, sql_agent, manuel
    date_debut         DATETIME2(0)   NOT NULL CONSTRAINT DF_execution_lot_debut DEFAULT (SYSDATETIME()),
    date_fin           DATETIME2(0)   NULL,
    duree_s            AS DATEDIFF(SECOND, date_debut, date_fin),
    statut             VARCHAR(12)    NOT NULL CONSTRAINT DF_execution_lot_statut DEFAULT ('EN_COURS')
                       CONSTRAINT CK_execution_lot_statut CHECK (statut IN ('EN_COURS','SUCCES','AVERTISSEMENT','ECHEC')),
    utilisateur        SYSNAME        NOT NULL CONSTRAINT DF_execution_lot_user DEFAULT (SUSER_SNAME()),
    machine            NVARCHAR(128)  NOT NULL CONSTRAINT DF_execution_lot_host DEFAULT (HOST_NAME()),
    execution_ssis_id  BIGINT         NULL,              -- System::ServerExecutionID (catalogue SSISDB)
    commentaire        NVARCHAR(400)  NULL
);
-- Fichiers sources chargés dans STG_RAW (renseigné par Scripts_Preparation.py)
CREATE TABLE audit.fichier_source (
    id_fichier         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_fichier_source PRIMARY KEY,
    id_chargement      INT            NOT NULL CONSTRAINT FK_fichier_source_lot REFERENCES audit.execution_lot (id_chargement),
    table_cible        SYSNAME        NOT NULL,
    chemin_fichier     NVARCHAR(400)  NOT NULL,
    taille_octets      BIGINT         NULL,
    empreinte_sha256   CHAR(64)       NULL,          -- détection d'un fichier rejoué à l'identique
    nb_lignes_fichier  INT            NOT NULL,
    nb_lignes_chargees INT            NOT NULL,
    date_chargement    DATETIME2(0)   NOT NULL CONSTRAINT DF_fichier_source_date DEFAULT (SYSDATETIME())
);
-- Une tâche = un objet chargé (table) dans une couche
CREATE TABLE audit.execution_tache (
    id_tache           BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_execution_tache PRIMARY KEY,
    id_chargement      INT            NOT NULL CONSTRAINT FK_execution_tache_lot REFERENCES audit.execution_lot (id_chargement),
    couche             VARCHAR(20)    NOT NULL CONSTRAINT CK_execution_tache_couche CHECK (couche IN ('STG_RAW','STG_CLEAN','STG_INTEGRATED','DWH','CONTROLE')),
    objet              NVARCHAR(200)  NOT NULL,
    nb_lus             INT            NULL,
    nb_inseres         INT            NULL,
    nb_maj             INT            NULL,
    nb_supprimes       INT            NULL,          -- lignes marquées ou supprimées (chargement incrémental)
    nb_rejetes         INT            NULL,
    statut             VARCHAR(12)    NOT NULL CONSTRAINT DF_execution_tache_statut DEFAULT ('SUCCES'),
    date_fin           DATETIME2(0)   NOT NULL CONSTRAINT DF_execution_tache_fin DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_execution_tache_lot ON audit.execution_tache (id_chargement, couche);
-- Erreurs techniques capturées dans les blocs CATCH (procédures) ou OnError (SSIS)
CREATE TABLE audit.journal_erreur (
    id_erreur          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_journal_erreur PRIMARY KEY,
    id_chargement      INT            NULL,
    objet              NVARCHAR(200)  NOT NULL,
    numero_erreur      INT            NULL,
    severite           INT            NULL,
    etat               INT            NULL,
    ligne              INT            NULL,
    procedure_sql      NVARCHAR(200)  NULL,
    message            NVARCHAR(4000) NULL,
    source             VARCHAR(10)    NOT NULL CONSTRAINT DF_journal_erreur_source DEFAULT ('SQL'),   -- SQL, SSIS, PYTHON
    date_erreur        DATETIME2(0)   NOT NULL CONSTRAINT DF_journal_erreur_date DEFAULT (SYSDATETIME())
);
-- Seuils paramétrables des contrôles
CREATE TABLE audit.parametre (
    cle                VARCHAR(50)    NOT NULL CONSTRAINT PK_parametre PRIMARY KEY,
    valeur             DECIMAL(18,4)  NOT NULL,
    description        NVARCHAR(200)  NOT NULL
);
INSERT INTO audit.parametre (cle, valeur, description) VALUES
('taux_rejet_max',          0.0200, N'Taux de rejet maximal toléré par table en STG_CLEAN (2 %)'),
('ecart_volumetrie_max',    0.1000, N'Écart maximal de volumétrie avec le lot précédent (10 %)'),
('taux_inconnu_max',        0.0050, N'Part maximale de clés -1 (inconnu) dans un fait (0,5 %)'),
('ecart_ca_max',            0.0100, N'Écart maximal toléré entre CA integ et CA DWH (TND)');
-- Résultats des contrôles (une ligne par contrôle et par lot)
CREATE TABLE audit.controle_resultat (
    id_controle        BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_controle_resultat PRIMARY KEY,
    id_chargement      INT            NOT NULL CONSTRAINT FK_controle_resultat_lot REFERENCES audit.execution_lot (id_chargement),
    code_controle      VARCHAR(20)    NOT NULL,
    categorie          VARCHAR(20)    NOT NULL,   -- VOLUMETRIE, QUALITE, REFERENTIEL, RECONCILIATION
    objet              NVARCHAR(200)  NOT NULL,
    description        NVARCHAR(400)  NOT NULL,
    valeur_mesuree     DECIMAL(18,4)  NULL,
    seuil              DECIMAL(18,4)  NULL,
    resultat           VARCHAR(12)    NOT NULL CONSTRAINT CK_controle_resultat CHECK (resultat IN ('OK','AVERTISSEMENT','ECHEC')),
    bloquant           BIT            NOT NULL,
    date_controle      DATETIME2(0)   NOT NULL CONSTRAINT DF_controle_resultat_date DEFAULT (SYSDATETIME())
);
CREATE INDEX IX_controle_resultat_lot ON audit.controle_resultat (id_chargement, resultat);
GO
/* ---------------------------------------------------------------------
   2. Procédures de journalisation
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE audit.usp_ouvrir_lot
    @declencheur NVARCHAR(50), @execution_ssis_id BIGINT = NULL, @commentaire NVARCHAR(400) = NULL,
    @id_chargement INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM audit.execution_lot WHERE statut = 'EN_COURS' AND date_debut > DATEADD(HOUR, -6, SYSDATETIME()))
        THROW 50001, N'Un lot est déjà en cours d''exécution : exécution concurrente refusée.', 1;
    INSERT INTO audit.execution_lot (declencheur, execution_ssis_id, commentaire) VALUES (@declencheur, @execution_ssis_id, @commentaire);
    SET @id_chargement = SCOPE_IDENTITY();
    SELECT @id_chargement AS id_chargement;   -- jeu de résultats exploitable par une tâche SSIS « Exécuter SQL »
END;
GO
CREATE OR ALTER PROCEDURE audit.usp_fermer_lot
    @id_chargement INT, @statut VARCHAR(12) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- Statut déduit des contrôles si non imposé
    IF @statut IS NULL
        SELECT @statut = CASE WHEN EXISTS (SELECT 1 FROM audit.journal_erreur WHERE id_chargement = @id_chargement) THEN 'ECHEC'
                              WHEN EXISTS (SELECT 1 FROM audit.controle_resultat WHERE id_chargement = @id_chargement AND resultat = 'ECHEC' AND bloquant = 1) THEN 'ECHEC'
                              WHEN EXISTS (SELECT 1 FROM audit.controle_resultat WHERE id_chargement = @id_chargement AND resultat <> 'OK') THEN 'AVERTISSEMENT'
                              ELSE 'SUCCES' END;
    UPDATE audit.execution_lot SET date_fin = SYSDATETIME(), statut = @statut WHERE id_chargement = @id_chargement;
END;
GO
CREATE OR ALTER PROCEDURE audit.usp_journaliser_tache
    @id_chargement INT, @couche VARCHAR(20), @objet NVARCHAR(200),
    @nb_lus INT = NULL, @nb_inseres INT = NULL, @nb_rejetes INT = NULL, @nb_maj INT = NULL, @nb_supprimes INT = NULL, @statut VARCHAR(12) = 'SUCCES'
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO audit.execution_tache (id_chargement, couche, objet, nb_lus, nb_inseres, nb_maj, nb_supprimes, nb_rejetes, statut)
    VALUES (@id_chargement, @couche, @objet, @nb_lus, @nb_inseres, @nb_maj, @nb_supprimes, @nb_rejetes, @statut);
END;
GO
-- À appeler dans un bloc CATCH : capture ERROR_*() du contexte appelant
CREATE OR ALTER PROCEDURE audit.usp_journaliser_erreur
    @id_chargement INT = NULL, @objet NVARCHAR(200), @source VARCHAR(10) = 'SQL', @message NVARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO audit.journal_erreur (id_chargement, objet, numero_erreur, severite, etat, ligne, procedure_sql, message, source)
    VALUES (@id_chargement, @objet, ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_LINE(), ERROR_PROCEDURE(),
            COALESCE(@message, ERROR_MESSAGE()), @source);
END;
GO
/* ---------------------------------------------------------------------
   3. Contrôles
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE audit.usp_enregistrer_controle
    @id_chargement INT, @code VARCHAR(20), @categorie VARCHAR(20), @objet NVARCHAR(200), @description NVARCHAR(400),
    @valeur DECIMAL(18,4), @seuil DECIMAL(18,4), @bloquant BIT, @sens CHAR(2) = '<='   -- OK si valeur <= seuil (ou >= si @sens = '>=')
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ok BIT = CASE WHEN @valeur IS NULL THEN 0
                           WHEN @sens = '<=' AND @valeur <= @seuil THEN 1
                           WHEN @sens = '>=' AND @valeur >= @seuil THEN 1
                           WHEN @sens = '=' AND @valeur = @seuil THEN 1 ELSE 0 END;
    INSERT INTO audit.controle_resultat (id_chargement, code_controle, categorie, objet, description, valeur_mesuree, seuil, resultat, bloquant)
    VALUES (@id_chargement, @code, @categorie, @objet, @description, @valeur, @seuil,
            CASE WHEN @ok = 1 THEN 'OK' WHEN @bloquant = 1 THEN 'ECHEC' ELSE 'AVERTISSEMENT' END, @bloquant);
END;
GO
-- Volumétrie : comparaison avec le dernier lot réussi + taux de rejet STG_CLEAN
CREATE OR ALTER PROCEDURE audit.usp_controler_volumetrie
    @id_chargement INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ecart_max DECIMAL(18,4) = (SELECT valeur FROM audit.parametre WHERE cle = 'ecart_volumetrie_max'),
            @rejet_max DECIMAL(18,4) = (SELECT valeur FROM audit.parametre WHERE cle = 'taux_rejet_max'),
            @lot_prec INT = (SELECT MAX(id_chargement) FROM audit.execution_lot WHERE id_chargement < @id_chargement AND statut IN ('SUCCES','AVERTISSEMENT'));
    DECLARE @objet NVARCHAR(200), @v DECIMAL(18,4), @code VARCHAR(20);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT t.objet,
               CASE WHEN p.nb_inseres IS NULL OR p.nb_inseres = 0 THEN 0 ELSE ABS(t.nb_inseres - p.nb_inseres) * 1.0 / p.nb_inseres END
        FROM audit.execution_tache t
        LEFT JOIN audit.execution_tache p ON p.id_chargement = @lot_prec AND p.objet = t.objet
        WHERE t.id_chargement = @id_chargement AND t.couche IN ('STG_CLEAN','STG_INTEGRATED');
    OPEN c; FETCH NEXT FROM c INTO @objet, @v;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC audit.usp_enregistrer_controle @id_chargement, 'VOL-01', 'VOLUMETRIE', @objet, N'Écart relatif de volumétrie avec le lot précédent', @v, @ecart_max, 0;
        FETCH NEXT FROM c INTO @objet, @v;
    END
    CLOSE c; DEALLOCATE c;
    DECLARE c2 CURSOR LOCAL FAST_FORWARD FOR
        SELECT objet, CASE WHEN nb_lus > 0 THEN nb_rejetes * 1.0 / nb_lus ELSE 0 END
        FROM audit.execution_tache WHERE id_chargement = @id_chargement AND couche = 'STG_CLEAN';
    OPEN c2; FETCH NEXT FROM c2 INTO @objet, @v;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC audit.usp_enregistrer_controle @id_chargement, 'VOL-02', 'VOLUMETRIE', @objet, N'Taux de lignes rejetées (doublons) en STG_CLEAN', @v, @rejet_max, 0;
        FETCH NEXT FROM c2 INTO @objet, @v;
    END
    CLOSE c2; DEALLOCATE c2;
END;
GO
-- Qualité, intégrité et réconciliation après chargement du DWH
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
    SELECT @v = AVG(CASE WHEN client_sk = -1 THEN 1.0 ELSE 0 END) FROM [TuniShop_DWH].dw.fact_commandes;
    EXEC audit.usp_enregistrer_controle @id_chargement, 'R-01', 'REFERENTIEL', N'[TuniShop_DWH].dw.fact_commandes', N'Part de commandes à client inconnu', @v, @inc_max, 0;
    SELECT @v = AVG(CASE WHEN produit_sk = -1 THEN 1.0 ELSE 0 END) FROM [TuniShop_DWH].dw.fact_ventes;
    EXEC audit.usp_enregistrer_controle @id_chargement, 'R-02', 'REFERENTIEL', N'[TuniShop_DWH].dw.fact_ventes', N'Part de lignes à produit inconnu', @v, @inc_max, 0;
    -- C-01 Réconciliation du CA TTC integ ↔ DWH
    SELECT @v = ABS((SELECT SUM(montant_ligne_ttc) FROM [TuniShop_STG_INTEGRATED].integ.v_ligne_commande) - (SELECT SUM(montant_ttc) FROM [TuniShop_DWH].dw.fact_ventes));
    EXEC audit.usp_enregistrer_controle @id_chargement, 'C-01', 'RECONCILIATION', N'[TuniShop_DWH].dw.fact_ventes', N'Écart de CA TTC entre STG_INTEGRATED et DWH', @v, @ca_max, 1;
    -- C-02 Réconciliation du nombre de commandes
    SELECT @v = ABS((SELECT COUNT(*) FROM [TuniShop_STG_INTEGRATED].integ.v_commande) - (SELECT COUNT(*) FROM [TuniShop_DWH].dw.fact_commandes));
    EXEC audit.usp_enregistrer_controle @id_chargement, 'C-02', 'RECONCILIATION', N'[TuniShop_DWH].dw.fact_commandes', N'Écart du nombre de commandes', @v, 0, 1;
    -- C-03 Une seule version courante par client
    SELECT @v = COUNT(*) FROM (SELECT client_id FROM [TuniShop_DWH].dw.dim_client WHERE est_courant = 1 GROUP BY client_id HAVING COUNT(*) > 1) x;
    EXEC audit.usp_enregistrer_controle @id_chargement, 'C-03', 'QUALITE', N'[TuniShop_DWH].dw.dim_client', N'Clients avec plusieurs versions courantes (SCD2)', @v, 0, 1;
    -- C-04 Chevauchement de versions produit
    SELECT @v = COUNT(*) FROM [TuniShop_DWH].dw.dim_produit a JOIN [TuniShop_DWH].dw.dim_produit b
        ON a.produit_id = b.produit_id AND a.produit_sk < b.produit_sk AND a.produit_sk > 0
       AND a.date_debut_validite <= b.date_fin_validite AND b.date_debut_validite <= a.date_fin_validite;
    EXEC audit.usp_enregistrer_controle @id_chargement, 'C-04', 'QUALITE', N'[TuniShop_DWH].dw.dim_produit', N'Versions de prix qui se chevauchent', @v, 0, 1;
END;
GO
/* ---------------------------------------------------------------------
   4. Vues de supervision (tableau de bord d'exploitation Power BI)
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW audit.v_supervision_lots AS
SELECT l.id_chargement, l.declencheur, l.date_debut, l.date_fin, l.duree_s, l.statut,
       (SELECT COUNT(*) FROM audit.execution_tache t WHERE t.id_chargement = l.id_chargement) AS nb_taches,
       (SELECT SUM(nb_inseres) FROM audit.execution_tache t WHERE t.id_chargement = l.id_chargement AND t.couche = 'DWH') AS nb_lignes_dwh,
       (SELECT COUNT(*) FROM audit.journal_erreur e WHERE e.id_chargement = l.id_chargement) AS nb_erreurs,
       (SELECT COUNT(*) FROM audit.controle_resultat c WHERE c.id_chargement = l.id_chargement AND c.resultat <> 'OK') AS nb_controles_ko
FROM audit.execution_lot l;
GO
CREATE OR ALTER VIEW audit.v_taches_dernier_lot AS
SELECT t.*
FROM audit.execution_tache t
WHERE t.id_chargement = (SELECT MAX(id_chargement) FROM audit.execution_lot);
GO
CREATE OR ALTER VIEW audit.v_rejets_par_regle AS
SELECT 'STG_CLEAN' AS couche, id_chargement, table_source, regle_id, niveau, COUNT(*) AS nb
FROM [TuniShop_STG_CLEAN].clean.rejets GROUP BY id_chargement, table_source, regle_id, niveau
UNION ALL
SELECT 'STG_INTEGRATED', id_chargement, table_source, regle_id, niveau, COUNT(*)
FROM [TuniShop_STG_INTEGRATED].integ.rejets GROUP BY id_chargement, table_source, regle_id, niveau;
GO
CREATE OR ALTER VIEW audit.v_controles_en_echec AS
SELECT c.*, l.date_debut AS date_lot
FROM audit.controle_resultat c JOIN audit.execution_lot l ON l.id_chargement = c.id_chargement
WHERE c.resultat <> 'OK';
GO
CREATE OR ALTER VIEW audit.v_erreurs_recentes AS
SELECT TOP (200) * FROM audit.journal_erreur ORDER BY date_erreur DESC;
GO
PRINT N'Schéma audit créé.';
GO
