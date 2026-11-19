-- TuniShop : schéma PostgreSQL de la couche de référence (généré automatiquement)
-- Charger avec : \copy <table> FROM 'donnees_reference/<table>.csv' CSV HEADER
CREATE SCHEMA IF NOT EXISTS tunishop;
SET search_path TO tunishop;

-- Référentiel des 24 gouvernorats tunisiens et de leur rattachement logistique.
CREATE TABLE ref_gouvernorats (
    gouvernorat_id VARCHAR(20) PRIMARY KEY,
    gouvernorat VARCHAR(20),
    region VARCHAR(20),
    entrepot_rattachement_id VARCHAR(20),
    zone_livraison VARCHAR(20)
);

-- Dimension date du 01/01/2023 au 31/12/2025 avec jours fériés tunisiens et périodes commerciales.
CREATE TABLE dim_calendrier (
    date DATE PRIMARY KEY,
    annee INTEGER,
    trimestre INTEGER,
    mois INTEGER,
    nom_mois VARCHAR(20),
    semaine_iso INTEGER,
    jour_semaine INTEGER,
    nom_jour VARCHAR(20),
    est_weekend BOOLEAN,
    est_jour_ferie BOOLEAN,
    nom_jour_ferie VARCHAR(40),
    est_ramadan BOOLEAN,
    periode_commerciale VARCHAR(30)
);

-- Entrepôts logistiques de TuniShop.
CREATE TABLE entrepots (
    entrepot_id VARCHAR(20) PRIMARY KEY,
    nom_entrepot VARCHAR(40),
    ville VARCHAR(20),
    gouvernorat_id VARCHAR(20),
    date_ouverture DATE,
    surface_m2 INTEGER
);

-- Transporteurs partenaires (noms fictifs).
CREATE TABLE transporteurs (
    transporteur_id VARCHAR(20) PRIMARY KEY,
    nom_transporteur VARCHAR(30),
    couverture VARCHAR(30),
    cout_base_ht NUMERIC(14,3),
    ecart_delai_moyen_j NUMERIC(14,3),
    date_debut_contrat DATE
);

-- Fournisseurs (noms fictifs), locaux et à l'import.
CREATE TABLE fournisseurs (
    fournisseur_id VARCHAR(20) PRIMARY KEY,
    nom_fournisseur VARCHAR(40),
    pays VARCHAR(20),
    delai_appro_moyen_j INTEGER,
    conditions_paiement VARCHAR(50),
    fiabilite_livraison NUMERIC(14,3),
    email_contact VARCHAR(50)
);

-- Catégories et sous-catégories de produits.
CREATE TABLE categories (
    categorie_id VARCHAR(20) PRIMARY KEY,
    categorie VARCHAR(40),
    sous_categorie VARCHAR(50),
    taux_tva INTEGER,
    taux_retour_cible NUMERIC(14,3),
    marge_brute_cible NUMERIC(14,3)
);

-- Catalogue produits, vue à la date d'arrêté (prix et coût actuels).
CREATE TABLE produits (
    produit_id VARCHAR(20) PRIMARY KEY,
    sku VARCHAR(20),
    nom_produit VARCHAR(80),
    categorie_id VARCHAR(20),
    marque VARCHAR(30),
    fournisseur_id VARCHAR(20),
    prix_catalogue_ttc_actuel NUMERIC(14,3),
    cout_achat_unitaire_ht_actuel NUMERIC(14,3),
    taux_tva INTEGER,
    poids_kg NUMERIC(14,3),
    date_lancement DATE,
    date_arret DATE,
    statut_produit VARCHAR(20)
);

-- Historique des prix et coûts (SCD type 2). Révision annuelle au 1er janvier.
CREATE TABLE produits_prix_historique (
    prix_id VARCHAR(20) PRIMARY KEY,
    produit_id VARCHAR(20),
    date_debut DATE,
    date_fin DATE,
    prix_catalogue_ttc NUMERIC(14,3),
    cout_achat_unitaire_ht NUMERIC(14,3),
    est_prix_actuel BOOLEAN
);

