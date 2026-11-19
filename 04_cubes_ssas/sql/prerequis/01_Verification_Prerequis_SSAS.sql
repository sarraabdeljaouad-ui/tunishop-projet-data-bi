/* =====================================================================
   01_Verification_Prerequis_SSAS.sql — TuniShop
   Phase 05 · Modèle décisionnel → prêt pour la phase 06 (cube SSAS Tabular)
   ---------------------------------------------------------------------
   Ce script vérifie, AVANT de créer le projet Tabular, que les vues bi.*
   du DWH correspondent exactement au modèle sémantique conçu
   (Specification_Modele_Semantique.xlsx).
   Résultat attendu : toutes les sections renvoient « OK » ou 0.
   Lecture seule : aucune donnée n'est modifiée.
   Chaque section est un lot séparé (GO) : si une colonne manque, seule la
   section concernée échoue, et la section 2 vous dit laquelle.
   Auteure : Sarra Abdeljaouad · 21/10/2026 (conception) · généré le 22/10/2026
   ===================================================================== */
USE TuniShop_DWH;
SET NOCOUNT ON;

/* 0. Édition du moteur relationnel (information).
      Rappel : SSAS Tabular n'est pas disponible avec l'édition Express ;
      il faut installer l'édition Developer (gratuite, dev/test). */
SELECT SERVERPROPERTY('Edition') AS edition, SERVERPROPERTY('ProductVersion') AS version;

/* 1. Les 23 vues sources du cube existent-elles ? (attendu : 0 ligne MANQUANTE) */
DECLARE @vues TABLE (nom_table SYSNAME, nature NVARCHAR(20));
INSERT INTO @vues VALUES
    (N'dim_date', N'Dimension'),
    (N'dim_client', N'Dimension'),
    (N'dim_produit', N'Dimension'),
    (N'dim_fournisseur', N'Dimension'),
    (N'dim_geographie', N'Dimension'),
    (N'dim_entrepot', N'Dimension'),
    (N'dim_transporteur', N'Dimension'),
    (N'dim_campagne', N'Dimension'),
    (N'dim_coupon', N'Dimension'),
    (N'dim_canal', N'Dimension'),
    (N'dim_mode_paiement', N'Dimension'),
    (N'dim_statut_commande', N'Dimension'),
    (N'dim_motif_retour', N'Dimension'),
    (N'fact_ventes', N'Fait'),
    (N'fact_commandes', N'Fait'),
    (N'fact_paiements', N'Fait'),
    (N'fact_livraisons', N'Fait'),
    (N'fact_remboursements', N'Fait'),
    (N'fact_avis', N'Fait'),
    (N'fact_marketing_quotidien', N'Fait'),
    (N'fact_achats_fournisseur', N'Fait'),
    (N'fact_mouvements_stock', N'Fait'),
    (N'fact_stock_mensuel', N'Fait');
SELECT v.nom_table, N'bi.v_' + v.nom_table AS vue_attendue, v.nature,
       CASE WHEN o.object_id IS NULL THEN N'MANQUANTE' ELSE N'OK' END AS statut
FROM @vues v
LEFT JOIN sys.views o ON o.name = N'v_' + v.nom_table AND SCHEMA_NAME(o.schema_id) = N'bi'
ORDER BY statut DESC, v.nature, v.nom_table;

/* 2. Les colonnes utilisées par le modèle sont-elles présentes dans les vues ?
      (attendu : 0 ligne). Une colonne manquante = à ajouter à la vue OU à retirer
      de la spécification avant de créer le projet Tabular. */
