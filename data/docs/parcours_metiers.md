# Parcours par métier - projet TuniShop de bout en bout

Le même jeu de données sert aux quatre métiers, dans l'ordre d'une vraie chaîne data. Chaque métier peut aussi démarrer seul : le Data Engineer part de `donnees_brutes/`, les trois autres peuvent partir de `donnees_reference/` (ou de la base SQLite) s'ils ne veulent pas attendre le pipeline.

## Contexte métier
TuniShop est un e-commerçant tunisien **fictif** généraliste (électronique, électroménager, mode, beauté, maison, épicerie fine, enfants, sport, fournitures scolaires). Il vend via son site, son application mobile et les réseaux sociaux, livre les 24 gouvernorats depuis trois entrepôts avec quatre transporteurs, et s'approvisionne auprès de fournisseurs locaux et étrangers. La direction veut piloter la croissance, la rentabilité, la qualité de service et le stock.

---

## 1. Data Engineer - de la donnée brute à une donnée fiable

**Point de départ** : `donnees_brutes/` (CSV mensuels, JSON Lines d'API, export marketing au format français, CRM avec doublons).

Étapes proposées :
1. **Ingestion (bronze)** : charger tous les fichiers tels quels dans un entrepôt (PostgreSQL, DuckDB, BigQuery...) en ajoutant `fichier_source` et `date_chargement`. Lire les 36 fichiers mensuels de commandes de manière incrémentale (un fichier = un lot).
2. **Standardisation (silver)** : typer les colonnes ; convertir les dates hétérogènes en ISO ; convertir `created_at` de l'API (UTC) en heure de Tunis ; aplatir le JSON (`amount.value`) ; traduire les codes anglais de l'API ; lire le marketing avec `;` et décimale `,` ; normaliser casse, espaces, accents, HTML ; normaliser les téléphones en `+216XXXXXXXX` ; corriger les montants en millimes.
3. **Dédoublonnage** : doublons techniques (lignes identiques, webhooks renvoyés) et doublons métier de clients (même nom + téléphone normalisé) avec table de correspondance.
4. **Contrôles qualité** : implémenter les règles de `docs/regles_qualite.md` (SQL fourni dans `sql/controles_qualite.sql`, ou Great Expectations / dbt tests / Soda). Mettre en quarantaine les lignes bloquantes, journaliser les résultats dans une table `dq_resultats`.
5. **Données en retard** : 60 commandes arrivent dans le fichier du mois suivant ; le traitement doit être idempotent (upsert sur `commande_id`).
6. **Modèle gold** : publier un schéma en étoile prêt pour la BI (voir partie 2).
7. **Orchestration** : DAG Airflow / Dagster / Prefect avec dépendances, reprise sur erreur et alertes.

**Livrables** : pipeline versionné, rapport qualité avant/après, schéma gold documenté.
**Auto-correction** : comparer vos tables nettoyées à `donnees_reference/` et vos détections à `solutions/anomalies_injectees.csv` (9 473 anomalies tracées ligne à ligne).

---

## 2. BI Engineer - modèle décisionnel et tableaux de bord

**Point de départ** : sortie gold du Data Engineer ou `donnees_reference/`.

Modèle en étoile suggéré :
- **Faits** : `fait_ventes` (grain ligne de commande), `fait_commandes`, `fait_livraisons`, `fait_retours`, `fait_paiements`, `fait_stock_mensuel` (snapshot), `fait_achats`, `fait_marketing_quotidien`.
- **Dimensions** : `dim_date` (fournie), `dim_client` (SCD1, segment), `dim_produit` + `dim_categorie`, `dim_prix` (SCD2 fourni), `dim_geographie`, `dim_entrepot`, `dim_transporteur`, `dim_fournisseur`, `dim_campagne`, `dim_canal`, `dim_mode_paiement`.

KPI à définir précisément (formule + règle de gestion) :
- CA brut TTC, CA net (après remboursements), CA HT, marge brute (HT - coût), panier moyen, articles par commande.
- Taux d'annulation, taux de rupture, taux d'échec de paiement, taux de refus de colis.
- Délai moyen de livraison, taux de livraison à l'heure (OTD), retard moyen par transporteur.
- Taux de retour (en lignes et en valeur), montant remboursé, délai de remboursement.
- Valeur du stock, couverture en jours, rotation, taux de rupture fournisseur, retard fournisseur moyen.
- Dépense marketing, CPC, CPM, taux de conversion, coût d'acquisition (CAC), ROAS.
- Nouveaux clients, clients actifs, taux de réachat, répartition par segment.

Tableaux de bord suggérés : Direction (synthèse), Ventes & produits, Logistique & transporteurs, Stock & achats, Marketing & acquisition, Service après-vente.
Exemples de requêtes : `sql/exemples_kpi.sql`.

---

## 3. Data Analyst - questions métier

Questions proposées (chacune a une réponse dans les données) :
1. Quelle est la croissance annuelle du CA et du nombre de commandes ? Le panier moyen évolue-t-il ?
2. Quel est l'effet du Ramadan, de l'Aïd, de la rentrée, des soldes et du Black Friday, par catégorie ?
3. Comment évoluent la part de l'application mobile et celle du paiement à la livraison ?
4. Quelles catégories ont le plus fort taux de retour, et pour quels motifs ?
5. Un transporteur se dégrade-t-il ? Depuis quand, dans quelles régions, avec quel impact sur les notes et les refus ?
6. Quels facteurs expliquent les refus de colis en paiement à la livraison ?
7. Quel canal marketing a le meilleur ROAS ? Le moins cher au clic est-il le plus rentable ?
8. Quelles régions sont sous-servies (délai, coût de transport, part de commandes servies depuis un autre entrepôt) ?
9. Quels fournisseurs causent des retards et des ruptures ? Que s'est-il passé à l'été 2024 ?
10. Analyse de cohortes mensuelles : rétention à 3, 6 et 12 mois selon le canal d'acquisition.
11. Analyse RFM : combien de clients à forte valeur sont « endormis » ?
12. Les promotions produit et les coupons génèrent-ils du volume incrémental ou dégradent-ils surtout la marge ?

**Livrable** : un rapport d'analyse avec recommandations chiffrées.

---

## 4. Data Scientist - cas d'usage de modélisation

| Cas d'usage | Cible | Grain | Points d'attention |
|---|---|---|---|
| Prévision de la demande | quantités vendues par produit (ou sous-catégorie) x entrepôt x jour/semaine | série temporelle | saisonnalité hebdomadaire et annuelle, fêtes lunaires qui se décalent de ~11 jours par an, ruptures qui censurent la demande |
| Attrition (churn) | pas de commande dans les 180 jours suivant une date de référence | client | définir la date de référence, éviter la fuite d'information (features calculées avant la date) |
| Valeur vie client (CLV) | CA net sur 12 mois futurs | client | modèles BG/NBD + Gamma-Gamma ou régression |
| Segmentation | personas | client | vérité terrain disponible : `solutions/verite_terrain_clients.csv` |
| Refus de colis COD | `statut_commande = livraison_echouee` | commande | variables connues au moment de l'expédition uniquement |
| Retard de livraison | retard > 0 jour | livraison | transporteur, distance, période, jour d'expédition |
| Probabilité de retour | ligne retournée | ligne de commande | catégorie, prix, promo, retard, client |
| Analyse de sentiment | note ou polarité | avis | textes en français et en derja latinisée |
| Optimisation du stock | point de commande / stock de sécurité | produit x entrepôt | simuler une politique et la comparer à l'historique |
| Attribution marketing / mix média | commandes incrémentales | campagne x jour | comparer last-click et modèle de mix média |

**Découpage temporel recommandé** : entraînement 2023-01 → 2024-12, validation 2025-01 → 2025-06, test 2025-07 → 2025-12.
**Vérité terrain** (pour évaluer, jamais comme feature) : `solutions/verite_terrain_clients.csv` contient le persona simulé, la date de fin d'activité simulée et le nombre de mauvaises expériences de chaque client.
