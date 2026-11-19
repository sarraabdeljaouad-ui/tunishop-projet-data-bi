# TuniShop – Projet Power BI (6 tableaux de bord)

Auteure : Sarra Abdeljaouad · v1.1 du 30/10/2026 (v1.0 du 29/10/2026) · Format : projet Power BI (.pbip, rapport au format PBIR)

## Contenu

| Fichier à ouvrir | Cube | Pages |
|---|---|---|
| TB1_Direction.pbip | Direction | Synthèse · Opérations |
| TB2_Ventes.pbip | Ventes | Chiffre d'affaires · Produits et marge · Commandes et paiements |
| TB3_Stock.pbip | Stock | Niveau de stock · Ruptures et mouvements |
| TB4_Achats.pbip | Achats | Vue des achats · Performance fournisseurs |
| TB5_Livraisons.pbip | Livraisons | Ponctualité · Retours et satisfaction |
| TB6_Marketing_Clients.pbip | Marketing Clients | Acquisition · Clients et fidélité |

Chaque page suit la maquette : bandeau bleu marine, volet FILTRES à gauche (segments déroulants),
une rangée de cartes KPI (valeur colorée par le feu : vert = mieux que l'année précédente, gris = stable, rouge = moins bien),
une rangée de cartes « Evolution / Ecart » juste dessous, puis les graphiques. Thème TuniShop inclus.

## Prérequis (obligatoires)

1. Power BI Desktop récent, avec l'option **Fichier > Options > Fonctionnalités en préversion > « Format de projet Power BI (.pbip) »** et **« Format de rapport amélioré Power BI (PBIR) »** cochées, puis redémarrer Desktop.
2. L'instance SSAS `localhost\DEV` démarrée, base `TuniShop_OLAP` déployée et traitée.
3. **Les calculs v2 installés dans les 6 cubes** (scripts 11a à 11f : mesures « A-1 », « Evolution », « Ecart », « Statut », « Couleur »). Sans eux, les cartes et graphiques qui les utilisent affichent une erreur.

## Ouvrir un rapport

1. Décompresser le dossier **en entier** (par exemple `C:\TuniShop\PowerBI\`). Ne pas déplacer un .pbip seul : il a besoin de ses dossiers `.Report` et `.SemanticModel`.
2. Double-cliquer `TB1_Direction.pbip`.
3. Si Power BI demande des identifiants : **Windows – utiliser mes informations d'identification actuelles**.
4. Faire **Fichier > Enregistrer sous > .pbix** si vous voulez un fichier unique pour la soutenance.

## Si l'ouverture échoue (« impossible de charger le modèle sémantique »)

Le lien vers le cube est déclaré dans `TBx.SemanticModel/modelReference.json`. Si votre version de Desktop ne l'accepte pas,
remplacez le contenu de `TBx.Report/definition.pbir` par ceci (exemple pour TB-1 ; changer `Cube=` pour les autres) :

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definitionProperties/1.0.0/schema.json",
  "version": "1.0",
  "datasetReference": {
    "byConnection": {
      "connectionString": "Data Source=localhost\\DEV;Initial Catalog=TuniShop_OLAP;Cube=Direction",
      "pbiServiceModelId": null, "pbiModelVirtualServerName": null, "pbiModelDatabaseName": null,
      "name": "EntityDataSource", "connectionType": "analysisServicesDatabaseLive"
    }
  }
}
```

Dernier recours : ouvrir un rapport vide, **Obtenir les données > Analysis Services > localhost\DEV, Connexion active**, choisir le cube, puis reconstruire les visuels d'après le cahier de conception.

## Si un visuel affiche « Corriger ceci » ou une croix

Cela veut dire qu'un nom de champ diffère légèrement dans votre cube. Cliquez le visuel, puis dans le volet **Données**
glissez le bon champ à la place du champ signalé. Les noms utilisés viennent de vos fichiers `.cube` et `.dim`
(dossier de mesures = table ; mesures calculées = table « Measures » ; dimension du cube = table ; attribut = colonne).

Si les couleurs des valeurs ne suivent pas les feux : sur la carte, **Mettre en forme > Valeur > Couleur > fx >
Style de mise en forme : Valeur du champ > champ « Couleur X »** (même nom que le KPI).

## À ajouter à la main (non générés)

- les boutons de navigation entre pages (Insérer > Boutons > Navigateur > Navigateur de pages) ;
- les pages d'extraction (drill-through) prévues au cahier ;
- la carte des gouvernorats (TB-5), remplacée ici par un graphique à barres Région → Gouvernorat.

## Contrôle conseillé (recette)

TB-1, segment Année = 2025 : comparer les cartes aux valeurs attendues de `12f` (requêtes 4 et 5).
TB-4, page Performance fournisseurs : Shenzhen Bright Tech, T2 2024, retard moyen 32,14 j.
TB-5, page Ponctualité : SahelLog, taux de retard ≈ 37 % au 2nd semestre 2024.

## Nouveautés de la v1.1 (levée de la réserve R1 de la recette)

- TB-1 (Synthèse et Opérations) : les 11 cartes KPI sont réparties sur 2 rangées (6 + 5), chacune suivie de sa rangée d'évolutions : plus de barre de défilement.
- Nombres de clients, de commandes, de ruptures et quantités affichés en valeur exacte (7 366 au lieu de « 7K ») ; les montants restent en millions (M) avec 3 décimales.
- Titres des cartes sur 2 lignes si nécessaire (plus de titres coupés).
- Les 6 rapports sont régénérés : remplacez le dossier TuniShop_PowerBI en entier (gardez une copie de l'ancien si vous l'aviez modifié).
