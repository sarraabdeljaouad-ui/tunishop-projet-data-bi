# TuniShop — Modèle décisionnel

Projet TuniShop · livrable 06 · version du 15/10/2026

Ce livrable fixe le modèle en étoile de l'entrepôt `TuniShop_DWH` (SQL Server), ses mesures, ses KPI et son chargement par SSIS. L'entrepôt est alimenté par le staging PostgreSQL décrit dans le livrable 04, après les règles de transformation du livrable 05.

**Sources.** `docs/parcours_metiers.md` (faits, dimensions et KPI proposés), `docs/regles_metier.md`, `sql/exemples_kpi.sql`. Les volumes et les cardinalités ont été recomptés sur `donnees_reference/`.

## 1. Modèle en étoile

L'entrepôt suit une modélisation en étoile (Kimball) : 9 tables de faits partagent 14 dimensions conformes, ce qui permet de croiser ventes, logistique, stock et marketing sur les mêmes axes. Il reprend la proposition de `parcours_metiers.md` (8 faits) et y ajoute `fait_avis`, nécessaire pour mesurer l'effet des retards sur les notes.

### 1.1 Matrice en bus

| Fait | Date | Client | Produit | Catégorie | Géographie | Entrepôt | Transporteur | Fournisseur | Campagne | Coupon | Canal vente | Mode paiement | Statut commande | Type rembours. |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| fait_ventes | ✓ | ✓ | ✓ | via produit | ✓ | ✓ |  |  | ✓ | ✓ | ✓ | ✓ | ✓ |  |
| fait_commandes | ✓ (×2) | ✓ |  |  | ✓ | ✓ |  |  | ✓ | ✓ | ✓ | ✓ | ✓ |  |
| fait_paiements | ✓ (×2) | ✓ |  |  |  |  |  |  |  |  |  | ✓ |  |  |
| fait_livraisons | ✓ (×3) | ✓ |  |  | ✓ | ✓ | ✓ |  |  |  |  | ✓ |  |  |
| fait_retours | ✓ (×2) | ✓ | ✓ | via produit |  |  |  |  |  |  |  | ✓ |  | ✓ |
| fait_stock_mensuel | ✓ |  | ✓ | via produit |  | ✓ |  |  |  |  |  |  |  |  |
| fait_achats | ✓ (×3) |  | ✓ | via produit |  | ✓ |  | ✓ |  |  |  |  |  |  |
| fait_marketing_quotidien | ✓ |  |  | ✓ |  |  |  |  | ✓ |  |  |  |  |  |
| fait_avis | ✓ | ✓ | ✓ | via produit |  |  |  |  |  |  |  |  |  |  |

« ×2 », « ×3 » = dimension date jouée plusieurs fois (rôles), par exemple date d'expédition, date prévue et date de livraison pour `fait_livraisons`.

### 1.2 Tables de faits

| Fait | Type | Grain | Lignes (réf.) | Mesures | Dimensions dégénérées |
| --- | --- | --- | --- | --- | --- |
| fait_ventes | Transaction | 1 ligne de commande | 115 903 | quantite, montant_ligne_ttc, montant_ligne_ht, montant_tva, remise_promo_ttc, cout_achat_ht, marge_ht | commande_id, ligne_id |
| fait_commandes | Transaction | 1 commande | 66 268 | nb_lignes, nb_articles, sous_total_ttc, remise_coupon_ttc, frais_livraison_ttc, montant_total_ttc, est_premiere_commande | commande_id |
| fait_paiements | Transaction | 1 tentative ou 1 encaissement | 64 493 | montant_ttc, num_tentative, est_reussi | commande_id, statut_paiement, code_erreur, prestataire |
| fait_livraisons | Cumulatif (jalons) | 1 colis | 61 793 | delai_livraison_j, retard_j, est_a_l_heure, nb_tentatives, poids_kg, cout_transport_ht | commande_id, statut_livraison |
| fait_retours | Transaction | 1 remboursement | 8 815 | quantite, montant_demande_ttc, montant_rembourse_ttc, delai_remboursement_j | commande_id, ligne_id |
| fait_stock_mensuel | Photo périodique | 1 produit × 1 entrepôt × 1 fin de mois | 56 562 | stock_fin_mois, quantite_en_commande, valeur_stock_ht | — |
| fait_achats | Cumulatif (jalons) | 1 ligne de bon fournisseur | 11 793 | quantite_commandee, quantite_recue, montant_ligne_ht, retard_reception_j | commande_fournisseur_id |
| fait_marketing_quotidien | Transaction | 1 campagne × 1 jour | 3 427 | depense_ht, impressions, clics, commandes_attribuees, nouveaux_clients_attribues, ca_attribue_ttc | — |
| fait_avis | Transaction | 1 avis | 9 314 | note, achat_verifie | commande_id, ligne_id |

