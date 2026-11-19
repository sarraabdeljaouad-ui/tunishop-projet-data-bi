# Règles de qualité des données - TuniShop

Chaque règle a un identifiant utilisé dans `sql/controles_qualite.sql`, `generateur/gen_part4_checks.py` et `solutions/anomalies_injectees.csv`.

Sévérité : **Bloquante** = la donnée ne doit pas entrer dans la couche nettoyée sans correction ; **Majeure** = corriger ou isoler en quarantaine ; **Mineure** = normaliser.

| Règle | Dimension | Contrôle | Tables | Sévérité |
|---|---|---|---|---|
| DQ-01 | Unicité | Clé primaire non nulle et unique | toutes | Bloquante |
| DQ-02 | Intégrité | Toute clé étrangère existe dans la table de référence | toutes | Bloquante |
| DQ-03 | Exactitude | Total commande = sous-total - remise + frais | commandes | Majeure |
| DQ-04 | Cohérence | Sous-total = Σ lignes ; nb_lignes et nb_articles cohérents | commandes, lignes | Majeure |
| DQ-05 | Exactitude | Prix unitaire, montant de ligne, HT/TVA/TTC cohérents | lignes_commande | Majeure |
| DQ-06 | Validité | Quantités > 0 | lignes, achats, retours | Bloquante |
| DQ-07 | Exactitude | Frais de livraison selon le seuil de 150 DT | commandes | Mineure |
| DQ-08 | Validité | 0 ≤ remise ≤ sous-total, remise nulle sans coupon | commandes | Majeure |
| DQ-09 | Validité | TVA ∈ {7, 13, 19} et égale à celle du produit | lignes_commande | Majeure |
| DQ-10 | Cohérence | Prix et coût de ligne = historique valide à la date | lignes, prix_historique | Majeure |
| DQ-11 | Chronologie | Inscription ≤ première commande | clients, commandes | Majeure |
| DQ-12 | Chronologie | Commande ≤ expédition ≤ livraison ; annulation ≥ commande | commandes, livraisons | Bloquante |
| DQ-13 | Cohérence | Statut commande ↔ statut livraison, 1 colis par commande expédiée | commandes, livraisons | Majeure |
| DQ-14 | Unicité | Au plus 1 paiement réussi par commande, montant = total | paiements | Bloquante |
| DQ-15 | Complétude | Commande livrée (hors virement) ou prépayée ⇒ paiement réussi | paiements | Majeure |
| DQ-16 | Cohérence | Paiement échoué ⇒ aucune réussite, aucune livraison, ≤ 3 tentatives | paiements | Majeure |
| DQ-17 | Chronologie | Paiement à la livraison encaissé à la livraison, reversé ensuite | paiements, livraisons | Mineure |
| DQ-18 | Conformité | Retour accepté demandé ≤ 10 jours ouvrables après livraison | remboursements | Majeure |
| DQ-19 | Exactitude | Quantité et montant retournés ≤ ligne (prorata coupon) | remboursements | Bloquante |
| DQ-20 | Chronologie | Demande ≤ réception ≤ remboursement | remboursements | Majeure |
| DQ-21 | Exactitude | Σ remboursements (hors gestes) ≤ total payé ; refus = 0 DT | remboursements | Majeure |
| DQ-22 | Cohérence | Stock cumulé jamais négatif ; signe des mouvements cohérent avec leur type | mouvements_stock | Bloquante |
| DQ-23 | Réconciliation | Sorties « vente » = articles des commandes servies | mouvements, commandes | Majeure |
| DQ-24 | Réconciliation | Réceptions = quantités reçues ; reçu ≤ commandé ; réception ≥ commande | achats, mouvements | Majeure |
| DQ-25 | Validité | Stock mensuel ≥ 0, valeur = quantité × coût | stocks_mensuels | Majeure |
| DQ-26 | Validité | Clics ≤ impressions, dépense ≥ 0, jour dans la campagne, attribution réconciliée | marketing | Majeure |
| DQ-27 | Cohérence | Campagne attribuée active le jour de la commande | commandes | Mineure |
| DQ-28 | Conformité | Coupon valide (dates, minimum, 1re commande) | commandes, coupons | Majeure |
| DQ-29 | Validité | Note 1-5, avis après livraison, cohérent avec la commande | avis_clients | Majeure |
| DQ-30 | Format | Email valide ; téléphone `+216` + 8 chiffres | clients | Mineure |
| DQ-31 | Exactitude | Segment fidélité conforme à la règle de calcul | clients | Mineure |
| DQ-32 | Cohérence | `est_premiere_commande` = 1re commande chronologique | commandes | Mineure |
| DQ-33 | Validité | Listes fermées (canal, mode de paiement, statut) | commandes | Majeure |
| DQ-34 | Fraîcheur | Aucune date après la date d'arrêté | toutes | Bloquante |
| DQ-35 | Format | Dates au format ISO 8601 (`AAAA-MM-JJ[ HH:MM:SS]`) | couche brute | Mineure |
| DQ-36 | Unicité | Pas de ligne en double à l'ingestion (ré-extractions, webhooks renvoyés), SKU unique | couche brute | Bloquante |
| DQ-37 | Unicité | Pas de doublon métier de client (même nom + téléphone normalisé) | clients | Majeure |
| DQ-38 | Normalisation | Libellés et identifiants normalisés (casse, espaces, accents, HTML) | couche brute | Mineure |
| DQ-39 | Exactitude | Montants en dinars et non en millimes | paiements (API) | Bloquante |
| DQ-40 | Fraîcheur | Données arrivées en retard : intégrer selon la date métier, pas le fichier | commandes | Majeure |
| DQ-41 | Complétude / plausibilité | Champs obligatoires renseignés, valeurs plausibles (âge, prix) | couche brute | Majeure |
| DQ-42 | Format | Horodatages API en UTC à convertir en heure de Tunis (+1 h) | paiements (API) | Information |

## Seuils d'acceptation suggérés pour un pipeline
- Règles bloquantes : 0 % toléré, les lignes en échec partent en quarantaine.
- Règles majeures : < 0,5 % des lignes, sinon le chargement est stoppé et une alerte est levée.
- Règles mineures : correction automatique (normalisation), suivi de l'évolution du taux.

## Attendus pour le Data Engineer
Le pipeline de nettoyage appliqué à `donnees_brutes/` doit retrouver les anomalies listées dans `solutions/anomalies_injectees.csv` et produire des tables qui passent DQ-01 à DQ-34 à 0 violation (hors lignes mises en quarantaine). Pour les doublons clients (DQ-37), la décision de fusion doit être tracée (table de correspondance ancien → nouvel identifiant).
