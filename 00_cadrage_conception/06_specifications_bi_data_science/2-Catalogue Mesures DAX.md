# Catalogue des mesures DAX – TuniShop

TS-DATA-PBI-001 · version 1.0 · 14/10/2026 · modèle Import sur les vues `rpt.*` de TuniShop_DW.

> Fichier distinct des maquettes. Valeur attendue 2025 : requête SQL équivalente sur l'entrepôt chargé par le pipeline.

## 1 Ventes

### M01 – Nb commandes

- Table d'accueil : `Commandes` · format : `#,0` · mesure de base · **KPI-01**
- Nombre de commandes passées, tous statuts.
- Valeur attendue 2025 : 30 021

```dax
Nb commandes =
COUNTROWS ( Commandes )
```

### M02 – Nb commandes valides

- Table d'accueil : `Commandes` · format : `#,0` · mesure composée · **KPI-02**
- Commandes dont le paiement n'a pas échoué (RG-02).
- Dépend de : [Nb commandes]
- Valeur attendue 2025 : 29 375

```dax
Nb commandes valides =
CALCULATE ( [Nb commandes], Commandes[statut_commande] <> "paiement_echoue" )
```

### M03 – Nb commandes livrées

- Table d'accueil : `Commandes` · format : `#,0` · mesure composée
- Commandes livrées, partiellement retournées ou retournées (RG-01).
- Dépend de : [Nb commandes]
- Valeur attendue 2025 : 26 531

```dax
Nb commandes livrées =
CALCULATE ( [Nb commandes], Commandes[est_livree] = TRUE () )
```

### M04 – Montant brut commandé TTC

- Table d'accueil : `Commandes` · format : `#,0" DT"` · mesure de base · **KPI-03**
- Valeur des commandes passées, tous statuts.
- Valeur attendue 2025 : 8 359 744

```dax
Montant brut commandé TTC =
SUM ( Commandes[montant_total_ttc] )
```

### M05 – CA livré TTC

- Table d'accueil : `Commandes` · format : `#,0" DT"` · mesure composée · **KPI-04**
- Chiffre d'affaires des commandes livrées.
- Dépend de : [Montant brut commandé TTC]
- Valeur attendue 2025 : 7 130 322

```dax
CA livré TTC =
CALCULATE ( [Montant brut commandé TTC], Commandes[est_livree] = TRUE () )
```

### M06 – Retours remboursés TTC

- Table d'accueil : `Commandes` · format : `#,0" DT"` · mesure de base
- Retours remboursés sur les commandes livrées.
- Valeur attendue 2025 : 409 138

```dax
Retours remboursés TTC =
CALCULATE ( SUM ( Commandes[montant_retours_rembourses_ttc] ), Commandes[est_livree] = TRUE () )
```

### M07 – CA net TTC

- Table d'accueil : `Commandes` · format : `#,0" DT"` · mesure composée · **KPI-06**
- CA livré moins les retours remboursés (RG-06).
- Dépend de : [CA livré TTC], [Retours remboursés TTC]
- Valeur attendue 2025 : 6 721 183

```dax
CA net TTC =
[CA livré TTC] - [Retours remboursés TTC]
```

### M08 – Remboursements versés TTC

- Table d'accueil : `Commandes` · format : `#,0" DT"` · mesure de base · **KPI-05**
- Tous remboursements versés : retours, annulations, gestes.
- Valeur attendue 2025 : 676 005

```dax
Remboursements versés TTC =
SUM ( Commandes[montant_rembourse_total_ttc] )
```

### M09 – CA livré HT

- Table d'accueil : `Ventes` · format : `#,0" DT"` · mesure de base · **KPI-07**
- Chiffre d'affaires HT des lignes livrées.
- Valeur attendue 2025 : 5 972 648

```dax
CA livré HT =
CALCULATE ( SUM ( Ventes[montant_ht] ), Ventes[est_livree] = TRUE () )
```

### M10 – Coût d'achat livré HT

- Table d'accueil : `Ventes` · format : `#,0" DT"` · mesure de base
- Coût d'achat HT des lignes livrées, au coût du jour de la vente.
- Valeur attendue 2025 : 4 103 535

```dax
Coût d'achat livré HT =
CALCULATE ( SUM ( Ventes[cout_achat_ht] ), Ventes[est_livree] = TRUE () )
```

### M11 – Marge brute HT