DECLARE @cols TABLE (vue SYSNAME, colonne SYSNAME);
INSERT INTO @cols VALUES
    (N'v_dim_date', N'date_sk'),
    (N'v_dim_date', N'date'),
    (N'v_dim_date', N'annee'),
    (N'v_dim_date', N'trimestre'),
    (N'v_dim_date', N'libelle_trimestre'),
    (N'v_dim_date', N'mois'),
    (N'v_dim_date', N'nom_mois'),
    (N'v_dim_date', N'annee_mois'),
    (N'v_dim_date', N'semaine_iso'),
    (N'v_dim_date', N'jour_mois'),
    (N'v_dim_date', N'jour_semaine'),
    (N'v_dim_date', N'nom_jour'),
    (N'v_dim_date', N'est_weekend'),
    (N'v_dim_date', N'est_jour_ferie'),
    (N'v_dim_date', N'nom_jour_ferie'),
    (N'v_dim_date', N'est_ramadan'),
    (N'v_dim_date', N'periode_commerciale'),
    (N'v_dim_client', N'client_sk'),
    (N'v_dim_client', N'client_id'),
    (N'v_dim_client', N'type_client'),
    (N'v_dim_client', N'nom_complet'),
    (N'v_dim_client', N'genre'),
    (N'v_dim_client', N'tranche_age'),
    (N'v_dim_client', N'gouvernorat_id'),
    (N'v_dim_client', N'gouvernorat'),
    (N'v_dim_client', N'region'),
    (N'v_dim_client', N'ville'),
    (N'v_dim_client', N'canal_inscription'),
    (N'v_dim_client', N'date_inscription'),
    (N'v_dim_client', N'cohorte_inscription'),
    (N'v_dim_client', N'opt_in_email'),
    (N'v_dim_client', N'opt_in_sms'),
    (N'v_dim_client', N'segment_fidelite'),
    (N'v_dim_client', N'date_debut_validite'),
    (N'v_dim_client', N'date_fin_validite'),
    (N'v_dim_client', N'est_courant'),
    (N'v_dim_produit', N'produit_sk'),
    (N'v_dim_produit', N'produit_id'),
    (N'v_dim_produit', N'prix_id'),
    (N'v_dim_produit', N'sku'),
    (N'v_dim_produit', N'nom_produit'),
    (N'v_dim_produit', N'marque'),
    (N'v_dim_produit', N'categorie'),
    (N'v_dim_produit', N'sous_categorie'),
    (N'v_dim_produit', N'fournisseur_id'),
    (N'v_dim_produit', N'taux_tva'),
    (N'v_dim_produit', N'gamme_prix'),
    (N'v_dim_produit', N'statut_produit'),
    (N'v_dim_produit', N'prix_catalogue_ttc'),
    (N'v_dim_produit', N'cout_achat_unitaire_ht'),
    (N'v_dim_produit', N'taux_retour_cible'),
    (N'v_dim_produit', N'marge_brute_cible'),
    (N'v_dim_produit', N'date_debut_validite'),
    (N'v_dim_produit', N'date_fin_validite'),
    (N'v_dim_produit', N'est_courant'),
    (N'v_dim_fournisseur', N'fournisseur_sk'),
    (N'v_dim_fournisseur', N'fournisseur_id'),
    (N'v_dim_fournisseur', N'nom_fournisseur'),
    (N'v_dim_fournisseur', N'pays'),
    (N'v_dim_fournisseur', N'est_local'),
    (N'v_dim_fournisseur', N'delai_appro_moyen_j'),
    (N'v_dim_fournisseur', N'conditions_paiement'),
    (N'v_dim_fournisseur', N'fiabilite_livraison'),
    (N'v_dim_geographie', N'geographie_sk'),
    (N'v_dim_geographie', N'gouvernorat_id'),
    (N'v_dim_geographie', N'gouvernorat'),
    (N'v_dim_geographie', N'region'),
    (N'v_dim_geographie', N'zone_livraison'),
    (N'v_dim_geographie', N'entrepot_rattachement'),
    (N'v_dim_geographie', N'pays'),
    (N'v_dim_entrepot', N'entrepot_sk'),
    (N'v_dim_entrepot', N'entrepot_id'),
    (N'v_dim_entrepot', N'nom_entrepot'),
    (N'v_dim_entrepot', N'ville'),
    (N'v_dim_entrepot', N'region'),
    (N'v_dim_entrepot', N'surface_m2'),
    (N'v_dim_entrepot', N'date_ouverture'),
    (N'v_dim_transporteur', N'transporteur_sk'),
    (N'v_dim_transporteur', N'transporteur_id'),
    (N'v_dim_transporteur', N'nom_transporteur'),
    (N'v_dim_transporteur', N'couverture'),
    (N'v_dim_transporteur', N'cout_base_ht'),
    (N'v_dim_campagne', N'campagne_sk'),
    (N'v_dim_campagne', N'campagne_id'),
    (N'v_dim_campagne', N'nom_campagne'),
    (N'v_dim_campagne', N'canal_media'),
    (N'v_dim_campagne', N'type_canal'),
    (N'v_dim_campagne', N'objectif'),
    (N'v_dim_campagne', N'theme'),
    (N'v_dim_campagne', N'date_debut'),
    (N'v_dim_campagne', N'date_fin'),
    (N'v_dim_campagne', N'budget_ht'),
    (N'v_dim_coupon', N'coupon_sk'),
    (N'v_dim_coupon', N'code_coupon'),
    (N'v_dim_coupon', N'type_remise'),
    (N'v_dim_coupon', N'valeur'),
    (N'v_dim_coupon', N'montant_min_ttc'),
    (N'v_dim_coupon', N'reserve_premiere_commande'),
    (N'v_dim_canal', N'canal_sk'),
    (N'v_dim_canal', N'canal'),
    (N'v_dim_canal', N'appareil'),
    (N'v_dim_canal', N'libelle_canal'),
    (N'v_dim_mode_paiement', N'mode_paiement_sk'),
    (N'v_dim_mode_paiement', N'mode_paiement'),
    (N'v_dim_mode_paiement', N'libelle_mode_paiement'),
    (N'v_dim_mode_paiement', N'est_paiement_differe'),
    (N'v_dim_statut_commande', N'statut_commande_sk'),
    (N'v_dim_statut_commande', N'statut_commande'),
    (N'v_dim_statut_commande', N'libelle_statut'),
    (N'v_dim_statut_commande', N'famille_statut'),
    (N'v_dim_statut_commande', N'est_ca_reconnu'),
    (N'v_dim_motif_retour', N'motif_retour_sk'),
    (N'v_dim_motif_retour', N'type_remboursement'),
    (N'v_dim_motif_retour', N'motif'),
    (N'v_dim_motif_retour', N'libelle_motif'),
    (N'v_dim_motif_retour', N'responsabilite'),
    (N'v_fact_ventes', N'ligne_id'),
    (N'v_fact_ventes', N'commande_id'),
    (N'v_fact_ventes', N'date_commande_sk'),
    (N'v_fact_ventes', N'client_sk'),
    (N'v_fact_ventes', N'produit_sk'),
    (N'v_fact_ventes', N'geographie_sk'),
    (N'v_fact_ventes', N'entrepot_sk'),
    (N'v_fact_ventes', N'canal_sk'),
    (N'v_fact_ventes', N'campagne_sk'),
    (N'v_fact_ventes', N'coupon_sk'),
    (N'v_fact_ventes', N'statut_commande_sk'),
    (N'v_fact_ventes', N'quantite'),
    (N'v_fact_ventes', N'prix_catalogue_ttc'),
    (N'v_fact_ventes', N'prix_unitaire_ttc'),
    (N'v_fact_ventes', N'montant_brut_ttc'),
    (N'v_fact_ventes', N'montant_remise_promo_ttc'),
    (N'v_fact_ventes', N'montant_ttc'),
    (N'v_fact_ventes', N'montant_ht'),
    (N'v_fact_ventes', N'montant_tva'),
    (N'v_fact_ventes', N'cout_achat_ht'),
    (N'v_fact_ventes', N'marge_brute_ht'),
    (N'v_fact_ventes', N'est_ca_reconnu'),
    (N'v_fact_commandes', N'commande_id'),
    (N'v_fact_commandes', N'date_commande_sk'),
    (N'v_fact_commandes', N'date_expedition_sk'),
    (N'v_fact_commandes', N'date_livraison_sk'),
    (N'v_fact_commandes', N'date_annulation_sk'),
    (N'v_fact_commandes', N'client_sk'),
    (N'v_fact_commandes', N'geographie_sk'),
    (N'v_fact_commandes', N'entrepot_sk'),
    (N'v_fact_commandes', N'canal_sk'),
    (N'v_fact_commandes', N'campagne_sk'),
    (N'v_fact_commandes', N'coupon_sk'),
    (N'v_fact_commandes', N'mode_paiement_sk'),
    (N'v_fact_commandes', N'statut_commande_sk'),
    (N'v_fact_commandes', N'nb_lignes'),
    (N'v_fact_commandes', N'nb_articles'),
    (N'v_fact_commandes', N'sous_total_ttc'),
    (N'v_fact_commandes', N'remise_coupon_ttc'),
    (N'v_fact_commandes', N'frais_livraison_ttc'),
    (N'v_fact_commandes', N'montant_total_ttc'),
    (N'v_fact_commandes', N'cout_achat_ht'),
    (N'v_fact_commandes', N'cout_transport_ht'),
    (N'v_fact_commandes', N'montant_rembourse_ttc'),
    (N'v_fact_commandes', N'nb_tentatives_paiement'),
    (N'v_fact_commandes', N'delai_livraison_j'),
    (N'v_fact_commandes', N'est_premiere_commande'),
    (N'v_fact_commandes', N'est_livree_a_temps'),
    (N'v_fact_commandes', N'est_ca_reconnu'),
    (N'v_fact_paiements', N'paiement_id'),
    (N'v_fact_paiements', N'commande_id'),
    (N'v_fact_paiements', N'date_paiement_sk'),
    (N'v_fact_paiements', N'date_reversement_sk'),
    (N'v_fact_paiements', N'client_sk'),
    (N'v_fact_paiements', N'mode_paiement_sk'),
    (N'v_fact_paiements', N'num_tentative'),
    (N'v_fact_paiements', N'statut_paiement'),
    (N'v_fact_paiements', N'code_erreur'),
    (N'v_fact_paiements', N'prestataire'),
    (N'v_fact_paiements', N'montant_ttc'),
    (N'v_fact_paiements', N'est_reussi'),
    (N'v_fact_paiements', N'delai_reversement_j'),
    (N'v_fact_livraisons', N'livraison_id'),
    (N'v_fact_livraisons', N'commande_id'),
    (N'v_fact_livraisons', N'date_expedition_sk'),
    (N'v_fact_livraisons', N'date_prevue_sk'),
    (N'v_fact_livraisons', N'date_livraison_sk'),
    (N'v_fact_livraisons', N'client_sk'),
    (N'v_fact_livraisons', N'entrepot_sk'),
    (N'v_fact_livraisons', N'transporteur_sk'),
    (N'v_fact_livraisons', N'geographie_sk'),
    (N'v_fact_livraisons', N'statut_livraison'),
    (N'v_fact_livraisons', N'nb_tentatives'),
    (N'v_fact_livraisons', N'poids_kg'),
    (N'v_fact_livraisons', N'cout_transport_ht'),
    (N'v_fact_livraisons', N'delai_preparation_h'),
    (N'v_fact_livraisons', N'delai_livraison_j'),
    (N'v_fact_livraisons', N'retard_j'),
    (N'v_fact_livraisons', N'est_livree'),
    (N'v_fact_livraisons', N'est_livree_a_temps'),
    (N'v_fact_livraisons', N'est_premiere_tentative'),
    (N'v_fact_remboursements', N'remboursement_id'),
    (N'v_fact_remboursements', N'commande_id'),
    (N'v_fact_remboursements', N'date_demande_sk'),
    (N'v_fact_remboursements', N'date_remboursement_sk'),
    (N'v_fact_remboursements', N'client_sk'),
    (N'v_fact_remboursements', N'produit_sk'),
    (N'v_fact_remboursements', N'motif_retour_sk'),
    (N'v_fact_remboursements', N'mode_remboursement'),
    (N'v_fact_remboursements', N'statut'),
    (N'v_fact_remboursements', N'etat_article'),
    (N'v_fact_remboursements', N'quantite'),
    (N'v_fact_remboursements', N'montant_demande_ttc'),
    (N'v_fact_remboursements', N'montant_rembourse_ttc'),
    (N'v_fact_remboursements', N'delai_traitement_j'),
    (N'v_fact_avis', N'avis_id'),
    (N'v_fact_avis', N'commande_id'),
    (N'v_fact_avis', N'date_avis_sk'),
    (N'v_fact_avis', N'client_sk'),
    (N'v_fact_avis', N'produit_sk'),
    (N'v_fact_avis', N'note'),
    (N'v_fact_avis', N'sentiment'),
    (N'v_fact_avis', N'a_commentaire'),
    (N'v_fact_avis', N'commentaire'),
    (N'v_fact_marketing_quotidien', N'depense_id'),
    (N'v_fact_marketing_quotidien', N'date_sk'),
    (N'v_fact_marketing_quotidien', N'campagne_sk'),
    (N'v_fact_marketing_quotidien', N'depense_ht'),
    (N'v_fact_marketing_quotidien', N'impressions'),
    (N'v_fact_marketing_quotidien', N'clics'),
    (N'v_fact_marketing_quotidien', N'commandes_attribuees'),
    (N'v_fact_marketing_quotidien', N'nouveaux_clients_attribues'),
    (N'v_fact_marketing_quotidien', N'ca_attribue_ttc'),
    (N'v_fact_achats_fournisseur', N'ligne_cf_id'),
    (N'v_fact_achats_fournisseur', N'commande_fournisseur_id'),
    (N'v_fact_achats_fournisseur', N'date_commande_sk'),
    (N'v_fact_achats_fournisseur', N'date_prevue_sk'),
    (N'v_fact_achats_fournisseur', N'date_reception_sk'),
    (N'v_fact_achats_fournisseur', N'fournisseur_sk'),
    (N'v_fact_achats_fournisseur', N'produit_sk'),
    (N'v_fact_achats_fournisseur', N'entrepot_sk'),
    (N'v_fact_achats_fournisseur', N'statut'),
    (N'v_fact_achats_fournisseur', N'quantite_commandee'),
    (N'v_fact_achats_fournisseur', N'quantite_recue'),
    (N'v_fact_achats_fournisseur', N'cout_unitaire_ht'),
    (N'v_fact_achats_fournisseur', N'montant_ht'),
    (N'v_fact_achats_fournisseur', N'delai_appro_reel_j'),
    (N'v_fact_achats_fournisseur', N'retard_appro_j'),
    (N'v_fact_mouvements_stock', N'mouvement_id'),
    (N'v_fact_mouvements_stock', N'date_sk'),
    (N'v_fact_mouvements_stock', N'produit_sk'),
    (N'v_fact_mouvements_stock', N'entrepot_sk'),
    (N'v_fact_mouvements_stock', N'type_mouvement'),
    (N'v_fact_mouvements_stock', N'sens'),
    (N'v_fact_mouvements_stock', N'reference_id'),
    (N'v_fact_mouvements_stock', N'quantite'),
    (N'v_fact_mouvements_stock', N'valeur_ht'),
    (N'v_fact_stock_mensuel', N'date_sk'),
    (N'v_fact_stock_mensuel', N'produit_sk'),
    (N'v_fact_stock_mensuel', N'entrepot_sk'),
    (N'v_fact_stock_mensuel', N'inventaire_id'),
    (N'v_fact_stock_mensuel', N'stock_fin_mois'),
    (N'v_fact_stock_mensuel', N'quantite_en_commande'),
    (N'v_fact_stock_mensuel', N'valeur_stock_ht'),
    (N'v_fact_stock_mensuel', N'est_rupture');
