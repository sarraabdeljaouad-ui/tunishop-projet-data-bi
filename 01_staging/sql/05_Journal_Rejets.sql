/* =====================================================================
   Projet      : TuniShop — Data Warehouse e-commerce (portfolio)
   Script      : 04b_Journal_Rejets.sql
   Objet       : Journal des rejets dans la base de contrôle TuniShop_ADMIN : catalogue des règles qualité, volumes attendus par règle et par niveau, vues de détail, de synthèse (constaté vs attendu) et de bilan par lot.
   Cible       : Microsoft SQL Server 2019+ (SSMS) — compatibilité 150
   Exécution   : SSMS, mode SQLCMD inutile ; exécuter en entier (F5)
   Généré le   : 2026-10-17 depuis le modèle de métadonnées du projet
   ===================================================================== */
SET NOCOUNT ON;
GO
/* Prérequis : 01, 02 et 03 exécutés.
   Script relançable sans perte : les tables sont créées si absentes, leur contenu est synchronisé (MERGE),
   les vues sont remplacées (CREATE OR ALTER). Ne touche ni aux rejets ni à l'historique des lots.

   Utilisation :
     SELECT * FROM TuniShop_ADMIN.audit.v_journal_rejets_bilan       ORDER BY id_chargement DESC;   -- conclusion par lot
     SELECT * FROM TuniShop_ADMIN.audit.v_journal_rejets_synthese    WHERE id_chargement = 3 ORDER BY couche, niveau, regle_id;
     SELECT * FROM TuniShop_ADMIN.audit.v_journal_rejets_par_table   WHERE id_chargement = 3;
     SELECT * FROM TuniShop_ADMIN.audit.v_journal_rejets_detail      WHERE id_chargement = 3 AND regle_id = 'QR27';
*/
USE [TuniShop_ADMIN];
GO