- Table d'accueil : `Ventes` · format : `#,0" DT"` · mesure composée · **KPI-08**
- Marge brute HT (RG-05).
- Dépend de : [CA livré HT], [Coût d'achat livré HT]
- Valeur attendue 2025 : 1 869 114

```dax
Marge brute HT =
[CA livré HT] - [Coût d'achat livré HT]
```

### M12 – Taux de marge brute

- Table d'accueil : `Ventes` · format : `0.0%` · mesure composée · **KPI-09**
- Part de la marge dans le CA HT.
- Dépend de : [Marge brute HT], [CA livré HT]
- Valeur attendue 2025 : 0.3129

```dax
Taux de marge brute =
DIVIDE ( [Marge brute HT], [CA livré HT] )
```

### M13 – Panier moyen TTC

- Table d'accueil : `Commandes` · format : `#,0.00" DT"` · mesure composée · **KPI-10**
- Montant moyen d'une commande livrée.
- Dépend de : [CA livré TTC], [Nb commandes livrées]
- Valeur attendue 2025 : 269

```dax
Panier moyen TTC =
DIVIDE ( [CA livré TTC], [Nb commandes livrées] )
```

### M14 – Part application mobile

- Table d'accueil : `Commandes` · format : `0.0%` · mesure composée · **KPI-11**
- Part des commandes passées via l'application.
- Dépend de : [Nb commandes], [Nb commandes]
- Valeur attendue 2025 : 0.4619

```dax
Part application mobile =
DIVIDE ( CALCULATE ( [Nb commandes], 'Canal paiement'[canal] = "application_mobile" ), [Nb commandes] )
```

## 2 Logistique

### M17 – Nb colis livrés

- Table d'accueil : `Livraisons` · format : `#,0` · mesure de base
- Colis livrés.
- Valeur attendue 2025 : 26 519

```dax
Nb colis livrés =
CALCULATE ( COUNTROWS ( Livraisons ), Livraisons[est_livre] = TRUE () )
```

### M18 – Nb colis en retard

- Table d'accueil : `Livraisons` · format : `#,0` · mesure de base
- Colis livrés après la date promise (RG-07).
- Valeur attendue 2025 : 4 600

```dax
Nb colis en retard =
CALCULATE ( COUNTROWS ( Livraisons ), Livraisons[est_en_retard] = TRUE () )
```

### M19 – Taux de livraison à l'heure

- Table d'accueil : `Livraisons` · format : `0.0%` · mesure composée · **KPI-14**
- Part des colis livrés au plus tard à la date promise.
- Dépend de : [Nb colis en retard], [Nb colis livrés]
- Valeur attendue 2025 : 0.8265

```dax
Taux de livraison à l'heure =
1 - DIVIDE ( [Nb colis en retard], [Nb colis livrés] )
```

### M20 – Taux de retard

- Table d'accueil : `Livraisons` · format : `0.0%` · mesure composée
- Complément du taux de livraison à l'heure.
- Dépend de : [Nb colis en retard], [Nb colis livrés]
- Valeur attendue 2025 : 0.1735

```dax
Taux de retard =
DIVIDE ( [Nb colis en retard], [Nb colis livrés] )
```

### M21 – Délai moyen de livraison (j)

- Table d'accueil : `Livraisons` · format : `0.00` · mesure de base · **KPI-15**
- Jours entre expédition et livraison.
- Valeur attendue 2025 : 2.7608

```dax
Délai moyen de livraison (j) =
CALCULATE ( AVERAGE ( Livraisons[delai_j] ), Livraisons[est_livre] = TRUE () )
```

### M22 – Nb colis COD clos

- Table d'accueil : `Livraisons` · format : `#,0` · mesure de base
- Colis payables à la livraison livrés ou revenus en échec.
- Valeur attendue 2025 : 13 182

```dax
Nb colis COD clos =
CALCULATE ( COUNTROWS ( Livraisons ), 'Canal paiement'[mode_paiement] = "paiement_a_la_livraison", Livraisons[statut_livraison] IN { "livree", "echec_retour_expediteur" } )
```

### M23 – Nb refus COD

- Table d'accueil : `Livraisons` · format : `#,0` · mesure de base
- Colis payables à la livraison revenus en échec (RG-08).
- Valeur attendue 2025 : 1 060

```dax
Nb refus COD =
CALCULATE ( COUNTROWS ( Livraisons ), Livraisons[est_refus_cod] = TRUE () )
```

### M24 – Taux de refus COD

- Table d'accueil : `Livraisons` · format : `0.0%` · mesure composée · **KPI-16**
- Taux de refus des colis payables à la livraison.
- Dépend de : [Nb refus COD], [Nb colis COD clos]
- Valeur attendue 2025 : 0.0804

```dax
Taux de refus COD =
DIVIDE ( [Nb refus COD], [Nb colis COD clos] )
```

### M25 – Coût moyen transport HT

- Table d'accueil : `Livraisons` · format : `#,0.00" DT"` · mesure de base · **KPI-17**
- Coût transporteur HT moyen par colis.
- Valeur attendue 2025 : 8.3842

```dax
Coût moyen transport HT =
AVERAGE ( Livraisons[cout_transport_ht] )
```

## 3 Retours

### M26 – Nb lignes livrées

- Table d'accueil : `Ventes` · format : `#,0` · mesure de base
- Lignes de commandes livrées.
- Valeur attendue 2025 : 45 742

```dax
Nb lignes livrées =
CALCULATE ( COUNTROWS ( Ventes ), Ventes[est_livree] = TRUE () )
```

### M27 – Nb lignes retournées

- Table d'accueil : `Ventes` · format : `#,0` · mesure composée
- Lignes livrées faisant l'objet d'un retour non refusé (RG-09).
- Dépend de : [Nb lignes livrées]
- Valeur attendue 2025 : 2 984

```dax
Nb lignes retournées =
CALCULATE ( [Nb lignes livrées], Ventes[est_retournee] = TRUE () )
```

### M28 – Taux de retour

- Table d'accueil : `Ventes` · format : `0.0%` · mesure composée · **KPI-18**
- Part des lignes livrées retournées.
- Dépend de : [Nb lignes retournées], [Nb lignes livrées]
- Valeur attendue 2025 : 0.0652

```dax
Taux de retour =
DIVIDE ( [Nb lignes retournées], [Nb lignes livrées] )
```

### M29 – Taux de retour cible

- Table d'accueil : `Ventes` · format : `0.0%` · mesure de base
- Cible métier ; lisible au niveau sous-catégorie.

```dax
Taux de retour cible =
MAX ( Produit[taux_retour_cible] )
```

### M30 – Écart au taux de retour cible

- Table d'accueil : `Ventes` · format : `+0.0%;-0.0%;0.0%` · mesure composée
- Écart en points ; vide au-dessus du niveau sous-catégorie.
- Dépend de : [Taux de retour], [Taux de retour cible]

```dax
Écart au taux de retour cible =
IF ( HASONEVALUE ( Produit[sous_categorie] ), [Taux de retour] - [Taux de retour cible] )
```

### M31 – Nb sous-catégories au-dessus de la cible

- Table d'accueil : `Ventes` · format : `#,0` · mesure composée · **KPI-19**
- Sous-catégories dont le taux de retour dépasse la cible.
- Dépend de : [Taux de retour], [Taux de retour cible]
- Valeur attendue 2025 : 9.0000

```dax
Nb sous-catégories au-dessus de la cible =
COUNTROWS ( FILTER ( VALUES ( Produit[sous_categorie] ), [Taux de retour] > [Taux de retour cible] ) )
```

### M32 – Note moyenne

- Table d'accueil : `Avis` · format : `0.00` · mesure de base · **KPI-20**
- Moyenne des notes des avis (date de l'avis).
- Valeur attendue 2025 : 4.0362

```dax
Note moyenne =
AVERAGE ( Avis[note] )
```

## 4 Achats et stocks

### M33 – Nb annulations rupture

- Table d'accueil : `Commandes` · format : `#,0` · mesure composée
- Commandes annulées faute de stock (RG-10).
- Dépend de : [Nb commandes]
- Valeur attendue 2025 : 359

```dax
Nb annulations rupture =
CALCULATE ( [Nb commandes], Commandes[est_rupture] = TRUE () )
```

### M34 – Taux d'annulation pour rupture

- Table d'accueil : `Commandes` · format : `0.00%` · mesure composée · **KPI-21**
- Part des commandes annulées pour rupture.
- Dépend de : [Nb annulations rupture], [Nb commandes]
- Valeur attendue 2025 : 0.0120

```dax
Taux d'annulation pour rupture =
DIVIDE ( [Nb annulations rupture], [Nb commandes] )
```

### M35 – Valeur du stock HT

- Table d'accueil : `Stock mensuel` · format : `#,0" DT"` · mesure de base · **KPI-22**
- Valeur du dernier inventaire de la période (semi-additive).
- Valeur attendue 2025 : 2 093 375

```dax
Valeur du stock HT =
CALCULATE ( SUM ( 'Stock mensuel'[valeur_stock_ht] ), LASTNONBLANK ( 'Date'[date], CALCULATE ( SUM ( 'Stock mensuel'[valeur_stock_ht] ) ) ) )
```

### M36 – Stock fin de période

- Table d'accueil : `Stock mensuel` · format : `#,0` · mesure de base
- Quantité en stock au dernier inventaire de la période.
- Valeur attendue 2025 : 18 156

```dax
Stock fin de période =
CALCULATE ( SUM ( 'Stock mensuel'[stock_fin_mois] ), LASTNONBLANK ( 'Date'[date], CALCULATE ( SUM ( 'Stock mensuel'[stock_fin_mois] ) ) ) )
```

### M37 – Ventes moyennes journalières 92 j

- Table d'accueil : `Mouvements stock` · format : `#,0.0` · mesure de base
- Sorties pour vente des 92 derniers jours de la période, par jour.
- Valeur attendue 2025 : 226

```dax
Ventes moyennes journalières 92 j =
DIVIDE ( - CALCULATE ( SUM ( 'Mouvements stock'[quantite] ), 'Mouvements stock'[type_mouvement] = "vente", DATESINPERIOD ( 'Date'[date], MAX ( 'Date'[date] ), -92, DAY ) ), 92 )
```

### M38 – Couverture de stock (j)

- Table d'accueil : `Stock mensuel` · format : `#,0.0` · mesure composée · **KPI-23**
- Jours de ventes couverts par le stock.
- Dépend de : [Stock fin de période], [Ventes moyennes journalières 92 j]
- Valeur attendue 2025 : 80

```dax
Couverture de stock (j) =
DIVIDE ( [Stock fin de période], [Ventes moyennes journalières 92 j] )
```

### M39 – Taux de service fournisseur

- Table d'accueil : `Achats` · format : `0.0%` · mesure de base · **KPI-24**
- Quantité reçue / quantité commandée, bons réceptionnés.
- Valeur attendue 2025 : 0.9817

```dax
Taux de service fournisseur =
CALCULATE ( DIVIDE ( SUM ( Achats[quantite_recue] ), SUM ( Achats[quantite_commandee] ) ), Achats[statut] IN { "receptionnee", "partiellement_receptionnee" } )
```

### M40 – Retard moyen fournisseur (j)

- Table d'accueil : `Achats` · format : `0.00` · mesure de base · **KPI-25**
- Retard moyen de réception par bon de commande.
- Valeur attendue 2025 : 1.2137

```dax
Retard moyen fournisseur (j) =
AVERAGEX ( FILTER ( SUMMARIZE ( Achats, Achats[commande_fournisseur_id], "retard", MAX ( Achats[retard_j] ) ), NOT ISBLANK ( [retard] ) ), [retard] )
```

## 5 Marketing

### M41 – Dépense marketing HT

- Table d'accueil : `Marketing` · format : `#,0" DT"` · mesure de base · **KPI-26**
- Dépense publicitaire HT.
- Valeur attendue 2025 : 781 583

```dax
Dépense marketing HT =
SUM ( Marketing[depense_ht] )
```

### M42 – CA attribué TTC

- Table d'accueil : `Marketing` · format : `#,0" DT"` · mesure de base
- CA attribué au dernier clic.
- Valeur attendue 2025 : 2 232 535

```dax
CA attribué TTC =
SUM ( Marketing[ca_attribue_ttc] )
```

### M43 – ROAS

- Table d'accueil : `Marketing` · format : `0.00` · mesure composée · **KPI-27**
- CA attribué TTC par dinar dépensé (RG-11).
- Dépend de : [CA attribué TTC], [Dépense marketing HT]
- Valeur attendue 2025 : 2.8564

```dax
ROAS =
DIVIDE ( [CA attribué TTC], [Dépense marketing HT] )
```

### M44 – Clics

- Table d'accueil : `Marketing` · format : `#,0` · mesure de base
- Clics.
- Valeur attendue 2025 : 1 794 408

```dax
Clics =
SUM ( Marketing[clics] )
```

### M45 – CPC

- Table d'accueil : `Marketing` · format : `0.000" DT"` · mesure composée · **KPI-28**
- Coût par clic.
- Dépend de : [Dépense marketing HT], [Clics]
- Valeur attendue 2025 : 0.4356

```dax
CPC =
DIVIDE ( [Dépense marketing HT], [Clics] )
```

### M46 – Nouveaux clients attribués

- Table d'accueil : `Marketing` · format : `#,0` · mesure de base
- Nouveaux clients attribués.
- Valeur attendue 2025 : 1 396

```dax
Nouveaux clients attribués =
SUM ( Marketing[nouveaux_clients_attribues] )
```

### M47 – CAC

- Table d'accueil : `Marketing` · format : `#,0.00" DT"` · mesure composée · **KPI-29**
- Coût d'acquisition client.
- Dépend de : [Dépense marketing HT], [Nouveaux clients attribués]
- Valeur attendue 2025 : 560

```dax
CAC =
DIVIDE ( [Dépense marketing HT], [Nouveaux clients attribués] )
```

## 6 Paiements

### M15 – Part paiement à la livraison

- Table d'accueil : `Commandes` · format : `0.0%` · mesure composée · **KPI-12**
- Part des commandes payées à la livraison.
- Dépend de : [Nb commandes], [Nb commandes]
- Valeur attendue 2025 : 0.4665

```dax
Part paiement à la livraison =
DIVIDE ( CALCULATE ( [Nb commandes], 'Canal paiement'[mode_paiement] = "paiement_a_la_livraison" ), [Nb commandes] )
```

### M16 – Taux d'échec paiement en ligne

- Table d'accueil : `Commandes` · format : `0.0%` · mesure composée · **KPI-13**
- Commandes payées en ligne dont toutes les tentatives ont échoué.
- Dépend de : [Nb commandes], [Nb commandes]
- Valeur attendue 2025 : 0.0427

```dax
Taux d'échec paiement en ligne =
VAR enLigne = CALCULATE ( [Nb commandes], 'Canal paiement'[est_paiement_en_ligne] = TRUE () )
RETURN DIVIDE ( CALCULATE ( [Nb commandes], 'Canal paiement'[est_paiement_en_ligne] = TRUE (), Commandes[statut_commande] = "paiement_echoue" ), enLigne )
```

### M52 – Délai moyen de reversement (j)

- Table d'accueil : `Paiements` · format : `0.00` · mesure de base · **KPI-33**
- Jours entre encaissement à la livraison et reversement.
- Valeur attendue 2025 : 6.4405

```dax
Délai moyen de reversement (j) =
CALCULATE ( AVERAGE ( Paiements[delai_reversement_j] ), 'Canal paiement'[mode_paiement] = "paiement_a_la_livraison", Paiements[statut_paiement] = "encaisse" )
```

## 7 Clients

### M48 – Clients actifs

- Table d'accueil : `Commandes` · format : `#,0` · mesure composée · **KPI-30**
- Clients ayant au moins une commande valide sur la période.
- Valeur attendue 2025 : 7 365

```dax
Clients actifs =
COUNTROWS ( FILTER ( CALCULATETABLE ( ADDCOLUMNS ( VALUES ( Client[client_id] ), "n", CALCULATE ( COUNTROWS ( Commandes ) ) ), Commandes[statut_commande] <> "paiement_echoue" ), [n] >= 1 ) )
```

### M49 – Clients réachat

- Table d'accueil : `Commandes` · format : `#,0` · mesure composée
- Clients ayant au moins deux commandes valides sur la période.
- Valeur attendue 2025 : 5 091

```dax
Clients réachat =
COUNTROWS ( FILTER ( CALCULATETABLE ( ADDCOLUMNS ( VALUES ( Client[client_id] ), "n", CALCULATE ( COUNTROWS ( Commandes ) ) ), Commandes[statut_commande] <> "paiement_echoue" ), [n] >= 2 ) )
```

### M50 – Taux de réachat

- Table d'accueil : `Commandes` · format : `0.0%` · mesure composée · **KPI-31**
- Part des clients actifs ayant commandé au moins deux fois.
- Dépend de : [Clients réachat], [Clients actifs]
- Valeur attendue 2025 : 0.6912

```dax
Taux de réachat =
DIVIDE ( [Clients réachat], [Clients actifs] )
```

### M51 – Part des clients or

- Table d'accueil : `Client` · format : `0.0%` · mesure de base · **KPI-32**
- Part des comptes au segment or (version courante).
- Valeur attendue 2025 : 0.0784

```dax
Part des clients or =
VAR tous = CALCULATE ( DISTINCTCOUNT ( Client[client_id] ), Client[est_courant] = TRUE (), Client[client_id] <> "?" )
RETURN DIVIDE ( CALCULATE ( DISTINCTCOUNT ( Client[client_id] ), Client[est_courant] = TRUE (), Client[segment_fidelite] = "or" ), tous )
```

## 8 Comparaisons

### M53 – CA livré TTC N-1

- Table d'accueil : `Commandes` · format : `#,0" DT"` · mesure composée
- CA livré de la même période l'année précédente.
- Dépend de : [CA livré TTC]
- Valeur attendue 2025 : 5 019 998

```dax
CA livré TTC N-1 =
CALCULATE ( [CA livré TTC], SAMEPERIODLASTYEAR ( 'Date'[date] ) )
```

### M54 – Évolution CA livré vs N-1

- Table d'accueil : `Commandes` · format : `+0.0%;-0.0%;0.0%` · mesure composée
- Évolution relative du CA livré.
- Dépend de : [CA livré TTC], [CA livré TTC N-1], [CA livré TTC N-1]
- Valeur attendue 2025 : 0.4204

```dax
Évolution CA livré vs N-1 =
DIVIDE ( [CA livré TTC] - [CA livré TTC N-1], [CA livré TTC N-1] )
```

### M55 – Nb commandes N-1

- Table d'accueil : `Commandes` · format : `#,0` · mesure composée
- Commandes de la même période l'année précédente.
- Dépend de : [Nb commandes]
- Valeur attendue 2025 : 21 166

```dax
Nb commandes N-1 =
CALCULATE ( [Nb commandes], SAMEPERIODLASTYEAR ( 'Date'[date] ) )
```

### M56 – Évolution commandes vs N-1

- Table d'accueil : `Commandes` · format : `+0.0%;-0.0%;0.0%` · mesure composée
- Évolution relative du nombre de commandes.
- Dépend de : [Nb commandes], [Nb commandes N-1], [Nb commandes N-1]
- Valeur attendue 2025 : 0.4184

```dax
Évolution commandes vs N-1 =
DIVIDE ( [Nb commandes] - [Nb commandes N-1], [Nb commandes N-1] )
```

### M57 – Taux de livraison à l'heure (date d'expédition)

- Table d'accueil : `Livraisons` · format : `0.0%` · mesure composée
- Même indicateur rattaché à la date d'expédition (relation inactive).
- Dépend de : [Taux de livraison à l'heure]
- Valeur attendue 2025 : 0.8267

```dax
Taux de livraison à l'heure (date d'expédition) =
CALCULATE ( [Taux de livraison à l'heure], USERELATIONSHIP ( Livraisons[date_expedition_key], 'Date'[date_key] ) )
```

## 9 Affichage

### M58 – Libellé période

- Table d'accueil : `_Mesures` · format : `Texte` · mesure composée
- Rappel de la période filtrée en en-tête de page.

```dax
Libellé période =
"Du " & FORMAT ( MIN ( 'Date'[date] ), "dd/mm/yyyy" ) & " au " & FORMAT ( MAX ( 'Date'[date] ), "dd/mm/yyyy" )
```

### M59 – Couleur écart retour

- Table d'accueil : `_Mesures` · format : `Texte` · mesure composée
- Mise en forme conditionnelle : rouge au-dessus de la cible.
- Dépend de : [Écart au taux de retour cible]

```dax
Couleur écart retour =
IF ( [Écart au taux de retour cible] > 0, "#C0392B", "#0F7C80" )
```

### M60 – Couleur ponctualité

- Table d'accueil : `_Mesures` · format : `Texte` · mesure composée
- Voyant : vert ≥ 90 %, orange ≥ 80 %, rouge sinon (seuils à valider).
- Dépend de : [Taux de livraison à l'heure], [Taux de livraison à l'heure]

```dax
Couleur ponctualité =
SWITCH ( TRUE (), [Taux de livraison à l'heure] >= 0.9, "#2E7D32", [Taux de livraison à l'heure] >= 0.8, "#E0A030", "#C0392B" )
```

### M61 – Dernier chargement

- Table d'accueil : `_Mesures` · format : `Texte` · mesure composée
- Date du dernier chargement de l'entrepôt (EF-24).

```dax
Dernier chargement =
"Données au " & FORMAT ( MAX ( Commandes[_date_maj] ), "dd/mm/yyyy hh:nn" )
```