SELECT c.vue, c.colonne, N'COLONNE ABSENTE DE LA VUE' AS statut
FROM @cols c
LEFT JOIN INFORMATION_SCHEMA.COLUMNS i
       ON i.TABLE_SCHEMA = N'bi' AND i.TABLE_NAME = c.vue AND i.COLUMN_NAME = c.colonne
WHERE i.COLUMN_NAME IS NULL
ORDER BY c.vue, c.colonne;

/* 3. Colonnes présentes dans les vues mais absentes de la spécification (information :
      à masquer ou à documenter). */
SELECT i.TABLE_NAME AS vue, i.COLUMN_NAME AS colonne, N'NON SPÉCIFIÉE' AS statut
FROM INFORMATION_SCHEMA.COLUMNS i
JOIN @vues v ON i.TABLE_NAME = N'v_' + v.nom_table AND i.TABLE_SCHEMA = N'bi'
LEFT JOIN @cols c ON c.vue = i.TABLE_NAME AND c.colonne = i.COLUMN_NAME
WHERE c.colonne IS NULL AND i.COLUMN_NAME NOT IN (N'id_chargement', N'date_maj', N'hash_scd2', N'est_supprime')
ORDER BY 1, 2;

GO

/* 4. Volumes par vue (à reporter dans la recette du cube, onglet 09). */
SELECT vue, lignes FROM (
SELECT N'v_dim_date', COUNT_BIG(*) FROM bi.v_dim_date
UNION ALL SELECT N'v_dim_client', COUNT_BIG(*) FROM bi.v_dim_client
UNION ALL SELECT N'v_dim_produit', COUNT_BIG(*) FROM bi.v_dim_produit
UNION ALL SELECT N'v_dim_fournisseur', COUNT_BIG(*) FROM bi.v_dim_fournisseur
UNION ALL SELECT N'v_dim_geographie', COUNT_BIG(*) FROM bi.v_dim_geographie
UNION ALL SELECT N'v_dim_entrepot', COUNT_BIG(*) FROM bi.v_dim_entrepot
UNION ALL SELECT N'v_dim_transporteur', COUNT_BIG(*) FROM bi.v_dim_transporteur
UNION ALL SELECT N'v_dim_campagne', COUNT_BIG(*) FROM bi.v_dim_campagne
UNION ALL SELECT N'v_dim_coupon', COUNT_BIG(*) FROM bi.v_dim_coupon
UNION ALL SELECT N'v_dim_canal', COUNT_BIG(*) FROM bi.v_dim_canal
UNION ALL SELECT N'v_dim_mode_paiement', COUNT_BIG(*) FROM bi.v_dim_mode_paiement
UNION ALL SELECT N'v_dim_statut_commande', COUNT_BIG(*) FROM bi.v_dim_statut_commande
UNION ALL SELECT N'v_dim_motif_retour', COUNT_BIG(*) FROM bi.v_dim_motif_retour
UNION ALL SELECT N'v_fact_ventes', COUNT_BIG(*) FROM bi.v_fact_ventes
UNION ALL SELECT N'v_fact_commandes', COUNT_BIG(*) FROM bi.v_fact_commandes
UNION ALL SELECT N'v_fact_paiements', COUNT_BIG(*) FROM bi.v_fact_paiements
UNION ALL SELECT N'v_fact_livraisons', COUNT_BIG(*) FROM bi.v_fact_livraisons
UNION ALL SELECT N'v_fact_remboursements', COUNT_BIG(*) FROM bi.v_fact_remboursements
UNION ALL SELECT N'v_fact_avis', COUNT_BIG(*) FROM bi.v_fact_avis
UNION ALL SELECT N'v_fact_marketing_quotidien', COUNT_BIG(*) FROM bi.v_fact_marketing_quotidien
UNION ALL SELECT N'v_fact_achats_fournisseur', COUNT_BIG(*) FROM bi.v_fact_achats_fournisseur
UNION ALL SELECT N'v_fact_mouvements_stock', COUNT_BIG(*) FROM bi.v_fact_mouvements_stock
UNION ALL SELECT N'v_fact_stock_mensuel', COUNT_BIG(*) FROM bi.v_fact_stock_mensuel
) x(vue, lignes) ORDER BY vue;

