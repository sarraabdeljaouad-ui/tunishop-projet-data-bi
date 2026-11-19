/* =====================================================================
   03_Charger_DWH_Option_A.sql — TuniShop
   Lancement du chargement du Data Warehouse depuis SSMS (option A)
   ---------------------------------------------------------------------
   À quoi sert ce script :
     - charger le DWH sans passer par SSIS (tests, mise au point) ;
     - dépanner : si un package SSIS échoue, l'exécuter pour voir
       l'erreur exacte, les volumes et les contrôles du lot.
   Prérequis :
     - 01_Creation_DWH.sql et 02_Procedures_DWH.sql déjà exécutés ;
     - le lot de staging est terminé (statut SUCCES ou AVERTISSEMENT).
   Utilisation :
     1. Renseigner @lot (numéro du lot de staging à charger).
     2. Exécuter tout le script (F5).
   Réexécution sans risque : les chargements sont en MERGE (pas de
   TRUNCATE) ; relancer le même lot ne crée pas de doublons.
   ===================================================================== */
USE TuniShop_DWH;
GO

DECLARE @lot INT = 8;   -- <<< numéro du lot à charger

/* 1. Le lot de staging est-il terminé avec succès ? Sinon on arrête. */
IF NOT EXISTS (SELECT 1 FROM TuniShop_ADMIN.audit.execution_lot
               WHERE id_chargement = @lot
                 AND statut IN ('SUCCES','AVERTISSEMENT')
                 AND date_fin IS NOT NULL)
BEGIN
    SELECT id_chargement, statut, date_fin
    FROM TuniShop_ADMIN.audit.execution_lot WHERE id_chargement = @lot;
    THROW 50100, N'Le lot de staging n''est pas terminé avec succès : chargement du DWH annulé.', 1;
END

/* 2. Chargement : dimensions puis faits, puis contrôles qualité */
EXEC dw.usp_charger_dwh @id_chargement = @lot;
EXEC dw.usp_charger_faits @id_chargement = @lot;

/* 3. Volumes par table (ajouts / modifications / suppressions) */
SELECT objet, nb_inseres AS ajouts, nb_maj AS modifications,
       nb_supprimes AS suppressions, date_fin
FROM TuniShop_ADMIN.audit.execution_tache
WHERE id_chargement = @lot AND couche = 'DWH'
ORDER BY id_tache;

/* 4. Résultat des contrôles qualité */
SELECT code_controle, description, valeur_mesuree, seuil, resultat
FROM TuniShop_ADMIN.audit.controle_resultat
WHERE id_chargement = @lot
ORDER BY id_controle;

/* 5. Erreurs éventuelles (vide = aucune erreur) */
SELECT objet, procedure_sql, ligne, message
FROM TuniShop_ADMIN.audit.journal_erreur
WHERE id_chargement = @lot;

/* 6. Contrôle rapide des volumes
      Attendu : fact_ventes 115 903 · fact_commandes 66 268 ·
                dim_client 16 000 · dim_produit 596 · dim_date ~1 800 */
SELECT 'fact_ventes' AS table_, COUNT(*) AS lignes FROM dw.fact_ventes WHERE est_supprime = 0
UNION ALL SELECT 'fact_commandes', COUNT(*) FROM dw.fact_commandes WHERE est_supprime = 0
UNION ALL SELECT 'dim_client', COUNT(*) FROM dw.dim_client WHERE est_courant = 1 AND client_sk > 0
UNION ALL SELECT 'dim_produit', COUNT(*) FROM dw.dim_produit WHERE est_courant = 1 AND produit_sk > 0
UNION ALL SELECT 'dim_date', COUNT(*) FROM dw.dim_date WHERE date_sk > 0;

/* 7. Chiffre d'affaires reconnu (vue utilisée par Power BI) */
SELECT CAST(SUM(montant_ttc) AS DECIMAL(18,2)) AS ca_ttc_reconnu
FROM bi.v_fact_ventes WHERE est_ca_reconnu = 1;
