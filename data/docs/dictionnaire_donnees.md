# Dictionnaire de données - TuniShop

Couche de référence (`donnees_reference/`). Encodage UTF-8, séparateur virgule, décimale point, dates ISO 8601, heure locale Tunis (UTC+1, sans heure d'été).
Montants en dinars tunisiens (DT, code ISO TND) avec 3 décimales (millimes). PK = clé primaire, FK = clé étrangère.

## ref_gouvernorats

Référentiel des 24 gouvernorats tunisiens et de leur rattachement logistique. Grain : 1 ligne = 1 gouvernorat. Volume : 24 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `gouvernorat_id` | VARCHAR(20) | PK | non | G13 | Identifiant (G01-G24). |
| `gouvernorat` | VARCHAR(20) |  | non | Monastir | Nom du gouvernorat. |
| `region` | VARCHAR(20) |  | non | Centre-Est | Grande région (Grand Tunis, Nord-Est, Nord-Ouest, Centre-Est, Centre-Ouest, Sud-Est, Sud-Ouest). |
| `entrepot_rattachement_id` | VARCHAR(20) | FK → entrepots | non | ENT02 | Entrepôt qui sert ce gouvernorat par défaut (FK entrepots). |
| `zone_livraison` | VARCHAR(20) |  | non | Z2 | Zone tarifaire transporteur (Z1 la plus proche à Z4 la plus éloignée). |

## dim_calendrier

Dimension date du 01/01/2023 au 31/12/2025 avec jours fériés tunisiens et périodes commerciales. Grain : 1 ligne = 1 jour. Volume : 1 096 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `date` | DATE | PK | non | 2024-07-02 | Date (AAAA-MM-JJ), clé. |
| `annee` | INTEGER |  | non | 2024 | Année. |
| `trimestre` | INTEGER |  | non | 3 | Trimestre (1-4). |
| `mois` | INTEGER |  | non | 7 | Mois (1-12). |
| `nom_mois` | VARCHAR(20) |  | non | juillet | Nom du mois en français. |
| `semaine_iso` | INTEGER |  | non | 27 | Numéro de semaine ISO. |
| `jour_semaine` | INTEGER |  | non | 2 | 1 = lundi ... 7 = dimanche. |
| `nom_jour` | VARCHAR(20) |  | non | mardi | Nom du jour. |
| `est_weekend` | BOOLEAN |  | non | False | Samedi ou dimanche. |
| `est_jour_ferie` | BOOLEAN |  | non | False | Jour férié national ou religieux (dates religieuses indicatives). |
| `nom_jour_ferie` | VARCHAR(40) |  | non |  | Libellé du jour férié. |
| `est_ramadan` | BOOLEAN |  | non | False | Jour inclus dans le mois de Ramadan (dates indicatives). |
| `periode_commerciale` | VARCHAR(30) |  | non | normale | normale, soldes_hiver, soldes_ete, ramadan, pre_aid_fitr, pre_aid_idha, rentree_scolaire, black_friday, fin_annee. |

## entrepots

Entrepôts logistiques de TuniShop. Grain : 1 ligne = 1 entrepôt. Volume : 3 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `entrepot_id` | VARCHAR(20) | PK | non | ENT02 | Identifiant (ENT01-ENT03). |
| `nom_entrepot` | VARCHAR(40) |  | non | Entrepôt Sahel | Nom. |
| `ville` | VARCHAR(20) |  | non | Sousse | Ville. |
| `gouvernorat_id` | VARCHAR(20) | FK → ref_gouvernorats | non | G12 | FK ref_gouvernorats. |
| `date_ouverture` | DATE |  | non | 2021-09-15 | Date d'ouverture. |
| `surface_m2` | INTEGER |  | non | 2500 | Surface en m². |

## transporteurs

Transporteurs partenaires (noms fictifs). Grain : 1 ligne = 1 transporteur. Volume : 4 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `transporteur_id` | VARCHAR(20) | PK | non | TR03 | Identifiant (TR01-TR04). |
| `nom_transporteur` | VARCHAR(30) |  | non | SahelLog | Nom commercial fictif. |
| `couverture` | VARCHAR(30) |  | non | régional Centre/Sud | Zone couverte. |
| `cout_base_ht` | NUMERIC(14,3) |  | non | 5.4 | Coût de base d'un colis (DT HT) avant majoration de zone et de poids. |
| `ecart_delai_moyen_j` | NUMERIC(14,3) |  | non | 0.2 | Écart de délai contractuel moyen (jours, + = plus lent). |
| `date_debut_contrat` | DATE |  | non | 2021-09-15 | Début du contrat. |

## fournisseurs

Fournisseurs (noms fictifs)  locaux et à l'import. Grain : 1 ligne = 1 fournisseur. Volume : 40 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `fournisseur_id` | VARCHAR(20) | PK | non | FRN021 | Identifiant (FRN001...). |
| `nom_fournisseur` | VARCHAR(40) |  | non | Mahdia Fashion | Raison sociale fictive. |
| `pays` | VARCHAR(20) |  | non | Tunisie | Pays du fournisseur. |
| `delai_appro_moyen_j` | INTEGER |  | non | 9 | Délai d'approvisionnement contractuel moyen (jours). |
| `conditions_paiement` | VARCHAR(50) |  | non | 60 jours | Conditions de paiement. |
| `fiabilite_livraison` | NUMERIC(14,3) |  | non | 0.9 | Probabilité contractuelle de livrer sans retard (0-1). |
| `email_contact` | VARCHAR(50) |  | non | achats@mahdiafashion.tn | Email fictif du service achats. |

## categories

Catégories et sous-catégories de produits. Grain : 1 ligne = 1 sous-catégorie. Volume : 19 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `categorie_id` | VARCHAR(20) | PK | non | CAT10 | Identifiant (CAT01...). |
| `categorie` | VARCHAR(40) |  | non | Mode | Catégorie (niveau 1). |
| `sous_categorie` | VARCHAR(50) |  | non | Mode Homme | Sous-catégorie (niveau 2). |
| `taux_tva` | INTEGER |  | non | 19 | Taux de TVA appliqué (%) - affectation pédagogique, à ne pas utiliser comme référence fiscale. |
| `taux_retour_cible` | NUMERIC(14,3) |  | non | 0.14 | Taux de retour attendu par le métier (objectif interne). |
| `marge_brute_cible` | NUMERIC(14,3) |  | non | 0.55 | Taux de marge brute cible sur le prix HT. |

## produits

Catalogue produits  vue à la date d'arrêté (prix et coût actuels). Grain : 1 ligne = 1 produit (SKU). Volume : 596 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `produit_id` | VARCHAR(20) | PK | non | PRD0299 | Identifiant (PRD0001...). |
| `sku` | VARCHAR(20) |  | non | TS-10-00299 | Code article unique. |
| `nom_produit` | VARCHAR(80) |  | non | Pantalon Barbary Confort 11 | Libellé (marques fictives). |
| `categorie_id` | VARCHAR(20) | FK → categories | non | CAT10 | FK categories. |
| `marque` | VARCHAR(30) |  | non | Barbary | Marque fictive. |
| `fournisseur_id` | VARCHAR(20) | FK → fournisseurs | non | FRN022 | Fournisseur principal (FK fournisseurs). |
| `prix_catalogue_ttc_actuel` | NUMERIC(14,3) |  | non | 234.9 | Prix de vente TTC en vigueur (DT, 3 décimales). |
| `cout_achat_unitaire_ht_actuel` | NUMERIC(14,3) |  | non | 88.51 | Coût d'achat unitaire HT en vigueur (DT). |
| `taux_tva` | INTEGER |  | non | 19 | Taux de TVA (%). |
| `poids_kg` | NUMERIC(14,3) |  | non | 1.17 | Poids unitaire (kg). |
| `date_lancement` | DATE |  | non | 2023-01-01 | Date de mise en vente. |
| `date_arret` | DATE |  | oui | 2023-11-09 | Date de fin de commercialisation (vide si actif). |
| `statut_produit` | VARCHAR(20) |  | non | actif | actif ou arrete. |

## produits_prix_historique

Historique des prix et coûts (SCD type 2). Révision annuelle au 1er janvier. Grain : 1 ligne = 1 produit x 1 période de validité. Volume : 1 601 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `prix_id` | VARCHAR(20) | PK | non | PRX00801 | Identifiant. |
| `produit_id` | VARCHAR(20) | FK → produits | non | PRD0289 | FK produits. |
| `date_debut` | DATE |  | non | 2025-01-01 | Début de validité (inclus). |
| `date_fin` | DATE |  | non | 2025-12-31 | Fin de validité (incluse, vide = en cours). |
| `prix_catalogue_ttc` | NUMERIC(14,3) |  | non | 29.9 | Prix de vente TTC sur la période. |
| `cout_achat_unitaire_ht` | NUMERIC(14,3) |  | non | 11.282 | Coût d'achat HT sur la période. |
| `est_prix_actuel` | BOOLEAN |  | non | False | Ligne en vigueur à la date d'arrêté. |

## campagnes_marketing

Campagnes marketing (paid  CRM  influence). Grain : 1 ligne = 1 campagne. Volume : 152 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `campagne_id` | VARCHAR(20) | PK | non | CMP0077 | Identifiant (CMP0001...). |
| `nom_campagne` | VARCHAR(70) |  | non | Été 2024 - Tiktok Ads | Nom. |
| `canal` | VARCHAR(20) |  | non | tiktok_ads | facebook_ads, instagram_ads, google_ads, tiktok_ads, emailing, sms, influence. |
| `objectif` | VARCHAR(20) |  | non | acquisition | acquisition, conversion ou fidelisation. |
| `theme` | VARCHAR(20) |  | non | ete | Temps fort (ramadan, pre_fitr, soldes, rentree, bf, fin_annee, ete) ou permanent. |
| `categorie_ciblee_id` | VARCHAR(20) | FK → categories | oui | CAT19 | Catégorie mise en avant (FK, optionnel). |
| `code_coupon` | VARCHAR(20) | FK → coupons | oui | PROMO24IN | Code promo associé (FK coupons, optionnel). |
| `date_debut` | DATE |  | non | 2024-06-17 | Premier jour. |
| `date_fin` | DATE |  | non | 2024-07-27 | Dernier jour. |
| `budget_ht` | NUMERIC(14,3) |  | non | 5589.271 | Budget prévu (DT HT). |

## coupons

Codes promotionnels. Grain : 1 ligne = 1 code. Volume : 68 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `code_coupon` | VARCHAR(20) | PK | non | PROMO24IN | Code (clé). |
| `type_remise` | VARCHAR(20) |  | non | montant_fixe | pourcentage ou montant_fixe. |
| `valeur` | NUMERIC(14,3) |  | non | 15.0 | % ou montant en DT TTC. |
| `montant_min_ttc` | NUMERIC(14,3) |  | non | 100.0 | Sous-total minimum pour utiliser le code. |
| `plafond_remise_ttc` | NUMERIC(14,3) |  | oui | 60.0 | Remise maximale (codes en pourcentage). |
| `date_debut` | DATE |  | non | 2024-09-19 | Début de validité. |
| `date_fin` | DATE |  | oui | 2024-09-26 | Fin de validité (vide = permanent). |
| `campagne_id` | VARCHAR(20) | FK → campagnes_marketing | oui | CMP0082 | Campagne liée (FK). |
| `reserve_premiere_commande` | BOOLEAN |  | non | False | Utilisable uniquement sur la 1re commande du client. |

## clients

Clients inscrits (particuliers et professionnels). Données entièrement fictives. Grain : 1 ligne = 1 compte client. Volume : 16 000 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `client_id` | VARCHAR(20) | PK | non | CLI008001 | Identifiant (CLI000001...). |
| `type_client` | VARCHAR(20) |  | non | particulier | particulier ou professionnel. |
| `prenom` | VARCHAR(20) |  | non | Malek | Prénom fictif. |
| `nom` | VARCHAR(20) |  | non | Zaouali | Nom fictif. |
| `genre` | VARCHAR(20) |  | non | M | F ou M. |
| `date_naissance` | DATE |  | oui | 1983-08-22 | Date de naissance (vide pour les professionnels). |
| `raison_sociale` | VARCHAR(50) |  | oui | Mabrouk Distribution SUARL | Raison sociale fictive (professionnels). |
| `matricule_fiscal` | VARCHAR(30) |  | oui | 8114267W/A/M/000 | Matricule fiscal fictif au format tunisien (professionnels). |
| `email` | VARCHAR(50) |  | oui | habib.sassi33@gmail.com | Email (vide si inscription par téléphone uniquement). |
| `telephone` | VARCHAR(20) |  | non | +21629411468 | Mobile au format E.164 (+216XXXXXXXX). |
| `gouvernorat_id` | VARCHAR(20) | FK → ref_gouvernorats | non | G05 | Gouvernorat de résidence (FK). |
| `ville` | VARCHAR(30) |  | non | Kélibia | Ville de résidence. |
| `date_inscription` | TIMESTAMP |  | non | 2024-05-21 20:01:29 | Horodatage de création du compte (heure locale Tunis). |
| `canal_inscription` | VARCHAR(40) |  | non | application_mobile | Canal d'acquisition déclaré. |
| `campagne_acquisition_id` | VARCHAR(20) | FK → campagnes_marketing | oui | CMP0073 | Campagne d'acquisition à l'origine de l'inscription (FK, peut être vide). |
| `opt_in_email` | BOOLEAN |  | non | False | Consentement emailing. |
| `opt_in_sms` | BOOLEAN |  | non | False | Consentement SMS. |
| `segment_fidelite` | VARCHAR(20) |  | non | aucun | Segment CRM calculé sur le CA net 2025 : or (>= 1500 DT), argent (>= 500), bronze (> 0), aucun. |

## marketing_depenses_quotidiennes

Performance quotidienne des campagnes (dépenses régie + attribution last-click interne). Grain : 1 ligne = 1 campagne x 1 jour. Volume : 3 427 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `depense_id` | VARCHAR(20) | PK | non | MKT001714 | Identifiant. |
| `campagne_id` | VARCHAR(20) | FK → campagnes_marketing | non | CMP0072 | FK campagnes_marketing. |
| `date` | DATE |  | non | 2024-12-14 | Jour. |
| `canal` | VARCHAR(20) |  | non | facebook_ads | Canal (dénormalisé). |
| `depense_ht` | NUMERIC(14,3) |  | non | 399.377 | Dépense du jour (DT HT). |
| `impressions` | INTEGER |  | non | 77511 | Impressions / envois. |
| `clics` | INTEGER |  | non | 970 | Clics. |
| `commandes_attribuees` | INTEGER |  | non | 3 | Commandes attribuées à la campagne ce jour (hors paiement échoué). |
| `nouveaux_clients_attribues` | INTEGER |  | non | 1 | Dont 1res commandes. |
| `ca_attribue_ttc` | NUMERIC(14,3) |  | non | 712.91 | CA TTC brut des commandes attribuées. |

## commandes

En-têtes de commandes e-commerce du 01/01/2023 au 31/12/2025. Grain : 1 ligne = 1 commande. Volume : 66 268 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `commande_id` | VARCHAR(20) | PK | non | CMD0033135 | Identifiant (CMD0000001...). |
| `client_id` | VARCHAR(20) | FK → clients | non | CLI009615 | FK clients. |
| `date_commande` | TIMESTAMP |  | non | 2024-11-23 18:10:26 | Horodatage de validation du panier (heure locale Tunis). |
| `canal` | VARCHAR(30) |  | non | site_web | site_web, application_mobile, reseaux_sociaux. |
| `appareil` | VARCHAR(20) |  | non | ordinateur | ordinateur, mobile, tablette. |
| `gouvernorat_livraison_id` | VARCHAR(20) | FK → ref_gouvernorats | non | G13 | Gouvernorat de livraison (FK). |
| `ville_livraison` | VARCHAR(30) |  | non | Ksar Hellal | Ville de livraison. |
| `entrepot_id` | VARCHAR(20) | FK → entrepots | oui | ENT01 | Entrepôt qui a servi la commande (vide si aucun stock ou paiement échoué). |
| `campagne_id` | VARCHAR(20) | FK → campagnes_marketing | oui | CMP0069 | Campagne attribuée (last-click, FK). |
| `code_coupon` | VARCHAR(20) | FK → coupons | oui | BIENVENUE10 | Code promo utilisé (FK). |
| `mode_paiement` | VARCHAR(40) |  | non | carte_prepayee | paiement_a_la_livraison, carte_bancaire, portefeuille_mobile, carte_prepayee, virement. |
| `nb_lignes` | INTEGER |  | non | 3 | Nombre de lignes. |
| `nb_articles` | INTEGER |  | non | 3 | Somme des quantités. |
| `sous_total_ttc` | NUMERIC(14,3) |  | non | 395.7 | Somme des montants de lignes TTC (après promotions produit). |
| `remise_coupon_ttc` | NUMERIC(14,3) |  | non | 0.0 | Remise du code promo (DT TTC). |
| `frais_livraison_ttc` | NUMERIC(14,3) |  | non | 0.0 | Frais facturés au client : 7,000 DT si (sous-total - remise) < 150 DT, sinon 0. |
| `montant_total_ttc` | NUMERIC(14,3) |  | non | 395.7 | Montant payé par le client = sous_total - remise + frais. |
| `statut_commande` | VARCHAR(40) |  | non | livree | Statut à la date d'arrêté : livree, partiellement_retournee, retournee, annulee, paiement_echoue, livraison_echouee, expediee, en_preparation. |
| `motif_annulation` | VARCHAR(30) |  | oui | rupture_stock | rupture_stock ou annulation_client. |
| `date_annulation` | TIMESTAMP |  | oui | 2024-10-20 22:39:41 | Horodatage d'annulation. |
| `est_premiere_commande` | BOOLEAN |  | non | True | 1re commande chronologique du client. |

## lignes_commande

Lignes de commandes. Grain : 1 ligne = 1 produit dans 1 commande. Volume : 115 903 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `ligne_id` | VARCHAR(20) | PK | non | LIG00057952 | Identifiant (LIG...). |
| `commande_id` | VARCHAR(20) | FK → commandes | non | CMD0033026 | FK commandes. |
| `num_ligne` | INTEGER |  | non | 2 | Rang de la ligne. |
| `produit_id` | VARCHAR(20) | FK → produits | non | PRD0247 | FK produits. |
| `quantite` | INTEGER |  | non | 1 | Quantité commandée. |
| `prix_catalogue_ttc` | NUMERIC(14,3) |  | non | 121.9 | Prix catalogue TTC à la date de commande. |
| `remise_promo_unitaire_ttc` | NUMERIC(14,3) |  | non | 0.0 | Remise promotionnelle unitaire (soldes, Black Friday). |
| `prix_unitaire_ttc` | NUMERIC(14,3) |  | non | 121.9 | Prix unitaire payé = catalogue - remise promo. |
| `taux_tva` | INTEGER |  | non | 19 | TVA (%). |
| `montant_ligne_ttc` | NUMERIC(14,3) |  | non | 121.9 | quantite x prix_unitaire_ttc. |
| `montant_ligne_ht` | NUMERIC(14,3) |  | non | 102.437 | montant TTC / (1 + TVA). |
| `montant_tva` | NUMERIC(14,3) |  | non | 19.463 | TTC - HT. |
| `cout_achat_unitaire_ht` | NUMERIC(14,3) |  | non | 44.203 | Coût d'achat unitaire HT à la date (pour la marge). |

## paiements

Transactions de paiement (tentatives en ligne et encaissements). Grain : 1 ligne = 1 tentative / 1 encaissement. Volume : 64 493 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `paiement_id` | VARCHAR(20) | PK | non | PAY0032247 | Identifiant. |
| `commande_id` | VARCHAR(20) | FK → commandes | non | CMD0033281 | FK commandes. |
| `num_tentative` | INTEGER |  | non | 1 | Rang de la tentative (1-3). |
| `mode_paiement` | VARCHAR(40) |  | non | carte_bancaire | Mode de paiement. |
| `montant_ttc` | NUMERIC(14,3) |  | non | 24.7 | Montant (DT). |
| `statut_paiement` | VARCHAR(20) |  | non | reussi | reussi, echoue (en ligne), encaisse (paiement à la livraison). |
| `code_erreur` | VARCHAR(50) |  | oui | carte_expiree | Motif de refus (tentatives échouées). |
| `date_paiement` | TIMESTAMP |  | non | 2024-11-24 21:43:40 | Horodatage (heure locale Tunis dans la couche de référence). |
| `prestataire` | VARCHAR(30) |  | non | TuniPay | Passerelle (TuniPay, fictive), transporteur collecteur ou banque. |
| `reference_transaction` | VARCHAR(20) |  | non | TXN8O4G6126AF | Référence fictive. |
| `date_reversement` | DATE |  | oui | 2024-10-28 | Paiement à la livraison : date de reversement des fonds par le transporteur. |

## remboursements

Remboursements : retours produits  annulations de commandes prépayées  gestes commerciaux. Grain : 1 ligne = 1 remboursement. Volume : 8 815 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `remboursement_id` | VARCHAR(20) | PK | non | RMB004408 | Identifiant. |
| `commande_id` | VARCHAR(20) | FK → commandes | non | CMD0032773 | FK commandes. |
| `ligne_id` | VARCHAR(20) | FK → lignes_commande | oui | LIG00056845 | Ligne concernée (retours uniquement). |
| `type_remboursement` | VARCHAR(30) |  | non | retour | retour, annulation, geste_commercial. |
| `motif` | VARCHAR(60) |  | non | erreur_de_preparation | Motif déclaré. |
| `quantite` | INTEGER |  | oui | 1 | Quantité retournée (retours). |
| `montant_rembourse_ttc` | NUMERIC(14,3) |  | non | 738.9 | Montant effectivement remboursé (0 si refusé). |
| `montant_demande_ttc` | NUMERIC(14,3) |  | non | 738.9 | Montant demandé (prix payé au prorata du coupon). |
| `date_demande` | TIMESTAMP |  | non | 2024-11-25 13:12:00 | Demande du client. |
| `date_reception_retour` | TIMESTAMP |  | oui | 2024-12-02 12:01:00 | Réception de l'article à l'entrepôt. |
| `date_remboursement` | TIMESTAMP |  | oui | 2024-11-25 08:58:00 | Exécution du remboursement. |
| `mode_remboursement` | VARCHAR(30) |  | non | bon_achat | Moyen de remboursement (identique au paiement si prépayé ; virement ou bon d'achat sinon). |
| `statut` | VARCHAR(20) |  | non | rembourse | rembourse, refuse, en_cours. |
| `etat_article` | VARCHAR(30) |  | oui | revendable | revendable ou non_revendable (contrôle qualité au retour). |

## livraisons

Expéditions transporteur. Grain : 1 ligne = 1 colis (1 par commande expédiée). Volume : 61 793 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `livraison_id` | VARCHAR(20) | PK | non | LIV0030897 | Identifiant. |
| `commande_id` | VARCHAR(20) | FK → commandes | non | CMD0033161 | FK commandes. |
| `entrepot_id` | VARCHAR(20) | FK → entrepots | non | ENT02 | Entrepôt expéditeur. |
| `transporteur_id` | VARCHAR(20) | FK → transporteurs | non | TR03 | FK transporteurs. |
| `gouvernorat_destination_id` | VARCHAR(20) | FK → ref_gouvernorats | non | G13 | Destination (FK). |
| `date_expedition` | TIMESTAMP |  | oui | 2024-11-26 16:58:00 | Remise au transporteur. |
| `date_livraison_prevue` | DATE |  | non | 2024-11-28 | Date promise au client (SLA). |
| `date_livraison_reelle` | TIMESTAMP |  | oui | 2024-11-26 12:59:00 | Livraison effective. |
| `date_dernier_evenement` | TIMESTAMP |  | oui | 2024-11-25 10:55:00 | Dernier événement de suivi (livraison ou échec). |
| `statut_livraison` | VARCHAR(40) |  | non | livree | livree, echec_retour_expediteur, en_transit, en_preparation. |
| `nb_tentatives` | INTEGER |  | oui | 1 | Nombre de passages du livreur. |
| `poids_kg` | NUMERIC(14,3) |  | non | 2.59 | Poids du colis. |
| `cout_transport_ht` | NUMERIC(14,3) |  | non | 6.416 | Coût facturé par le transporteur à TuniShop (DT HT). |

## commandes_fournisseurs

Bons de commande d'achat (réapprovisionnement automatique par point de commande). Grain : 1 ligne = 1 bon de commande. Volume : 10 370 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `commande_fournisseur_id` | VARCHAR(20) | PK | non | CF005186 | Identifiant (CF...). |
| `fournisseur_id` | VARCHAR(20) | FK → fournisseurs | non | FRN038 | FK fournisseurs. |
| `entrepot_id` | VARCHAR(20) | FK → entrepots | non | ENT03 | Entrepôt destinataire. |
| `date_commande` | TIMESTAMP |  | non | 2024-09-23 10:00:00 | Émission du bon. |
| `date_livraison_prevue` | DATE |  | non | 2024-10-28 | Date de livraison prévue (délai contractuel). |
| `date_reception` | TIMESTAMP |  | oui | 2024-10-12 08:00:00 | Réception effective (vide si en cours). |
| `statut` | VARCHAR(40) |  | non | receptionnee | receptionnee, partiellement_receptionnee, en_cours. |
| `montant_total_ht` | NUMERIC(14,3) |  | non | 556.95 | Montant commandé HT. |

## lignes_commande_fournisseur

Lignes des bons de commande d'achat. Grain : 1 ligne = 1 produit dans 1 bon. Volume : 11 793 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `ligne_cf_id` | VARCHAR(20) | PK | non | LCF0005897 | Identifiant. |
| `commande_fournisseur_id` | VARCHAR(20) | FK → commandes_fournisseurs | non | CF005290 | FK commandes_fournisseurs. |
| `produit_id` | VARCHAR(20) | FK → produits | non | PRD0177 | FK produits. |
| `quantite_commandee` | INTEGER |  | non | 5 | Quantité commandée. |
| `quantite_recue` | INTEGER |  | oui | 35 | Quantité reçue (peut être inférieure : livraison partielle, pas de reliquat). |
| `cout_unitaire_ht` | NUMERIC(14,3) |  | non | 2055.925 | Coût négocié. |
| `montant_ligne_ht` | NUMERIC(14,3) |  | non | 10279.625 | quantite_commandee x coût. |

## mouvements_stock

Grand livre des mouvements de stock (source de vérité du stock). Grain : 1 ligne = 1 mouvement. Volume : 140 184 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `mouvement_id` | VARCHAR(20) | PK | non | MVT0070138 | Identifiant. |
| `date_mouvement` | TIMESTAMP |  | non | 2024-11-11 18:12:00 | Horodatage. |
| `produit_id` | VARCHAR(20) | FK → produits | non | PRD0255 | FK produits. |
| `entrepot_id` | VARCHAR(20) | FK → entrepots | non | ENT02 | FK entrepots. |
| `type_mouvement` | VARCHAR(50) |  | non | retour_client | stock_initial, reception_fournisseur, vente, annulation_commande, retour_echec_livraison, retour_client, retour_client_non_revendable, mise_au_rebut, ajustement_inventaire. |
| `quantite` | INTEGER |  | non | 1 | Quantité signée (+ entrée, - sortie). |
| `reference_id` | VARCHAR(30) |  | non | CMD0031339 | Pièce d'origine (commande, bon fournisseur, inventaire). |
| `cout_unitaire_ht` | NUMERIC(14,3) |  | non | 37.463 | Coût unitaire valorisé. |

## stocks_mensuels

Photo du stock en fin de mois  calculée à partir des mouvements. Grain : 1 ligne = 1 produit x 1 entrepôt x 1 fin de mois. Volume : 56 562 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `inventaire_id` | VARCHAR(20) | PK | non | INV0028282 | Identifiant. |
| `date_inventaire` | DATE |  | non | 2024-08-31 | Dernier jour du mois. |
| `produit_id` | VARCHAR(20) | FK → produits | non | PRD0532 | FK produits. |
| `entrepot_id` | VARCHAR(20) | FK → entrepots | non | ENT02 | FK entrepots. |
| `stock_fin_mois` | INTEGER |  | non | 3 | Quantité en stock à 23:59:59. |
| `quantite_en_commande` | INTEGER |  | non | 0 | Quantité commandée aux fournisseurs non encore reçue. |
| `cout_unitaire_ht` | NUMERIC(14,3) |  | non | 25.744 | Coût de l'année. |
| `valeur_stock_ht` | NUMERIC(14,3) |  | non | 77.232 | stock x coût. |

## avis_clients

Avis clients après livraison (commentaires en français et en derja latinisée). Grain : 1 ligne = 1 avis. Volume : 9 314 lignes.

| Colonne | Type | Clé | Nullable | Exemple | Description |
|---|---|---|---|---|---|
| `avis_id` | VARCHAR(20) | PK | non | AVI004658 | Identifiant. |
| `commande_id` | VARCHAR(20) | FK → commandes | non | CMD0033417 | FK commandes. |
| `ligne_id` | VARCHAR(20) | FK → lignes_commande | non | LIG00058605 | FK lignes_commande. |
| `produit_id` | VARCHAR(20) | FK → produits | non | PRD0031 | FK produits. |
| `client_id` | VARCHAR(20) | FK → clients | non | CLI005786 | FK clients. |
| `date_avis` | TIMESTAMP |  | non | 2024-12-17 13:23:00 | Horodatage. |
| `note` | INTEGER |  | non | 5 | Note de 1 à 5. |
| `commentaire` | VARCHAR(80) |  | oui | Qualité décevante, je ne recommande pas. | Texte libre (peut être vide). |
| `achat_verifie` | BOOLEAN |  | non | True | Avis lié à un achat livré. |

## Différences de la couche brute (`donnees_brutes/`)

La couche brute reproduit des exports de systèmes sources hétérogènes. Les colonnes sont identiques à la couche de référence sauf indication contraire.

| Source | Particularités à traiter |
|---|---|
| `ventes/commandes/commandes_AAAA_MM.csv` | 36 extractions mensuelles + données arrivées en retard dans le fichier du mois suivant ; doublons de ré-extraction. |
| `ventes/lignes_commande/lignes_commande_AAAA_MM.csv` | Découpage mensuel selon la date de commande. |
| `paiements_api/paiements.jsonl` | JSON Lines issu de l'API de la passerelle : champs en anglais, montant imbriqué `amount.value`, horodatage `created_at` en **UTC** (ajouter 1 h pour l'heure de Tunis). Correspondances : `method` COD→paiement_a_la_livraison, CARD→carte_bancaire, WALLET→portefeuille_mobile, PREPAID_CARD→carte_prepayee, BANK_TRANSFER→virement ; `status` SUCCESS→reussi, FAILED→echoue, COLLECTED→encaisse ; `payment_id`→paiement_id, `order_ref`→commande_id, `attempt`→num_tentative, `error_code`→code_erreur, `provider`→prestataire, `transaction_ref`→reference_transaction, `settlement_date`→date_reversement. |
| `marketing/*.csv` | Export régie publicitaire : séparateur `;`, décimale `,`, dates `JJ/MM/AAAA` dans le fichier quotidien. |
| `crm/clients.csv` | Contient des comptes en double (identifiants CLI9xxxxx) et des formats de téléphone / email / date non normalisés. |
