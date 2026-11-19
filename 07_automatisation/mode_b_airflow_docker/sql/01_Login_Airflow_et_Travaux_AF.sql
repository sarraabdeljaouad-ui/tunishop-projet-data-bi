/* =====================================================================
   TuniShop - 01_Login_Airflow_et_Travaux_AF.sql            Version 2.0
   ---------------------------------------------------------------------
   OÙ L'EXÉCUTER : SSMS, connecté à l'instance par défaut « ABDELJAOUAD »
                   (celle qui porte SQL Server Agent et le job de nuit).
   RELANÇABLE    : oui. Les 3 travaux AF sont supprimés puis recréés.

   CE QUE FAIT LE SCRIPT
     1. Crée le compte SQL « airflow_tunishop » qu'utilisera Airflow.
        Ce compte peut seulement démarrer des travaux et lire leur historique.
     2. CLONE les étapes de ton job qui marche, « TuniShop - Chaine complete »,
        dans 3 travaux SANS planification (c'est Airflow qui décide quand) :
          TuniShop AF - 1 Staging Python  = étape 1
          TuniShop AF - 2 DWH et cubes    = étapes 2 à 5
          TuniShop AF - 3 Analyses ML     = étape 6
        Commandes, chemins, proxy, serveur SSAS, fichiers .log : tout est
        copié à l'identique. Rien à recopier à la main.

   SI TU MODIFIES UN JOUR TON JOB DE NUIT : relance ce script, les travaux
   AF seront remis à jour. Si le nombre d'étapes change, adapte @groupes.

   CHANGEMENTS PAR RAPPORT À LA VERSION 1.0 (02/11/2026)
     - Instance ABDELJAOUAD au lieu de localhost\DEV.
     - Packages .dtsx lancés en /FILE (plus de SSISDB).
     - Étape cubes dédiée + journal du cube, au lieu du traitement dans DWH_02.
     - Les commandes ne sont plus écrites dans le script : elles sont lues
       dans le job de nuit.

   Auteure : Sarra Abdeljaouad
   ===================================================================== */
USE master;
GO
SET NOCOUNT ON;

/* ----------------------------- À ADAPTER ----------------------------- */
-- Mot de passe du compte Airflow (12 caractères mini, majuscule, chiffre, symbole).
-- Tu le retaperas dans Airflow (Admin > Connections). Ne le mets jamais sur GitHub.
DECLARE @mdp_airflow NVARCHAR(128) = N'<MOT_DE_PASSE_A_CHOISIR>';  -- à remplacer avant exécution, ne jamais publier la vraie valeur
/* --------------------------------------------------------------------- */

-- Airflow se connecte avec un compte SQL. Il faut donc le mode d'authentification mixte.
IF CAST(SERVERPROPERTY('IsIntegratedSecurityOnly') AS INT) = 1
    PRINT N'ATTENTION : l''instance est en « Authentification Windows » seule. '
        + N'Le compte sera créé, mais Airflow ne pourra pas se connecter tant que '
        + N'le mode « SQL Server et Windows » n''est pas activé (voir le guide).';

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'airflow_tunishop')
BEGIN
    DECLARE @sql NVARCHAR(MAX) = N'CREATE LOGIN airflow_tunishop WITH PASSWORD = N'''
        + REPLACE(@mdp_airflow, N'''', N'''''')
        + N''', DEFAULT_DATABASE = msdb, CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;';
    EXEC (@sql);
    PRINT N'1. Compte airflow_tunishop créé.';
END
ELSE PRINT N'1. Compte airflow_tunishop déjà présent (mot de passe inchangé).';
GO

USE msdb;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'airflow_tunishop')
    CREATE USER airflow_tunishop FOR LOGIN airflow_tunishop;
-- SQLAgentOperatorRole : peut démarrer les travaux locaux et voir leur historique.
ALTER ROLE SQLAgentOperatorRole ADD MEMBER airflow_tunishop;
-- Lecture des tables d'état utilisées par le DAG pour attendre la fin d'un travail.
GRANT SELECT ON dbo.sysjobs        TO airflow_tunishop;
GRANT SELECT ON dbo.sysjobactivity TO airflow_tunishop;
GRANT SELECT ON dbo.sysjobhistory  TO airflow_tunishop;
GRANT SELECT ON dbo.syssessions    TO airflow_tunishop;
PRINT N'   Droits accordés dans msdb.';
GO

/* =====================================================================
   2. Les 3 travaux pilotés par Airflow, clonés du job de nuit
   ===================================================================== */