/* ---------------------------------------------------------------------
   1. Catalogue des règles qualité (copie de Regles_Qualite_Transformation.xlsx)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'audit.regle_qualite', N'U') IS NULL
CREATE TABLE audit.regle_qualite (
    regle_id         VARCHAR(10)    NOT NULL CONSTRAINT PK_regle_qualite PRIMARY KEY,
    couche           VARCHAR(20)    NOT NULL,
    table_cible      NVARCHAR(100)  NOT NULL,
    colonne          NVARCHAR(100)  NOT NULL,
    dimension        NVARCHAR(50)   NOT NULL,     -- unicité, validité, complétude, cohérence…
    anomalie         NVARCHAR(400)  NOT NULL,
    volume_constate  INT            NOT NULL,     -- volume mesuré pendant la conception
    regle            NVARCHAR(600)  NOT NULL,
    action           NVARCHAR(30)   NOT NULL,
    severite         NVARCHAR(20)   NOT NULL
);
GO
MERGE audit.regle_qualite AS t
USING (VALUES
    (N'QR01', N'STG_CLEAN', N'commandes', N'(ligne entière)', N'Unicité', N'Lignes en double exact (même commande_id, toutes colonnes identiques)', 300, N'Conserver une occurrence par commande_id (ROW_NUMBER() OVER (PARTITION BY commande_id ORDER BY id_chargement, num_ligne_fichier))', N'Dédoublonner', N'Bloquante'),
    (N'QR02', N'STG_CLEAN', N'lignes_commande', N'(ligne entière)', N'Unicité', N'Lignes en double exact', 120, N'Une occurrence par ligne_id', N'Dédoublonner', N'Bloquante'),
    (N'QR03', N'STG_CLEAN', N'mouvements_stock', N'(ligne entière)', N'Unicité', N'Lignes en double exact', 100, N'Une occurrence par mouvement_id', N'Dédoublonner', N'Bloquante'),
    (N'QR04', N'STG_CLEAN', N'avis_clients', N'(ligne entière)', N'Unicité', N'Lignes en double exact', 30, N'Une occurrence par avis_id', N'Dédoublonner', N'Bloquante'),
    (N'QR05', N'STG_CLEAN', N'paiements', N'(ligne entière)', N'Unicité', N'Lignes JSON en double exact', 644, N'Une occurrence par payment_id', N'Dédoublonner', N'Bloquante'),
    (N'QR06', N'STG_CLEAN', N'commandes', N'date_commande', N'Conformité de format', N'Format JJ/MM/AAAA HH:MI (secondes perdues) au lieu de AAAA-MM-JJ HH:MI:SS', 2650, N'Si motif ''__/__/____ __:__'' : reconstruire AAAA-MM-JJ HH:MI:00 puis TRY_CONVERT style 120', N'Corriger', N'Majeure'),
    (N'QR07', N'STG_CLEAN', N'clients', N'date_naissance', N'Conformité de format', N'Format JJ/MM/AAAA', 1262, N'TRY_CONVERT(DATE, x, 103) si motif ''__/__/____'', sinon style 23', N'Corriger', N'Majeure'),
    (N'QR08', N'STG_CLEAN', N'marketing_depenses_quotidiennes', N'date ; montants', N'Conformité de format', N'Séparateur '';'', virgule décimale, dates JJ/MM/AAAA (aussi campagnes et coupons pour les montants)', 3427, N'Lecture avec séparateur '';'' ; REPLACE('','', ''.'') avant conversion décimale ; style 103 pour les dates', N'Corriger', N'Majeure'),
    (N'QR09', N'STG_CLEAN', N'clients', N'telephone', N'Conformité de format', N'5 formats : 8 chiffres, 99-999-999, +216 99 999 999, 00216…, +216…', 1379, N'Garder les chiffres ; 8 chiffres → ''+216''+n ; 216+8 → ''+''+n ; 00216+8 → ''+216''+8 derniers ; sinon NULL + rejet', N'Corriger', N'Mineure'),
    (N'QR10', N'STG_CLEAN', N'clients', N'email', N'Validité', N'Majuscules ou espaces parasites', 365, N'LOWER(TRIM(email)) ; vide → NULL', N'Corriger', N'Mineure'),
    (N'QR11', N'STG_CLEAN', N'clients', N'ville', N'Conformité de format', N'Casse incohérente, espaces et accents perdus (Rades / Radès)', 615, N'TRIM puis graphie la plus fréquente de la même ville, comparée sans casse ni accents (COLLATE Latin1_General_CI_AI)', N'Corriger', N'Mineure'),
    (N'QR12', N'STG_CLEAN', N'clients', N'genre', N'Complétude', N'Genre manquant', 243, N'Imputation par le genre du prénom si celui-ci est non ambigu (≥ 90 % d''un même genre) ; genre_impute = 1', N'Imputer', N'Mineure'),
    (N'QR13', N'STG_CLEAN', N'commandes', N'statut_commande', N'Conformité de format', N'28 variantes (casse, accents, espaces) pour 8 statuts', 333, N'LOWER(TRIM()) + suppression des accents ; contrôle d''appartenance à la liste des 8 statuts', N'Corriger', N'Majeure'),
    (N'QR14', N'STG_CLEAN', N'livraisons', N'transporteur_id', N'Conformité de format', N'Identifiants en minuscules (tr01…)', 100, N'UPPER(TRIM())', N'Corriger', N'Mineure'),
    (N'QR15', N'STG_CLEAN', N'produits', N'marque', N'Conformité de format', N'Espaces finaux et casse incohérente', 15, N'TRIM puis graphie majoritaire de la marque (insensible à la casse)', N'Corriger', N'Mineure'),
    (N'QR16', N'STG_CLEAN', N'produits', N'categorie_id', N'Complétude', N'Catégorie manquante', 6, N'Déduction depuis le SKU : ''CAT'' + SUBSTRING(sku, 4, 2)', N'Imputer', N'Majeure'),
    (N'QR17', N'STG_CLEAN', N'produits', N'sku', N'Unicité', N'SKU dupliqués entre produits différents', 3, N'Reconstruction : ''TS-'' + RIGHT(categorie_id,2) + ''-'' + RIGHT(''00000''+numéro produit,5)', N'Corriger', N'Majeure'),
    (N'QR18', N'STG_CLEAN', N'produits', N'prix_catalogue_ttc_actuel', N'Validité', N'Prix négatif (3) ou nul (3)', 6, N'Remplacer par le prix de la dernière version de produits_prix_historique', N'Corriger', N'Bloquante'),
    (N'QR19', N'STG_CLEAN', N'commandes', N'canal', N'Complétude', N'Canal de vente manquant', 662, N'appareil ordinateur/tablette → ''site_web'' ; mobile → ''non_renseigne''', N'Imputer', N'Mineure'),
    (N'QR20', N'STG_CLEAN', N'commandes', N'montant_total_ttc', N'Cohérence', N'Total ≠ sous_total − remise_coupon + frais_livraison', 55, N'Recalcul montant_total_ttc = sous_total_ttc − remise_coupon_ttc + frais_livraison_ttc', N'Corriger', N'Bloquante'),
    (N'QR21', N'STG_CLEAN', N'lignes_commande', N'quantite', N'Validité', N'Quantité négative (36) ou nulle (9)', 45, N'quantite = ROUND(montant_ligne_ht × (1 + taux_tva/100) / prix_unitaire_ttc, 0)', N'Corriger', N'Bloquante'),
    (N'QR22', N'STG_CLEAN', N'lignes_commande', N'montant_ligne_ttc', N'Cohérence', N'Montant TTC ≠ quantité × prix unitaire', 40, N'montant_ligne_ttc = quantite × prix_unitaire_ttc (après QR21)', N'Corriger', N'Bloquante'),
    (N'QR23', N'STG_INTEGRATED', N'commandes', N'client_id', N'Intégrité référentielle', N'Client inexistant (CLI0999xxx)', 25, N'Conserver la commande, client_id_maitre = NULL → membre inconnu (-1) en DWH ; signalement', N'Signaler', N'Majeure'),
    (N'QR24', N'STG_INTEGRATED', N'lignes_commande', N'produit_id', N'Intégrité référentielle', N'Produit inexistant (PRD9xxx)', 20, N'Conserver la ligne, produit → membre inconnu (-1) ; signalement', N'Signaler', N'Majeure'),
    (N'QR25', N'STG_INTEGRATED', N'marketing_depenses_quotidiennes', N'campagne_id', N'Intégrité référentielle', N'Campagne inexistante (CMP9xxx)', 5, N'Rattacher à l''unique campagne du même canal active à la date ; sinon membre inconnu', N'Corriger', N'Majeure'),
    (N'QR26', N'STG_INTEGRATED', N'paiements', N'commande_id', N'Intégrité référentielle', N'Paiement sans commande', 15, N'Rapprochement : commande unique de même montant total et même mode, passée dans les 15 jours précédant le paiement et sans autre paiement ; sinon rejet (integ.rejets)', N'Corriger', N'Majeure'),
    (N'QR27', N'STG_INTEGRATED', N'clients', N'client_id', N'Unicité', N'Même personne sous deux identifiants (CLI9xxxxx)', 150, N'Paires de clients particuliers de même prénom + nom, même téléphone normalisé, et même date de naissance (ou absente d''un côté) ; maître = identifiant hors plage CLI9xxxxx ; table de correspondance', N'Dédoublonner', N'Bloquante'),
    (N'QR28', N'STG_CLEAN', N'avis_clients', N'note', N'Validité', N'Note hors 1–5 (0, 6, 10)', 10, N'Note mise à NULL (exclue des moyennes) ; rejet informatif', N'Corriger', N'Majeure'),
    (N'QR29', N'STG_CLEAN', N'avis_clients', N'commentaire', N'Conformité de format', N'Espaces parasites (10) et balises HTML <p>, <br/> (10)', 20, N'Suppression des balises, TRIM ; vide → NULL', N'Corriger', N'Mineure'),
    (N'QR30', N'STG_CLEAN', N'marketing_depenses_quotidiennes', N'impressions', N'Cohérence', N'Impressions inférieures aux clics', 15, N'Impressions mises à NULL ; signalement', N'Corriger', N'Mineure'),
    (N'QR31', N'STG_CLEAN', N'lignes_commande_fournisseur', N'quantite_recue', N'Cohérence', N'Quantité reçue > quantité commandée (facteur 10)', 10, N'Si multiple de 10 et ÷ 10 ≤ commandée : ÷ 10 (zéro en trop), sinon plafonner à quantite_commandee', N'Corriger', N'Majeure'),
    (N'QR32', N'STG_CLEAN', N'remboursements', N'montant_rembourse_ttc', N'Cohérence', N'Montant remboursé > montant demandé', 20, N'Plafonner à montant_demande_ttc', N'Corriger', N'Majeure'),
    (N'QR33', N'STG_CLEAN', N'remboursements', N'date_remboursement', N'Cohérence', N'Date de remboursement antérieure à la demande', 15, N'Mise à NULL + signalement (délai non calculable)', N'Signaler', N'Mineure'),
    (N'QR34', N'STG_CLEAN', N'livraisons', N'date_livraison_reelle', N'Cohérence', N'Livraison antérieure à l''expédition', 25, N'Remplacer par date_dernier_evenement', N'Corriger', N'Majeure'),
    (N'QR35', N'STG_CLEAN', N'livraisons', N'statut_livraison', N'Complétude', N'Statut manquant', 30, N'''livree'' si date_livraison_reelle renseignée, sinon ''en_transit'' si date_expedition, sinon ''en_preparation''', N'Imputer', N'Mineure'),
    (N'QR36', N'STG_CLEAN', N'mouvements_stock', N'quantite', N'Cohérence', N'Signe incohérent avec le type de mouvement', 40, N'vente, mise_au_rebut → −ABS ; entrées → +ABS ; ajustement_inventaire inchangé', N'Corriger', N'Majeure'),
    (N'QR37', N'STG_CLEAN', N'stocks_mensuels', N'stock_fin_mois', N'Validité', N'Stock de fin de mois négatif', 10, N'ABS(stock_fin_mois) + signalement', N'Corriger', N'Majeure'),
    (N'QR38', N'STG_INTEGRATED', N'clients', N'date_inscription', N'Validité', N'Date d''inscription future (toutes sur des doublons)', 38, N'Valeur du client maître conservée lors de la fusion ; contrôle date ≤ date de chargement', N'Signaler', N'Mineure'),
    (N'QR39', N'STG_CLEAN', N'paiements', N'method ; status ; created_at', N'Conformité de format', N'Codes anglais et horodatage UTC', 65137, N'Transcodage (COD→paiement_a_la_livraison, CARD→carte_bancaire, WALLET→portefeuille_mobile, PREPAID_CARD→carte_prepayee, BANK_TRANSFER→virement ; SUCCESS→reussi, COLLECTED→encaisse, FAILED→echoue) ; UTC → heure de Tunis (UTC+1)', N'Corriger', N'Majeure'),
    (N'QR40', N'STG_INTEGRATED', N'produits_prix_historique', N'est_prix_actuel', N'Exactitude', N'Indicateur jamais vrai', 1601, N'est_prix_actuel = 1 pour la version de date_fin maximale de chaque produit', N'Corriger', N'Mineure'),
    (N'QR41', N'STG_INTEGRATED', N'commandes', N'sous_total_ttc ; nb_lignes ; nb_articles', N'Cohérence', N'Écart entre l''en-tête et la somme des lignes', 0, N'Contrôle après corrections : écart attendu = 0 ; sinon signalement et en-tête recalculé depuis les lignes', N'Contrôler', N'Bloquante'),
    (N'QR42', N'STG_INTEGRATED', N'commandes', N'entrepot_id', N'Complétude', N'Entrepôt vide sur commandes annulées ou à paiement échoué (attendu métier)', 2206, N'Aucune correction ; membre ''Non affecté'' (-2) en DWH', N'Accepter', N'Info'),
    (N'QR43', N'STG_CLEAN', N'(toutes)', N'(toutes)', N'Conformité de format', N'Valeur non convertible dans le type cible', 0, N'TRY_CONVERT ; toute valeur non vide qui échoue → NULL + ligne dans clean.rejets', N'Rejeter', N'Majeure'),
    (N'QR44', N'STG_CLEAN', N'clients', N'date_naissance', N'Validité', N'Dates aberrantes (valeurs répétées 2015-07-03, 1880-11-30, 2031-05-12…) : âge < 16 ans, > 100 ans ou naissance future', 36, N'Mise à NULL si l''âge au 31/12/2025 sort de [16 ; 100] ans ; signalement', N'Corriger', N'Mineure'),
    (N'QR45', N'STG_CLEAN', N'clients', N'email', N'Validité', N'E-mails malformés : '' at '' (24), ''@@'' (25), ''@'' absent (31)', 80, N''' at '' → ''@'' ; ''@@'' → ''@'' ; ''@'' réinséré devant un domaine connu (gmail.com, hotmail.com, yahoo.fr, outlook.com, topnet.tn, gnet.tn) ; sinon NULL', N'Corriger', N'Mineure'),
    (N'QR46', N'STG_CLEAN', N'marketing_depenses_quotidiennes', N'depense_ht', N'Validité', N'Dépense négative', 10, N'ABS(depense_ht)', N'Corriger', N'Majeure'),
    (N'QR47', N'STG_INTEGRATED', N'paiements', N'montant_ttc', N'Exactitude', N'Montant multiplié par 1 000 (erreur d''unité millimes/dinars)', 50, N'Si montant / 1 000 = montant total de la commande : montant / 1 000 ; tout autre écart est signalé', N'Corriger', N'Bloquante'),
    (N'QR48', N'STG_INTEGRATED', N'commandes_fournisseurs', N'date_reception', N'Cohérence', N'Date de réception antérieure à la date de commande', 8, N'Remplacée par la date de la dernière entrée en stock (type reception_fournisseur) dont reference_id = commande_fournisseur_id ; signalement', N'Corriger', N'Majeure'),
    (N'QR49', N'STG_CLEAN', N'commandes', N'(fichier)', N'Exactitude', N'Commandes livrées dans le fichier mensuel suivant (données arrivées en retard)', 60, N'Concaténation des 36 fichiers puis dédoublonnage sur commande_id : chaque commande est chargée une seule fois, quel que soit son fichier ; le rechargement est idempotent', N'Contrôler', N'Mineure')
) AS s (regle_id, couche, table_cible, colonne, dimension, anomalie, volume_constate, regle, action, severite)
ON t.regle_id = s.regle_id
WHEN MATCHED THEN UPDATE SET couche = s.couche, table_cible = s.table_cible, colonne = s.colonne, dimension = s.dimension, anomalie = s.anomalie,
                             volume_constate = s.volume_constate, regle = s.regle, action = s.action, severite = s.severite
WHEN NOT MATCHED BY TARGET THEN INSERT VALUES (s.regle_id, s.couche, s.table_cible, s.colonne, s.dimension, s.anomalie, s.volume_constate, s.regle, s.action, s.severite)
WHEN NOT MATCHED BY SOURCE THEN DELETE;
GO

/* ---------------------------------------------------------------------
   2. Volumes attendus par couche × règle × niveau (lot complet sur donnees_brutes)
   Niveaux : REJET (écarté), SIGNALEMENT (mis à NULL ou rattaché autrement), CORRECTION (valeur corrigée)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'audit.rejets_attendus', N'U') IS NULL
CREATE TABLE audit.rejets_attendus (
    couche          VARCHAR(20)  NOT NULL,
    regle_id        VARCHAR(10)  NOT NULL CONSTRAINT FK_rejets_attendus_regle REFERENCES audit.regle_qualite (regle_id),
    niveau          VARCHAR(12)  NOT NULL CONSTRAINT CK_rejets_attendus_niveau CHECK (niveau IN ('REJET','SIGNALEMENT','CORRECTION')),
    volume_attendu  INT          NOT NULL,
    CONSTRAINT PK_rejets_attendus PRIMARY KEY (couche, regle_id, niveau)
);
GO
MERGE audit.rejets_attendus AS t
USING (VALUES
    (N'STG_CLEAN', N'QR01', N'REJET', 300),
    (N'STG_CLEAN', N'QR02', N'REJET', 120),
    (N'STG_CLEAN', N'QR03', N'REJET', 100),
    (N'STG_CLEAN', N'QR04', N'REJET', 30),
    (N'STG_CLEAN', N'QR05', N'REJET', 644),
    (N'STG_CLEAN', N'QR06', N'CORRECTION', 2650),
    (N'STG_CLEAN', N'QR07', N'CORRECTION', 1262),
    (N'STG_CLEAN', N'QR08', N'CORRECTION', 3427),
    (N'STG_CLEAN', N'QR09', N'CORRECTION', 1379),
    (N'STG_CLEAN', N'QR10', N'CORRECTION', 365),
    (N'STG_CLEAN', N'QR11', N'CORRECTION', 620),
    (N'STG_CLEAN', N'QR12', N'CORRECTION', 230),
    (N'STG_CLEAN', N'QR13', N'CORRECTION', 333),
    (N'STG_CLEAN', N'QR14', N'CORRECTION', 100),
    (N'STG_CLEAN', N'QR15', N'CORRECTION', 15),
    (N'STG_CLEAN', N'QR16', N'CORRECTION', 6),
    (N'STG_CLEAN', N'QR17', N'CORRECTION', 3),
    (N'STG_CLEAN', N'QR18', N'SIGNALEMENT', 6),
    (N'STG_CLEAN', N'QR19', N'CORRECTION', 662),
    (N'STG_CLEAN', N'QR20', N'CORRECTION', 55),
    (N'STG_CLEAN', N'QR21', N'CORRECTION', 45),
    (N'STG_CLEAN', N'QR22', N'CORRECTION', 40),
    (N'STG_CLEAN', N'QR28', N'SIGNALEMENT', 10),
    (N'STG_CLEAN', N'QR29', N'CORRECTION', 20),
    (N'STG_CLEAN', N'QR30', N'SIGNALEMENT', 15),
    (N'STG_CLEAN', N'QR31', N'CORRECTION', 10),
    (N'STG_CLEAN', N'QR32', N'CORRECTION', 20),
    (N'STG_CLEAN', N'QR33', N'SIGNALEMENT', 15),
    (N'STG_CLEAN', N'QR34', N'CORRECTION', 25),
    (N'STG_CLEAN', N'QR35', N'CORRECTION', 30),
    (N'STG_CLEAN', N'QR36', N'CORRECTION', 40),
    (N'STG_CLEAN', N'QR37', N'CORRECTION', 10),
    (N'STG_CLEAN', N'QR44', N'SIGNALEMENT', 36),
    (N'STG_CLEAN', N'QR45', N'CORRECTION', 80),
    (N'STG_CLEAN', N'QR46', N'CORRECTION', 10),
    (N'STG_INTEGRATED', N'QR23', N'SIGNALEMENT', 25),
    (N'STG_INTEGRATED', N'QR24', N'SIGNALEMENT', 20),
    (N'STG_INTEGRATED', N'QR25', N'SIGNALEMENT', 5),
    (N'STG_INTEGRATED', N'QR26', N'REJET', 2),
    (N'STG_INTEGRATED', N'QR26', N'SIGNALEMENT', 13),
    (N'STG_INTEGRATED', N'QR27', N'SIGNALEMENT', 150),
    (N'STG_INTEGRATED', N'QR47', N'SIGNALEMENT', 50),
    (N'STG_INTEGRATED', N'QR48', N'SIGNALEMENT', 8)
) AS s (couche, regle_id, niveau, volume_attendu)
ON t.couche = s.couche AND t.regle_id = s.regle_id AND t.niveau = s.niveau
WHEN MATCHED THEN UPDATE SET volume_attendu = s.volume_attendu
WHEN NOT MATCHED BY TARGET THEN INSERT VALUES (s.couche, s.regle_id, s.niveau, s.volume_attendu)
WHEN NOT MATCHED BY SOURCE THEN DELETE;
GO

/* ---------------------------------------------------------------------
   3. Vues
   --------------------------------------------------------------------- */
