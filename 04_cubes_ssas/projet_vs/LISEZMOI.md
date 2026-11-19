# Projet Visual Studio TuniShop_OLAP (prêt à l'emploi)

5 cubes métier (Ventes, Stock, Achats, Livraisons, Marketing Clients), 14 dimensions, 50 calculs MDX,
plus le cube Direction ajouté ensuite (voir `../LISEZMOI_Cube_Direction.md`),
partitions annuelles de Ventes et Commandes (cube Ventes). Mesures de même type que leur colonne source.

Prérequis : `sql/10_Preparer_Source_Cube.sql` v1.2 exécuté sur le DWH (instance Express `localhost`).

1. Double-clic sur `TuniShop_OLAP.sln`.
2. Clic droit sur le projet, Properties, Deployment : Server `localhost\DEV`, Database `TuniShop_OLAP`.
3. Build, puis clic droit sur le projet, Deploy.
4. Recette : scripts `ssas/12a` à `12e` dans SSMS ; preuve des écarts : `sql/17_Controle_Ecarts_Cube.sql`.

Plan B : `ssas/16_Creer_Base_OLAP.xmla` dans SSMS (Analysis Services), puis « Importer à partir du serveur ».