SET NOCOUNT ON;

/* ----------------------------- À ADAPTER ----------------------------- */
DECLARE @job_source SYSNAME = N'TuniShop - Chaine complete';

-- Quelles étapes du job de nuit vont dans quel travail AF.
DECLARE @groupes TABLE (ordre INT, travail SYSNAME, premiere INT, derniere INT, description NVARCHAR(512));
INSERT INTO @groupes VALUES
 (1, N'TuniShop AF - 1 Staging Python', 1, 1,
     N'Piloté par Airflow (DAG tunishop_chaine_complete). Clone de l''étape 1 du job de nuit : staging Python.'),
 (2, N'TuniShop AF - 2 DWH et cubes',   2, 5,
     N'Piloté par Airflow. Clone des étapes 2 à 5 du job de nuit : DWH dimensions, DWH faits, cubes SSAS, journal du cube.'),
 (3, N'TuniShop AF - 3 Analyses ML',    6, 6,
     N'Piloté par Airflow. Clone de l''étape 6 du job de nuit : notebooks EDA, data mining, ML et publication.');
/* --------------------------------------------------------------------- */

DECLARE @job_id_source UNIQUEIDENTIFIER, @proprietaire SYSNAME;
SELECT @job_id_source = job_id, @proprietaire = SUSER_SNAME(owner_sid)
FROM   dbo.sysjobs WHERE name = @job_source;

IF @job_id_source IS NULL
    THROW 50020, N'Job source « TuniShop - Chaine complete » introuvable sur cette instance. Es-tu bien connectée à ABDELJAOUAD ?', 1;

IF (SELECT COUNT(*) FROM dbo.sysjobsteps WHERE job_id = @job_id_source)
   <> (SELECT SUM(derniere - premiere + 1) FROM @groupes)
BEGIN
    SELECT step_id, step_name, subsystem FROM dbo.sysjobsteps WHERE job_id = @job_id_source ORDER BY step_id;
    THROW 50021, N'Le job de nuit n''a pas le nombre d''étapes attendu (6). Compare avec la liste affichée et adapte @groupes.', 1;
END;

DECLARE @travail SYSNAME, @premiere INT, @derniere INT, @desc NVARCHAR(512);
DECLARE @sid INT, @nouvel_id INT, @nom SYSNAME, @ss NVARCHAR(40), @cmd NVARCHAR(MAX), @param NVARCHAR(MAX),
        @code INT, @succ TINYINT, @succ_id INT, @fail TINYINT, @fail_id INT,
        @srv SYSNAME, @db SYSNAME, @dbu SYSNAME, @retry INT, @retry_int INT,
        @out NVARCHAR(200), @flags INT, @proxy SYSNAME,
        @succ_n TINYINT, @succ_id_n INT, @fail_n TINYINT, @fail_id_n INT;

DECLARE g CURSOR LOCAL FAST_FORWARD FOR
    SELECT travail, premiere, derniere, description FROM @groupes ORDER BY ordre;