-- Campagnes marketing (paid, CRM, influence).
CREATE TABLE campagnes_marketing (
    campagne_id VARCHAR(20) PRIMARY KEY,
    nom_campagne VARCHAR(70),
    canal VARCHAR(20),
    objectif VARCHAR(20),
    theme VARCHAR(20),
    categorie_ciblee_id VARCHAR(20),
    code_coupon VARCHAR(20),
    date_debut DATE,
    date_fin DATE,
    budget_ht NUMERIC(14,3)
);

-- Codes promotionnels.
CREATE TABLE coupons (
    code_coupon VARCHAR(20) PRIMARY KEY,
    type_remise VARCHAR(20),
    valeur NUMERIC(14,3),
    montant_min_ttc NUMERIC(14,3),
    plafond_remise_ttc NUMERIC(14,3),
    date_debut DATE,
    date_fin DATE,
    campagne_id VARCHAR(20),
    reserve_premiere_commande BOOLEAN
);

-- Clients inscrits (particuliers et professionnels). Données entièrement fictives.
CREATE TABLE clients (
    client_id VARCHAR(20) PRIMARY KEY,
    type_client VARCHAR(20),
    prenom VARCHAR(20),
    nom VARCHAR(20),
    genre VARCHAR(20),
    date_naissance DATE,
    raison_sociale VARCHAR(50),
    matricule_fiscal VARCHAR(30),
    email VARCHAR(50),
    telephone VARCHAR(20),
    gouvernorat_id VARCHAR(20),
    ville VARCHAR(30),
    date_inscription TIMESTAMP,
    canal_inscription VARCHAR(40),
    campagne_acquisition_id VARCHAR(20),
    opt_in_email BOOLEAN,
    opt_in_sms BOOLEAN,
    segment_fidelite VARCHAR(20)
);

-- Performance quotidienne des campagnes (dépenses régie + attribution last-click interne).
CREATE TABLE marketing_depenses_quotidiennes (
    depense_id VARCHAR(20) PRIMARY KEY,
    campagne_id VARCHAR(20),
    date DATE,
    canal VARCHAR(20),
    depense_ht NUMERIC(14,3),
    impressions INTEGER,
    clics INTEGER,
    commandes_attribuees INTEGER,
    nouveaux_clients_attribues INTEGER,
    ca_attribue_ttc NUMERIC(14,3)
);

-- En-têtes de commandes e-commerce du 01/01/2023 au 31/12/2025.
CREATE TABLE commandes (
    commande_id VARCHAR(20) PRIMARY KEY,
    client_id VARCHAR(20),
    date_commande TIMESTAMP,
    canal VARCHAR(30),
    appareil VARCHAR(20),
    gouvernorat_livraison_id VARCHAR(20),
    ville_livraison VARCHAR(30),
    entrepot_id VARCHAR(20),
    campagne_id VARCHAR(20),
    code_coupon VARCHAR(20),
    mode_paiement VARCHAR(40),
    nb_lignes INTEGER,
    nb_articles INTEGER,
    sous_total_ttc NUMERIC(14,3),
    remise_coupon_ttc NUMERIC(14,3),
    frais_livraison_ttc NUMERIC(14,3),
    montant_total_ttc NUMERIC(14,3),
    statut_commande VARCHAR(40),
    motif_annulation VARCHAR(30),
    date_annulation TIMESTAMP,
    est_premiere_commande BOOLEAN
);

-- Lignes de commandes.
CREATE TABLE lignes_commande (
    ligne_id VARCHAR(20) PRIMARY KEY,
    commande_id VARCHAR(20),
    num_ligne INTEGER,
    produit_id VARCHAR(20),
    quantite INTEGER,
    prix_catalogue_ttc NUMERIC(14,3),
    remise_promo_unitaire_ttc NUMERIC(14,3),
    prix_unitaire_ttc NUMERIC(14,3),
    taux_tva INTEGER,
    montant_ligne_ttc NUMERIC(14,3),
    montant_ligne_ht NUMERIC(14,3),
    montant_tva NUMERIC(14,3),
    cout_achat_unitaire_ht NUMERIC(14,3)
);

