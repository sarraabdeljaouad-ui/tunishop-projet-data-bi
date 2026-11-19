# Règles métier - TuniShop

Ces règles décrivent le fonctionnement simulé de l'entreprise. Elles sont **toutes respectées dans la couche de référence** (vérifiées par les contrôles DQ-01 à DQ-34) et servent de spécification pour nettoyer la couche brute.

## 1. Conventions générales
- **Devise** : dinar tunisien (DT, code ISO TND), 3 décimales (millimes). Les prix de vente sont exprimés **TTC** ; HT = TTC / (1 + TVA).
- **TVA** : taux de 19 %, 13 % et 7 % selon la sous-catégorie. L'affectation par sous-catégorie est pédagogique (simplifiée) et ne constitue pas une référence fiscale.
- **Prix psychologiques** : les prix catalogue se terminent par ,900 DT.
- **Horodatage** : heure locale de Tunis (UTC+1, pas d'heure d'été), sauf l'API de paiement brute (UTC).
- **Date d'arrêté** : 31/12/2025 23:59:59. Tout événement postérieur n'existe pas encore : les statuts reflètent la situation à cette date (commandes « expediee » ou « en_preparation », remboursements « en_cours »).
- **Semaine ouvrée** : expéditions du lundi au samedi hors jours fériés ; pas de livraison le dimanche ni les jours fériés.

## 2. Catalogue et prix
- Les prix et coûts sont révisés au **1er janvier** de chaque année (historique SCD2 dans `produits_prix_historique`). Une ligne de commande porte le prix et le coût valides au jour de la commande.
- Un produit ne peut être vendu qu'entre sa `date_lancement` et sa `date_arret`.
- **Promotions produit** : pendant les soldes (hiver : 1er février - 7 mars ; été : 1er août - 7 septembre) certains articles de mode, chaussures et décoration sont remisés de 20 à 50 % ; pendant la semaine du Black Friday certains articles d'électronique et d'électroménager sont remisés de 10 à 30 %. `prix_unitaire_ttc = prix_catalogue_ttc - remise_promo_unitaire_ttc`.

## 3. Commandes
- `montant_ligne_ttc = quantite × prix_unitaire_ttc` ; `sous_total_ttc = Σ montant_ligne_ttc`.
- **Coupons** : un seul code par commande, valide aux dates du code, sous-total ≥ montant minimum, remise plafonnée pour les codes en pourcentage. `BIENVENUE10` (10 %, plafond 30 DT, minimum 50 DT) est réservé à la **première commande** du client.
- **Frais de livraison** : 7,000 DT TTC si (sous-total - remise) < 150 DT, gratuits au-delà.
- `montant_total_ttc = sous_total_ttc - remise_coupon_ttc + frais_livraison_ttc`.
- **Attribution marketing** : une commande peut être attribuée (last-click interne) à une campagne active le jour de la commande.
- **Cycle de vie** : paiement en ligne (si prépayé) → réservation du stock → éventuelle annulation client avant expédition → expédition → livraison ou échec → éventuels retours.

## 4. Paiements
- Modes : paiement à la livraison (majoritaire, en baisse), carte bancaire, portefeuille mobile, carte prépayée, virement (clients professionnels).
- **Paiement en ligne** : jusqu'à 3 tentatives ; si aucune ne réussit, la commande passe en `paiement_echoue` (pas de stock réservé, pas de livraison).
- **Paiement à la livraison** : une ligne `encaisse` est créée à l'heure exacte de livraison ; le transporteur reverse les fonds 3 à 10 jours plus tard (`date_reversement`). Un colis refusé ne génère aucun paiement.
- **Virement** (professionnels) : payé 5 à 40 jours après livraison ; un virement non encore reçu à la date d'arrêté n'apparaît pas.
- Un seul paiement réussi par commande, d'un montant égal au total de la commande.

## 5. Stock et entrepôts
- Trois entrepôts : Grand Tunis (Ben Arous), Sahel (Sousse), Sud (Sfax). Chaque gouvernorat est rattaché à un entrepôt.
- Une commande est servie **en totalité depuis un seul entrepôt** : l'entrepôt de rattachement s'il a tout le stock, sinon un autre entrepôt (délai plus long). Si aucun entrepôt ne peut servir la commande complète, elle est **annulée pour rupture de stock** (et remboursée si prépayée).
- Le stock est décrémenté à la validation de la commande et réintégré en cas d'annulation, d'échec de livraison (retour expéditeur) ou de retour client revendable. Un retour non revendable est réintégré puis immédiatement mis au rebut.
- **Réapprovisionnement** automatique chaque jour ouvré : point de commande = demande moyenne des 28 derniers jours × (délai fournisseur + 6 jours) ; quantité = couverture de délai + 36 jours, arrondie par 5. Les livraisons fournisseurs peuvent être en retard ou partielles (pas de reliquat).
- Inventaire tournant en fin de mois : ajustements de quelques unités (démarque, erreurs de comptage).
- Le grand livre `mouvements_stock` est la source de vérité : le stock n'y est jamais négatif ; `stocks_mensuels` en est l'agrégation à chaque fin de mois.

## 6. Livraison
- Expédition le jour même si la commande est passée avant 14 h un jour d'expédition, sinon le jour d'expédition suivant ; 1 jour de plus possible en période de pointe (Black Friday, pré-Aïd).
- Date promise = date d'expédition + délai SLA selon l'entrepôt et la région (dimanches exclus).
- Le délai réel dépend de la distance, du transporteur, des pics d'activité et du nombre de tentatives (1 à 3).
- Échec de livraison : principalement des refus de colis en paiement à la livraison (plus fréquents pour une 1re commande, un panier > 400 DT ou une livraison en retard). Le colis revient à l'entrepôt 2 à 6 jours après.

## 7. Retours et remboursements
- Droit de rétractation : demande dans les **10 jours ouvrables** suivant la livraison (loi tunisienne n° 2000-83 relative aux échanges et au commerce électronique). Les demandes hors délai sont refusées.
- Montant remboursé d'un retour = prix unitaire payé × quantité retournée × (1 - remise coupon / sous-total). Les frais de livraison ne sont pas remboursés.
- Un retour peut être refusé après contrôle (article non revendable dans un cas sur cinq environ).
- Moyen de remboursement : identique au paiement si prépayé ; virement ou bon d'achat si paiement à la livraison.
- **Annulation** d'une commande prépayée (rupture, annulation client, échec de livraison) : remboursement intégral.
- **Geste commercial** : bon d'achat de 10 ou 20 DT pour certains retards de 3 jours ou plus.

## 8. Clients et CRM
- Un client s'inscrit avant (ou au moment de) sa première commande.
- Segment fidélité (calculé à la date d'arrêté sur le CA net 2025 = commandes livrées - remboursements) : **or** ≥ 1 500 DT, **argent** ≥ 500 DT, **bronze** > 0, **aucun** sinon.
- Un client peut cesser d'acheter (attrition). Les mauvaises expériences (retard ≥ 3 jours, échec de livraison, retour refusé) augmentent la probabilité d'attrition.

## 9. Marketing
- Les dépenses quotidiennes ne dépassent pas le budget de la campagne ; clics ≤ impressions.
- `commandes_attribuees` et `ca_attribue_ttc` sont calculés à partir des commandes (hors paiement échoué) attribuées à la campagne ce jour-là.
