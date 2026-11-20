/* =============================================================================
   TuniShop — Étape 7, version 1.4 : text mining des avis
   Script 09 : vues pbi.v_tm_*, catalogue et contrôles
   Auteure : Sarra Abdeljaouad

   Version 1.5.2 : pbi.v_tm_avis réécrite. Le transporteur de l'avis (celui de la 1re livraison de la commande)
   était cherché avis par avis (OUTER APPLY ... TOP (1)) : 6 081 recherches dans les livraisons, 157 s à l'export
   du 20/11/2026. Il est maintenant calculé en une passe (ROW_NUMBER), même règle, même résultat (script 09b).

   ORDRE : exécuter APRÈS le notebook 02_Data_Mining/05_Text_Mining_Avis.
   Le notebook crée et remplit les 4 tables ana.tm_* (via cfg.exporter_table) ;
   ce script crée les vues qui les lisent (une vue SQL Server exige que ses tables existent).

   Exécution : SSMS, instance ABDELJAOUAD (localhost), F5. Le script peut être relancé.
   ============================================================================= */
USE TuniShop_ANALYTICS;
GO

IF OBJECT_ID(N'ana.tm_avis', N'U') IS NULL OR OBJECT_ID(N'ana.tm_avis_themes', N'U') IS NULL
   OR OBJECT_ID(N'ana.tm_produits', N'U') IS NULL OR OBJECT_ID(N'ana.tm_verification_faits', N'U') IS NULL
BEGIN
    RAISERROR(N'Tables ana.tm_* absentes : exécute d''abord le notebook 02_Data_Mining/05_Text_Mining_Avis.', 16, 1);
    SET NOEXEC ON;     -- la suite du script n'est pas exécutée
END
GO

/* -----------------------------------------------------------------------------
   1. Un avis commenté par ligne, avec client et transporteur
   ----------------------------------------------------------------------------- */
CREATE OR ALTER VIEW pbi.v_tm_avis
AS
-- Transporteur de la 1re livraison de chaque commande (plus petit livraison_id dont le transporteur est connu),
-- calculé une seule fois pour toutes les commandes, puis joint aux avis (v1.5.2 : remplace un OUTER APPLY ligne à ligne).
WITH premiere_livraison AS (
    SELECT l.commande_id, t.nom_transporteur,
           ROW_NUMBER() OVER (PARTITION BY l.commande_id ORDER BY l.livraison_id) AS rang
    FROM TuniShop_DWH.bi.v_fact_livraisons AS l
    JOIN TuniShop_DWH.bi.v_dim_transporteur AS t ON t.transporteur_sk = l.transporteur_sk
)
SELECT a.avis_id, a.commande_id, a.client_sk, c.client_id, a.produit_id, a.categorie,
       a.date_avis, a.note, a.sentiment_dwh, a.langue, a.texte_nettoye, a.texte_fr,
       a.themes, a.nb_themes, a.polarite_globale, a.coherence,
       tr.nom_transporteur AS transporteur
FROM ana.tm_avis AS a
LEFT JOIN TuniShop_DWH.bi.v_dim_client AS c ON c.client_sk = a.client_sk
LEFT JOIN premiere_livraison AS tr ON tr.commande_id = a.commande_id AND tr.rang = 1;
GO

/* -----------------------------------------------------------------------------
   2. Un thème d'avis par ligne, avec le contexte de l'avis (pour compter par thème)
   ----------------------------------------------------------------------------- */
CREATE OR ALTER VIEW pbi.v_tm_avis_themes
AS
SELECT t.avis_id, t.theme, t.polarite, t.langue,
       a.commande_id, a.client_id, a.produit_id, a.categorie, a.date_avis,
       DATEFROMPARTS(YEAR(a.date_avis), MONTH(a.date_avis), 1) AS mois,
       a.note, a.transporteur
FROM ana.tm_avis_themes AS t
JOIN pbi.v_tm_avis AS a ON a.avis_id = t.avis_id;
GO

/* -----------------------------------------------------------------------------
   3. Synthèse par produit, avec son nom
   ----------------------------------------------------------------------------- */
CREATE OR ALTER VIEW pbi.v_tm_produits
AS
SELECT s.produit_id, p.nom_produit, s.categorie, s.nb_avis, s.note_moyenne, s.nb_commentes,
       s.part_derja, s.part_positif, s.part_negatif, s.theme_negatif_principal, s.nb_incoherents
FROM ana.tm_produits AS s
LEFT JOIN TuniShop_DWH.bi.v_dim_produit AS p
       ON p.produit_id = s.produit_id AND p.est_courant = 1 AND p.produit_sk > 0;
GO

