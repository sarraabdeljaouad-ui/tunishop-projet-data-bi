# 05_Validation_Cube — validation des cubes SSAS TuniShop_OLAP (v2.0)

Auteure : Sarra Abdeljaouad · Date de validation : 04/11/2026 · Version 2.0 (remplace la v1.0) · Décision : **VALIDÉ SANS RÉSERVE**

| Dossier | Contenu |
|---|---|
| `01_Rapport_Validation` | Rapport_Validation_Cube_v2.0 (.docx + .pdf) : 6 cubes, recette, preuve cube = DWH, cube Direction, relation SSIS → SSAS, journalisation TuniShop_ADMIN |
| `02_Controles_Validation` | Controles_Validation_Cube_v2.0.xlsx : 10 feuilles, statuts calculés par formules |
| `03_Validation_Finale` | PV_Validation_Cube_v2.0 (.docx + .pdf) |
| `04_Captures` | 61 captures SSMS et Visual Studio des 28 et 29/10/2026 (52, 53, 55 : exécution SSIS du 29/10 avec Direction ; 61 : audit du lot 8 par couche, ex-capture 55) |

Résultats : 6 cubes déployés ; 176 comparaisons sur les 5 cubes métier (165 identiques, 11 écarts expliqués E1 à E3) ;
16 / 16 recalculs SQL égaux au cube ; 21 contrôles métier ; cube Direction : 46 comparaisons, Direction = cubes métier (LookupCube 44 / 44) ;
traitement des cubes par SSIS (tâche DDL, ProcessFull de la base) et lignes CUBE dans audit.execution_tache (id_tache 555 le 28/10, 566 le 29/10 à 10:52, après l'ajout de Direction) ; 0 réserve.

Scripts de référence : 10, 11a à 11f, 12a à 12f, 13, 13b, 15_Journaliser_Cube.sql, 17, 18 ; package SSIS DWH_02_Chargement_Faits.
