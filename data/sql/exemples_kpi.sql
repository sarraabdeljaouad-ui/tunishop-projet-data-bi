-- TuniShop : exemples de requêtes KPI (PostgreSQL, adaptables à SQLite / DuckDB)
SET search_path TO tunishop;

-- CA mensuel brut, remboursé et net (commandes livrées ou retournées)
WITH cmd AS (
  SELECT commande_id, date_trunc('month', date_commande) AS mois, montant_total_ttc
  FROM commandes WHERE statut_commande IN ('livree','retournee','partiellement_retournee')),
rmb AS (SELECT commande_id, SUM(montant_rembourse_ttc) m FROM remboursements WHERE statut = 'rembourse' GROUP BY commande_id)
SELECT mois, COUNT(*) commandes, SUM(montant_total_ttc) ca_brut_ttc, COALESCE(SUM(m), 0) rembourse_ttc,
       SUM(montant_total_ttc) - COALESCE(SUM(m), 0) ca_net_ttc, ROUND(AVG(montant_total_ttc), 3) panier_moyen
FROM cmd LEFT JOIN rmb USING (commande_id) GROUP BY mois ORDER BY mois;

-- Marge brute HT par catégorie et par année
SELECT EXTRACT(YEAR FROM c.date_commande) annee, k.categorie,
       SUM(l.montant_ligne_ht) ca_ht, SUM(l.montant_ligne_ht - l.quantite * l.cout_achat_unitaire_ht) marge_ht,
       ROUND(SUM(l.montant_ligne_ht - l.quantite * l.cout_achat_unitaire_ht) / SUM(l.montant_ligne_ht), 3) taux_marge
FROM lignes_commande l JOIN commandes c USING (commande_id) JOIN produits p USING (produit_id) JOIN categories k USING (categorie_id)
WHERE c.statut_commande IN ('livree','retournee','partiellement_retournee')
GROUP BY 1, 2 ORDER BY 1, 4 DESC;

-- Livraison à l'heure (OTD) par transporteur et par trimestre
SELECT t.nom_transporteur, date_trunc('quarter', v.date_expedition) trimestre, COUNT(*) livraisons,
       ROUND(AVG(CASE WHEN v.date_livraison_reelle::date <= v.date_livraison_prevue THEN 1 ELSE 0 END), 3) taux_otd,
       ROUND(AVG(v.date_livraison_reelle::date - v.date_expedition::date), 2) delai_moyen_j
FROM livraisons v JOIN transporteurs t USING (transporteur_id)
WHERE v.statut_livraison = 'livree' GROUP BY 1, 2 ORDER BY 1, 2;

-- Taux de retour par catégorie (lignes livrées)
SELECT k.categorie, COUNT(*) lignes, ROUND(AVG(CASE WHEN r.ligne_id IS NOT NULL THEN 1 ELSE 0 END), 3) taux_retour
FROM lignes_commande l JOIN commandes c USING (commande_id) JOIN produits p USING (produit_id) JOIN categories k USING (categorie_id)
LEFT JOIN remboursements r ON r.ligne_id = l.ligne_id AND r.type_remboursement = 'retour' AND r.statut <> 'refuse'
WHERE c.statut_commande IN ('livree','retournee','partiellement_retournee') GROUP BY 1 ORDER BY 3 DESC;

-- ROAS, CPC et CAC par canal marketing
SELECT canal, SUM(depense_ht) depense, SUM(ca_attribue_ttc) / NULLIF(SUM(depense_ht), 0) roas,
       SUM(depense_ht) / NULLIF(SUM(clics), 0) cpc, SUM(depense_ht) / NULLIF(SUM(nouveaux_clients_attribues), 0) cac
FROM marketing_depenses_quotidiennes GROUP BY canal ORDER BY roas DESC;

-- Couverture de stock (jours) à fin 2025 : stock / ventes moyennes journalières du T4
WITH v AS (SELECT produit_id, entrepot_id, -SUM(quantite) / 92.0 vmj FROM mouvements_stock
           WHERE type_mouvement = 'vente' AND date_mouvement >= '2025-10-01' GROUP BY 1, 2)
SELECT s.produit_id, s.entrepot_id, s.stock_fin_mois, ROUND(v.vmj, 2) ventes_moy_j, ROUND(s.stock_fin_mois / NULLIF(v.vmj, 0), 1) couverture_j
FROM stocks_mensuels s JOIN v USING (produit_id, entrepot_id) WHERE s.date_inventaire = '2025-12-31' ORDER BY couverture_j NULLS LAST;

-- Cohortes : rétention mensuelle par mois de 1re commande
WITH o AS (SELECT client_id, date_trunc('month', date_commande) m FROM commandes WHERE statut_commande <> 'paiement_echoue'),
f AS (SELECT client_id, MIN(m) cohorte FROM o GROUP BY client_id)
SELECT f.cohorte, (EXTRACT(YEAR FROM age(o.m, f.cohorte)) * 12 + EXTRACT(MONTH FROM age(o.m, f.cohorte)))::int mois_ecoule,
       COUNT(DISTINCT o.client_id) clients_actifs
FROM o JOIN f USING (client_id) GROUP BY 1, 2 ORDER BY 1, 2;
