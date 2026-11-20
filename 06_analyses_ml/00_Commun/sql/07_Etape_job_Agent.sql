/* =====================================================================================
   TuniShop — 07. Ajouter l'analyse au job de nuit SQL Server Agent (FACULTATIF)
   =====================================================================================
   Auteure   : Sarra Abdeljaouad
   Version   : 1.2 (06/11/2026)
   À lancer  : sur localhost (ABDELJAOUAD), l'instance qui porte le job « TuniShop - Chaine complete »
               et SQL Server Agent (instance passée de Express à Developer le 05/11/2026).

   Historique
     1.2  06/11/2026  La commande redéfinit USERPROFILE, APPDATA et LOCALAPPDATA avant de lancer Python.
                      Sous l'Agent, le profil Windows n'est pas chargé : Python ne voyait pas les
                      bibliothèques installées dans AppData\Roaming\Python (jupyter_core, ipykernel)
                      et s'arrêtait sur « No module named jupyter ».
     1.1  06/11/2026  La commande passe par « cmd /c cd /d <racine> && python ... ».
                      Lancé directement, python.exe (situé dans le profil utilisateur) provoquait
                      « The process could not be created ... (reason: Accès refusé) » : l'Agent
                      ne peut pas ouvrir un exécutable du profil ; cmd.exe, lui, est accessible.
                      Ajout d'un fichier journal de l'étape (@dossier_logs).
     1.0  Création.

   Ce que fait le script
     1. ajoute à la FIN du job une étape « Analyse et publication » (type CmdExec) qui lance
        00_Commun/executer_analyse.py : EDA, data mining, ML puis publication dans TuniShop_ANALYTICS ;
     2. modifie la dernière étape actuelle pour qu'en cas de SUCCÈS elle passe à cette nouvelle
        étape (au lieu de terminer le job). En cas d'échec, elle garde son comportement :
        l'analyse ne tourne jamais sur un DWH mal chargé.
     Si l'étape existe déjà, le script ne fait rien.

   Avant de lancer : adapter les 3 variables ci-dessous.
     @python   : chemin complet de python.exe (celui où pandas, pyodbc... sont installés)
     @racine   : dossier TuniShop_Etape7_Analyse sur ton PC
     @proxy    : proxy de l'étape (le même que tes étapes Python / SSIS), ou NULL pour le compte
                 du service Agent. Ce compte doit avoir les droits du script 05.
     @profil   : profil Windows du compte du proxy (pour retrouver ses bibliothèques Python).
     @dossier_logs : dossier des journaux de l'Agent (le compte NT Service\SQLSERVERAGENT doit
                 pouvoir y écrire). NULL = pas de fichier journal pour l'étape.
   Aucun mot de passe ici : le proxy utilise le credential déjà créé dans SSMS.
   ===================================================================================== */

USE msdb;
GO

DECLARE @nom_job SYSNAME       = N'TuniShop - Chaine complete';
DECLARE @nom_etape SYSNAME     = N'Analyse et publication (notebooks)';
-- >>> À ADAPTER
DECLARE @python NVARCHAR(400)  = N'C:\chemin\vers\python.exe'   -- À ADAPTER : « where python » dans PowerShell;
DECLARE @racine NVARCHAR(400)  = N'C:\chemin\vers\tunishop-projet-data-bi\06_analyses_ml'   -- À ADAPTER : dossier du projet;
DECLARE @proxy SYSNAME         = N'Proxy_TuniShop';
DECLARE @dossier_logs NVARCHAR(400) = N'C:\TuniShop\6-Automatisation\Logs_Agent';
DECLARE @profil NVARCHAR(400)  = N'C:\Users\<ton_utilisateur>';   -- À ADAPTER : profil Windows du compte du proxy

DECLARE @job_id UNIQUEIDENTIFIER = (SELECT job_id FROM dbo.sysjobs WHERE name = @nom_job);
IF @job_id IS NULL
BEGIN
    RAISERROR (N'Job « %s » introuvable sur cette instance.', 16, 1, @nom_job);
    RETURN;
END
IF EXISTS (SELECT 1 FROM dbo.sysjobsteps WHERE job_id = @job_id AND step_name = @nom_etape)
BEGIN
    PRINT N'L''étape existe déjà : rien à faire.';
    RETURN;
END

-- 1. La dernière étape actuelle passera à l'étape suivante en cas de succès (on_success_action = 3)
DECLARE @derniere INT = (SELECT MAX(step_id) FROM dbo.sysjobsteps WHERE job_id = @job_id);
EXEC dbo.sp_update_jobstep @job_id = @job_id, @step_id = @derniere, @on_success_action = 3;

-- 2. Nouvelle étape : python executer_analyse.py (toutes les phases), lancé par cmd.exe depuis @racine
DECLARE @commande NVARCHAR(MAX) =
      N'cmd /c set "USERPROFILE=' + @profil + N'"'
    + N' && set "APPDATA=' + @profil + N'\AppData\Roaming"'
    + N' && set "LOCALAPPDATA=' + @profil + N'\AppData\Local"'
    + N' && cd /d "' + @racine + N'" && "' + @python + N'" "00_Commun\executer_analyse.py"';
DECLARE @fichier NVARCHAR(400)  = CASE WHEN @dossier_logs IS NULL THEN NULL
                                       ELSE @dossier_logs + N'\04_Analyse_et_publication.log' END;
EXEC dbo.sp_add_jobstep
     @job_id            = @job_id,
     @step_name         = @nom_etape,
     @subsystem         = N'CmdExec',
     @command           = @commande,
     @proxy_name        = @proxy,
     @on_success_action = 1,      -- fin du job : succès
     @on_fail_action    = 2,      -- fin du job : échec (visible dans l'historique)
     @retry_attempts    = 0,
     @output_file_name  = @fichier,
     @flags             = 0;      -- le fichier journal est remplacé à chaque exécution

PRINT N'Étape ajoutée en position ' + CAST(@derniere + 1 AS NVARCHAR(10)) + N' : ' + @commande;

-- 3. Vérification : les étapes du job dans l'ordre
SELECT s.step_id, s.step_name, s.subsystem,
       CASE s.on_success_action WHEN 1 THEN N'fin (succès)' WHEN 3 THEN N'étape suivante' ELSE CAST(s.on_success_action AS NVARCHAR(5)) END AS si_succes,
       CASE s.on_fail_action    WHEN 2 THEN N'fin (échec)'  WHEN 3 THEN N'étape suivante' ELSE CAST(s.on_fail_action AS NVARCHAR(5)) END AS si_echec
FROM dbo.sysjobsteps AS s
WHERE s.job_id = @job_id
ORDER BY s.step_id;
GO
