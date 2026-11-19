-- TuniShop : contrôles qualité (PostgreSQL). Chaque requête doit renvoyer 0 sur la couche nettoyée.
SET search_path TO tunishop;

-- DQ-01 Unicité de la clé primaire (exemple sur commandes, à décliner sur chaque table)
SELECT 'DQ-01' AS regle, COUNT(*) - COUNT(DISTINCT commande_id) AS violations FROM commandes;

-- DQ-02 Intégrité référentielle (exemples)
SELECT 'DQ-02' AS regle, COUNT(*) AS violations FROM commandes c LEFT JOIN clients k ON k.client_id = c.client_id WHERE k.client_id IS NULL;
SELECT 'DQ-02' AS regle, COUNT(*) AS violations FROM lignes_commande l LEFT JOIN produits p ON p.produit_id = l.produit_id WHERE p.produit_id IS NULL;
SELECT 'DQ-02' AS regle, COUNT(*) AS violations FROM paiements p LEFT JOIN commandes c ON c.commande_id = p.commande_id WHERE c.commande_id IS NULL;

-- DQ-03 Total commande
SELECT 'DQ-03' AS regle, COUNT(*) AS violations FROM commandes
WHERE ABS(montant_total_ttc - (sous_total_ttc - remise_coupon_ttc + frais_livraison_ttc)) > 0.0015;

-- DQ-04 Sous-total = somme des lignes
SELECT 'DQ-04' AS regle, COUNT(*) AS violations FROM commandes c
JOIN (SELECT commande_id, SUM(montant_ligne_ttc) st, COUNT(*) n, SUM(quantite) q FROM lignes_commande GROUP BY commande_id) l USING (commande_id)
WHERE ABS(c.sous_total_ttc - l.st) > 0.0015 * l.n OR c.nb_lignes <> l.n OR c.nb_articles <> l.q;

-- DQ-05 Cohérence des montants de ligne
SELECT 'DQ-05' AS regle, COUNT(*) AS violations FROM lignes_commande
WHERE ABS(prix_unitaire_ttc - (prix_catalogue_ttc - remise_promo_unitaire_ttc)) > 0.0015
   OR ABS(montant_ligne_ttc - quantite * prix_unitaire_ttc) > 0.0015
   OR ABS(montant_ligne_ht + montant_tva - montant_ligne_ttc) > 0.0015;

-- DQ-06 Quantités positives
SELECT 'DQ-06' AS regle, COUNT(*) AS violations FROM lignes_commande WHERE quantite <= 0;

-- DQ-07 Frais de livraison
SELECT 'DQ-07' AS regle, COUNT(*) AS violations FROM commandes
WHERE frais_livraison_ttc <> CASE WHEN sous_total_ttc - remise_coupon_ttc < 150 THEN 7 ELSE 0 END;

-- DQ-09 TVA cohérente avec le produit
SELECT 'DQ-09' AS regle, COUNT(*) AS violations FROM lignes_commande l JOIN produits p USING (produit_id)
WHERE l.taux_tva NOT IN (7, 13, 19) OR l.taux_tva <> p.taux_tva;

-- DQ-10 Prix de ligne = historique valide à la date de commande
SELECT 'DQ-10' AS regle, COUNT(*) AS violations FROM lignes_commande l JOIN commandes c USING (commande_id)
LEFT JOIN produits_prix_historique h ON h.produit_id = l.produit_id
  AND c.date_commande::date BETWEEN h.date_debut AND COALESCE(h.date_fin, DATE '2099-12-31')
WHERE h.prix_id IS NULL OR ABS(h.prix_catalogue_ttc - l.prix_catalogue_ttc) > 0.0005;

-- DQ-11 Inscription avant la 1re commande
SELECT 'DQ-11' AS regle, COUNT(*) AS violations FROM clients k
JOIN (SELECT client_id, MIN(date_commande) d FROM commandes GROUP BY client_id) f USING (client_id) WHERE k.date_inscription > f.d;

-- DQ-12 Chronologie de livraison
SELECT 'DQ-12' AS regle, COUNT(*) AS violations FROM livraisons v JOIN commandes c USING (commande_id)
WHERE v.date_expedition < c.date_commande OR v.date_livraison_reelle < v.date_expedition;

-- DQ-13 Statut commande cohérent avec la livraison
SELECT 'DQ-13' AS regle, COUNT(*) AS violations FROM commandes c LEFT JOIN livraisons v USING (commande_id)
WHERE (c.statut_commande IN ('livree','retournee','partiellement_retournee') AND COALESCE(v.statut_livraison,'') <> 'livree')
   OR (c.statut_commande = 'livraison_echouee' AND COALESCE(v.statut_livraison,'') <> 'echec_retour_expediteur')
   OR (c.statut_commande IN ('annulee','paiement_echoue') AND v.livraison_id IS NOT NULL);

-- DQ-14 Un seul paiement réussi, montant = total
SELECT 'DQ-14' AS regle, COUNT(*) AS violations FROM (
  SELECT p.commande_id, COUNT(*) n, MAX(ABS(p.montant_ttc - c.montant_total_ttc)) ecart
  FROM paiements p JOIN commandes c USING (commande_id) WHERE p.statut_paiement IN ('reussi','encaisse') GROUP BY p.commande_id) x