Les mesures additives (montants, quantités) se somment ; `stock_fin_mois` et `valeur_stock_ht` sont semi-additives (somme par entrepôt ou produit, jamais dans le temps : on prend la dernière fin de mois).

### 1.3 Dimensions

| Dimension | Lignes (réf.) | Historisation | Source staging | Attributs principaux |
| --- | --- | --- | --- | --- |
| dim_date | 1 096 | Fixe | dim_calendrier | annee, trimestre, mois, semaine_iso, est_weekend, est_jour_ferie, est_ramadan, periode_commerciale |
| dim_client | 16 000 | SCD1 | clients + correspondance_clients | type_client, genre, tranche_age, gouvernorat, ville, canal_inscription, campagne_acquisition, date_inscription, segment_fidelite |
| dim_produit | 1 601 versions de 596 produits | SCD2 (prix, coût) | produits + produits_prix_historique | sku, nom, marque, categorie_sk, fournisseur_sk, prix_catalogue_ttc, cout_achat_unitaire_ht, date_debut, date_fin, est_version_courante |
| dim_categorie | 19 | SCD1 | categories | categorie, sous_categorie, taux_tva, taux_retour_cible, marge_brute_cible |
| dim_fournisseur | 40 | SCD1 | fournisseurs | nom, pays, delai_appro_moyen_j, fiabilite_livraison |
| dim_geographie | 24 | SCD1 | ref_gouvernorats | gouvernorat, region, zone_livraison, entrepot_rattachement |
| dim_entrepot | 3 | SCD1 | entrepots | nom, ville, gouvernorat, surface_m2 |
| dim_transporteur | 4 | SCD1 | transporteurs | nom, couverture, cout_base_ht |
| dim_campagne | 152 | SCD1 | campagnes_marketing | nom, canal_marketing, objectif, theme, categorie_ciblee, budget_ht, date_debut, date_fin |
| dim_coupon | 68 | SCD1 | coupons | type_remise, valeur, montant_min_ttc, plafond_remise_ttc, reserve_premiere_commande |
| dim_canal_vente | 5 + inconnu | Fixe | commandes (canal × appareil) | canal, appareil |
| dim_mode_paiement | 5 | Fixe | liste fermée | mode_paiement, est_prepaye |
| dim_statut_commande | 9 | Fixe | commandes (statut × motif d'annulation) | statut_commande, motif_annulation, est_commande_valorisee |
| dim_type_remboursement | 178 combinaisons observées | Fixe | remboursements | type_remboursement, motif, statut, mode_remboursement, etat_article |

Chaque dimension contient un membre `-1 « Inconnu »` : une clé absente (canal `inconnu`, campagne vide) pointe vers lui au lieu de faire disparaître la ligne de fait. `dim_canal_vente` compte 5 combinaisons dans la référence (application_mobile × mobile, reseaux_sociaux × mobile, site_web × 3 appareils).

**SCD2 de `dim_produit`.** Chaque ligne de `produits_prix_historique` devient une version, valable de `date_debut` à `date_fin`. Une vente pointe vers la version valable à sa date de commande : la marge reste juste même si le coût change au 1er janvier (`regles_metier.md` §2).

### 1.4 KPI et formules

| KPI | Formule | Fait |
| --- | --- | --- |
| CA brut TTC | Σ montant_total_ttc des commandes valorisées (livree, retournee, partiellement_retournee) | fait_commandes |
| CA net TTC | CA brut − Σ montant_rembourse_ttc des remboursements au statut `rembourse` | fait_commandes, fait_retours |
| CA HT, marge brute | Σ montant_ligne_ht ; Σ (montant_ligne_ht − quantite × cout_achat_unitaire_ht) | fait_ventes |
| Panier moyen | CA brut TTC / nb commandes valorisées | fait_commandes |
| Taux d'annulation | Commandes annulées / commandes passées (hors paiement échoué) | fait_commandes |
| Taux d'échec de paiement | Tentatives `echoue` / tentatives en ligne | fait_paiements |
| OTD (livraison à l'heure) | Colis livrés avec date réelle ≤ date prévue / colis livrés | fait_livraisons |
| Délai moyen de livraison | Moyenne (date réelle − date d'expédition), en jours | fait_livraisons |
| Taux de refus de colis | Colis `echec_retour_expediteur` / colis expédiés | fait_livraisons |
| Taux de retour | Lignes retournées (type retour, hors refusés) / lignes valorisées | fait_ventes, fait_retours |
| Couverture de stock | Stock fin de mois / ventes moyennes journalières du trimestre | fait_stock_mensuel, fait_ventes |
| Taux de service fournisseur | Σ quantite_recue / Σ quantite_commandee | fait_achats |
| ROAS | Σ ca_attribue_ttc / Σ depense_ht | fait_marketing_quotidien |
| CPC, CAC | Σ depense_ht / Σ clics ; Σ depense_ht / Σ nouveaux_clients_attribues | fait_marketing_quotidien |

Source des formules : `sql/exemples_kpi.sql` (CA, marge, OTD, retours, ROAS, CPC, CAC, couverture) et `docs/parcours_metiers.md` (liste des KPI). Ces formules sont à implémenter une seule fois, en mesures DAX dans Power BI et en champs calculés dans Tableau, avec les mêmes noms.

## 2. Chargement de l'entrepôt (SSIS)

SSIS charge l'entrepôt depuis le staging en deux temps : toutes les dimensions, puis toutes les tables de faits. Chaque exécution est rejouable sans créer de doublon.

| Package | Contenu | Technique |
| --- | --- | --- |
| `00_Maitre.dtsx` | Ouvre un lot dans `etl.lots_dwh`, lance les packages dans l'ordre, ferme le lot | Execute Package Task, gestion d'erreur au niveau du maître |
| `10_Dimensions_SCD1.dtsx` | 12 dimensions SCD1 ou fixes | Source OLE DB filtrée par `etl.watermark` → table de transit → `MERGE` (insert si nouvelle clé, update si `hash_ligne` différent) |
| `11_Dim_Produit_SCD2.dtsx` | Versions de prix et de coût | `MERGE` : ferme l'ancienne version (`date_fin`, `est_version_courante = 0`) et insère la nouvelle |
| `12_Dim_Date.dtsx` | Chargement unique de `dim_calendrier` | Clé `AAAAMMJJ` |
| `20_Faits_*.dtsx` | Un package par fait (9) | Lookups vers les dimensions (cache complet), clé `-1` si non trouvée, puis upsert sur la clé métier (ligne_id, commande_id…) |
| `21_Fait_Stock_Mensuel.dtsx` | Photo de fin de mois | Suppression puis réinsertion du mois concerné |
| `90_Controles.dtsx` | Réconciliation staging ↔ entrepôt | Requêtes de comparaison, résultat dans `etl.lots_dwh` |

Le `MERGE` en T-SQL est préféré au composant « Slowly Changing Dimension » de SSIS, trop lent au-delà de quelques milliers de lignes. Le lookup produit SCD2 se fait sur `produit_id` et `date_commande` entre `date_debut` et `date_fin`.

**Dimension arrivée en retard.** Une vente dont le client n'est pas encore en dimension reçoit la clé `-1`. Au lot suivant, un `UPDATE` repasse sur les faits en `-1` pour leur donner la bonne clé.

Les contrôles de réconciliation staging ↔ entrepôt et les critères d'acceptation sont dans le livrable 05 (section 2).

## 3. Points ouverts

| Sujet | Option retenue par défaut | Alternative | Impact si on change |
| --- | --- | --- | --- |
| `dim_client` | SCD1 (le segment est calculé à la date d'arrêté) | SCD2 sur segment et ville | Utile seulement si le segment est recalculé à chaque période |
| Mouvements de stock | Gardés en staging, pas de fait dédié | `fait_mouvements_stock` (140 184 lignes) | Analyse fine des entrées et sorties, au prix d'un fait de plus |