/* -----------------------------------------------------------------------------
   4. Confrontation aux faits (thème x polarité)
   ----------------------------------------------------------------------------- */
CREATE OR ALTER VIEW pbi.v_tm_verification_faits
AS
SELECT v.theme, v.polarite, v.avis, v.part_colis_en_retard, v.part_retour,
       v.motifs_lies, v.part_retour_motif_lie
FROM ana.tm_verification_faits AS v;
GO

/* -----------------------------------------------------------------------------
   5. Catalogue des tables (même format que 02_Tables_ana.sql)
   ----------------------------------------------------------------------------- */
MERGE ctl.catalogue_tables AS cible
USING (VALUES
    (N'ana.tm_avis', N'Data mining', N'05_Text_Mining_Avis', N'06_Exports/Tables/TM_avis.csv', N'avis_id', N'avis_id, client_sk, produit_id', N'Un avis commenté par ligne : langue, texte traduit, thèmes, polarité globale, cohérence avec la note'),
    (N'ana.tm_avis_themes', N'Data mining', N'05_Text_Mining_Avis', N'06_Exports/Tables/TM_avis_themes.csv', N'avis_id, theme', N'avis_id', N'Un thème d''avis par ligne, avec sa polarité'),
    (N'ana.tm_produits', N'Data mining', N'05_Text_Mining_Avis', N'06_Exports/Tables/TM_produits.csv', N'produit_id', N'produit_id', N'Synthèse du text mining par produit'),
    (N'ana.tm_verification_faits', N'Data mining', N'05_Text_Mining_Avis', N'06_Exports/Tables/TM_verification_faits.csv', NULL, NULL, N'Confrontation des thèmes d''avis aux faits du DWH : retards et retours')
) AS source (table_sql, phase, notebook, source, cle, lien_dwh, description)
ON cible.table_sql = source.table_sql
WHEN MATCHED THEN UPDATE SET phase = source.phase, notebook = source.notebook, source = source.source,
                             cle = source.cle, lien_dwh = source.lien_dwh, description = source.description
WHEN NOT MATCHED THEN INSERT (table_sql, phase, notebook, source, cle, lien_dwh, description)
                      VALUES (source.table_sql, source.phase, source.notebook, source.source, source.cle, source.lien_dwh, source.description);
GO

/* =============================================================================
   CONTRÔLES (résultats à reporter dans la recette)
   ============================================================================= */
-- T1. Un avis commenté du DWH = une ligne dans ana.tm_avis (les deux nombres égaux)
SELECT (SELECT COUNT(*) FROM ana.tm_avis) AS tm_avis,
       (SELECT COUNT(*) FROM TuniShop_DWH.bi.v_fact_avis WHERE a_commentaire = 1) AS dwh_avis_commentes;

-- T2. Aucun avis sans thème, aucun thème orphelin (attendu : 0 et 0)
SELECT (SELECT COUNT(*) FROM ana.tm_avis WHERE nb_themes = 0) AS avis_sans_theme,
       (SELECT COUNT(*) FROM ana.tm_avis_themes AS t
         WHERE NOT EXISTS (SELECT 1 FROM ana.tm_avis AS a WHERE a.avis_id = t.avis_id)) AS themes_orphelins;

-- T3. Clients et produits retrouvés dans le DWH (attendu : 0 et 0)
SELECT (SELECT COUNT(*) FROM pbi.v_tm_avis WHERE client_id IS NULL) AS clients_absents,
       (SELECT COUNT(*) FROM pbi.v_tm_produits WHERE nom_produit IS NULL) AS produits_absents;

-- T4. Répartition par langue et par polarité (à comparer au notebook, section 3)
SELECT langue, polarite_globale, COUNT(*) AS avis
FROM ana.tm_avis GROUP BY langue, polarite_globale ORDER BY langue, polarite_globale;

-- T6. (v1.5.2) Durée de lecture des vues : quelques secondes au plus (157 s et 132 s avant la réécriture)
DECLARE @t0 DATETIME2 = SYSDATETIME();
SELECT COUNT(*) AS avis, COUNT(transporteur) AS avis_avec_transporteur FROM pbi.v_tm_avis;
SELECT COUNT(*) AS themes FROM pbi.v_tm_avis_themes;
SELECT DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) / 1000.0 AS duree_s;

-- T5. Les 4 tables sont publiées et tracées
SELECT table_sql, lignes, publie_le
FROM ctl.v_derniere_publication WHERE table_sql LIKE N'ana.tm[_]%' ORDER BY table_sql;

PRINT N'Étape 09 terminée : 4 vues pbi.v_tm_* et catalogue à jour.';
GO
SET NOEXEC OFF;
GO
