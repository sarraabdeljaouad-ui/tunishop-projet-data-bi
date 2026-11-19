# Dictionnaire de l'entrepôt TuniShop_DW

Version 1.0 – 14/10/2026 – généré depuis `sql/dw_sqlserver/outils/dw_spec.py`.

## dw.dim_date

*Dimension* – Calendrier du 01/01/2023 au 31/12/2025 avec jours fériés tunisiens et périodes commerciales.  
Grain : 1 ligne = 1 jour du calendrier. Historisation / chargement : Statique (générée une fois par an).

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `date_key` | INT | Non | Clé primaire | Clé de date au format AAAAMMJJ ; -1 = date inconnue |
| `date` | DATE | Non | Clé métier | Date |
| `annee` | SMALLINT | Non | Attribut | Année |
| `trimestre` | TINYINT | Non | Attribut | Trimestre (1 à 4) |
| `mois` | TINYINT | Non | Attribut | Mois (1 à 12) |
| `nom_mois` | NVARCHAR(20) | Non | Attribut | Nom du mois en français |
| `annee_mois` | CHAR(7) | Non | Attribut | Année et mois (AAAA-MM), pour les axes mensuels |
| `semaine_iso` | TINYINT | Non | Attribut | Numéro de semaine ISO |
| `jour_semaine` | TINYINT | Non | Attribut | 1 = lundi … 7 = dimanche |
| `nom_jour` | NVARCHAR(20) | Non | Attribut | Nom du jour |
| `est_weekend` | BIT | Non | Indicateur 0/1 | Samedi ou dimanche |
| `est_jour_ferie` | BIT | Non | Indicateur 0/1 | Jour férié national ou religieux |
| `nom_jour_ferie` | NVARCHAR(40) | Oui | Attribut | Libellé du jour férié |
| `est_ramadan` | BIT | Non | Indicateur 0/1 | Jour du mois de Ramadan (dates indicatives) |
| `periode_commerciale` | NVARCHAR(30) | Non | Attribut | Période commerciale (soldes, Ramadan, Black Friday…) |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.dim_geographie

*Dimension* – Gouvernorats, régions et zones de livraison, avec l'entrepôt de rattachement.  
Grain : 1 ligne = 1 gouvernorat. Historisation / chargement : Type 1.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `geo_key` | INT IDENTITY(1,1) | Non | Clé de substitution | Clé de substitution ; -1 = inconnu |
| `gouvernorat_id` | NVARCHAR(20) | Non | Clé métier | Identifiant du gouvernorat (G01 à G24) |
| `gouvernorat` | NVARCHAR(30) | Non | Attribut | Nom du gouvernorat |
| `region` | NVARCHAR(30) | Non | Attribut | Grande région |
| `zone_livraison` | NVARCHAR(5) | Non | Attribut | Zone tarifaire transporteur (Z1 à Z4) |
| `entrepot_rattachement_id` | NVARCHAR(20) | Non | Attribut | Entrepôt de rattachement |
| `entrepot_rattachement` | NVARCHAR(40) | Non | Attribut | Nom de l'entrepôt de rattachement |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.dim_entrepot

*Dimension* – Entrepôts logistiques.  
Grain : 1 ligne = 1 entrepôt. Historisation / chargement : Type 1.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `entrepot_key` | INT IDENTITY(1,1) | Non | Clé de substitution | Clé de substitution ; -1 = inconnu |
| `entrepot_id` | NVARCHAR(20) | Non | Clé métier | Identifiant de l'entrepôt |
| `nom_entrepot` | NVARCHAR(40) | Non | Attribut | Nom de l'entrepôt |
| `ville` | NVARCHAR(30) | Non | Attribut | Ville |
| `surface_m2` | INT | Oui | Attribut | Surface en m² |
| `date_ouverture` | DATE | Oui | Attribut | Date d'ouverture |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.dim_transporteur

*Dimension* – Transporteurs partenaires.  
Grain : 1 ligne = 1 transporteur. Historisation / chargement : Type 1.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `transporteur_key` | INT IDENTITY(1,1) | Non | Clé de substitution | Clé de substitution ; -1 = inconnu |
| `transporteur_id` | NVARCHAR(20) | Non | Clé métier | Identifiant du transporteur |
| `nom_transporteur` | NVARCHAR(30) | Non | Attribut | Nom commercial |
| `couverture` | NVARCHAR(30) | Non | Attribut | Zone couverte |
| `cout_base_ht` | DECIMAL(14,3) | Oui | Attribut | Coût de base d'un colis (DT HT) |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.dim_fournisseur

