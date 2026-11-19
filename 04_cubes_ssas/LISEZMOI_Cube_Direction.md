# TuniShop — Cube 6 « Direction » (synthèse pour le tableau de bord de direction)

Auteure : Sarra Abdeljaouad · Base `TuniShop_OLAP` (localhost\DEV) · s'ajoute aux 5 cubes existants, sans les modifier.

## Contenu du cube

| Domaine | Groupe de mesures (cube d'origine) | Vue DSV | KPI de direction |
|---|---|---|---|
| Ventes | Ventes, Commandes (Ventes) | olap_v_fact_ventes, olap_v_fact_commandes | CA Reconnu TTC, Évolution CA Reconnu, Taux Marge Brute, Panier Moyen TTC |
| Clients | Clients distincts (Marketing Clients) | olap_v_fact_commandes | Clients Actifs |
| Stock | Stock mensuel (Stock) | olap_v_fact_stock_mensuel | Valeur Stock HT, Taux Rupture Stock |
| Achats | Achats (Achats) | olap_v_fact_achats_fournisseur | Montant Achat HT, Taux Service Fournisseur |
| Livraisons | Livraisons, Avis (Livraisons) | olap_v_fact_livraisons, olap_v_fact_avis | OTD, Note Moyenne |
| Marketing | Marketing (Marketing Clients) | olap_v_fact_marketing_quotidien | ROAS |

Dimensions du cube : Date, Produit, Géographie, Canal, Statut Commande, Entrepôt (dimensions partagées existantes).
Les dimensions de détail (Client, Fournisseur, Transporteur, Campagne, Coupon, Mode Paiement, Date Livraison) restent dans les cubes métier.

Formules : copiées à l'identique des scripts 11a à 11e (vérifié par script). Les KPI sont rangés dans le dossier d'affichage « KPI Direction ».
Dimensions non liées : comportement SSAS par défaut (IgnoreUnrelatedDimensions = vrai). Un filtre Produit n'a pas d'effet sur le ROAS, par exemple : la valeur affichée est le total.

## Fichiers

| Fichier | Rôle |
|---|---|
| `projet_vs/TuniShop_OLAP/Direction.cube` | le cube (dimensions, 8 groupes de mesures, 51 mesures de base, script de calcul) |
| `projet_vs/TuniShop_OLAP/Direction.partitions` | une partition par groupe de mesures |
| `projet_vs/TuniShop_OLAP/TuniShop_OLAP.dwproj` | votre fichier projet + le cube Direction (seule modification) |
| `ssas/11f_Calculs_Cube_Direction.mdx` | référence du script de calcul (déjà intégré au cube) |
| `ssas/12f_Recette_Cube_Direction.mdx` | recette : valeurs attendues + preuve automatique « Direction = cubes métier » |
| `ssas/13b_Traiter_Cube_Direction.xmla` | traite le seul cube Direction |
| `ssas/18_Creer_Cube_Direction.xmla` | plan B : crée le cube depuis SSMS, sans Visual Studio |

## Installation (Visual Studio)

1. Fermez Visual Studio. Sauvegardez votre dossier `projet_vs` (copie zip).
2. Copiez `Direction.cube`, `Direction.partitions` et `TuniShop_OLAP.dwproj` dans votre dossier `projet_vs\TuniShop_OLAP` et acceptez le remplacement du `.dwproj`.
   Si vous avez modifié le projet depuis l'envoi du zip, ne remplacez pas le `.dwproj` : ajoutez à la main, avant `</Cubes>`, le bloc `<ProjectItem>` de Direction (9 lignes, visible en fin de section `<Cubes>` du fichier fourni).
3. Ouvrez `TuniShop_OLAP.sln` : « Direction » apparaît sous Cubes.
4. Build, puis Deploy. Si le cube n'est pas traité automatiquement, exécutez `13b_Traiter_Cube_Direction.xmla` dans SSMS.
5. Recette : `12f_Recette_Cube_Direction.mdx` (requête 1 = valeurs attendues ; requête 2 = 0 partout).

## Plan B (SSMS, sans Visual Studio)

`18_Creer_Cube_Direction.xmla` puis `13b_Traiter_Cube_Direction.xmla`.
Attention : un déploiement ultérieur depuis un projet Visual Studio qui ne contient pas Direction.cube supprimerait le cube. Ajoutez donc aussi les fichiers au projet.

## Ensuite

`13_Traiter_Cube.xmla` (ProcessFull de toute la base) traite désormais les 6 cubes, sans modification.
Power BI : Obtenir les données → Analysis Services → localhost\DEV → connexion active → TuniShop_OLAP → cube Direction.
