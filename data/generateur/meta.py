# -*- coding: utf-8 -*-
"""Dictionnaire de données TuniShop : description des tables et colonnes."""
META = {
"ref_gouvernorats": ("Référentiel des 24 gouvernorats tunisiens et de leur rattachement logistique.", "1 ligne = 1 gouvernorat", {
    "gouvernorat_id": "Identifiant (G01-G24).", "gouvernorat": "Nom du gouvernorat.", "region": "Grande région (Grand Tunis, Nord-Est, Nord-Ouest, Centre-Est, Centre-Ouest, Sud-Est, Sud-Ouest).",
    "entrepot_rattachement_id": "Entrepôt qui sert ce gouvernorat par défaut (FK entrepots).", "zone_livraison": "Zone tarifaire transporteur (Z1 la plus proche à Z4 la plus éloignée)."}),
"dim_calendrier": ("Dimension date du 01/01/2023 au 31/12/2025 avec jours fériés tunisiens et périodes commerciales.", "1 ligne = 1 jour", {
    "date": "Date (AAAA-MM-JJ), clé.", "annee": "Année.", "trimestre": "Trimestre (1-4).", "mois": "Mois (1-12).", "nom_mois": "Nom du mois en français.",
    "semaine_iso": "Numéro de semaine ISO.", "jour_semaine": "1 = lundi ... 7 = dimanche.", "nom_jour": "Nom du jour.", "est_weekend": "Samedi ou dimanche.",
    "est_jour_ferie": "Jour férié national ou religieux (dates religieuses indicatives).", "nom_jour_ferie": "Libellé du jour férié.",
    "est_ramadan": "Jour inclus dans le mois de Ramadan (dates indicatives).",
    "periode_commerciale": "normale, soldes_hiver, soldes_ete, ramadan, pre_aid_fitr, pre_aid_idha, rentree_scolaire, black_friday, fin_annee."}),
"entrepots": ("Entrepôts logistiques de TuniShop.", "1 ligne = 1 entrepôt", {
    "entrepot_id": "Identifiant (ENT01-ENT03).", "nom_entrepot": "Nom.", "ville": "Ville.", "gouvernorat_id": "FK ref_gouvernorats.",
    "date_ouverture": "Date d'ouverture.", "surface_m2": "Surface en m²."}),
"transporteurs": ("Transporteurs partenaires (noms fictifs).", "1 ligne = 1 transporteur", {
    "transporteur_id": "Identifiant (TR01-TR04).", "nom_transporteur": "Nom commercial fictif.", "couverture": "Zone couverte.",
    "cout_base_ht": "Coût de base d'un colis (DT HT) avant majoration de zone et de poids.", "ecart_delai_moyen_j": "Écart de délai contractuel moyen (jours, + = plus lent).",
    "date_debut_contrat": "Début du contrat."}),
"fournisseurs": ("Fournisseurs (noms fictifs), locaux et à l'import.", "1 ligne = 1 fournisseur", {
    "fournisseur_id": "Identifiant (FRN001...).", "nom_fournisseur": "Raison sociale fictive.", "pays": "Pays du fournisseur.",
    "delai_appro_moyen_j": "Délai d'approvisionnement contractuel moyen (jours).", "conditions_paiement": "Conditions de paiement.",
    "fiabilite_livraison": "Probabilité contractuelle de livrer sans retard (0-1).", "email_contact": "Email fictif du service achats."}),
"categories": ("Catégories et sous-catégories de produits.", "1 ligne = 1 sous-catégorie", {
    "categorie_id": "Identifiant (CAT01...).", "categorie": "Catégorie (niveau 1).", "sous_categorie": "Sous-catégorie (niveau 2).",
    "taux_tva": "Taux de TVA appliqué (%) - affectation pédagogique, à ne pas utiliser comme référence fiscale.",
    "taux_retour_cible": "Taux de retour attendu par le métier (objectif interne).", "marge_brute_cible": "Taux de marge brute cible sur le prix HT."}),
"produits": ("Catalogue produits, vue à la date d'arrêté (prix et coût actuels).", "1 ligne = 1 produit (SKU)", {
    "produit_id": "Identifiant (PRD0001...).", "sku": "Code article unique.", "nom_produit": "Libellé (marques fictives).", "categorie_id": "FK categories.",
    "marque": "Marque fictive.", "fournisseur_id": "Fournisseur principal (FK fournisseurs).", "prix_catalogue_ttc_actuel": "Prix de vente TTC en vigueur (DT, 3 décimales).",
    "cout_achat_unitaire_ht_actuel": "Coût d'achat unitaire HT en vigueur (DT).", "taux_tva": "Taux de TVA (%).", "poids_kg": "Poids unitaire (kg).",
    "date_lancement": "Date de mise en vente.", "date_arret": "Date de fin de commercialisation (vide si actif).", "statut_produit": "actif ou arrete."}),
"produits_prix_historique": ("Historique des prix et coûts (SCD type 2). Révision annuelle au 1er janvier.", "1 ligne = 1 produit x 1 période de validité", {
    "prix_id": "Identifiant.", "produit_id": "FK produits.", "date_debut": "Début de validité (inclus).", "date_fin": "Fin de validité (incluse, vide = en cours).",
    "prix_catalogue_ttc": "Prix de vente TTC sur la période.", "cout_achat_unitaire_ht": "Coût d'achat HT sur la période.", "est_prix_actuel": "Ligne en vigueur à la date d'arrêté."}),
"clients": ("Clients inscrits (particuliers et professionnels). Données entièrement fictives.", "1 ligne = 1 compte client", {
    "client_id": "Identifiant (CLI000001...).", "type_client": "particulier ou professionnel.", "prenom": "Prénom fictif.", "nom": "Nom fictif.", "genre": "F ou M.",
    "date_naissance": "Date de naissance (vide pour les professionnels).", "raison_sociale": "Raison sociale fictive (professionnels).",
    "matricule_fiscal": "Matricule fiscal fictif au format tunisien (professionnels).", "email": "Email (vide si inscription par téléphone uniquement).",
    "telephone": "Mobile au format E.164 (+216XXXXXXXX).", "gouvernorat_id": "Gouvernorat de résidence (FK).", "ville": "Ville de résidence.",
    "date_inscription": "Horodatage de création du compte (heure locale Tunis).", "canal_inscription": "Canal d'acquisition déclaré.",
    "campagne_acquisition_id": "Campagne d'acquisition à l'origine de l'inscription (FK, peut être vide).", "opt_in_email": "Consentement emailing.",
    "opt_in_sms": "Consentement SMS.", "segment_fidelite": "Segment CRM calculé sur le CA net 2025 : or (>= 1500 DT), argent (>= 500), bronze (> 0), aucun."}),
"campagnes_marketing": ("Campagnes marketing (paid, CRM, influence).", "1 ligne = 1 campagne", {
    "campagne_id": "Identifiant (CMP0001...).", "nom_campagne": "Nom.", "canal": "facebook_ads, instagram_ads, google_ads, tiktok_ads, emailing, sms, influence.",
    "objectif": "acquisition, conversion ou fidelisation.", "theme": "Temps fort (ramadan, pre_fitr, soldes, rentree, bf, fin_annee, ete) ou permanent.",
    "categorie_ciblee_id": "Catégorie mise en avant (FK, optionnel).", "code_coupon": "Code promo associé (FK coupons, optionnel).",
    "date_debut": "Premier jour.", "date_fin": "Dernier jour.", "budget_ht": "Budget prévu (DT HT)."}),
"coupons": ("Codes promotionnels.", "1 ligne = 1 code", {
    "code_coupon": "Code (clé).", "type_remise": "pourcentage ou montant_fixe.", "valeur": "% ou montant en DT TTC.", "montant_min_ttc": "Sous-total minimum pour utiliser le code.",
    "plafond_remise_ttc": "Remise maximale (codes en pourcentage).", "date_debut": "Début de validité.", "date_fin": "Fin de validité (vide = permanent).",
    "campagne_id": "Campagne liée (FK).", "reserve_premiere_commande": "Utilisable uniquement sur la 1re commande du client."}),
"marketing_depenses_quotidiennes": ("Performance quotidienne des campagnes (dépenses régie + attribution last-click interne).", "1 ligne = 1 campagne x 1 jour", {
    "depense_id": "Identifiant.", "campagne_id": "FK campagnes_marketing.", "date": "Jour.", "canal": "Canal (dénormalisé).", "depense_ht": "Dépense du jour (DT HT).",
    "impressions": "Impressions / envois.", "clics": "Clics.", "commandes_attribuees": "Commandes attribuées à la campagne ce jour (hors paiement échoué).",
    "nouveaux_clients_attribues": "Dont 1res commandes.", "ca_attribue_ttc": "CA TTC brut des commandes attribuées."}),
"commandes": ("En-têtes de commandes e-commerce du 01/01/2023 au 31/12/2025.", "1 ligne = 1 commande", {
    "commande_id": "Identifiant (CMD0000001...).", "client_id": "FK clients.", "date_commande": "Horodatage de validation du panier (heure locale Tunis).",
    "canal": "site_web, application_mobile, reseaux_sociaux.", "appareil": "ordinateur, mobile, tablette.", "gouvernorat_livraison_id": "Gouvernorat de livraison (FK).",
    "ville_livraison": "Ville de livraison.", "entrepot_id": "Entrepôt qui a servi la commande (vide si aucun stock ou paiement échoué).",
    "campagne_id": "Campagne attribuée (last-click, FK).", "code_coupon": "Code promo utilisé (FK).",
    "mode_paiement": "paiement_a_la_livraison, carte_bancaire, portefeuille_mobile, carte_prepayee, virement.", "nb_lignes": "Nombre de lignes.",
    "nb_articles": "Somme des quantités.", "sous_total_ttc": "Somme des montants de lignes TTC (après promotions produit).",
    "remise_coupon_ttc": "Remise du code promo (DT TTC).", "frais_livraison_ttc": "Frais facturés au client : 7,000 DT si (sous-total - remise) < 150 DT, sinon 0.",
    "montant_total_ttc": "Montant payé par le client = sous_total - remise + frais.",
    "statut_commande": "Statut à la date d'arrêté : livree, partiellement_retournee, retournee, annulee, paiement_echoue, livraison_echouee, expediee, en_preparation.",
    "motif_annulation": "rupture_stock ou annulation_client.", "date_annulation": "Horodatage d'annulation.", "est_premiere_commande": "1re commande chronologique du client."}),
"lignes_commande": ("Lignes de commandes.", "1 ligne = 1 produit dans 1 commande", {
    "ligne_id": "Identifiant (LIG...).", "commande_id": "FK commandes.", "num_ligne": "Rang de la ligne.", "produit_id": "FK produits.", "quantite": "Quantité commandée.",
    "prix_catalogue_ttc": "Prix catalogue TTC à la date de commande.", "remise_promo_unitaire_ttc": "Remise promotionnelle unitaire (soldes, Black Friday).",
    "prix_unitaire_ttc": "Prix unitaire payé = catalogue - remise promo.", "taux_tva": "TVA (%).", "montant_ligne_ttc": "quantite x prix_unitaire_ttc.",
    "montant_ligne_ht": "montant TTC / (1 + TVA).", "montant_tva": "TTC - HT.", "cout_achat_unitaire_ht": "Coût d'achat unitaire HT à la date (pour la marge)."}),
"paiements": ("Transactions de paiement (tentatives en ligne et encaissements).", "1 ligne = 1 tentative / 1 encaissement", {
    "paiement_id": "Identifiant.", "commande_id": "FK commandes.", "num_tentative": "Rang de la tentative (1-3).", "mode_paiement": "Mode de paiement.",
    "montant_ttc": "Montant (DT).", "statut_paiement": "reussi, echoue (en ligne), encaisse (paiement à la livraison).",
    "code_erreur": "Motif de refus (tentatives échouées).", "date_paiement": "Horodatage (heure locale Tunis dans la couche de référence).",
    "prestataire": "Passerelle (TuniPay, fictive), transporteur collecteur ou banque.", "reference_transaction": "Référence fictive.",
    "date_reversement": "Paiement à la livraison : date de reversement des fonds par le transporteur."}),
"remboursements": ("Remboursements : retours produits, annulations de commandes prépayées, gestes commerciaux.", "1 ligne = 1 remboursement", {
    "remboursement_id": "Identifiant.", "commande_id": "FK commandes.", "ligne_id": "Ligne concernée (retours uniquement).",
    "type_remboursement": "retour, annulation, geste_commercial.", "motif": "Motif déclaré.", "quantite": "Quantité retournée (retours).",
    "montant_rembourse_ttc": "Montant effectivement remboursé (0 si refusé).", "montant_demande_ttc": "Montant demandé (prix payé au prorata du coupon).",
    "date_demande": "Demande du client.", "date_reception_retour": "Réception de l'article à l'entrepôt.", "date_remboursement": "Exécution du remboursement.",
    "mode_remboursement": "Moyen de remboursement (identique au paiement si prépayé ; virement ou bon d'achat sinon).",
    "statut": "rembourse, refuse, en_cours.", "etat_article": "revendable ou non_revendable (contrôle qualité au retour)."}),
"livraisons": ("Expéditions transporteur.", "1 ligne = 1 colis (1 par commande expédiée)", {
    "livraison_id": "Identifiant.", "commande_id": "FK commandes.", "entrepot_id": "Entrepôt expéditeur.", "transporteur_id": "FK transporteurs.",
    "gouvernorat_destination_id": "Destination (FK).", "date_expedition": "Remise au transporteur.", "date_livraison_prevue": "Date promise au client (SLA).",
    "date_livraison_reelle": "Livraison effective.", "date_dernier_evenement": "Dernier événement de suivi (livraison ou échec).",
    "statut_livraison": "livree, echec_retour_expediteur, en_transit, en_preparation.", "nb_tentatives": "Nombre de passages du livreur.",
    "poids_kg": "Poids du colis.", "cout_transport_ht": "Coût facturé par le transporteur à TuniShop (DT HT)."}),
"commandes_fournisseurs": ("Bons de commande d'achat (réapprovisionnement automatique par point de commande).", "1 ligne = 1 bon de commande", {
    "commande_fournisseur_id": "Identifiant (CF...).", "fournisseur_id": "FK fournisseurs.", "entrepot_id": "Entrepôt destinataire.", "date_commande": "Émission du bon.",
    "date_livraison_prevue": "Date de livraison prévue (délai contractuel).", "date_reception": "Réception effective (vide si en cours).",
    "statut": "receptionnee, partiellement_receptionnee, en_cours.", "montant_total_ht": "Montant commandé HT."}),
"lignes_commande_fournisseur": ("Lignes des bons de commande d'achat.", "1 ligne = 1 produit dans 1 bon", {
    "ligne_cf_id": "Identifiant.", "commande_fournisseur_id": "FK commandes_fournisseurs.", "produit_id": "FK produits.", "quantite_commandee": "Quantité commandée.",
    "quantite_recue": "Quantité reçue (peut être inférieure : livraison partielle, pas de reliquat).", "cout_unitaire_ht": "Coût négocié.", "montant_ligne_ht": "quantite_commandee x coût."}),
"mouvements_stock": ("Grand livre des mouvements de stock (source de vérité du stock).", "1 ligne = 1 mouvement", {
    "mouvement_id": "Identifiant.", "date_mouvement": "Horodatage.", "produit_id": "FK produits.", "entrepot_id": "FK entrepots.",
    "type_mouvement": "stock_initial, reception_fournisseur, vente, annulation_commande, retour_echec_livraison, retour_client, retour_client_non_revendable, mise_au_rebut, ajustement_inventaire.",
    "quantite": "Quantité signée (+ entrée, - sortie).", "reference_id": "Pièce d'origine (commande, bon fournisseur, inventaire).", "cout_unitaire_ht": "Coût unitaire valorisé."}),
"stocks_mensuels": ("Photo du stock en fin de mois, calculée à partir des mouvements.", "1 ligne = 1 produit x 1 entrepôt x 1 fin de mois", {
    "inventaire_id": "Identifiant.", "date_inventaire": "Dernier jour du mois.", "produit_id": "FK produits.", "entrepot_id": "FK entrepots.",
    "stock_fin_mois": "Quantité en stock à 23:59:59.", "quantite_en_commande": "Quantité commandée aux fournisseurs non encore reçue.",
    "cout_unitaire_ht": "Coût de l'année.", "valeur_stock_ht": "stock x coût."}),
"avis_clients": ("Avis clients après livraison (commentaires en français et en derja latinisée).", "1 ligne = 1 avis", {
    "avis_id": "Identifiant.", "commande_id": "FK commandes.", "ligne_id": "FK lignes_commande.", "produit_id": "FK produits.", "client_id": "FK clients.",
    "date_avis": "Horodatage.", "note": "Note de 1 à 5.", "commentaire": "Texte libre (peut être vide).", "achat_verifie": "Avis lié à un achat livré."}),
}