OPEN g;
FETCH NEXT FROM g INTO @travail, @premiere, @derniere, @desc;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- Suppression de l'ancienne version (relance du script)
    IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = @travail)
        EXEC dbo.sp_delete_job @job_name = @travail, @delete_unused_schedule = 1;

    EXEC dbo.sp_add_job @job_name = @travail, @description = @desc,
         @owner_login_name = @proprietaire, @notify_level_eventlog = 2;

    /* Passe 1 : copie des étapes, enchaînement provisoire (succès = fin, échec = fin en échec) */
    DECLARE e CURSOR LOCAL FAST_FORWARD FOR
        SELECT s.step_id, s.step_name, s.subsystem, s.command, CAST(s.additional_parameters AS NVARCHAR(MAX)),
               s.cmdexec_success_code, s.server, s.database_name, s.database_user_name,
               s.retry_attempts, s.retry_interval, s.output_file_name, s.flags, p.name
        FROM   dbo.sysjobsteps s
        LEFT JOIN dbo.sysproxies p ON p.proxy_id = s.proxy_id
        WHERE  s.job_id = @job_id_source AND s.step_id BETWEEN @premiere AND @derniere
        ORDER BY s.step_id;
    OPEN e;
    FETCH NEXT FROM e INTO @sid, @nom, @ss, @cmd, @param, @code, @srv, @db, @dbu, @retry, @retry_int, @out, @flags, @proxy;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @nouvel_id = @sid - @premiere + 1;
        EXEC dbo.sp_add_jobstep @job_name = @travail, @step_id = @nouvel_id, @step_name = @nom,
             @subsystem = @ss, @command = @cmd, @additional_parameters = @param,
             @cmdexec_success_code = @code, @on_success_action = 1, @on_fail_action = 2,
             @server = @srv, @database_name = @db, @database_user_name = @dbu,
             @retry_attempts = @retry, @retry_interval = @retry_int,
             @output_file_name = @out, @flags = @flags, @proxy_name = @proxy;
        FETCH NEXT FROM e INTO @sid, @nom, @ss, @cmd, @param, @code, @srv, @db, @dbu, @retry, @retry_int, @out, @flags, @proxy;
    END
    CLOSE e;
    DEALLOCATE e;

    /* Passe 2 : enchaînement identique au job de nuit, renuméroté dans le travail AF.
       - « étape suivante » sur la dernière étape du groupe = fin en succès
         (dans le job de nuit, la chaîne continuait : Airflow prend le relais) ;
       - « aller à l'étape N » dans le groupe = renuméroté ;
       - « aller à l'étape N » hors du groupe = fin en succès (même logique). */
    DECLARE a CURSOR LOCAL FAST_FORWARD FOR
        SELECT step_id, on_success_action, on_success_step_id, on_fail_action, on_fail_step_id
        FROM   dbo.sysjobsteps
        WHERE  job_id = @job_id_source AND step_id BETWEEN @premiere AND @derniere
        ORDER BY step_id;
    OPEN a;
    FETCH NEXT FROM a INTO @sid, @succ, @succ_id, @fail, @fail_id;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @succ_n = CASE WHEN @succ = 3 AND @sid = @derniere                     THEN 1
                           WHEN @succ = 4 AND @succ_id BETWEEN @premiere AND @derniere THEN 4
                           WHEN @succ = 4                                          THEN 1
                           ELSE @succ END;
        SET @fail_n = CASE WHEN @fail = 3 AND @sid = @derniere                     THEN 1
                           WHEN @fail = 4 AND @fail_id BETWEEN @premiere AND @derniere THEN 4
                           WHEN @fail = 4                                          THEN 1
                           ELSE @fail END;
        SET @succ_id_n = CASE WHEN @succ_n = 4 THEN @succ_id - @premiere + 1 ELSE 0 END;
        SET @fail_id_n = CASE WHEN @fail_n = 4 THEN @fail_id - @premiere + 1 ELSE 0 END;
        SET @nouvel_id = @sid - @premiere + 1;

        EXEC dbo.sp_update_jobstep @job_name = @travail, @step_id = @nouvel_id,
             @on_success_action = @succ_n, @on_success_step_id = @succ_id_n,
             @on_fail_action = @fail_n, @on_fail_step_id = @fail_id_n;
        FETCH NEXT FROM a INTO @sid, @succ, @succ_id, @fail, @fail_id;
    END
    CLOSE a;
    DEALLOCATE a;

    EXEC dbo.sp_add_jobserver @job_name = @travail, @server_name = N'(local)';
    PRINT N'2. Travail créé : ' + @travail;

    FETCH NEXT FROM g INTO @travail, @premiere, @derniere, @desc;
END
CLOSE g;
DEALLOCATE g;

/* Contrôle : compare avec ton job de nuit, les commandes doivent être identiques */
SELECT j.name AS travail, s.step_id AS etape, s.step_name AS nom_etape, s.subsystem AS type,
       p.name AS proxy, s.server AS serveur,
       CASE s.on_success_action WHEN 1 THEN N'fin succès' WHEN 2 THEN N'fin échec' WHEN 3 THEN N'étape suivante'
            ELSE N'aller à ' + CAST(s.on_success_step_id AS NVARCHAR(10)) END AS si_succes,
       CASE s.on_fail_action    WHEN 1 THEN N'fin succès' WHEN 2 THEN N'fin échec' WHEN 3 THEN N'étape suivante'
            ELSE N'aller à ' + CAST(s.on_fail_step_id AS NVARCHAR(10)) END AS si_echec,
       s.command AS commande
FROM   dbo.sysjobs j
JOIN   dbo.sysjobsteps s ON s.job_id = j.job_id
LEFT JOIN dbo.sysproxies p ON p.proxy_id = s.proxy_id
WHERE  j.name LIKE N'TuniShop AF%' OR j.name = N'TuniShop - Chaine complete'
ORDER BY CASE WHEN j.name LIKE N'TuniShop AF%' THEN 1 ELSE 0 END, j.name, s.step_id;
GO
