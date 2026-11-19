# TuniShop — Règles de transformation

Projet TuniShop · livrable 05 · version du 15/10/2026

Ce livrable fixe comment chaque donnée brute devient une donnée propre dans le staging PostgreSQL, et comment le pipeline est contrôlé. Les schémas de stockage cités (`src`, `staging`, `audit`) sont décrits dans le livrable 04 ; les règles s'appuient sur l'audit du livrable 02.

**Sources.** `docs/regles_metier.md`, `docs/regles_qualite.md`, `docs/dictionnaire_donnees.md`, `sql/exemples_kpi.sql`. Les règles d'imputation (canal, statut de livraison) ont été vérifiées sur `donnees_reference/`.

## 1. Règles de transformation

Le passage source → staging applique les règles dans un ordre fixe, pour qu'un contrôle ne tourne jamais sur une donnée pas encore normalisée. Chaque correction est écrite dans `audit.corrections`, chaque rejet dans `audit.quarantaine`.

1. Lecture et typage : séparateur, décimale, encodage, puis conversion de chaque colonne vers le type du DDL.
2. Normalisation : formats, casse, espaces, accents, codes.
3. Dédoublonnage : doublons techniques, puis doublons métier.
4. Correction des valeurs calculables : montants recalculés, signes, unités.
5. Contrôles bloquants et majeurs : quarantaine ou arrêt selon les seuils de `regles_qualite.md`.
6. Upsert dans le staging sur la clé métier, niveau par niveau.

### 1.1 Règles transverses

| Règle | Transformation | DQ |
| --- | --- | --- |
| Dates | Accepter `AAAA-MM-JJ`, `JJ/MM/AAAA`, `JJ/MM/AAAA HH:MM` ; toujours jour avant mois ; secondes absentes = `:00` et tracées | DQ-35 |
| Fuseau | Tout en heure de Tunis ; seul l'API est en UTC (+1 h, pas d'heure d'été) | DQ-42 |
| Décimales | Fichiers marketing : `;` séparateur, `,` décimale ; arrondi à 3 décimales partout | — |
| Textes | `trim`, espaces multiples réduits, balises HTML retirées ; libellés de liste fermée en minuscules sans accents | DQ-38 |
| Identifiants | Majuscules et `trim` avant toute jointure (`tr01` → `TR01`) | DQ-38 |
| Doublons techniques | Ligne identique → garder la première ; même clé, contenu différent → garder la plus récente par `fichier_source` | DQ-36 |
| Date d'arrêté | Toute date > 31/12/2025 23:59:59 → quarantaine | DQ-34 |
| Clés orphelines | Quarantaine avec statut « à rejouer » : rejouée au lot suivant, au cas où le parent arrive en retard | DQ-02 |

### 1.2 Règles par table

| Table | Colonne | Transformation | DQ |
| --- | --- | --- | --- |
| clients | telephone | Garder les chiffres, retirer `00216` ou `216` en tête, garder 8 chiffres → `+216XXXXXXXX` | DQ-30 |
| clients | email | `trim` + minuscules ; si format invalide (`at`, `@@`, `@` manquant) → NULL et trace, pas de correction devinée | DQ-30, DQ-38 |
| clients | ville | Clé sans accents ni casse → graphie de référence (table de correspondance des villes) | DQ-38 |
| clients | date_naissance | Hors 16-100 ans au 31/12/2025 → NULL et trace | DQ-41 |
| clients | genre | Vide → NULL (« non renseigné ») ; jamais déduit du prénom | DQ-41 |
| clients | client_id | Même prénom + nom + 8 derniers chiffres du téléphone → fusion vers le compte d'origine, ligne dans `correspondance_clients` ; les comptes `CLI9xxxxx` sont les doublons | DQ-37 |
| commandes | statut_commande | Minuscules sans accents, puis contrôle de la liste fermée (8 valeurs) | DQ-33, DQ-38 |
| commandes | canal | Vide + appareil `ordinateur` ou `tablette` → `site_web` (seul canal possible pour ces appareils dans la référence) ; vide + `mobile` → `inconnu` | DQ-41 |
| commandes | montant_total_ttc | Recalculé = `sous_total_ttc − remise_coupon_ttc + frais_livraison_ttc` ; valeur source gardée dans `audit.corrections` | DQ-03 |
| commandes | (lot) | Mois de `date_commande` ≠ mois du fichier → donnée en retard : upsert normal, compteur dans `audit.lots` | DQ-40 |
| lignes_commande | montant_ligne_ttc | Recalculé = `quantite × prix_unitaire_ttc` ; HT = TTC / (1 + TVA) ; TVA = TTC − HT | DQ-05 |
| lignes_commande | quantite | ≤ 0 → quarantaine | DQ-06 |
| lignes_commande | prix, coût | Contrôlés contre `produits_prix_historique` valide à la date de commande | DQ-10 |
| paiements | structure | Aplatir `amount.value` ; renommer `payment_id`, `order_ref`, `attempt`, `error_code`, `provider`, `transaction_ref`, `settlement_date` | — |
| paiements | method, status | COD → paiement_a_la_livraison, CARD → carte_bancaire, WALLET → portefeuille_mobile, PREPAID_CARD → carte_prepayee, BANK_TRANSFER → virement ; SUCCESS → reussi, FAILED → echoue, COLLECTED → encaisse | — |
| paiements | montant_ttc | Si montant / total de la commande ≈ 1 000 → ÷ 1 000 | DQ-39 |
| paiements | payment_id | Webhook renvoyé → garder la première réception | DQ-36 |
| livraisons | statut_livraison | Vide + `date_livraison_reelle` renseignée → `livree` ; vide sans date → quarantaine | DQ-41 |
| livraisons | dates | Livraison réelle < expédition → quarantaine | DQ-12 |
| mouvements_stock | quantite | Type `vente` avec quantité > 0 → signe inversé ; `ajustement_inventaire` accepte les deux signes | DQ-22 |
| stocks_mensuels | stock_fin_mois | Recalculé depuis les mouvements nettoyés ; valeur = stock × coût unitaire | DQ-25 |
| produits | marque, prix | Marque normalisée ; prix ≤ 0 → prix actuel de l'historique | DQ-38, DQ-41 |
| produits | sku | SKU en double → quarantaine et arbitrage métier | DQ-36 |
| remboursements | montant, dates | Montant > ligne → quarantaine ; remboursement avant demande ou réception → quarantaine | DQ-19, DQ-20 |
| achats | quantite_recue, date_reception | Reçu > commandé ou réception < commande → quarantaine | DQ-24 |
| marketing_depenses | clics, depense_ht | Clics > impressions ou dépense < 0 → quarantaine | DQ-26 |
| avis_clients | note, commentaire | Note hors 1-5 → quarantaine ; commentaire nettoyé (HTML, espaces) | DQ-29, DQ-38 |