-- 3.1 Détail : toutes les lignes de quarantaine des deux couches
CREATE OR ALTER VIEW audit.v_journal_rejets_detail AS
SELECT 'STG_CLEAN' AS couche, r.rejet_id, r.id_chargement, r.table_source, r.cle_enregistrement, r.colonne, r.valeur_recue,
       r.regle_id, r.niveau, r.message, r.date_rejet
FROM [TuniShop_STG_CLEAN].clean.rejets r
UNION ALL
SELECT 'STG_INTEGRATED', r.rejet_id, r.id_chargement, r.table_source, r.cle_enregistrement, r.colonne, r.valeur_recue,
       r.regle_id, r.niveau, r.message, r.date_rejet
FROM [TuniShop_STG_INTEGRATED].integ.rejets r;
GO

-- 3.2 Synthèse : constaté vs attendu, pour chaque lot ayant un journal
CREATE OR ALTER VIEW audit.v_journal_rejets_synthese AS
WITH constate AS (
    SELECT id_chargement, couche, regle_id, niveau, COUNT(*) AS nb
    FROM audit.v_journal_rejets_detail
    GROUP BY id_chargement, couche, regle_id, niveau
), lots AS (
    SELECT DISTINCT id_chargement FROM constate
), attendu AS (
    SELECT l.id_chargement, a.couche, a.regle_id, a.niveau, a.volume_attendu
    FROM lots l CROSS JOIN audit.rejets_attendus a
)
SELECT COALESCE(a.id_chargement, c.id_chargement) AS id_chargement,
       COALESCE(a.couche, c.couche)               AS couche,
       COALESCE(a.regle_id, c.regle_id)           AS regle_id,
       COALESCE(a.niveau, c.niveau)               AS niveau,
       q.table_cible, q.colonne, q.anomalie, q.regle,
       ISNULL(c.nb, 0)                            AS volume_constate,
       a.volume_attendu,
       ISNULL(c.nb, 0) - a.volume_attendu         AS ecart,
       CASE WHEN a.volume_attendu IS NULL THEN 'NON ATTENDU'
            WHEN ISNULL(c.nb, 0) = a.volume_attendu THEN 'CONFORME'
            ELSE 'ECART' END                      AS statut