*Dimension* – Fournisseurs.  
Grain : 1 ligne = 1 fournisseur. Historisation / chargement : Type 1.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `fournisseur_key` | INT IDENTITY(1,1) | Non | Clé de substitution | Clé de substitution ; -1 = inconnu |
| `fournisseur_id` | NVARCHAR(20) | Non | Clé métier | Identifiant du fournisseur |
| `nom_fournisseur` | NVARCHAR(60) | Non | Attribut | Raison sociale |
| `pays` | NVARCHAR(30) | Non | Attribut | Pays |
| `delai_appro_moyen_j` | SMALLINT | Oui | Attribut | Délai d'approvisionnement contractuel moyen (jours) |
| `fiabilite_livraison` | DECIMAL(5,3) | Oui | Attribut | Probabilité contractuelle de livrer sans retard |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.dim_produit

*Dimension* – Produits, avec leur catégorie et leur fournisseur ; les prix sont portés par les faits.  
Grain : 1 ligne = 1 version d'un produit. Historisation / chargement : Type 2 sur univers, sous-catégorie et statut ; type 1 sinon.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `produit_key` | INT IDENTITY(1,1) | Non | Clé de substitution | Clé de substitution ; -1 = inconnu |
| `produit_id` | NVARCHAR(20) | Non | Clé métier | Identifiant du produit |
| `sku` | NVARCHAR(20) | Non | Attribut | Code article |
| `nom_produit` | NVARCHAR(80) | Non | Attribut | Libellé |
| `marque` | NVARCHAR(40) | Oui | Attribut | Marque |
| `categorie_id` | NVARCHAR(20) | Non | Attribut historisé (type 2) | Sous-catégorie (identifiant) |
| `univers` | NVARCHAR(40) | Non | Attribut historisé (type 2) | Catégorie de niveau 1 |
| `sous_categorie` | NVARCHAR(50) | Non | Attribut historisé (type 2) | Catégorie de niveau 2 |
| `taux_tva` | TINYINT | Non | Attribut | Taux de TVA (%) |
| `taux_retour_cible` | DECIMAL(5,3) | Oui | Attribut | Taux de retour attendu |
| `marge_brute_cible` | DECIMAL(5,3) | Oui | Attribut | Taux de marge brute cible |
| `fournisseur_id` | NVARCHAR(20) | Non | Attribut | Fournisseur (identifiant) |
| `statut_produit` | NVARCHAR(20) | Non | Attribut historisé (type 2) | Actif ou arrêté |
| `date_lancement` | DATE | Oui | Attribut | Date de lancement |
| `date_arret` | DATE | Oui | Attribut | Date d'arrêt |
| `date_debut_validite` | DATE | Non | Historisation | Début de validité de la version |
| `date_fin_validite` | DATE | Non | Historisation | Fin de validité (9999-12-31 si courante) |
| `est_courant` | BIT | Non | Historisation | 1 pour la version en vigueur |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.dim_client

*Dimension* – Clients ; les données personnelles (nom, courriel, téléphone, date de naissance) restent en staging et ne sont pas copiées.  
Grain : 1 ligne = 1 version d'un client (après fusion des doublons). Historisation / chargement : Type 2 sur segment, gouvernorat et région ; type 1 sinon.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `client_key` | INT IDENTITY(1,1) | Non | Clé de substitution | Clé de substitution ; -1 = inconnu |
| `client_id` | NVARCHAR(20) | Non | Clé métier | Identifiant du client |
| `type_client` | NVARCHAR(20) | Non | Attribut | Particulier ou professionnel |
| `genre` | NVARCHAR(12) | Non | Attribut | M, F ou Non renseigné |
| `tranche_age` | NVARCHAR(12) | Non | Attribut | Tranche d'âge au 31/12/2025 ; Non renseignée si inconnue |
| `gouvernorat_id` | NVARCHAR(20) | Non | Attribut historisé (type 2) | Gouvernorat de résidence |
| `gouvernorat` | NVARCHAR(30) | Non | Attribut historisé (type 2) | Nom du gouvernorat |
| `region` | NVARCHAR(30) | Non | Attribut historisé (type 2) | Grande région |
| `canal_inscription` | NVARCHAR(30) | Non | Attribut | Canal d'inscription |
| `date_inscription` | DATE | Non | Attribut | Date d'inscription |
| `campagne_acquisition_id` | NVARCHAR(20) | Oui | Attribut | Campagne d'acquisition |
| `opt_in_email` | BIT | Non | Attribut | Accord pour l'emailing |
| `opt_in_sms` | BIT | Non | Attribut | Accord pour les SMS |
| `segment_fidelite` | NVARCHAR(10) | Non | Attribut historisé (type 2) | Or, argent, bronze ou aucun |
| `date_debut_validite` | DATE | Non | Historisation | Début de validité de la version |
| `date_fin_validite` | DATE | Non | Historisation | Fin de validité (9999-12-31 si courante) |
| `est_courant` | BIT | Non | Historisation | 1 pour la version en vigueur |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.dim_campagne

