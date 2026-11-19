# TuniShop · Étape 4 : cubes SSAS multidimensionnels (architecture 6 cubes)

Une base `TuniShop_OLAP` (serveur `localhost\DEV`, SQL Server 2019 Developer, mode multidimensionnel) contenant
**6 cubes** qui partagent les mêmes dimensions : Ventes, Stock, Achats, Livraisons, Marketing Clients, et Direction (synthèse des KPI pour le tableau de bord de direction, voir `LISEZMOI_Cube_Direction.md`).
Source : les vues `olap.v_*` du DWH. Guide pas à pas : doc « Créer le cube SSAS TuniShop pas à pas ».

| Cube | Groupes de mesures (vues) | Dimensions |
|---|---|---|
| Ventes | Ventes, Commandes, Paiements | Date, Produit, Client, Géographie, Canal, Mode Paiement, Statut Commande, Coupon, Entrepôt |
| Stock | Stock mensuel, Mouvements stock | Date, Produit, Entrepôt, Type Mouvement |
| Achats | Achats | Date, Fournisseur, Produit, Entrepôt |
| Livraisons | Livraisons, Remboursements, Avis | Date, Date Livraison, Transporteur, Géographie, Entrepôt, Client, Produit, Motif Retour |
| Marketing Clients | Marketing, Commandes, Clients distincts | Date, Campagne, Client, Géographie, Canal, Statut Commande |
| Direction | Ventes, Commandes, Clients distincts, Stock mensuel, Achats, Livraisons, Avis, Marketing | Date, Produit, Géographie, Canal, Statut Commande, Entrepôt |

| Fichier | Où l'exécuter |
|---|---|
| `sql/10_Preparer_Source_Cube.sql` | SSMS, Moteur de base de données `localhost` (DWH) : schéma `olap`, 24 vues, droits du compte SSAS (v1.2) |
| `ssas/11a` à `11e_Calculs_Cube_*.mdx` | Visual Studio : onglet Calculs de CHAQUE cube (un fichier par cube, 50 calculs au total) |
| `ssas/12a` à `12e_Recette_Cube_*.mdx` | SSMS, Analysis Services `localhost\DEV` : requêtes de recette + valeurs attendues, par cube |
| `ssas/13_Traiter_Cube.xmla` | SSMS, Analysis Services : traite les 5 cubes métier |
| `ssas/13b_Traiter_Cube_Direction.xmla` | SSMS, Analysis Services : traite le cube Direction |
| `ssas/11f_Calculs_Cube_Direction.mdx`, `ssas/12f_Recette_Cube_Direction.mdx` | Calculs et recette du cube Direction |
| `ssas/18_Creer_Cube_Direction.xmla` | SSMS, Analysis Services : crée le cube Direction |
| `ssas/14_Requetes_Partitions.sql` | Visual Studio, onglet Partitions (Ventes / Commandes par année) |
| `sql/15_Journaliser_Cube.sql` | SSMS, Moteur de base de données (TuniShop_ADMIN) : couche `CUBE` dans l'audit |
| `projet_vs/TuniShop_OLAP.sln` | Visual Studio : le projet complet, prêt à déployer (voir `projet_vs/LISEZMOI.md`) |
| `ssas/16_Creer_Base_OLAP.xmla` | SSMS, Analysis Services : plan B, crée toute la base sans Visual Studio |
| `sql/17_Controle_Ecarts_Cube.sql` | SSMS, Moteur de base de données (DWH) : recalcule en SQL les indicateurs à petit écart, pour prouver que le cube = le DWH |

Rien n'est modifié dans le staging ; dans le DWH, seul le schéma `olap` (vues) est ajouté.
Les KPI absents des données (devise, valeur vie client, couverture et rotation du stock) restent calculés en Python.