-- Transactions de paiement (tentatives en ligne et encaissements).
CREATE TABLE paiements (
    paiement_id VARCHAR(20) PRIMARY KEY,
    commande_id VARCHAR(20),
    num_tentative INTEGER,
    mode_paiement VARCHAR(40),
    montant_ttc NUMERIC(14,3),
    statut_paiement VARCHAR(20),
    code_erreur VARCHAR(50),
    date_paiement TIMESTAMP,
    prestataire VARCHAR(30),
    reference_transaction VARCHAR(20),
    date_reversement DATE
);

-- Remboursements : retours produits, annulations de commandes prépayées, gestes commerciaux.
CREATE TABLE remboursements (
    remboursement_id VARCHAR(20) PRIMARY KEY,
    commande_id VARCHAR(20),
    ligne_id VARCHAR(20),
    type_remboursement VARCHAR(30),
    motif VARCHAR(60),
    quantite INTEGER,
    montant_rembourse_ttc NUMERIC(14,3),
    montant_demande_ttc NUMERIC(14,3),
    date_demande TIMESTAMP,
    date_reception_retour TIMESTAMP,
    date_remboursement TIMESTAMP,
    mode_remboursement VARCHAR(30),
    statut VARCHAR(20),
    etat_article VARCHAR(30)
);

-- Expéditions transporteur.
CREATE TABLE livraisons (
    livraison_id VARCHAR(20) PRIMARY KEY,
    commande_id VARCHAR(20),
    entrepot_id VARCHAR(20),
    transporteur_id VARCHAR(20),
    gouvernorat_destination_id VARCHAR(20),
    date_expedition TIMESTAMP,
    date_livraison_prevue DATE,
    date_livraison_reelle TIMESTAMP,
    date_dernier_evenement TIMESTAMP,
    statut_livraison VARCHAR(40),
    nb_tentatives INTEGER,
    poids_kg NUMERIC(14,3),
    cout_transport_ht NUMERIC(14,3)
);

-- Bons de commande d'achat (réapprovisionnement automatique par point de commande).
CREATE TABLE commandes_fournisseurs (
    commande_fournisseur_id VARCHAR(20) PRIMARY KEY,
    fournisseur_id VARCHAR(20),
    entrepot_id VARCHAR(20),
    date_commande TIMESTAMP,
    date_livraison_prevue DATE,
    date_reception TIMESTAMP,
    statut VARCHAR(40),
    montant_total_ht NUMERIC(14,3)
);

-- Lignes des bons de commande d'achat.
CREATE TABLE lignes_commande_fournisseur (
    ligne_cf_id VARCHAR(20) PRIMARY KEY,
    commande_fournisseur_id VARCHAR(20),
    produit_id VARCHAR(20),
    quantite_commandee INTEGER,
    quantite_recue INTEGER,
    cout_unitaire_ht NUMERIC(14,3),
    montant_ligne_ht NUMERIC(14,3)
);

-- Grand livre des mouvements de stock (source de vérité du stock).
CREATE TABLE mouvements_stock (
    mouvement_id VARCHAR(20) PRIMARY KEY,
    date_mouvement TIMESTAMP,
    produit_id VARCHAR(20),
    entrepot_id VARCHAR(20),
    type_mouvement VARCHAR(50),
    quantite INTEGER,
    reference_id VARCHAR(30),
    cout_unitaire_ht NUMERIC(14,3)
);

-- Photo du stock en fin de mois, calculée à partir des mouvements.
CREATE TABLE stocks_mensuels (
    inventaire_id VARCHAR(20) PRIMARY KEY,
    date_inventaire DATE,
    produit_id VARCHAR(20),
    entrepot_id VARCHAR(20),
    stock_fin_mois INTEGER,
    quantite_en_commande INTEGER,
    cout_unitaire_ht NUMERIC(14,3),
    valeur_stock_ht NUMERIC(14,3)
);