*Dimension* – Campagnes marketing et coupon associé ; -1 = commande non attribuée.  
Grain : 1 ligne = 1 campagne. Historisation / chargement : Type 1.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `campagne_key` | INT IDENTITY(1,1) | Non | Clé de substitution | Clé de substitution ; -1 = aucune campagne |
| `campagne_id` | NVARCHAR(20) | Non | Clé métier | Identifiant de la campagne |
| `nom_campagne` | NVARCHAR(100) | Non | Attribut | Nom de la campagne |
| `canal_marketing` | NVARCHAR(30) | Non | Attribut | Canal (instagram_ads, emailing…) |
| `objectif` | NVARCHAR(20) | Non | Attribut | Acquisition, conversion ou fidélisation |
| `theme` | NVARCHAR(30) | Oui | Attribut | Thème commercial |
| `categorie_ciblee` | NVARCHAR(50) | Oui | Attribut | Sous-catégorie ciblée |
| `code_coupon` | NVARCHAR(20) | Oui | Attribut | Coupon associé |
| `type_remise` | NVARCHAR(20) | Oui | Attribut | Type de remise du coupon |
| `date_debut` | DATE | Non | Attribut | Début de la campagne |
| `date_fin` | DATE | Non | Attribut | Fin de la campagne |
| `budget_ht` | DECIMAL(14,3) | Oui | Attribut | Budget HT |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.dim_canal_paiement

*Dimension* – Combinaisons observées de canal de commande, appareil et mode de paiement.  
Grain : 1 ligne = 1 combinaison canal, appareil et mode de paiement. Historisation / chargement : Type 1 (dimension fourre-tout).

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `canal_paiement_key` | INT IDENTITY(1,1) | Non | Clé de substitution | Clé de substitution ; -1 = inconnu |
| `canal` | NVARCHAR(30) | Non | Clé métier | Canal de commande ; Non renseigné si absent ; Sans objet pour un paiement seul |
| `appareil` | NVARCHAR(20) | Non | Clé métier | Appareil utilisé |
| `mode_paiement` | NVARCHAR(30) | Non | Clé métier | Mode de paiement |
| `est_paiement_en_ligne` | BIT | Non | Indicateur 0/1 | 1 pour carte, portefeuille ou carte prépayée |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.fait_ventes

