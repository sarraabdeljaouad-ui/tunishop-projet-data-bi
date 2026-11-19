/* =====================================================================================
   TuniShop — Automatisation A01. Création du job SQL Server Agent « TuniShop - Chaine complete »
   =====================================================================================
   Auteure   : Sarra Abdeljaouad
   Version   : 1.3 (05/11/2026 : staging « tout --forcer » ; cubes et leur journal sortis du package DWH_02)
   À lancer  : dans SSMS, connecté au moteur de base de données localhost (ABDELJAOUAD),
               l'instance qui porte les bases TuniShop et SQL Server Agent.
               localhost\DEV n'est que l'instance SSAS : seule l'étape 03 Cubes la vise.

   Ce que fait le script
     1. crée le proxy Proxy_TuniShop (ton compte Windows) pour les étapes Python et SSIS ;
     2. crée le job avec 5 étapes, enchaînées « si succès, étape suivante ; si échec, arrêt » :
          01 Staging (Python, tout --forcer) -> 02a DWH Dimensions (SSIS) -> 02b DWH Faits (SSIS)
          -> 03 Cubes SSAS (traitement complet) -> 03b Journaliser le cube (T-SQL, TuniShop_ADMIN)
        Les étapes 03 et 03b remplacent les tâches « Traiter les cubes » et « SQL - Journaliser le cube »
        retirées du package DWH_02_Chargement_Faits (une étape du job = un seul rôle).
     3. crée la planification de nuit, DÉSACTIVÉE tant que le test manuel n'est pas concluant.
   L'étape 04 « Analyse et publication » s'ajoute ensuite avec le script 07 de 00_Commun/sql.

   AVANT DE LANCER
     a) Créer le credential (une seule fois, à la main, pour que ton mot de passe ne soit
        jamais écrit dans un script) :
        SSMS > localhost (ABDELJAOUAD) > Sécurité > Informations d'identification > Nouvelle
          Nom : Cred_TuniShop    Identité : TON_PC\ton_compte    Mot de passe : celui de Windows
     b) Vérifier les variables de la section « À ADAPTER » (déjà remplies pour ton poste).
        Le fichier est en UTF-8 avec BOM : SSMS lit correctement le « é » de « Développement ».
     c) Déclarer le compte de l'Agent, NT Service\SQLSERVERAGENT, administrateur de
        l'instance SSAS localhost\DEV (étape 03 : elle tourne avec ce compte, pas le proxy).
     d) Vérifier que ton script de staging se termine par un code d'erreur s'il échoue
        (sys.exit(1)). Sinon l'Agent croira à un succès et lancera le DWH sur un staging raté.

   Relançable : si le job existe déjà, le script s'arrête, sauf si @recreer = 1.
   ===================================================================================== */

USE msdb;
GO

SET NOCOUNT ON;

/* ---------------------------------------------------------------------------------
   À ADAPTER
   --------------------------------------------------------------------------------- */
DECLARE @nom_job        SYSNAME       = N'TuniShop - Chaine complete';
DECLARE @recreer        BIT           = 0;      -- 1 = supprime et recrée le job s'il existe

DECLARE @credential     SYSNAME       = N'Cred_TuniShop';
DECLARE @proxy          SYSNAME       = N'Proxy_TuniShop';