GO

/* 5. Unicité des clés de dimension (attendu : 0 doublon partout). */
SELECT vue, cle, doublons FROM (
SELECT N'v_dim_date', N'date_sk', COUNT_BIG(*) - COUNT_BIG(DISTINCT date_sk) FROM bi.v_dim_date
UNION ALL SELECT N'v_dim_client', N'client_sk', COUNT_BIG(*) - COUNT_BIG(DISTINCT client_sk) FROM bi.v_dim_client
UNION ALL SELECT N'v_dim_produit', N'produit_sk', COUNT_BIG(*) - COUNT_BIG(DISTINCT produit_sk) FROM bi.v_dim_produit
UNION ALL SELECT N'v_dim_fournisseur', N'fournisseur_sk', COUNT_BIG(*) - COUNT_BIG(DISTINCT fournisseur_sk) FROM bi.v_dim_fournisseur
UNION ALL SELECT N'v_dim_geographie', N'geographie_sk', COUNT_BIG(*) - COUNT_BIG(DISTINCT geographie_sk) FROM bi.v_dim_geographie
UNION ALL SELECT N'v_dim_entrepot', N'entrepot_sk', COUNT_BIG(*) - COUNT_BIG(DISTINCT entrepot_sk) FROM bi.v_dim_entrepot
UNION ALL SELECT N'v_dim_transporteur', N'transporteur_sk', COUNT_BIG(*) - COUNT_BIG(DISTINCT transporteur_sk) FROM bi.v_dim_transporteur
UNION ALL SELECT N'v_dim_campagne', N'campagne_sk', COUNT_BIG(*) - COUNT_BIG(DISTINCT campagne_sk) FROM bi.v_dim_campagne
UNION ALL SELECT N'v_dim_coupon', N'coupon_sk', COUNT_BIG(*) - COUNT_BIG(DISTINCT coupon_sk) FROM bi.v_dim_coupon
UNION ALL SELECT N'v_dim_canal', N'canal_sk', COUNT_BIG(*) - COUNT_BIG(DISTINCT canal_sk) FROM bi.v_dim_canal
UNION ALL SELECT N'v_dim_mode_paiement', N'mode_paiement_sk', COUNT_BIG(*) - COUNT_BIG(DISTINCT mode_paiement_sk) FROM bi.v_dim_mode_paiement
UNION ALL SELECT N'v_dim_statut_commande', N'statut_commande_sk', COUNT_BIG(*) - COUNT_BIG(DISTINCT statut_commande_sk) FROM bi.v_dim_statut_commande
UNION ALL SELECT N'v_dim_motif_retour', N'motif_retour_sk', COUNT_BIG(*) - COUNT_BIG(DISTINCT motif_retour_sk) FROM bi.v_dim_motif_retour
) x(vue, cle, doublons) ORDER BY doublons DESC, vue;

