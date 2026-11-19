# Générateur TuniShop

- `gen_part1.py` : référentiels (géographie, calendrier, catégories, produits, fournisseurs, campagnes, clients) et paramètres.
- `gen_part2.py` : planification des commandes puis simulation jour par jour (paiements, stock, expéditions, livraisons, retours, réapprovisionnement).
- `gen_part3.py` : construction des tables finales (clients, avis, marketing, stocks mensuels).
- `gen_part4_checks.py` : 34 contrôles de règles métier / qualité.
- `gen_part5_export.py` : export de la couche de référence, injection des anomalies de la couche brute, dictionnaire, DDL, rapport.
- `meta.py` : descriptions des tables et colonnes.

Lancer : `python generer_tunishop.py`. Graine fixe (`SEED = 2026` dans gen_part1.py) : modifiez-la pour obtenir un autre jeu cohérent.
Paramètres faciles à ajuster dans gen_part1.py : `N_CUST` (nombre de clients), `RATE_M` (fréquence d'achat par persona), `START`/`END` (période), `CATS` (catalogue).
Les documents rédigés (README, règles, parcours, SQL de contrôle et KPI) ne sont pas régénérés.