*Fait* – Ventes au niveau article : quantités, montants TTC et HT, coût et marge au prix du jour.  
Grain : 1 ligne = 1 ligne de commande. Historisation / chargement : Incrémental par date de commande (fenêtre de 35 jours), MERGE sur ligne_id.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `ligne_id` | NVARCHAR(20) | Non | Clé primaire | Identifiant de la ligne de commande (clé du fait) |
| `commande_id` | NVARCHAR(20) | Non | Dimension dégénérée | Identifiant de la commande |
| `date_key` | INT | Non | Clé étrangère | Date de commande |
| `client_key` | INT | Non | Clé étrangère | Client (version valide à la date de commande) |
| `produit_key` | INT | Non | Clé étrangère | Produit (version valide à la date de commande) |
| `geo_key` | INT | Non | Clé étrangère | Gouvernorat de livraison |
| `entrepot_key` | INT | Non | Clé étrangère | Entrepôt qui sert la commande ; -1 si aucun |
| `campagne_key` | INT | Non | Clé étrangère | Campagne attribuée ; -1 si aucune |
| `canal_paiement_key` | INT | Non | Clé étrangère | Canal, appareil et mode de paiement |
| `statut_commande` | NVARCHAR(30) | Non | Attribut | Statut de la commande à la date d'arrêté |
| `est_livree` | BIT | Non | Indicateur 0/1 | 1 si commande livrée, partiellement retournée ou retournée (RG-01) |
| `est_premiere_commande` | BIT | Non | Indicateur 0/1 | 1 si première commande du client |
| `quantite` | INT | Non | Mesure | Quantité commandée |
| `prix_catalogue_ttc` | DECIMAL(14,3) | Non | Mesure | Prix catalogue unitaire TTC du jour |
| `remise_promo_ttc` | DECIMAL(14,3) | Non | Mesure | Remise promotionnelle totale de la ligne |
| `montant_ttc` | DECIMAL(14,3) | Non | Mesure | Montant TTC de la ligne |
| `montant_ht` | DECIMAL(14,3) | Non | Mesure | Montant HT de la ligne |
| `montant_tva` | DECIMAL(14,3) | Non | Mesure | TVA de la ligne |
| `cout_achat_ht` | DECIMAL(14,3) | Non | Mesure | Coût d'achat HT (quantité × coût du jour) |
| `marge_ht` | DECIMAL(14,3) | Non | Mesure | Marge brute HT (RG-05) |
| `est_retournee` | BIT | Non | Indicateur 0/1 | 1 si la ligne fait l'objet d'un retour non refusé (RG-09) |
| `quantite_retournee` | INT | Non | Mesure | Quantité retournée |
| `montant_retour_rembourse_ttc` | DECIMAL(14,3) | Non | Mesure | Montant des retours remboursés sur la ligne |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.fait_commandes

*Fait* – En-têtes de commande : montants, statut, remise, frais et remboursements.  
Grain : 1 ligne = 1 commande. Historisation / chargement : Incrémental par date de commande (fenêtre de 35 jours), MERGE sur commande_id ; les statuts évoluent, la ligne est mise à jour.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `commande_id` | NVARCHAR(20) | Non | Clé primaire | Identifiant de la commande (clé du fait) |
| `date_key` | INT | Non | Clé étrangère | Date de commande |
| `date_annulation_key` | INT | Non | Clé étrangère | Date d'annulation ; -1 si non annulée |
| `client_key` | INT | Non | Clé étrangère | Client (version valide à la date de commande) |
| `geo_key` | INT | Non | Clé étrangère | Gouvernorat de livraison |
| `entrepot_key` | INT | Non | Clé étrangère | Entrepôt ; -1 si aucun |
| `campagne_key` | INT | Non | Clé étrangère | Campagne attribuée ; -1 si aucune |
| `canal_paiement_key` | INT | Non | Clé étrangère | Canal, appareil et mode de paiement |
| `code_coupon` | NVARCHAR(20) | Oui | Dimension dégénérée | Coupon utilisé |
| `statut_commande` | NVARCHAR(30) | Non | Attribut | Statut à la date d'arrêté |
| `motif_annulation` | NVARCHAR(30) | Oui | Attribut | Motif d'annulation (dont rupture_stock) |
| `est_premiere_commande` | BIT | Non | Indicateur 0/1 | 1 si première commande du client |
| `est_livree` | BIT | Non | Indicateur 0/1 | 1 si commande livrée (RG-01) |
| `est_rupture` | BIT | Non | Indicateur 0/1 | 1 si annulée pour rupture de stock (RG-10) |
| `nb_lignes` | SMALLINT | Non | Mesure | Nombre de lignes |
| `nb_articles` | SMALLINT | Non | Mesure | Nombre d'articles |
| `sous_total_ttc` | DECIMAL(14,3) | Non | Mesure | Somme des lignes TTC |
| `remise_coupon_ttc` | DECIMAL(14,3) | Non | Mesure | Remise du coupon |
| `frais_livraison_ttc` | DECIMAL(14,3) | Non | Mesure | Frais de livraison |
| `montant_total_ttc` | DECIMAL(14,3) | Non | Mesure | Montant total TTC (DQ-03) |
| `montant_retours_rembourses_ttc` | DECIMAL(14,3) | Non | Mesure | Retours remboursés (RG-06) |
| `montant_rembourse_total_ttc` | DECIMAL(14,3) | Non | Mesure | Tous remboursements versés (retours, annulations, gestes) |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.fait_livraisons

