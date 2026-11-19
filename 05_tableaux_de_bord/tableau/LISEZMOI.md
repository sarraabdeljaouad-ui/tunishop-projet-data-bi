# TuniShop – Tableaux de bord Tableau (Direction et Ventes)

Auteur : Sarra Abdeljaouad · v1.0 du 29/10/2026 · Tableau Desktop (Windows)

## Contenu

| Fichier | Rôle |
|---|---|
| `19_Vues_Tableau.sql` | Crée le schéma `tab` et 2 vues dans TuniShop_DWH, puis 3 requêtes de contrôle |
| `TB1_Direction.twb` | Tableau de bord Direction : 2 onglets (Synthèse, Tendances 2023-2025) |
| `TB2_Ventes.twb` | Tableau de bord Ventes : 3 onglets (Chiffre d'affaires, Produits et marge, Commandes et paiements) |

## Pourquoi le DWH et pas les cubes

Le connecteur Analysis Services de Tableau limite les calculs (pas de calculs FIXED, compatibilité
mesures/dimensions). Tableau lit donc les vues `tab.v_direction` et `tab.v_ventes`, construites sur la
même couche `olap.v_*` que les cubes, et recalcule les KPI avec les mêmes règles que les scripts 11a à 11f.
Les requêtes de contrôle du script 19 doivent redonner les valeurs de la recette des cubes.

## Étape 1 – Créer les vues (SSMS)

1. Ouvrez SSMS, connectez-vous au **moteur de base de données** `localhost` (instance du DWH).
2. Ouvrez `19_Vues_Tableau.sql`, puis **Exécuter** (F5).
3. Comparez les résultats aux valeurs attendues écrites dans les titres de colonnes
   (par exemple CA Reconnu TTC 2025 = 7 134 752,765). Faites une capture : elle servira à la recette.

## Étape 2 – Ouvrir les classeurs (Tableau Desktop)

1. Double-cliquez `TB1_Direction.twb`.
2. Si Tableau demande la connexion : serveur `localhost`, **Authentification Windows**, base `TuniShop_DWH`.
   Si Tableau demande d'installer un pilote, installez le pilote ODBC SQL Server proposé, puis rouvrez le fichier.
3. Le classeur s'ouvre sur l'onglet **Direction - Synthèse**. Choisissez l'année dans « Année analysée ».
4. Conseil : **Données > TuniShop Direction > Extraire les données** pour des affichages plus rapides,
   puis **Fichier > Enregistrer sous > Classeur empaqueté (.twbx)** pour la soutenance.

## Ce que montrent les tableaux de bord

- **Cartes KPI** : valeur de l'année choisie, puis évolution par rapport à l'année précédente
  (▲/▼, en % pour les montants et nombres, en points pour les taux). Couleur : vert = mieux,
  gris = stable (moins de 2 % ou 0,5 point) ou sans comparaison, rouge = moins bien, bleu = indicateur neutre
  (valeur du stock, achats, taux de remise, parts).
- **Filtre Région** (et Canal, Mode de paiement pour les ventes) : il s'applique à toutes les feuilles.
  Dans Direction, stock, achats, avis et marketing ne dépendent pas de la région : ils restent au total,
  comme dans le cube Direction.

## Contrôle (recette) – année 2025

| KPI | Attendu (cube) |
|---|---|
| CA reconnu TTC | 7,13 M TND (▲ +42,1 % vs 2024) |
| Taux de marge brute | 31,28 % |
| Panier moyen TTC | 268,8 TND |
| Clients actifs | 7 366 |
| ROAS | 2,853 |
| Valeur du stock HT | 2,09 M TND |
| Taux de rupture de stock | 3,13 % |
| Achats HT | 4,18 M TND |
| Taux de service fournisseur | 98,17 % |
| OTD | 82,67 % |
| Note moyenne | 4,036 |
| Ventes : taux d'annulation / refus de colis / échec de paiement | 4,57 % / 4,37 % / 7,07 % |

## Si un message d'erreur s'affiche à l'ouverture

Ces classeurs ont été générés sans pouvoir être ouverts dans Tableau. Si Tableau signale une erreur
(« classeur endommagé », « champ introuvable »…), faites une capture du message complet et envoyez-la :
il indique la ligne en cause et je corrige le fichier.

## Limites connues

- Les barres ne sont pas triées : cliquez l'icône de tri de l'axe pour les trier.
- La liste du filtre Région contient « Null » : ce sont les lignes sans région (stock, achats, marketing).
- Les parts « paiement à la livraison » et « application mobile » se lisent sans filtre Mode de paiement ni Canal.
- Les montants des cartes sont arrondis (M TND) ; les valeurs exactes sont dans les infobulles des graphiques.