GO

/* 6. Intégrité des 54 relations du modèle (attendu : 0 ligne orpheline partout).
      Les clés -1 (inconnu) et -2 (non applicable) doivent exister dans chaque dimension. */
SELECT fait, cle, dimension, lignes_orphelines FROM (
SELECT N'fact_ventes' AS fait, N'date_commande_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_ventes f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_commande_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_ventes' AS fait, N'client_sk' AS cle, N'dim_client' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_ventes f LEFT JOIN bi.v_dim_client d ON d.client_sk = f.client_sk
WHERE d.client_sk IS NULL
UNION ALL
SELECT N'fact_ventes' AS fait, N'produit_sk' AS cle, N'dim_produit' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_ventes f LEFT JOIN bi.v_dim_produit d ON d.produit_sk = f.produit_sk
WHERE d.produit_sk IS NULL
UNION ALL
SELECT N'fact_ventes' AS fait, N'geographie_sk' AS cle, N'dim_geographie' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_ventes f LEFT JOIN bi.v_dim_geographie d ON d.geographie_sk = f.geographie_sk
WHERE d.geographie_sk IS NULL
UNION ALL
SELECT N'fact_ventes' AS fait, N'entrepot_sk' AS cle, N'dim_entrepot' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_ventes f LEFT JOIN bi.v_dim_entrepot d ON d.entrepot_sk = f.entrepot_sk
WHERE d.entrepot_sk IS NULL
UNION ALL
SELECT N'fact_ventes' AS fait, N'canal_sk' AS cle, N'dim_canal' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_ventes f LEFT JOIN bi.v_dim_canal d ON d.canal_sk = f.canal_sk
WHERE d.canal_sk IS NULL
UNION ALL
SELECT N'fact_ventes' AS fait, N'campagne_sk' AS cle, N'dim_campagne' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_ventes f LEFT JOIN bi.v_dim_campagne d ON d.campagne_sk = f.campagne_sk
WHERE d.campagne_sk IS NULL
UNION ALL
SELECT N'fact_ventes' AS fait, N'coupon_sk' AS cle, N'dim_coupon' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_ventes f LEFT JOIN bi.v_dim_coupon d ON d.coupon_sk = f.coupon_sk
WHERE d.coupon_sk IS NULL
UNION ALL
SELECT N'fact_ventes' AS fait, N'statut_commande_sk' AS cle, N'dim_statut_commande' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_ventes f LEFT JOIN bi.v_dim_statut_commande d ON d.statut_commande_sk = f.statut_commande_sk
WHERE d.statut_commande_sk IS NULL
UNION ALL
SELECT N'fact_commandes' AS fait, N'date_commande_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_commandes f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_commande_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_commandes' AS fait, N'date_expedition_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_commandes f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_expedition_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_commandes' AS fait, N'date_livraison_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_commandes f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_livraison_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_commandes' AS fait, N'date_annulation_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_commandes f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_annulation_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_commandes' AS fait, N'client_sk' AS cle, N'dim_client' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_commandes f LEFT JOIN bi.v_dim_client d ON d.client_sk = f.client_sk
WHERE d.client_sk IS NULL
UNION ALL
SELECT N'fact_commandes' AS fait, N'geographie_sk' AS cle, N'dim_geographie' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_commandes f LEFT JOIN bi.v_dim_geographie d ON d.geographie_sk = f.geographie_sk
WHERE d.geographie_sk IS NULL
UNION ALL
SELECT N'fact_commandes' AS fait, N'entrepot_sk' AS cle, N'dim_entrepot' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_commandes f LEFT JOIN bi.v_dim_entrepot d ON d.entrepot_sk = f.entrepot_sk
WHERE d.entrepot_sk IS NULL
UNION ALL
SELECT N'fact_commandes' AS fait, N'canal_sk' AS cle, N'dim_canal' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_commandes f LEFT JOIN bi.v_dim_canal d ON d.canal_sk = f.canal_sk
WHERE d.canal_sk IS NULL
UNION ALL
SELECT N'fact_commandes' AS fait, N'campagne_sk' AS cle, N'dim_campagne' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_commandes f LEFT JOIN bi.v_dim_campagne d ON d.campagne_sk = f.campagne_sk
WHERE d.campagne_sk IS NULL
UNION ALL
SELECT N'fact_commandes' AS fait, N'coupon_sk' AS cle, N'dim_coupon' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_commandes f LEFT JOIN bi.v_dim_coupon d ON d.coupon_sk = f.coupon_sk
WHERE d.coupon_sk IS NULL
UNION ALL
SELECT N'fact_commandes' AS fait, N'mode_paiement_sk' AS cle, N'dim_mode_paiement' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_commandes f LEFT JOIN bi.v_dim_mode_paiement d ON d.mode_paiement_sk = f.mode_paiement_sk
WHERE d.mode_paiement_sk IS NULL
UNION ALL
SELECT N'fact_commandes' AS fait, N'statut_commande_sk' AS cle, N'dim_statut_commande' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_commandes f LEFT JOIN bi.v_dim_statut_commande d ON d.statut_commande_sk = f.statut_commande_sk
WHERE d.statut_commande_sk IS NULL
UNION ALL
SELECT N'fact_paiements' AS fait, N'date_paiement_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_paiements f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_paiement_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_paiements' AS fait, N'date_reversement_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_paiements f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_reversement_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_paiements' AS fait, N'client_sk' AS cle, N'dim_client' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_paiements f LEFT JOIN bi.v_dim_client d ON d.client_sk = f.client_sk
WHERE d.client_sk IS NULL
UNION ALL
SELECT N'fact_paiements' AS fait, N'mode_paiement_sk' AS cle, N'dim_mode_paiement' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_paiements f LEFT JOIN bi.v_dim_mode_paiement d ON d.mode_paiement_sk = f.mode_paiement_sk
WHERE d.mode_paiement_sk IS NULL
UNION ALL
SELECT N'fact_livraisons' AS fait, N'date_expedition_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_livraisons f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_expedition_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_livraisons' AS fait, N'date_prevue_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_livraisons f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_prevue_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_livraisons' AS fait, N'date_livraison_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_livraisons f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_livraison_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_livraisons' AS fait, N'client_sk' AS cle, N'dim_client' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_livraisons f LEFT JOIN bi.v_dim_client d ON d.client_sk = f.client_sk
WHERE d.client_sk IS NULL
UNION ALL
SELECT N'fact_livraisons' AS fait, N'entrepot_sk' AS cle, N'dim_entrepot' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_livraisons f LEFT JOIN bi.v_dim_entrepot d ON d.entrepot_sk = f.entrepot_sk
WHERE d.entrepot_sk IS NULL
UNION ALL
SELECT N'fact_livraisons' AS fait, N'transporteur_sk' AS cle, N'dim_transporteur' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_livraisons f LEFT JOIN bi.v_dim_transporteur d ON d.transporteur_sk = f.transporteur_sk
WHERE d.transporteur_sk IS NULL
UNION ALL
SELECT N'fact_livraisons' AS fait, N'geographie_sk' AS cle, N'dim_geographie' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_livraisons f LEFT JOIN bi.v_dim_geographie d ON d.geographie_sk = f.geographie_sk
WHERE d.geographie_sk IS NULL
UNION ALL
SELECT N'fact_remboursements' AS fait, N'date_demande_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_remboursements f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_demande_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_remboursements' AS fait, N'date_remboursement_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_remboursements f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_remboursement_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_remboursements' AS fait, N'client_sk' AS cle, N'dim_client' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_remboursements f LEFT JOIN bi.v_dim_client d ON d.client_sk = f.client_sk
WHERE d.client_sk IS NULL
UNION ALL
SELECT N'fact_remboursements' AS fait, N'produit_sk' AS cle, N'dim_produit' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_remboursements f LEFT JOIN bi.v_dim_produit d ON d.produit_sk = f.produit_sk
WHERE d.produit_sk IS NULL
UNION ALL
SELECT N'fact_remboursements' AS fait, N'motif_retour_sk' AS cle, N'dim_motif_retour' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_remboursements f LEFT JOIN bi.v_dim_motif_retour d ON d.motif_retour_sk = f.motif_retour_sk
WHERE d.motif_retour_sk IS NULL
UNION ALL
SELECT N'fact_avis' AS fait, N'date_avis_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_avis f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_avis_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_avis' AS fait, N'client_sk' AS cle, N'dim_client' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_avis f LEFT JOIN bi.v_dim_client d ON d.client_sk = f.client_sk
WHERE d.client_sk IS NULL
UNION ALL
SELECT N'fact_avis' AS fait, N'produit_sk' AS cle, N'dim_produit' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_avis f LEFT JOIN bi.v_dim_produit d ON d.produit_sk = f.produit_sk
WHERE d.produit_sk IS NULL
UNION ALL
SELECT N'fact_marketing_quotidien' AS fait, N'date_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_marketing_quotidien f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_marketing_quotidien' AS fait, N'campagne_sk' AS cle, N'dim_campagne' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_marketing_quotidien f LEFT JOIN bi.v_dim_campagne d ON d.campagne_sk = f.campagne_sk
WHERE d.campagne_sk IS NULL
UNION ALL
SELECT N'fact_achats_fournisseur' AS fait, N'date_commande_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_achats_fournisseur f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_commande_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_achats_fournisseur' AS fait, N'date_prevue_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_achats_fournisseur f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_prevue_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_achats_fournisseur' AS fait, N'date_reception_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_achats_fournisseur f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_reception_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_achats_fournisseur' AS fait, N'fournisseur_sk' AS cle, N'dim_fournisseur' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_achats_fournisseur f LEFT JOIN bi.v_dim_fournisseur d ON d.fournisseur_sk = f.fournisseur_sk
WHERE d.fournisseur_sk IS NULL
UNION ALL
SELECT N'fact_achats_fournisseur' AS fait, N'produit_sk' AS cle, N'dim_produit' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_achats_fournisseur f LEFT JOIN bi.v_dim_produit d ON d.produit_sk = f.produit_sk
WHERE d.produit_sk IS NULL
UNION ALL
SELECT N'fact_achats_fournisseur' AS fait, N'entrepot_sk' AS cle, N'dim_entrepot' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_achats_fournisseur f LEFT JOIN bi.v_dim_entrepot d ON d.entrepot_sk = f.entrepot_sk
WHERE d.entrepot_sk IS NULL
UNION ALL
SELECT N'fact_mouvements_stock' AS fait, N'date_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_mouvements_stock f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_mouvements_stock' AS fait, N'produit_sk' AS cle, N'dim_produit' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_mouvements_stock f LEFT JOIN bi.v_dim_produit d ON d.produit_sk = f.produit_sk
WHERE d.produit_sk IS NULL
UNION ALL
SELECT N'fact_mouvements_stock' AS fait, N'entrepot_sk' AS cle, N'dim_entrepot' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_mouvements_stock f LEFT JOIN bi.v_dim_entrepot d ON d.entrepot_sk = f.entrepot_sk
WHERE d.entrepot_sk IS NULL
UNION ALL
SELECT N'fact_stock_mensuel' AS fait, N'date_sk' AS cle, N'dim_date' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_stock_mensuel f LEFT JOIN bi.v_dim_date d ON d.date_sk = f.date_sk
WHERE d.date_sk IS NULL
UNION ALL
SELECT N'fact_stock_mensuel' AS fait, N'produit_sk' AS cle, N'dim_produit' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_stock_mensuel f LEFT JOIN bi.v_dim_produit d ON d.produit_sk = f.produit_sk
WHERE d.produit_sk IS NULL
UNION ALL
SELECT N'fact_stock_mensuel' AS fait, N'entrepot_sk' AS cle, N'dim_entrepot' AS dimension, COUNT(*) AS lignes_orphelines
FROM bi.v_fact_stock_mensuel f LEFT JOIN bi.v_dim_entrepot d ON d.entrepot_sk = f.entrepot_sk
WHERE d.entrepot_sk IS NULL
) r
ORDER BY lignes_orphelines DESC, fait, cle;

