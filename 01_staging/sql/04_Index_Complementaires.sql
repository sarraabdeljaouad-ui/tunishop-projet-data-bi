/* =====================================================================
   Projet      : TuniShop — Data Warehouse e-commerce (portfolio)
   Script      : 04_Index_Complementaires.sql
   Objet       : Index complémentaires pour les procédures CLEAN → INTEGRATED
                 et la base de contrôle TuniShop_ADMIN.
   Exécution   : SSMS, script complet (F5). Peut être exécuté APRÈS l'ingestion :
                 ne modifie aucune donnée ; relançable sans risque (IF NOT EXISTS).
                 Ne pas lancer pendant un chargement (verrou bref sur les tables).
   Prérequis   : 01_Creation_Bases.sql et 02_Audit_Logs.sql exécutés.
   À relancer  : après toute réexécution de 01_Creation_Bases.sql (qui recrée les tables).
   ===================================================================== */
SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------
   1. TuniShop_STG_CLEAN — colonnes lues par les procédures INTEGRATED
   --------------------------------------------------------------------- */
USE [TuniShop_STG_CLEAN];
GO
-- Règle QR48 : date d'entrée en stock de chaque commande fournisseur (10 370 recherches parmi 140 184 mouvements)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_clean_mouvements_reference' AND object_id = OBJECT_ID(N'clean.mouvements_stock'))
    CREATE INDEX IX_clean_mouvements_reference ON clean.mouvements_stock (reference_id, type_mouvement) INCLUDE (date_mouvement);

-- Totaux par commande (nb_lignes, nb_articles, sous-totaux, coût d'achat)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_clean_lignes_commande_commande' AND object_id = OBJECT_ID(N'clean.lignes_commande'))
    CREATE INDEX IX_clean_lignes_commande_commande ON clean.lignes_commande (commande_id)
        INCLUDE (quantite, montant_ligne_ttc, montant_ligne_ht, cout_achat_unitaire_ht);

-- Règle QR26 : rapprochement des paiements orphelins (commandes sans paiement)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_clean_paiements_commande' AND object_id = OBJECT_ID(N'clean.paiements'))
    CREATE INDEX IX_clean_paiements_commande ON clean.paiements (commande_id);

-- Règle QR27 : détection des clients en double (prénom + nom + téléphone)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_clean_clients_identite' AND object_id = OBJECT_ID(N'clean.clients'))
    CREATE INDEX IX_clean_clients_identite ON clean.clients (prenom, nom, telephone);

-- Dates de première et dernière commande par client
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_clean_commandes_client' AND object_id = OBJECT_ID(N'clean.commandes'))
    CREATE INDEX IX_clean_commandes_client ON clean.commandes (client_id) INCLUDE (date_commande);
GO

/* ---------------------------------------------------------------------
   2. TuniShop_STG_INTEGRATED — quarantaine
   --------------------------------------------------------------------- */
USE [TuniShop_STG_INTEGRATED];
GO
-- Purge et bilan des rejets par lot
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_integ_rejets_lot' AND object_id = OBJECT_ID(N'integ.rejets'))
    CREATE INDEX IX_integ_rejets_lot ON integ.rejets (id_chargement, table_source, regle_id);
GO

/* ---------------------------------------------------------------------
   3. TuniShop_ADMIN — lecture de la supervision par lot
   --------------------------------------------------------------------- */
USE [TuniShop_ADMIN];
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_journal_erreur_lot' AND object_id = OBJECT_ID(N'audit.journal_erreur'))
    CREATE INDEX IX_journal_erreur_lot ON audit.journal_erreur (id_chargement);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_fichier_source_lot' AND object_id = OBJECT_ID(N'audit.fichier_source'))
    CREATE INDEX IX_fichier_source_lot ON audit.fichier_source (id_chargement);
GO

/* ---------------------------------------------------------------------
   4. Vérification : 9 index attendus
   --------------------------------------------------------------------- */
SELECT 'TuniShop_STG_CLEAN' AS base, OBJECT_SCHEMA_NAME(i.object_id, DB_ID('TuniShop_STG_CLEAN')) + '.' + OBJECT_NAME(i.object_id, DB_ID('TuniShop_STG_CLEAN')) AS table_, i.name AS index_
FROM TuniShop_STG_CLEAN.sys.indexes i
WHERE i.name IN ('IX_clean_mouvements_reference','IX_clean_lignes_commande_commande','IX_clean_paiements_commande','IX_clean_clients_identite','IX_clean_commandes_client')
UNION ALL
SELECT 'TuniShop_STG_INTEGRATED', 'integ.rejets', name FROM TuniShop_STG_INTEGRATED.sys.indexes WHERE name = 'IX_integ_rejets_lot'
UNION ALL
SELECT 'TuniShop_ADMIN', OBJECT_SCHEMA_NAME(i.object_id, DB_ID('TuniShop_ADMIN')) + '.' + OBJECT_NAME(i.object_id, DB_ID('TuniShop_ADMIN')), i.name
FROM TuniShop_ADMIN.sys.indexes i WHERE i.name IN ('IX_journal_erreur_lot','IX_fichier_source_lot')
ORDER BY base, index_;
GO
PRINT N'Index complémentaires créés ou déjà présents.';
GO