-- À ADAPTER : chemin de python.exe (commande « where python » dans PowerShell)
-- et dossier où tu as téléchargé le projet.
-- Python (le même que pour les notebooks)
DECLARE @python         NVARCHAR(400) = N'C:\chemin\vers\python.exe';
-- Staging : dossier de travail du script + chemin complet du script
DECLARE @racine_projet  NVARCHAR(400) = N'C:\chemin\vers\tunishop-projet-data-bi';
DECLARE @dossier_stg    NVARCHAR(400) = @racine_projet + N'\1-Staging';
DECLARE @script_stg     NVARCHAR(400) = @dossier_stg + N'\1-tunishop_pipeline.py';
DECLARE @args_stg       NVARCHAR(200) = N'tout --forcer';   -- fichiers -> RAW -> CLEAN -> INTEGRATED ; clôture un lot resté EN_COURS
-- DWH : les deux packages SSIS, lancés dans cet ordre (dimensions puis faits)
DECLARE @dossier_ssis   NVARCHAR(400) = @racine_projet + N'\2-DWH\TuniShop_DWH_SSIS\TuniShop_DWH_SSIS';
DECLARE @pkg_dim        NVARCHAR(400) = @dossier_ssis + N'\DWH_01_Chargement_Dimensions.dtsx';
DECLARE @pkg_faits      NVARCHAR(400) = @dossier_ssis + N'\DWH_02_Chargement_Faits.dtsx';
-- Cubes : instance et base SSAS
DECLARE @serveur_ssas   SYSNAME       = N'localhost\DEV';
DECLARE @base_ssas      SYSNAME       = N'TuniShop_OLAP';   -- ID de la base SSAS (Propriétés de la base dans SSMS)
-- Journaux texte de chaque étape (dossier existant, accessible en écriture par ton compte)
DECLARE @dossier_logs   NVARCHAR(400) = N'C:\TuniShop\Logs_Agent';   -- hors du Bureau : l'Agent doit pouvoir y écrire
-- Planification : tous les jours à 02:00 (HHMMSS)
DECLARE @heure_nuit     INT           = 20000;

/* ---------------------------------------------------------------------------------
   0. Contrôles
   --------------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.credentials WHERE name = @credential)
BEGIN
    RAISERROR (N'Credential « %s » introuvable : crée-le d''abord (voir AVANT DE LANCER, point a).', 16, 1, @credential);
    RETURN;
END

IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = @nom_job)
BEGIN
    IF @recreer = 0
    BEGIN
        PRINT N'Le job existe déjà : rien à faire (mets @recreer = 1 pour le recréer).';
        RETURN;
    END
    EXEC dbo.sp_delete_job @job_name = @nom_job, @delete_unused_schedule = 1;
    PRINT N'Ancien job supprimé.';
END

/* ---------------------------------------------------------------------------------
   1. Proxy : les étapes Python (CmdExec) et SSIS tournent avec ton compte Windows
   --------------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM dbo.sysproxies WHERE name = @proxy)
BEGIN
    EXEC dbo.sp_add_proxy @proxy_name = @proxy, @credential_name = @credential, @enabled = 1,
         @description = N'TuniShop : étapes Python et SSIS avec le compte Windows de l''auteure';
    PRINT N'Proxy créé : ' + @proxy;
END

DECLARE @sous_systemes TABLE (nom NVARCHAR(40));
INSERT INTO @sous_systemes VALUES (N'CmdExec'), (N'SSIS');
DECLARE @nom_ss NVARCHAR(40);
DECLARE ss CURSOR LOCAL FAST_FORWARD FOR SELECT nom FROM @sous_systemes;
OPEN ss;
FETCH NEXT FROM ss INTO @nom_ss;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.sysproxysubsystem AS ps
                   JOIN dbo.sysproxies    AS p ON p.proxy_id = ps.proxy_id
                   JOIN dbo.syssubsystems AS u ON u.subsystem_id = ps.subsystem_id
                   WHERE p.name = @proxy AND u.subsystem = @nom_ss)
        EXEC dbo.sp_grant_proxy_to_subsystem @proxy_name = @proxy, @subsystem_name = @nom_ss;
    FETCH NEXT FROM ss INTO @nom_ss;
END
CLOSE ss;
DEALLOCATE ss;

/* ---------------------------------------------------------------------------------
   2. Le job et ses étapes
   --------------------------------------------------------------------------------- */
EXEC dbo.sp_add_job
     @job_name    = @nom_job,
     @enabled     = 1,
     @description = N'TuniShop : staging (Python) -> DWH (SSIS) -> cubes SSAS -> analyse et ML (étape 04, script 07).';