GO

/* 7. Table de dates : une ligne par jour, sans trou (obligatoire pour « Marquer comme table de dates »). */
SELECT MIN([date]) AS premiere_date, MAX([date]) AS derniere_date, COUNT(*) AS jours,
       DATEDIFF(DAY, MIN([date]), MAX([date])) + 1 AS jours_attendus,
       CASE WHEN COUNT(*) = DATEDIFF(DAY, MIN([date]), MAX([date])) + 1 AND COUNT(*) = COUNT(DISTINCT [date])
            THEN N'OK' ELSE N'TROU OU DOUBLON' END AS statut
FROM bi.v_dim_date WHERE date_sk > 0;

GO

/* 8. SCD2 : une seule version courante par client et par produit (attendu : 0). */
SELECT N'dim_client' AS dimension, COUNT(*) AS cles_avec_plusieurs_versions_courantes
FROM (SELECT client_id FROM bi.v_dim_client WHERE est_courant = 1 AND client_sk > 0 GROUP BY client_id HAVING COUNT(*) > 1) x
UNION ALL
SELECT N'dim_produit', COUNT(*)
FROM (SELECT produit_id FROM bi.v_dim_produit WHERE est_courant = 1 AND produit_sk > 0 GROUP BY produit_id HAVING COUNT(*) > 1) x;
GO