FROM attendu a
FULL OUTER JOIN constate c
  ON c.id_chargement = a.id_chargement AND c.couche = a.couche AND c.regle_id = a.regle_id AND c.niveau = a.niveau
LEFT JOIN audit.regle_qualite q ON q.regle_id = COALESCE(a.regle_id, c.regle_id);
GO

-- 3.3 Par table source et par niveau
CREATE OR ALTER VIEW audit.v_journal_rejets_par_table AS
SELECT id_chargement, couche, table_source,
       SUM(CASE WHEN niveau = 'REJET'       THEN 1 ELSE 0 END) AS nb_rejets,
       SUM(CASE WHEN niveau = 'SIGNALEMENT' THEN 1 ELSE 0 END) AS nb_signalements,
       SUM(CASE WHEN niveau = 'CORRECTION'  THEN 1 ELSE 0 END) AS nb_corrections,
       COUNT(*)                                                AS total
FROM audit.v_journal_rejets_detail
GROUP BY id_chargement, couche, table_source;
GO

-- 3.4 Bilan par lot : la conclusion du livrable
CREATE OR ALTER VIEW audit.v_journal_rejets_bilan AS
SELECT s.id_chargement,
       l.date_debut, l.statut AS statut_lot,
       SUM(s.volume_constate)                                              AS lignes_journal,
       SUM(CASE WHEN s.niveau = 'REJET'       THEN s.volume_constate END)  AS nb_rejets,
       SUM(CASE WHEN s.niveau = 'SIGNALEMENT' THEN s.volume_constate END)  AS nb_signalements,
       SUM(CASE WHEN s.niveau = 'CORRECTION'  THEN s.volume_constate END)  AS nb_corrections,
       SUM(CASE WHEN s.statut = 'CONFORME' THEN 1 ELSE 0 END)              AS combinaisons_conformes,
       COUNT(*)                                                            AS combinaisons_total,
       CASE WHEN SUM(CASE WHEN s.statut <> 'CONFORME' THEN 1 ELSE 0 END) = 0
            THEN N'Journal conforme : toutes les règles s''appliquent aux volumes attendus'
            ELSE CONCAT(SUM(CASE WHEN s.statut <> 'CONFORME' THEN 1 ELSE 0 END), N' écart(s) à analyser dans audit.v_journal_rejets_synthese') END AS conclusion
FROM audit.v_journal_rejets_synthese s
LEFT JOIN audit.execution_lot l ON l.id_chargement = s.id_chargement
GROUP BY s.id_chargement, l.date_debut, l.statut;
GO
PRINT N'Journal des rejets : catalogue, volumes attendus et 4 vues créés dans TuniShop_ADMIN.audit.';
GO