*Fait* – Expéditions : délais, retards, échecs, coût de transport.  
Grain : 1 ligne = 1 colis. Historisation / chargement : Incrémental par date du dernier événement (fenêtre de 35 jours), MERGE sur livraison_id.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `livraison_id` | NVARCHAR(20) | Non | Clé primaire | Identifiant du colis (clé du fait) |
| `commande_id` | NVARCHAR(20) | Non | Dimension dégénérée | Commande expédiée |
| `date_commande_key` | INT | Non | Clé étrangère | Date de commande (rattachement des KPI au millésime de la commande) |
| `date_expedition_key` | INT | Non | Clé étrangère | Date d'expédition |
| `date_prevue_key` | INT | Non | Clé étrangère | Date promise |
| `date_livraison_key` | INT | Non | Clé étrangère | Date de livraison réelle ; -1 si non livré |
| `transporteur_key` | INT | Non | Clé étrangère | Transporteur |
| `entrepot_key` | INT | Non | Clé étrangère | Entrepôt d'expédition |
| `geo_key` | INT | Non | Clé étrangère | Gouvernorat de destination |
| `client_key` | INT | Non | Clé étrangère | Client |
| `canal_paiement_key` | INT | Non | Clé étrangère | Canal et mode de paiement de la commande |
| `statut_livraison` | NVARCHAR(30) | Non | Attribut | Statut du colis |
| `est_premiere_commande` | BIT | Non | Indicateur 0/1 | 1 si première commande du client |
| `est_livre` | BIT | Non | Indicateur 0/1 | 1 si colis livré |
| `est_en_retard` | BIT | Non | Indicateur 0/1 | 1 si livré après la date promise (RG-07) |
| `retard_j` | SMALLINT | Oui | Mesure | Jours de retard (négatif = en avance) |
| `delai_j` | SMALLINT | Oui | Mesure | Jours entre expédition et livraison |
| `est_echec` | BIT | Non | Indicateur 0/1 | 1 si colis revenu à l'expéditeur |
| `est_refus_cod` | BIT | Non | Indicateur 0/1 | 1 si échec d'un colis payable à la livraison (RG-08) |
| `nb_tentatives` | TINYINT | Oui | Mesure | Nombre de tentatives de livraison |
| `poids_kg` | DECIMAL(8,3) | Oui | Mesure | Poids du colis |
| `cout_transport_ht` | DECIMAL(14,3) | Oui | Mesure | Coût du transport HT |
| `montant_commande_ttc` | DECIMAL(14,3) | Non | Mesure | Montant total de la commande (tranches de panier) |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.fait_retours

*Fait* – Retours, annulations remboursées et gestes commerciaux.  
Grain : 1 ligne = 1 remboursement. Historisation / chargement : Incrémental par date de demande (fenêtre de 35 jours), MERGE sur remboursement_id ; les statuts évoluent.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `remboursement_id` | NVARCHAR(20) | Non | Clé primaire | Identifiant du remboursement (clé du fait) |
| `commande_id` | NVARCHAR(20) | Non | Dimension dégénérée | Commande concernée |
| `ligne_id` | NVARCHAR(20) | Oui | Dimension dégénérée | Ligne retournée ; vide pour une annulation ou un geste |
| `date_commande_key` | INT | Non | Clé étrangère | Date de la commande d'origine |
| `date_demande_key` | INT | Non | Clé étrangère | Date de la demande |
| `date_remboursement_key` | INT | Non | Clé étrangère | Date du remboursement ; -1 si non remboursé |
| `client_key` | INT | Non | Clé étrangère | Client |
| `produit_key` | INT | Non | Clé étrangère | Produit retourné ; -1 si sans objet |
| `type_remboursement` | NVARCHAR(20) | Non | Attribut | Retour, annulation ou geste commercial |
| `motif` | NVARCHAR(40) | Oui | Attribut | Motif du retour |
| `statut` | NVARCHAR(20) | Non | Attribut | Remboursé, refusé ou en cours |
| `etat_article` | NVARCHAR(20) | Oui | Attribut | Revendable ou non revendable |
| `mode_remboursement` | NVARCHAR(30) | Oui | Attribut | Moyen de remboursement |
| `quantite` | INT | Oui | Mesure | Quantité retournée |
| `montant_demande_ttc` | DECIMAL(14,3) | Oui | Mesure | Montant demandé |
| `montant_rembourse_ttc` | DECIMAL(14,3) | Non | Mesure | Montant remboursé (0 si refusé) |
| `delai_traitement_j` | SMALLINT | Oui | Mesure | Jours entre demande et remboursement |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.fait_paiements