WHERE n > 1 OR ecart > 0.0015;

-- DQ-15 Commande livrée (hors virement) => paiement réussi
SELECT 'DQ-15' AS regle, COUNT(*) AS violations FROM commandes c
WHERE c.statut_commande IN ('livree','retournee','partiellement_retournee') AND c.mode_paiement <> 'virement'
  AND NOT EXISTS (SELECT 1 FROM paiements p WHERE p.commande_id = c.commande_id AND p.statut_paiement IN ('reussi','encaisse'));

-- DQ-18 Retour accepté dans les 10 jours ouvrables (jours ouvrables comptés avec dim_calendrier)
SELECT 'DQ-18' AS regle, COUNT(*) AS violations FROM remboursements r JOIN livraisons v USING (commande_id)
WHERE r.type_remboursement = 'retour' AND r.statut <> 'refuse'
  AND (SELECT COUNT(*) FROM dim_calendrier d WHERE d.date > v.date_livraison_reelle::date AND d.date <= r.date_demande::date
       AND NOT d.est_weekend AND NOT d.est_jour_ferie) > 10;

-- DQ-19 Montant de retour <= montant net de la ligne
SELECT 'DQ-19' AS regle, COUNT(*) AS violations FROM remboursements r JOIN lignes_commande l USING (ligne_id) JOIN commandes c ON c.commande_id = r.commande_id
WHERE r.quantite > l.quantite
   OR r.montant_rembourse_ttc > l.prix_unitaire_ttc * r.quantite * (1 - c.remise_coupon_ttc / c.sous_total_ttc) + 0.0015;

-- DQ-20 Chronologie des remboursements
SELECT 'DQ-20' AS regle, COUNT(*) AS violations FROM remboursements
WHERE date_reception_retour < date_demande OR date_remboursement < date_demande OR date_remboursement < date_reception_retour;

-- DQ-22 Stock jamais négatif
SELECT 'DQ-22' AS regle, COUNT(*) AS violations FROM (
  SELECT SUM(quantite) OVER (PARTITION BY produit_id, entrepot_id ORDER BY date_mouvement, mouvement_id) AS cumul FROM mouvements_stock) x
WHERE cumul < 0;

-- DQ-23 Sorties vente = articles des commandes servies
SELECT 'DQ-23' AS regle, COUNT(*) AS violations FROM commandes c
LEFT JOIN (SELECT reference_id, -SUM(quantite) q FROM mouvements_stock WHERE type_mouvement = 'vente' GROUP BY reference_id) m ON m.reference_id = c.commande_id
WHERE c.entrepot_id IS NOT NULL AND COALESCE(m.q, 0) <> c.nb_articles;

-- DQ-24 Achats
SELECT 'DQ-24' AS regle, COUNT(*) AS violations FROM lignes_commande_fournisseur WHERE quantite_recue > quantite_commandee;
SELECT 'DQ-24' AS regle, COUNT(*) AS violations FROM commandes_fournisseurs WHERE date_reception < date_commande;

-- DQ-25 Stock mensuel
SELECT 'DQ-25' AS regle, COUNT(*) AS violations FROM stocks_mensuels
WHERE stock_fin_mois < 0 OR ABS(valeur_stock_ht - stock_fin_mois * cout_unitaire_ht) > 0.002;

-- DQ-26 Marketing
SELECT 'DQ-26' AS regle, COUNT(*) AS violations FROM marketing_depenses_quotidiennes m JOIN campagnes_marketing c USING (campagne_id)
WHERE m.clics > m.impressions OR m.depense_ht < 0 OR m.date NOT BETWEEN c.date_debut AND c.date_fin;

-- DQ-28 Coupon BIENVENUE10 sur 1re commande uniquement
SELECT 'DQ-28' AS regle, COUNT(*) AS violations FROM commandes WHERE code_coupon = 'BIENVENUE10' AND NOT est_premiere_commande;

-- DQ-29 Notes d'avis
SELECT 'DQ-29' AS regle, COUNT(*) AS violations FROM avis_clients WHERE note NOT BETWEEN 1 AND 5;

-- DQ-30 Formats email / téléphone
SELECT 'DQ-30' AS regle, COUNT(*) AS violations FROM clients
WHERE telephone !~ '^\+216[2-9][0-9]{7}$' OR (email IS NOT NULL AND email !~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$');

-- DQ-34 Aucune date après l'arrêté
SELECT 'DQ-34' AS regle, COUNT(*) AS violations FROM commandes WHERE date_commande > TIMESTAMP '2025-12-31 23:59:59';

-- DQ-36 Doublons techniques (à exécuter sur la couche bronze)
-- SELECT commande_id, COUNT(*) FROM bronze.commandes GROUP BY commande_id HAVING COUNT(*) > 1;

-- DQ-37 Doublons métier de clients (à exécuter sur la couche silver, téléphone déjà normalisé)
-- SELECT lower(prenom), lower(nom), telephone, COUNT(*) FROM silver.clients GROUP BY 1,2,3 HAVING COUNT(*) > 1;