-- Avis clients après livraison (commentaires en français et en derja latinisée).
CREATE TABLE avis_clients (
    avis_id VARCHAR(20) PRIMARY KEY,
    commande_id VARCHAR(20),
    ligne_id VARCHAR(20),
    produit_id VARCHAR(20),
    client_id VARCHAR(20),
    date_avis TIMESTAMP,
    note INTEGER,
    commentaire VARCHAR(80),
    achat_verifie BOOLEAN
);

-- Clés étrangères (ajoutées après chargement ; les références circulaires gouvernorats<->entrepots et campagnes<->coupons sont incluses)
ALTER TABLE clients ADD CONSTRAINT fk_clients_gouvernorat_id FOREIGN KEY (gouvernorat_id) REFERENCES ref_gouvernorats(gouvernorat_id);
ALTER TABLE clients ADD CONSTRAINT fk_clients_campagne_acquisition_id FOREIGN KEY (campagne_acquisition_id) REFERENCES campagnes_marketing(campagne_id);
ALTER TABLE produits ADD CONSTRAINT fk_produits_categorie_id FOREIGN KEY (categorie_id) REFERENCES categories(categorie_id);
ALTER TABLE produits ADD CONSTRAINT fk_produits_fournisseur_id FOREIGN KEY (fournisseur_id) REFERENCES fournisseurs(fournisseur_id);
ALTER TABLE produits_prix_historique ADD CONSTRAINT fk_produits_prix_histor_produit_id FOREIGN KEY (produit_id) REFERENCES produits(produit_id);
ALTER TABLE entrepots ADD CONSTRAINT fk_entrepots_gouvernorat_id FOREIGN KEY (gouvernorat_id) REFERENCES ref_gouvernorats(gouvernorat_id);
ALTER TABLE campagnes_marketing ADD CONSTRAINT fk_campagnes_marketing_categorie_ciblee_id FOREIGN KEY (categorie_ciblee_id) REFERENCES categories(categorie_id);
ALTER TABLE coupons ADD CONSTRAINT fk_coupons_campagne_id FOREIGN KEY (campagne_id) REFERENCES campagnes_marketing(campagne_id);
ALTER TABLE marketing_depenses_quotidiennes ADD CONSTRAINT fk_marketing_depenses_q_campagne_id FOREIGN KEY (campagne_id) REFERENCES campagnes_marketing(campagne_id);
ALTER TABLE commandes ADD CONSTRAINT fk_commandes_client_id FOREIGN KEY (client_id) REFERENCES clients(client_id);
ALTER TABLE commandes ADD CONSTRAINT fk_commandes_gouvernorat_livraison_id FOREIGN KEY (gouvernorat_livraison_id) REFERENCES ref_gouvernorats(gouvernorat_id);
ALTER TABLE commandes ADD CONSTRAINT fk_commandes_entrepot_id FOREIGN KEY (entrepot_id) REFERENCES entrepots(entrepot_id);
ALTER TABLE commandes ADD CONSTRAINT fk_commandes_campagne_id FOREIGN KEY (campagne_id) REFERENCES campagnes_marketing(campagne_id);
ALTER TABLE commandes ADD CONSTRAINT fk_commandes_code_coupon FOREIGN KEY (code_coupon) REFERENCES coupons(code_coupon);
ALTER TABLE lignes_commande ADD CONSTRAINT fk_lignes_commande_commande_id FOREIGN KEY (commande_id) REFERENCES commandes(commande_id);
ALTER TABLE lignes_commande ADD CONSTRAINT fk_lignes_commande_produit_id FOREIGN KEY (produit_id) REFERENCES produits(produit_id);
ALTER TABLE paiements ADD CONSTRAINT fk_paiements_commande_id FOREIGN KEY (commande_id) REFERENCES commandes(commande_id);
ALTER TABLE remboursements ADD CONSTRAINT fk_remboursements_commande_id FOREIGN KEY (commande_id) REFERENCES commandes(commande_id);
ALTER TABLE remboursements ADD CONSTRAINT fk_remboursements_ligne_id FOREIGN KEY (ligne_id) REFERENCES lignes_commande(ligne_id);
ALTER TABLE livraisons ADD CONSTRAINT fk_livraisons_commande_id FOREIGN KEY (commande_id) REFERENCES commandes(commande_id);
ALTER TABLE livraisons ADD CONSTRAINT fk_livraisons_entrepot_id FOREIGN KEY (entrepot_id) REFERENCES entrepots(entrepot_id);
ALTER TABLE livraisons ADD CONSTRAINT fk_livraisons_transporteur_id FOREIGN KEY (transporteur_id) REFERENCES transporteurs(transporteur_id);
ALTER TABLE livraisons ADD CONSTRAINT fk_livraisons_gouvernorat_destination_i FOREIGN KEY (gouvernorat_destination_id) REFERENCES ref_gouvernorats(gouvernorat_id);
ALTER TABLE commandes_fournisseurs ADD CONSTRAINT fk_commandes_fournisseu_fournisseur_id FOREIGN KEY (fournisseur_id) REFERENCES fournisseurs(fournisseur_id);
ALTER TABLE commandes_fournisseurs ADD CONSTRAINT fk_commandes_fournisseu_entrepot_id FOREIGN KEY (entrepot_id) REFERENCES entrepots(entrepot_id);
ALTER TABLE lignes_commande_fournisseur ADD CONSTRAINT fk_lignes_commande_four_commande_fournisseur_id FOREIGN KEY (commande_fournisseur_id) REFERENCES commandes_fournisseurs(commande_fournisseur_id);
ALTER TABLE lignes_commande_fournisseur ADD CONSTRAINT fk_lignes_commande_four_produit_id FOREIGN KEY (produit_id) REFERENCES produits(produit_id);
ALTER TABLE mouvements_stock ADD CONSTRAINT fk_mouvements_stock_produit_id FOREIGN KEY (produit_id) REFERENCES produits(produit_id);
ALTER TABLE mouvements_stock ADD CONSTRAINT fk_mouvements_stock_entrepot_id FOREIGN KEY (entrepot_id) REFERENCES entrepots(entrepot_id);
ALTER TABLE stocks_mensuels ADD CONSTRAINT fk_stocks_mensuels_produit_id FOREIGN KEY (produit_id) REFERENCES produits(produit_id);
ALTER TABLE stocks_mensuels ADD CONSTRAINT fk_stocks_mensuels_entrepot_id FOREIGN KEY (entrepot_id) REFERENCES entrepots(entrepot_id);
ALTER TABLE avis_clients ADD CONSTRAINT fk_avis_clients_commande_id FOREIGN KEY (commande_id) REFERENCES commandes(commande_id);
ALTER TABLE avis_clients ADD CONSTRAINT fk_avis_clients_ligne_id FOREIGN KEY (ligne_id) REFERENCES lignes_commande(ligne_id);
ALTER TABLE avis_clients ADD CONSTRAINT fk_avis_clients_produit_id FOREIGN KEY (produit_id) REFERENCES produits(produit_id);
ALTER TABLE avis_clients ADD CONSTRAINT fk_avis_clients_client_id FOREIGN KEY (client_id) REFERENCES clients(client_id);
ALTER TABLE ref_gouvernorats ADD CONSTRAINT fk_ref_gouvernorats_entrepot_rattachement_id FOREIGN KEY (entrepot_rattachement_id) REFERENCES entrepots(entrepot_id);
ALTER TABLE campagnes_marketing ADD CONSTRAINT fk_campagnes_marketing_code_coupon FOREIGN KEY (code_coupon) REFERENCES coupons(code_coupon);