*Fait* – Tentatives de paiement en ligne et encaissements à la livraison.  
Grain : 1 ligne = 1 tentative de paiement ou 1 encaissement. Historisation / chargement : Incrémental par date de paiement (fenêtre de 35 jours), MERGE sur paiement_id.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `paiement_id` | NVARCHAR(20) | Non | Clé primaire | Identifiant du paiement (clé du fait) |
| `commande_id` | NVARCHAR(20) | Non | Dimension dégénérée | Commande réglée |
| `date_paiement_key` | INT | Non | Clé étrangère | Date de la tentative ou de l'encaissement (heure de Tunis) |
| `date_reversement_key` | INT | Non | Clé étrangère | Date de reversement ; -1 si sans objet |
| `client_key` | INT | Non | Clé étrangère | Client |
| `canal_paiement_key` | INT | Non | Clé étrangère | Canal et mode de paiement |
| `statut_paiement` | NVARCHAR(20) | Non | Attribut | Réussi, échoué ou encaissé |
| `num_tentative` | TINYINT | Non | Attribut | Numéro de tentative (1 à 3) |
| `code_erreur` | NVARCHAR(30) | Oui | Attribut | Code d'erreur de la passerelle |
| `prestataire` | NVARCHAR(30) | Oui | Attribut | Passerelle ou transporteur encaisseur |
| `montant_ttc` | DECIMAL(14,3) | Non | Mesure | Montant (DQ-39) |
| `delai_reversement_j` | SMALLINT | Oui | Mesure | Jours entre encaissement et reversement |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.fait_stock_mensuel

*Fait* – Photo du stock en fin de mois (mesures semi-additives : ne pas sommer sur le temps).  
Grain : 1 ligne = 1 produit × 1 entrepôt × 1 fin de mois. Historisation / chargement : Ajout de la photo du mois clos ; MERGE sur inventaire_id.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `inventaire_id` | NVARCHAR(20) | Non | Clé primaire | Identifiant de la photo (clé du fait) |
| `date_key` | INT | Non | Clé étrangère | Date d'inventaire (fin de mois) |
| `produit_key` | INT | Non | Clé étrangère | Produit |
| `entrepot_key` | INT | Non | Clé étrangère | Entrepôt |
| `stock_fin_mois` | INT | Non | Mesure | Quantité en stock (semi-additive) |
| `quantite_en_commande` | INT | Non | Mesure | Quantité en commande fournisseur |
| `cout_unitaire_ht` | DECIMAL(14,3) | Non | Mesure | Coût unitaire HT |
| `valeur_stock_ht` | DECIMAL(14,3) | Non | Mesure | Valeur du stock HT (semi-additive) |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.fait_mouvements_stock

*Fait* – Grand livre des mouvements (ventes, réceptions, retours, rebuts, ajustements) ; sert au calcul de la couverture.  
Grain : 1 ligne = 1 mouvement de stock. Historisation / chargement : Incrémental par date de mouvement (fenêtre de 35 jours), MERGE sur mouvement_id.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `mouvement_id` | NVARCHAR(20) | Non | Clé primaire | Identifiant du mouvement (clé du fait) |
| `date_key` | INT | Non | Clé étrangère | Date du mouvement |
| `produit_key` | INT | Non | Clé étrangère | Produit |
| `entrepot_key` | INT | Non | Clé étrangère | Entrepôt |
| `type_mouvement` | NVARCHAR(40) | Non | Attribut | Type (vente, réception, retour, rebut, ajustement…) |
| `reference_id` | NVARCHAR(30) | Oui | Dimension dégénérée | Pièce d'origine (commande, bon d'achat…) |
| `quantite` | INT | Non | Mesure | Quantité signée (+ entrée, − sortie) |
| `cout_unitaire_ht` | DECIMAL(14,3) | Non | Mesure | Coût unitaire HT |
| `valeur_ht` | DECIMAL(16,3) | Non | Mesure | Valeur signée du mouvement |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.fait_achats