-- Les étapes : une ligne par étape. Pour plusieurs packages SSIS, ajoute des lignes.
DECLARE @etapes TABLE (ordre INT, nom SYSNAME, sous_systeme NVARCHAR(40), commande NVARCHAR(MAX),
                       serveur SYSNAME NULL, avec_proxy BIT, base SYSNAME NULL);

INSERT INTO @etapes VALUES
 (1, N'01 Staging (Python)', N'CmdExec',
     -- cd /d : le script tourne depuis son dossier (chemins relatifs du staging)
     N'cmd /c cd /d "' + @dossier_stg + N'" && "' + @python + N'" "' + @script_stg + N'" ' + @args_stg,
     NULL, 1, NULL),
 (2, N'02a DWH Dimensions (SSIS)', N'SSIS',
     N'/FILE "\"' + @pkg_dim + N'\"" /CHECKPOINTING OFF /REPORTING E',
     NULL, 1, NULL),
 (3, N'02b DWH Faits (SSIS)', N'SSIS',
     N'/FILE "\"' + @pkg_faits + N'\"" /CHECKPOINTING OFF /REPORTING E',
     NULL, 1, NULL),
 (4, N'03 Cubes SSAS (traitement complet)', N'ANALYSISCOMMAND',
     -- Cubes multidimensionnels : traitement complet de la base SSAS (XMLA)
     N'<Batch xmlns="http://schemas.microsoft.com/analysisservices/2003/engine">'
   + N'<Process><Object><DatabaseID>' + @base_ssas + N'</DatabaseID></Object>'
   + N'<Type>ProcessFull</Type></Process></Batch>',
     -- Si ton modèle SSAS est TABULAIRE, remplace par :
     -- N'{"refresh":{"type":"full","objects":[{"database":"' + @base_ssas + N'"}]}}'
     @serveur_ssas, 0, NULL),
 (5, N'03b Journaliser le cube (T-SQL)', N'TSQL',
     -- Même règle que l'ancienne tâche du package : le lot traité est le dernier lot (MAX id_chargement)
     N'DECLARE @lot INT = (SELECT MAX(id_chargement) FROM audit.execution_lot);' + NCHAR(13) + NCHAR(10)
   + N'IF @lot IS NULL THROW 50001, N''Aucun lot dans audit.execution_lot : journalisation impossible.'', 1;' + NCHAR(13) + NCHAR(10)
   + N'EXEC audit.usp_journaliser_cube @id_chargement = @lot;',
     NULL, 0, N'TuniShop_ADMIN');

DECLARE @ordre INT, @nom SYSNAME, @ss NVARCHAR(40), @cmd NVARCHAR(MAX), @srv SYSNAME, @avec_proxy BIT, @base SYSNAME;
DECLARE @derniere INT = (SELECT MAX(ordre) FROM @etapes);
DECLARE @proxy_etape SYSNAME, @succes TINYINT, @fichier NVARCHAR(400);

DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT ordre, nom, sous_systeme, commande, serveur, avec_proxy, base FROM @etapes ORDER BY ordre;
OPEN c;
FETCH NEXT FROM c INTO @ordre, @nom, @ss, @cmd, @srv, @avec_proxy, @base;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @proxy_etape = CASE WHEN @avec_proxy = 1 THEN @proxy END;
    SET @succes      = CASE WHEN @ordre = @derniere THEN 1 ELSE 3 END;   -- 1 = fin (succès), 3 = étape suivante
    SET @fichier     = @dossier_logs + N'\' + REPLACE(REPLACE(@nom, N' ', N'_'), N'(', N'') + N'.log';
    SET @fichier     = REPLACE(@fichier, N')', N'');

    EXEC dbo.sp_add_jobstep
         @job_name          = @nom_job,
         @step_id           = @ordre,
         @step_name         = @nom,
         @subsystem         = @ss,
         @command           = @cmd,
         @server            = @srv,
         @database_name     = @base,
         @proxy_name        = @proxy_etape,
         @on_success_action = @succes,
         @on_fail_action    = 2,           -- arrêt du job en échec : on ne charge jamais sur une étape ratée
         @retry_attempts    = 0,
         @output_file_name  = @fichier,
         @flags             = 0;           -- 0 = le fichier est remplacé à chaque exécution

    PRINT N'Étape ' + CAST(@ordre AS NVARCHAR(5)) + N' ajoutée : ' + @nom;
    FETCH NEXT FROM c INTO @ordre, @nom, @ss, @cmd, @srv, @avec_proxy, @base;
END
CLOSE c;
DEALLOCATE c;

EXEC dbo.sp_update_job @job_name = @nom_job, @start_step_id = 1;
EXEC dbo.sp_add_jobserver @job_name = @nom_job, @server_name = N'(local)';

/* ---------------------------------------------------------------------------------
   3. Planification de nuit (créée DÉSACTIVÉE : on l'active après le test manuel)
   --------------------------------------------------------------------------------- */
DECLARE @nom_planif SYSNAME = N'TuniShop - Chaque nuit';
IF NOT EXISTS (SELECT 1 FROM dbo.sysschedules WHERE name = @nom_planif)
    EXEC dbo.sp_add_schedule
         @schedule_name     = @nom_planif,
         @enabled           = 0,
         @freq_type         = 4,          -- quotidien
         @freq_interval     = 1,          -- tous les jours
         @active_start_time = @heure_nuit;
EXEC dbo.sp_attach_schedule @job_name = @nom_job, @schedule_name = @nom_planif;

PRINT N'Job créé. Planification « ' + @nom_planif + N' » créée DÉSACTIVÉE.';

/* ---------------------------------------------------------------------------------
   4. Vérification
   --------------------------------------------------------------------------------- */
SELECT s.step_id, s.step_name, s.subsystem, ISNULL(p.name, N'(compte du service Agent)') AS compte,
       CASE s.on_success_action WHEN 1 THEN N'fin (succès)' WHEN 3 THEN N'étape suivante' END AS si_succes,
       CASE s.on_fail_action    WHEN 2 THEN N'fin (échec)' END AS si_echec,
       s.output_file_name, s.database_name, s.command
FROM dbo.sysjobsteps AS s
JOIN dbo.sysjobs AS j ON j.job_id = s.job_id
LEFT JOIN dbo.sysproxies AS p ON p.proxy_id = s.proxy_id
WHERE j.name = @nom_job
ORDER BY s.step_id;
GO

/* =====================================================================================
   APRÈS LE SCRIPT
   1. Ajouter l'étape 04 : script 00_Commun/sql/07_Etape_job_Agent.sql
      avec @proxy = N'Proxy_TuniShop' et @racine = ton dossier d'analyse.
   2. Test manuel, étape par étape si besoin :
        EXEC msdb.dbo.sp_start_job @job_name = N'TuniShop - Chaine complete';
        -- ou à partir d'une étape : @step_name = N'03 Cubes SSAS (traitement complet)'
   3. Suivre l'exécution :
        SELECT TOP (20) h.run_date, h.run_time, h.step_id, h.step_name,
               CASE h.run_status WHEN 0 THEN N'ÉCHEC' WHEN 1 THEN N'OK' WHEN 4 THEN N'en cours' ELSE N'autre' END AS statut,
               h.run_duration, LEFT(h.message, 400) AS message
        FROM msdb.dbo.sysjobhistory AS h
        JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
        WHERE j.name = N'TuniShop - Chaine complete'
        ORDER BY h.instance_id DESC;
   4. Quand tout est OK : activer la planification
        EXEC msdb.dbo.sp_update_schedule @name = N'TuniShop - Chaque nuit', @enabled = 1;
   ===================================================================================== */