### 1.3 Colonnes dérivées calculées en staging

| Colonne | Table | Calcul | Source |
| --- | --- | --- | --- |
| `delai_livraison_j` | livraisons | `date_livraison_reelle::date − date_expedition::date` | `exemples_kpi.sql` |
| `est_a_l_heure` | livraisons | `date_livraison_reelle::date ≤ date_livraison_prevue` | `exemples_kpi.sql` |
| `marge_ligne_ht` | lignes_commande | `montant_ligne_ht − quantite × cout_achat_unitaire_ht` | `exemples_kpi.sql` |
| `est_commande_valorisee` | commandes | statut ∈ {livree, retournee, partiellement_retournee} | `exemples_kpi.sql` (périmètre du CA) |
| `segment_fidelite_recalcule` | clients | CA net 2025 : or ≥ 1 500 DT, argent ≥ 500 DT, bronze > 0, sinon aucun ; comparé à la valeur source | `regles_metier.md` §8, DQ-31 |

## 2. Contrôles et reprise

### 2.1 Contrôles de bout en bout

| Étape | Contrôle | Seuil | Décision si échec |
| --- | --- | --- | --- |
| Source → staging | Nb lus = nb chargés + nb en quarantaine, par fichier | Égalité stricte | Arrêt du lot |
| Staging | Règles bloquantes DQ-01, 02, 06, 12, 14, 19, 22, 34, 36, 39 | 0 % | Lignes en quarantaine |
| Staging | Règles majeures | < 0,5 % des lignes | Au-delà : arrêt et alerte |
| Staging | Règles mineures | Correction automatique | Suivi du taux dans `audit.dq_resultats` |
| Staging → entrepôt | Nb lignes et Σ montants par fait = staging | Égalité stricte | Arrêt du lot |
| Entrepôt | Faits en clé `-1` | < 0,1 % | Alerte, résolution au lot suivant |

Les seuils viennent de `regles_qualite.md` (« Seuils d'acceptation suggérés »), sauf les deux derniers, proposés ici.

### 2.2 Orchestration et reprise

L'ordre complet est : chargement de la base source → ETL Python vers le staging, niveau par niveau (livrable 01) → packages SSIS → actualisation des jeux de données Power BI et Tableau. Chaque étape ne démarre que si la précédente a fini en succès.

- **Idempotence** : un fichier déjà présent dans `src.registre_fichiers` avec le même hash n'est pas relu ; un lot rejoué refait les mêmes upserts.
- **Reprise** : un lot en échec est rejoué depuis l'étape en échec, pas depuis le début ; la quarantaine marquée « à rejouer » est relue au lot suivant.
- **Historique** : `audit.lots`, `audit.dq_resultats` et `etl.lots_dwh` gardent toutes les exécutions, pour un tableau de bord de suivi qualité.

### 2.3 Critères d'acceptation

- [ ] Le staging passe DQ-01 à DQ-34 à 0 violation, hors lignes en quarantaine.
- [ ] `audit.corrections` + `audit.quarantaine` retrouvent les 9 473 anomalies de `solutions/anomalies_injectees.csv`.
- [ ] Les tables de staging égalent `donnees_reference/` en nombre de lignes et en sommes de contrôle (568 525 lignes au total), à l'écart près des lignes en quarantaine, chacune expliquée.
- [ ] Le CA brut TTC calculé dans Power BI, dans Tableau et par `sql/exemples_kpi.sql` est identique, mois par mois.
- [ ] Un deuxième passage complet du pipeline ne change aucune ligne.

## 3. Point ouvert

| Sujet | Option retenue par défaut | Alternative | Impact si on change |
| --- | --- | --- | --- |
| Clés orphelines | Quarantaine puis rejeu au lot suivant | Rattacher au membre `-1` dès le staging | Moins de rejets, mais des ventes sans client réel |