*Fait* – Achats : quantités commandées et reçues, retards de réception.  
Grain : 1 ligne = 1 ligne de bon de commande fournisseur. Historisation / chargement : Incrémental par date de commande (fenêtre de 35 jours), MERGE sur ligne_cf_id ; les réceptions évoluent.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `ligne_cf_id` | NVARCHAR(20) | Non | Clé primaire | Identifiant de la ligne d'achat (clé du fait) |
| `commande_fournisseur_id` | NVARCHAR(20) | Non | Dimension dégénérée | Bon de commande |
| `date_commande_key` | INT | Non | Clé étrangère | Date du bon de commande |
| `date_prevue_key` | INT | Non | Clé étrangère | Date de livraison prévue |
| `date_reception_key` | INT | Non | Clé étrangère | Date de réception ; -1 si en cours |
| `fournisseur_key` | INT | Non | Clé étrangère | Fournisseur |
| `produit_key` | INT | Non | Clé étrangère | Produit |
| `entrepot_key` | INT | Non | Clé étrangère | Entrepôt destinataire |
| `statut` | NVARCHAR(30) | Non | Attribut | Réceptionnée, partiellement réceptionnée ou en cours |
| `quantite_commandee` | INT | Non | Mesure | Quantité commandée |
| `quantite_recue` | INT | Oui | Mesure | Quantité reçue (DQ-24) |
| `cout_unitaire_ht` | DECIMAL(14,3) | Non | Mesure | Coût unitaire HT |
| `montant_ht` | DECIMAL(14,3) | Non | Mesure | Montant HT de la ligne |
| `retard_j` | SMALLINT | Oui | Mesure | Jours de retard de réception |
| `est_en_retard` | BIT | Non | Indicateur 0/1 | 1 si réception après la date prévue |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.fait_marketing

*Fait* – Performance quotidienne des campagnes.  
Grain : 1 ligne = 1 campagne × 1 jour. Historisation / chargement : Incrémental par date (fenêtre de 35 jours), MERGE sur depense_id.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `depense_id` | NVARCHAR(20) | Non | Clé primaire | Identifiant de la ligne de dépense (clé du fait) |
| `date_key` | INT | Non | Clé étrangère | Jour |
| `campagne_key` | INT | Non | Clé étrangère | Campagne |
| `canal_marketing` | NVARCHAR(30) | Non | Attribut | Canal de la dépense |
| `depense_ht` | DECIMAL(14,3) | Non | Mesure | Dépense HT (DQ-26) |
| `impressions` | INT | Non | Mesure | Impressions |
| `clics` | INT | Non | Mesure | Clics |
| `commandes_attribuees` | INT | Non | Mesure | Commandes attribuées au dernier clic |
| `nouveaux_clients_attribues` | INT | Non | Mesure | Nouveaux clients attribués |
| `ca_attribue_ttc` | DECIMAL(14,3) | Non | Mesure | Chiffre d'affaires attribué TTC |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |

## dw.fait_avis

*Fait* – Avis clients, reliés au retard de livraison de la commande évaluée.  
Grain : 1 ligne = 1 avis client. Historisation / chargement : Incrémental par date d'avis (fenêtre de 35 jours), MERGE sur avis_id.

| Colonne | Type | NULL | Rôle | Description |
|---|---|---|---|---|
| `avis_id` | NVARCHAR(20) | Non | Clé primaire | Identifiant de l'avis (clé du fait) |
| `commande_id` | NVARCHAR(20) | Non | Dimension dégénérée | Commande évaluée |
| `ligne_id` | NVARCHAR(20) | Non | Dimension dégénérée | Ligne évaluée |
| `date_key` | INT | Non | Clé étrangère | Date de l'avis |
| `produit_key` | INT | Non | Clé étrangère | Produit évalué |
| `client_key` | INT | Non | Clé étrangère | Client |
| `transporteur_key` | INT | Non | Clé étrangère | Transporteur du colis |
| `note` | TINYINT | Non | Mesure | Note de 1 à 5 (DQ-29) |
| `achat_verifie` | BIT | Non | Indicateur 0/1 | Avis lié à un achat livré |
| `retard_livraison_j` | SMALLINT | Oui | Mesure | Retard du colis de la commande évaluée |
| `commentaire` | NVARCHAR(400) | Oui | Attribut | Commentaire nettoyé (DQ-38) |
| `_run_id` | NVARCHAR(40) | Oui | Audit | Exécution qui a écrit la ligne |
| `_date_maj` | DATETIME2(0) | Non | Audit | Date de dernière écriture |
