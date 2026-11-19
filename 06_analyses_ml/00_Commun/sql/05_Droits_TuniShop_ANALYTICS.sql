/* =====================================================================================
   TuniShop — 05. Droits d'accès entre TuniShop_ANALYTICS et TuniShop_DWH
   =====================================================================================
   Auteure   : Sarra Abdeljaouad
   À lancer  : après 04 (F5 dans SSMS). Peut être relancé sans risque.

   Faut-il le lancer ?
     - Si les notebooks et Power BI tournent avec TON compte Windows et que ce compte est
       administrateur (sysadmin) du serveur : NON, tu as déjà tous les droits.
       (Le script crée quand même les deux rôles ; il ne donne des droits à personne
        tant que les deux variables ci-dessous sont vides.)
     - Si le job SQL Server Agent lance les notebooks avec un autre compte (compte du proxy
       du job, visible dans SSMS : Agent SQL Server > Proxys) : OUI -> @compte_job.
     - Si une autre personne lit le tableau de bord Power BI : OUI -> @compte_lecteur.

   Pourquoi des droits dans DEUX bases ?
     Les vues pbi lisent TuniShop_DWH.bi.v_... Entre deux bases, SQL Server vérifie les droits
     du compte dans les DEUX bases (le chaînage de propriété entre bases est désactivé par défaut).

   Aucun mot de passe : comptes Windows uniquement (CREATE LOGIN ... FROM WINDOWS).
   ===================================================================================== */

SET NOCOUNT ON;

-- >>> À ADAPTER : nom complet des comptes Windows (ex. N'MONPC\Sarra'), ou N'' pour aucun
DECLARE @compte_job     SYSNAME = N'';   -- compte qui exécute les notebooks dans le job
DECLARE @compte_lecteur SYSNAME = N'';   -- compte d'un lecteur du tableau de bord Power BI

DECLARE @sql NVARCHAR(MAX);

/* ---------- 1. Les deux rôles de TuniShop_ANALYTICS ---------- */
EXEC (N'USE TuniShop_ANALYTICS;
IF DATABASE_PRINCIPAL_ID(N''role_publication'') IS NULL CREATE ROLE role_publication AUTHORIZATION dbo;
-- écrire les résultats : remplir, vider, recréer les tables du schéma ana
GRANT SELECT, INSERT, UPDATE, DELETE, ALTER ON SCHEMA::ana TO role_publication;
GRANT CREATE TABLE TO role_publication;
GRANT SELECT, INSERT ON ctl.journal_publication TO role_publication;
GRANT SELECT ON SCHEMA::ctl TO role_publication;
GRANT EXECUTE ON ctl.usp_controler_publication TO role_publication;
GRANT SELECT ON SCHEMA::pbi TO role_publication;

IF DATABASE_PRINCIPAL_ID(N''role_lecture_pbi'') IS NULL CREATE ROLE role_lecture_pbi AUTHORIZATION dbo;
-- lire le tableau de bord : uniquement les vues pbi
GRANT SELECT ON SCHEMA::pbi TO role_lecture_pbi;');
PRINT N'Rôles role_publication et role_lecture_pbi prêts dans TuniShop_ANALYTICS.';

/* ---------- 2. Un compte : login Windows + utilisateur dans les 2 bases + droits ---------- */
DECLARE @comptes TABLE (compte SYSNAME, role_analytics SYSNAME);
INSERT INTO @comptes VALUES (@compte_job, N'role_publication'), (@compte_lecteur, N'role_lecture_pbi');

DECLARE @compte SYSNAME, @role SYSNAME;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT compte, role_analytics FROM @comptes WHERE compte <> N'';
OPEN c;
FETCH NEXT FROM c INTO @compte, @role;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- 2a. connexion au serveur
    IF SUSER_ID(@compte) IS NULL
    BEGIN
        SET @sql = N'CREATE LOGIN ' + QUOTENAME(@compte) + N' FROM WINDOWS;';
        EXEC (@sql);
    END
    -- 2b. DWH : lecture des vues bi seulement (jamais les tables dw)
    SET @sql = N'USE TuniShop_DWH;
        IF USER_ID(N' + QUOTENAME(@compte, '''') + N') IS NULL CREATE USER ' + QUOTENAME(@compte) + N' FOR LOGIN ' + QUOTENAME(@compte) + N';
        GRANT SELECT ON SCHEMA::bi TO ' + QUOTENAME(@compte) + N';';
    EXEC (@sql);
    -- 2c. ANALYTICS : membre du rôle
    SET @sql = N'USE TuniShop_ANALYTICS;
        IF USER_ID(N' + QUOTENAME(@compte, '''') + N') IS NULL CREATE USER ' + QUOTENAME(@compte) + N' FOR LOGIN ' + QUOTENAME(@compte) + N';
        ALTER ROLE ' + QUOTENAME(@role) + N' ADD MEMBER ' + QUOTENAME(@compte) + N';';
    EXEC (@sql);
    PRINT N'Droits donnés à ' + @compte + N' (' + @role + N' + lecture de TuniShop_DWH.bi).';
    FETCH NEXT FROM c INTO @compte, @role;
END
CLOSE c;
DEALLOCATE c;

/* ---------- 3. Vérification : membres des deux rôles ---------- */
EXEC (N'USE TuniShop_ANALYTICS;
SELECT r.name AS role_bdd, m.name AS membre
FROM sys.database_role_members AS rm
JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals AS m ON m.principal_id = rm.member_principal_id
WHERE r.name IN (N''role_publication'', N''role_lecture_pbi'');');
